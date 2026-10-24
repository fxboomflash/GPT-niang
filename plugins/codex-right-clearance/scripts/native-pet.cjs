'use strict';
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const {spawn,execFile}=require('node:child_process');
const {promisify}=require('node:util');
const run=promisify(execFile);
function read(file){return JSON.parse(fs.readFileSync(file,'utf8').replace(/^\uFEFF/,''));}
function widgetPet(snapshot,presence,settings){
 if(snapshot.status!=='visible')return {status:snapshot.status,reason:snapshot.reason,pets:[],provider:'gpt-niang-widget',native:snapshot};
 const w=snapshot.widget,c=Number(presence.sizing?.character),b=Number(presence.sizing?.bubble);
 if(!w||![w.left,w.top,w.width,w.height,c,b].every(Number.isFinite)||w.width<=0||w.height<=0||c<0.2||c>4||b<0.2||b>4)return {status:'unavailable',pets:[],provider:'gpt-niang-widget',reason:'Invalid native widget layout.'};
 // The actual 378px stage has 14px animation padding around its 350px root.
 // Character and speech-bubble scales are independent; never reserve the full transparent window.
 const relative=c/Math.max(c,b),size=208*relative,x=settings.side==='left'?14:364-size,y=364-size;
 const scale=Math.min(w.width,w.height)/378,padX=(w.width-378*scale)/2,padY=(w.height-378*scale)/2;
 let pet={left:w.left+padX+x*scale,top:w.top+padY+y*scale,right:w.left+padX+(x+size)*scale,bottom:w.top+padY+(y+size)*scale};
 if(presence.followHost&&snapshot.hostFrame){const f=snapshot.hostFrame;pet={left:Math.max(pet.left,f.left),top:Math.max(pet.top,f.top),right:Math.min(pet.right,f.right),bottom:Math.min(pet.bottom,f.bottom)}}
 return {status:pet.right>pet.left&&pet.bottom>pet.top?'visible':'hidden',provider:'gpt-niang-widget',coordinateSpace:'screen-physical',hostClient:snapshot.hostClient,hostFrame:snapshot.hostFrame,hostDpi:snapshot.hostDpi,pets:[pet],characterScale:c,bubbleScale:b,sampledAt:Date.now()};
}
class NativePetProvider {
 constructor(data){this.data=data;this.child=null;this.pending=null;this.preparing=null;}
 async start(){
  if(this.child)return;
  if(this.preparing)return this.preparing;
  this.preparing=(async()=>{
   const source=path.join(__dirname,'../native/NativePetGeometry.cs');
   const hash=crypto.createHash('sha256').update(fs.readFileSync(source)).digest('hex').slice(0,16);
   const dir=path.join(this.data,'native-pet',hash),helper=path.join(dir,'NativePetGeometry.exe');fs.mkdirSync(dir,{recursive:true});
   if(!fs.existsSync(helper)){const compiler=path.join(process.env.WINDIR,'Microsoft.NET/Framework64/v4.0.30319/csc.exe');await run(compiler,['/nologo','/target:exe','/platform:x64','/r:System.Web.Extensions.dll','/r:System.Management.dll','/out:'+helper,source],{windowsHide:true,timeout:20000});}
   const child=spawn(helper,[],{windowsHide:true,stdio:['pipe','pipe','ignore']});this.child=child;let buffer='';
   child.stdout.setEncoding('utf8');child.stdout.on('data',chunk=>{buffer+=chunk;if(buffer.length>65536){buffer='';return}let at;while((at=buffer.indexOf('\n'))>=0){const line=buffer.slice(0,at);buffer=buffer.slice(at+1);const pending=this.pending;if(pending){this.pending=null;clearTimeout(pending.timer);try{pending.resolve(JSON.parse(line))}catch(error){pending.reject(error)}}}});
   const failed=()=>{if(this.child===child)this.child=null;if(this.pending){clearTimeout(this.pending.timer);this.pending.reject(Error('Native geometry reader disconnected.'));this.pending=null}};
   child.on('error',failed);child.on('exit',failed);child.stdin.on('error',failed);
  })();try{await this.preparing}finally{this.preparing=null}
 }
 async sample(installation,owners){
  if(!installation)return {status:'hidden',provider:'gpt-niang-widget',pets:[],reason:'No native widget integration configured.'};
  try{
   const config=read(installation),presence=read(path.join(config.dataDir,'presence.json')),settings=read(path.join(config.dataDir,'settings.json'));
   if(!Number.isFinite(presence.at)||Date.now()-presence.at>4000||presence.at>Date.now()+2000)return {status:'hidden',provider:'gpt-niang-widget',pets:[],reason:'Widget presence expired.'};
   if(!presence.visible)return {status:'hidden',provider:'gpt-niang-widget',pets:[]};
   if(!owners||owners.length!==1)throw Error('Native host ownership is not unique.');
   await this.start();if(this.pending)throw Error('Native reader is busy.');
   const snapshot=await new Promise((resolve,reject)=>{const timer=setTimeout(()=>{this.pending=null;reject(Error('Native geometry timed out.'))},2000);this.pending={resolve,reject,timer};this.child.stdin.write(JSON.stringify({pid:presence.pid,widget:presence.widget,host:presence.host,hostPid:owners[0],widgetScript:path.join(config.appDir,'widget.ps1')})+'\n')});
   return widgetPet(snapshot,presence,settings);
  }catch(error){return {status:'unavailable',provider:'gpt-niang-widget',pets:[],reason:error.message.slice(0,300)}}
 }
 stop(){this.child?.stdin.end();}
}
module.exports={NativePetProvider,widgetPet};
