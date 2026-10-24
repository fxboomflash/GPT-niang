// Read-only CDP diagnostics. Never launches an app, navigates, sends keys, or injects styles.
const fs=require('node:fs');
const path=require('node:path');
const args=process.argv.slice(2);
const at=args.indexOf('--output');
const output=at<0?path.resolve(__dirname,'../run/target-diagnostic.json'):path.resolve(args[at+1]);
const endpoint='http://127.0.0.1:19327';
function safeUrl(value){try{const u=new URL(value);return u.protocol+'//'+u.host+u.pathname}catch{return '<invalid>'}}
function trustedApp(value){
 try{const u=new URL(value);if(u.protocol==='app:')return u.hostname==='-'&&u.pathname==='/index.html'&&!/^\/(avatar-overlay|detached-window)(\/|$)/.test(u.searchParams.get('initialRoute')||'');return u.protocol==='file:'&&/[\\/]OpenAI\.Codex_[0-9.]+_x64__2p2nqsd0c76g0[\\/]app[\\/]resources[\\/]app\.asar[\\/]webview[\\/]index\.html$/i.test(decodeURIComponent(u.pathname))}catch{return false}
}
function trustedWork(value){try{const u=new URL(value);return u.protocol==='https:'&&u.hostname==='chatgpt.com'&&!u.username&&!u.password;}catch{return false}}
function trustedPage(value){return trustedApp(value)||trustedWork(value);}
function socketAllowed(value,port){try{const u=new URL(value);return u.protocol==='ws:'&&['127.0.0.1','localhost','[::1]'].includes(u.hostname)&&u.port===String(port)&&!u.username&&!u.password}catch{return false}}
async function connect(address,port=19327){
 if(!socketAllowed(address,port))throw Error('Unexpected debugger address.');
 const ws=new WebSocket(address);let id=0;const pending=new Map(),contexts=new Map();
 ws.addEventListener('message',event=>{
  const message=JSON.parse(String(event.data));
  if(message.method==='Runtime.executionContextCreated'){const c=message.params.context;contexts.set(c.id,c)}
  if(message.method==='Runtime.executionContextDestroyed')contexts.delete(message.params.executionContextId);
  if(message.method==='Runtime.executionContextsCleared')contexts.clear();
  const p=pending.get(message.id);if(!p)return;pending.delete(message.id);clearTimeout(p.timer);message.error?p.reject(Error(message.error.message)):p.resolve(message.result);
 });
 await new Promise((resolve,reject)=>{const timer=setTimeout(()=>{ws.close();reject(Error('Connect timeout'))},3000);ws.addEventListener('open',()=>{clearTimeout(timer);resolve()},{once:true});ws.addEventListener('error',()=>{clearTimeout(timer);reject(Error('Connect error'))},{once:true})});
 return {contexts,close:()=>ws.close(),command:(method,params={})=>new Promise((resolve,reject)=>{const n=++id;const timer=setTimeout(()=>{pending.delete(n);reject(Error(method+' timed out'))},3000);pending.set(n,{resolve,reject,timer});ws.send(JSON.stringify({id:n,method,params}))})};
}
const expression=`(() => {
 const docs=[document];let walked=0;for(let d=0;d<docs.length&&docs.length<40;d++){for(const e of docs[d].querySelectorAll('*')){if(++walked>15000)break;if(e.shadowRoot)docs.push(e.shadowRoot)}}
 const all=s=>docs.flatMap(d=>[...d.querySelectorAll(s)]),visible=e=>{const r=e.getBoundingClientRect();return r.width>0&&r.height>0};
 const roots=all('[data-codex-composer-root]');
 const candidates=roots.filter(e=>e.getAttribute('data-composer-placement')==='thread'&&visible(e)).flatMap(e=>[...e.querySelectorAll('[data-composer-surface-variant]')]);
 return {readyState:document.readyState,activeFrameTrial:Boolean(window.__codexFrameClearanceV2),viewportCssPx:[innerWidth,innerHeight],shadowRoots:docs.length-1,iframeCount:all('iframe').length,rootCount:roots.length,roots:roots.map(e=>{const r=e.getBoundingClientRect();return{placement:e.getAttribute('data-composer-placement'),visible:visible(e),surfaceCount:e.querySelectorAll('[data-composer-surface-variant]').length,editorAttributes:[...e.querySelectorAll('[contenteditable]')].map(x=>x.getAttribute('contenteditable')),rect:{left:r.left,top:r.top,width:r.width,height:r.height}}}),oldSelectorEligibleCount:candidates.filter(e=>visible(e)&&e.querySelector('[contenteditable="true"],textarea')&&e.getBoundingClientRect().bottom>innerHeight*.65).length};
})()`;
function frames(tree,out=[]){if(tree?.frame)out.push(tree.frame);for(const child of tree?.childFrames||[])frames(child,out);return out}
async function collect(){
 const response=await fetch(endpoint+'/json/list',{signal:AbortSignal.timeout(3000)});if(!response.ok)throw Error('Target listing failed.');
 const targets=await response.json();const observations=[];
 for(const target of targets.slice(0,24)){
  const row={id:target.id,type:target.type,url:safeUrl(target.url),oldTypeFilterWouldInclude:target.type==='page',oldUrlFilterWouldInclude:trustedApp(target.url),frames:[],contexts:[]};observations.push(row);
  if(!['page','webview','iframe','other'].includes(target.type)||!target.webSocketDebuggerUrl){row.skipped='Not a document-like target';continue}
  let client;
  try{
   client=await connect(target.webSocketDebuggerUrl);
   let f=[];try{f=frames((await client.command('Page.getFrameTree')).frameTree)}catch(error){row.frameError=error.message}
   row.frames=f.map(x=>({id:x.id,parentId:x.parentId||null,url:safeUrl(x.url),trustedApp:trustedApp(x.url)}));
   if(!trustedApp(target.url)&&!f.some(x=>trustedApp(x.url))){row.skipped='No known Codex app frame; no DOM was read.';continue}
   await client.command('Runtime.enable');
   const selected=[...client.contexts.values()].filter(c=>c.auxData?.isDefault===true&&f.some(frame=>frame.id===c.auxData.frameId&&trustedApp(frame.url)));
   if(selected.length===0&&trustedApp(target.url))selected.push({id:null,auxData:{frameId:f[0]?.id||null},fallback:true});
   for(const context of selected){
    const entry={frameId:context.auxData.frameId,contextId:context.id,defaultWorldFallback:context.fallback||false};row.contexts.push(entry);
    const evaluated=await client.command('Runtime.evaluate',{expression,returnByValue:true,...context.id==null?{}:{contextId:context.id}});
    if(evaluated.exceptionDetails)entry.error=evaluated.exceptionDetails.text;else entry.dom=evaluated.result?.value;
   }
  }catch(error){row.error=error.message}finally{client?.close()}
 }
 const report={time:new Date().toISOString(),status:'diagnosed',readOnly:true,applicationRestarted:false,styleInjected:false,scope:'Target/frame metadata plus marker counts in known Codex app frames only. No chat text, storage, credentials, or network bodies.',targetCount:targets.length,unexaminedTargetCount:Math.max(0,targets.length-24),observations};
 return report;
}
async function main(){const report=await collect();fs.mkdirSync(path.dirname(output),{recursive:true});fs.writeFileSync(output,JSON.stringify(report,null,2));console.log(JSON.stringify({status:report.status,targetCount:report.targetCount,appFrameObservations:report.observations.flatMap(x=>x.contexts).length,rootCount:report.observations.flatMap(x=>x.contexts).reduce((n,x)=>n+(x.dom?.rootCount||0),0),output},null,2));}
module.exports={collect,connect,trustedApp,trustedWork,trustedPage};
if(require.main===module)main().catch(error=>{console.error(error.message);process.exitCode=1});
