'use strict';
const fs=require('node:fs'),path=require('node:path'),net=require('node:net'),crypto=require('node:crypto');
const {execFile}=require('node:child_process');
const runFile=require('node:util').promisify(execFile);
const INTERVAL_MS=60000;

function identity(value){
 const pid=value?.pid,started=Date.parse(value?.startedAt);
 if(!Number.isInteger(pid)||pid<=0||!Number.isFinite(started))return null;
 return {pid,startedAt:new Date(started).toISOString()};
}
function key(value){const session=identity(value);return session?session.pid+'|'+session.startedAt:null;}
function clearanceProof(result){
 return Boolean(result&&result.status==='active'&&result.pageVisible===true&&result.placement==='bottom'&&result.geometryVerified===true&&
  Number.isFinite(result.clearanceCssPx)&&result.clearanceCssPx>=1&&Number.isFinite(result.requestedClearanceCssPx)&&result.requestedClearanceCssPx>=1&&
  Math.abs(result.clearanceCssPx-result.requestedClearanceCssPx)<=1&&Number.isFinite(result.inputWidthCssPx)&&result.inputWidthCssPx>=360&&
  Number.isFinite(result.leftShiftCssPx)&&Math.abs(result.leftShiftCssPx)<=1&&Number.isFinite(result.bottomShiftCssPx)&&Math.abs(result.bottomShiftCssPx)<=1&&
  Number.isFinite(result.heightChangeCssPx)&&(Math.abs(result.heightChangeCssPx)<=1||result.naturalHeightReflowVerified===true)&&result.domButtonsUncovered===true);
}
function inspect(sample,session,now){
 if(!key(session)||key(sample?.hostSession)!==key(session))return {passed:false,reason:'waiting-for-current-client-observation',repair:true};
 const age=now-Date.parse(sample?.time);
 if(!Number.isFinite(age)||age<0||age>15000)return {passed:false,reason:'worker-heartbeat-expired',repair:true};
 if(sample.connectionSetup?.state!=='connected')return {passed:false,reason:'connection-unavailable',repair:true};
 const result=sample.results?.find(clearanceProof);
 if(!result)return {passed:false,reason:'no-verified-visible-bottom-clearance',repair:['error','stopped','disabled'].includes(sample.status)};
 return {passed:true,reason:'actual-right-clearance-verified',evidence:{
  clearanceCssPx:result.clearanceCssPx,requestedClearanceCssPx:result.requestedClearanceCssPx,inputWidthCssPx:result.inputWidthCssPx,
  leftShiftCssPx:result.leftShiftCssPx,bottomShiftCssPx:result.bottomShiftCssPx,geometryVerified:true,pageVisible:true,placement:'bottom',domButtonsUncovered:true
 }};
}

// Dependencies isolate time and OS calls for tests; the production interval is fixed.
async function runSelfCheck({detect,readWorker,readState,saveState,startWorker,enabled,acquire,now=Date.now,wait=ms=>new Promise(resolve=>setTimeout(resolve,ms))}){
 if(!enabled())return {state:'disabled',running:false};
 const discoveryRelease=await acquire('client-discovery');
 if(!discoveryRelease)return {state:'duplicate-checker',running:false};
 let session;
 try{
  while(enabled()){
   try{
    const first=await detect();session=identity(first);
    if(first?.state==='not-running'||first?.state==='disabled')return {state:'client-closed',running:false};
    if(session)break;
   }catch{}
   await wait(INTERVAL_MS);
  }
 }finally{await discoveryRelease();}
 if(!session)return {state:'disabled',running:false};
 const release=await acquire(key(session));
 if(!release)return {state:'duplicate-checker',running:false};
 try{
  const saved=readState();
  if(key(saved?.session)===key(session)&&saved.state==='completed'&&saved.evidence?.geometryVerified===true&&saved.evidence?.clearanceCssPx>=1){return saved;}
  let state=key(saved?.session)===key(session)&&saved.state==='waiting'&&Number.isInteger(saved.checkCount)&&saved.checkCount>=0?{...saved}:{
   schemaVersion:1,trigger:'codex-process-start',intervalSeconds:60,state:'waiting',running:true,session,
   checkerStartedAt:new Date(now()).toISOString(),checkCount:0,lastCheckedAt:null,completedAt:null,
   nextCheckAt:new Date(Math.min(now()+INTERVAL_MS,Math.max(now(),Date.parse(session.startedAt)+INTERVAL_MS))).toISOString(),lastReason:'waiting-for-first-check'
  };
  state.checkerPid=process.pid;state.clientRestartAllowed=false;
  let initialized=false;
  function persist(){
   const current=readState();
   if(current?.session&&key(current.session)!==key(session)&&(initialized||Date.parse(current.session.startedAt)>Date.parse(session.startedAt)))return false;
   saveState({...state,updatedAt:new Date(now()).toISOString()});initialized=true;return true;
  }
  if(!persist())return {state:'superseded',running:false};
  while(true){
   const remaining=Date.parse(state.nextCheckAt)-now();
   if(remaining>0)await wait(Math.min(remaining,INTERVAL_MS));
   if(!enabled()){state={...state,state:'paused',running:false,nextCheckAt:null,lastReason:'plugin-disabled'};persist();return state;}
   if(now()<Date.parse(state.nextCheckAt))continue;
   let current,outcome;
   try{current=await detect();}catch(error){outcome={passed:false,reason:'client-detection-unavailable',detail:error.message.slice(0,300),repair:false};}
   if(current?.state==='not-running'||current?.state==='disabled'||(identity(current)&&key(current)!==key(session))){
    state={...state,state:'client-closed',running:false,nextCheckAt:null,lastReason:'client-session-ended'};persist();return state;
   }
   if(!outcome){
    if(!identity(current))outcome={passed:false,reason:'client-detection-unavailable',repair:false};
    else if(current.state!=='connected')outcome={passed:false,reason:'connection-unavailable',repair:true};
    else outcome=inspect(readWorker(),session,now());
   }
   state={...state,checkCount:state.checkCount+1,lastCheckedAt:new Date(now()).toISOString(),lastReason:outcome.reason,lastDetail:outcome.detail??null};
   if(outcome.passed){
    state={...state,state:'completed',running:false,nextCheckAt:null,completedAt:new Date(now()).toISOString(),evidence:outcome.evidence};
    persist();return state;
   }
   if(outcome.repair){
    try{await startWorker();state.lastRepair='layout-worker-requested';}catch(error){state.lastRepair='layout-worker-start-failed';state.lastDetail=error.message.slice(0,300);}
   }else state.lastRepair='not-needed';
   state.nextCheckAt=new Date(now()+INTERVAL_MS).toISOString();
   if(!persist())return {state:'superseded',running:false};
  }
 }finally{await release();}
}

function read(file,fallback=null){try{return JSON.parse(fs.readFileSync(file,'utf8').replace(/^\uFEFF/,''));}catch{return fallback;}}
function write(file,value){const temporary=file+'.'+process.pid+'.tmp';fs.writeFileSync(temporary,JSON.stringify(value,null,2));fs.renameSync(temporary,file);}
async function cli(){
 const at=process.argv.indexOf('--home');
 const homeDir=fs.realpathSync(path.resolve(at>=0?process.argv[at+1]:process.env.CODEX_HOME||path.join(process.env.USERPROFILE,'.codex')));
 const data=path.join(homeDir,'plugin-data','codex-right-clearance-v3');
 fs.mkdirSync(data,{recursive:true});
 const stateFile=path.join(data,'startup-self-check.json');
 function enabled(){
  if(read(path.join(data,'settings.json'),{}).enabled!==true)return false;
  const text=fs.readFileSync(path.join(homeDir,'config.toml'),'utf8');
  const section=text.match(/^\[plugins\."codex-right-clearance@codex-ui-local"\]\s*\r?\n([\s\S]*?)(?=^\[|$(?![\s\S]))/m);
  return Boolean(section&&/^enabled\s*=\s*true\s*(?:#.*)?$/m.test(section[1]));
 }
 async function detect(){
  const output=await runFile('powershell.exe',['-NoLogo','-NoProfile','-ExecutionPolicy','RemoteSigned','-WindowStyle','Hidden','-File',path.join(__dirname,'ensure-connection.ps1')],{env:{...process.env,CODEX_HOME:homeDir},windowsHide:true,timeout:20000,maxBuffer:16000});
  return JSON.parse(output.stdout.replace(/^\uFEFF/,''));
 }
 async function acquire(sessionKey){
  const pipe='\\\\.\\pipe\\CodexClearanceSelfCheck-'+crypto.createHash('sha256').update(data.toLowerCase()+'|'+sessionKey).digest('hex').slice(0,24);
  const guard=net.createServer(socket=>socket.end());
  const owned=await new Promise((resolve,reject)=>{guard.once('error',error=>error.code==='EADDRINUSE'?resolve(false):reject(error));guard.listen(pipe,()=>resolve(true));});
  return owned?()=>new Promise(resolve=>guard.close(resolve)):null;
 }
 const result=await runSelfCheck({detect,readWorker:()=>read(path.join(data,'status.json')),readState:()=>read(stateFile),saveState:value=>write(stateFile,value),enabled,acquire,
  startWorker:()=>runFile('powershell.exe',['-NoLogo','-NoProfile','-ExecutionPolicy','RemoteSigned','-WindowStyle','Hidden','-File',path.join(__dirname,'Control.ps1'),'-Action','BootstrapWorker'],{env:{...process.env,CODEX_HOME:homeDir},windowsHide:true,timeout:20000,maxBuffer:16000})});
 console.log(JSON.stringify(result));
}
module.exports={INTERVAL_MS,identity,key,clearanceProof,inspect,runSelfCheck};
if(require.main===module)cli().catch(error=>{console.error('Startup self-check: '+error.message);process.exitCode=1;});
