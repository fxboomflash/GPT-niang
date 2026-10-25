'use strict';
const fs = require('node:fs');
const path = require('node:path');
const net = require('node:net');
const crypto = require('node:crypto');
const {execFile} = require('node:child_process');
const {promisify} = require('node:util');
const runFile = promisify(execFile);
const {connect, trustedApp, trustedWork, trustedPage} = require('./cdp.cjs');
const {NativePetProvider}=require('./native-pet.cjs');
const homeAt=process.argv.indexOf('--home');
const configHome = fs.realpathSync(path.resolve(homeAt>=0 ? process.argv[homeAt+1] : process.env.CODEX_HOME || path.join(process.env.USERPROFILE, '.codex')));
process.env.CODEX_HOME=configHome;
const data = path.join(configHome,'plugin-data','codex-right-clearance-v3');
const settingsFile = path.join(data, 'settings.json');
const statusFile = path.join(data, 'status.json');
function debugPort(){const n=settings().debugPort??19327;if(!Number.isInteger(n)||n<19327||n>19426)throw Error('Invalid local debug port.');return n;}
const pluginId = 'codex-right-clearance@codex-ui-local';
fs.mkdirSync(data, {recursive:true});
function read(file, fallback) { try { return JSON.parse(fs.readFileSync(file, 'utf8').replace(/^\uFEFF/,'')); } catch { return fallback; } }
function write(file, value) {
  const temp = file + '.' + process.pid + '.tmp';
  fs.writeFileSync(temp, JSON.stringify(value, null, 2));
  fs.renameSync(temp, file);
}
function settings() { return {...read(settingsFile, {enabled:false}),autoRestart:false}; }
function validButtonPosition(value){return value===null||Boolean(value&&typeof value==='object'&&!Array.isArray(value)&&Object.keys(value).length===2&&Object.keys(value).every(key=>['xRatio','yRatio'].includes(key))&&[value.xRatio,value.yRatio].every(n=>Number.isFinite(n)&&n>=0&&n<=1));}
function preferences() {
  const value=settings();
  return {mode:value.mode==='manual'?'manual':'auto',gapCssPx:Number.isInteger(value.gapCssPx)&&value.gapCssPx>=0&&value.gapCssPx<=80?value.gapCssPx:10,manualClearanceCssPx:Number.isInteger(value.manualClearanceCssPx)&&value.manualClearanceCssPx>=0&&value.manualClearanceCssPx<=600?value.manualClearanceCssPx:96,buttonPosition:validButtonPosition(value.buttonPosition)?value.buttonPosition:null};
}
const preferenceSchema={type:'object',properties:{mode:{type:'string',enum:['auto','manual']},gapCssPx:{type:'integer',minimum:0,maximum:80},manualClearanceCssPx:{type:'integer',minimum:0,maximum:600},buttonPosition:{anyOf:[{type:'null'},{type:'object',properties:{xRatio:{type:'number',minimum:0,maximum:1},yRatio:{type:'number',minimum:0,maximum:1}},required:['xRatio','yRatio'],additionalProperties:false}]}},additionalProperties:false};
function savePreferences(value) {
  if(!value||typeof value!=='object'||Array.isArray(value))throw Error('Expected a settings object.');
  for(const [name,item]of Object.entries(value)){
    const rule=preferenceSchema.properties[name];
    if(!rule||rule.enum&&!rule.enum.includes(item)||rule.type==='integer'&&(!Number.isInteger(item)||item<rule.minimum||item>rule.maximum)||name==='buttonPosition'&&!validButtonPosition(item))throw Error('Invalid preference: '+name);
  }
  write(settingsFile,{...settings(),...value,autoRestart:false});
  const current=read(statusFile,{});
  if(!current.time||Date.now()-Date.parse(current.time)>15000||['stopped','disabled'].includes(current.status))startWatcher('settings-changed');
  return {status:'configured',preferences:preferences(),appliesOnNextTick:true,clientClosed:false};
}
function pluginEnabled() {
  try {
    const text = fs.readFileSync(path.join(configHome,'config.toml'),'utf8');
    const escaped = pluginId.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    const section = text.match(new RegExp('^\\[plugins\\."'+escaped+'"\\]\\s*\\r?\\n([\\s\\S]*?)(?=^\\[|$(?![\\s\\S]))','m'));
    return Boolean(section && /^enabled\s*=\s*true\s*(?:#.*)?$/m.test(section[1]));
  } catch { return false; }
}
function status() {
  const value = read(statusFile, {status:'not-started'});
  const registration=read(path.join(data,'startup-registration.json'),null);
  const pending=registration?.enabled===true&&value.connectionSetup?.state==='connection-unavailable'&&value.status!=='active'&&value.status!=='original-layout';
  return {...value,...pending?{status:'awaiting-manual-reopen',reason:'Local startup loader is registered. This already-running client has no connection; no automatic restart will be performed.'}:{}, enabled:settings().enabled === true, pluginEnabled:pluginEnabled(),
    heartbeatFresh:Boolean(value.time && Date.now() - Date.parse(value.time) < 15000),
    launcherRequired:false, debugPort:debugPort(), pluginVersion:'1.4.6',runtimeRevision:'dynamic-pet-7-attachment-reflow',automaticConnectionSetup:false,clientRestartAllowed:false,clearanceMode:preferences().mode,preferences:preferences(),fallbackClearanceCssPx:96,pollIntervalMs:300,startupRegistration:registration};
}
function startWatcher(reason='control') {
  if (!settings().enabled || !pluginEnabled()) return;
  fs.appendFileSync(path.join(data,'bootstrap-events.jsonl'),JSON.stringify({time:new Date().toISOString(),reason,pid:process.pid,pluginRoot:path.resolve(__dirname,'..'),version:'1.4.6'})+'\n');
  runFile('powershell.exe',['-NoLogo','-NoProfile','-ExecutionPolicy','RemoteSigned','-WindowStyle','Hidden','-File',path.join(__dirname,'Control.ps1'),'-Action','Bootstrap'],{windowsHide:true,timeout:20000,maxBuffer:16000}).catch(error=>write(statusFile,{time:new Date().toISOString(),status:'error',reason:'Independent worker startup failed: '+error.message}));
}
const geometrySource=fs.readFileSync(path.join(__dirname,'pet-geometry.js'),'utf8');
const source = geometrySource+'\n'+fs.readFileSync(path.join(__dirname,'layout.js'),'utf8') + '\n' + fs.readFileSync(path.join(__dirname,'auto-layout.js'),'utf8')+'\n'+fs.readFileSync(path.join(__dirname,'settings-button.js'),'utf8');
function trustedPet(value){try{const u=new URL(value);return u.protocol==='app:'&&u.hostname==='-'&&u.pathname==='/index.html'&&u.searchParams.get('initialRoute')==='/avatar-overlay'}catch{return false}}
function frameList(tree, result=[]) { if(tree?.frame)result.push(tree.frame); for(const child of tree?.childFrames || [])frameList(child,result); return result; }
const pause = ms => new Promise(resolve => setTimeout(resolve,ms));
async function validate(port) {
  const value = await runFile('powershell.exe',['-NoLogo','-NoProfile','-ExecutionPolicy','RemoteSigned','-File',path.join(__dirname,'validate-endpoint.ps1'),'-Port',String(port)],{windowsHide:true,timeout:12000,maxBuffer:16000});
  const result = JSON.parse(value.stdout.replace(/^\uFEFF/,''));
  if (!result.verified) throw Error('Endpoint ownership check failed.');
  return result;
}
async function watch() {
  const nativePet=new NativePetProvider(data);
  const pipe = '\\\\.\\pipe\\CodexRightClearance-' + crypto.createHash('sha256').update(data.toLowerCase()).digest('hex').slice(0,16);
  const guard = net.createServer(socket => socket.end());
  const acquired = await new Promise((resolve,reject) => {guard.once('error', e=>e.code==='EADDRINUSE'?resolve(false):reject(e));guard.listen(pipe,()=>resolve(true));});
  if (!acquired) return;
  const clients = new Map();
  let stopping = false, lastSeen = Date.now(), verifiedAt = 0, lastValidation = null, lastSetup=0, verifiedPort=null, lastConnectionSetup=null;
  let petObservation={status:'unavailable',pets:[]},lastPet=null,lastPetAt=0,lastReportAt=0,lastReportSignature='',lastSettingsOpen=0;
  process.on('SIGTERM',()=>{stopping=true;}); process.on('SIGINT',()=>{stopping=true;});
  const report = value => {
    const signature=JSON.stringify([value.status,value.reason,value.results?.map(r=>[r.status,r.clearanceCssPx,r.requestedClearanceCssPx,r.placement,r.petReason])]);
    if(signature===lastReportSignature&&Date.now()-lastReportAt<1500)return;
    lastReportAt=Date.now();lastReportSignature=signature;
    write(statusFile,{time:new Date().toISOString(),pid:process.pid,connectionSetup:lastConnectionSetup,...value});
  };
  async function evaluate(client, action) {
    const frames = frameList((await client.command('Page.getFrameTree')).frameTree).filter(f => trustedPage(f.url));
    const results=[];
    for(const frame of frames) {
      const contexts=[...client.contexts.values()].filter(c=>c.auxData?.isDefault===true && c.auxData.frameId===frame.id);
      if(contexts.length!==1)continue;
      const options=JSON.stringify(preferences());
      const output=await client.command('Runtime.evaluate',{expression:source+'\n(()=>{const result=autoClearance('+JSON.stringify(action)+','+JSON.stringify(petObservation)+','+options+');return {...result,settingsButton:codexClearanceSettingsButton('+JSON.stringify(action)+','+options+')}})();',contextId:contexts[0].id,returnByValue:true});
      if(output.exceptionDetails)throw Error('Layout evaluation failed: '+(output.exceptionDetails.exception?.description||output.exceptionDetails.text));
      const result=output.result?.value;
      if(result?.settingsButton?.positionChanged&&validButtonPosition(result.settingsButton.positionChanged))savePreferences({buttonPosition:result.settingsButton.positionChanged});
      if(result?.settingsButton?.requestOpen===true&&Date.now()-lastSettingsOpen>=1000){
        lastSettingsOpen=Date.now();
        control('open_settings').catch(error=>fs.appendFileSync(path.join(data,'bootstrap-events.jsonl'),JSON.stringify({time:new Date().toISOString(),reason:'settings-open-failed',message:error.message.slice(0,500)})+'\n'));
      }
      if(result?.status==='active' && !(result.geometryVerified===true&&Number.isFinite(result.requestedClearanceCssPx)&&result.requestedClearanceCssPx>0&&Math.abs(result.clearanceCssPx-result.requestedClearanceCssPx)<=1&&Math.abs(result.leftShiftCssPx)<=1&&Math.abs(result.bottomShiftCssPx??0)<=1&&(Math.abs(result.heightChangeCssPx)<=1||result.naturalHeightReflowVerified===true)&&result.domButtonsUncovered===true))throw Error('Active input geometry did not pass verification.');
      results.push(result);
    }
    return results;
  }
  async function restoreAll() { for(const client of clients.values()) {try{await evaluate(client,'restore');}catch{}} }
  try {
    while(!stopping) {
      let nextDelay=300;
      if(!settings().enabled || !pluginEnabled()) {await restoreAll();report({status:'disabled',restored:true});return;}
      try {
        const port=debugPort(),endpoint='http://127.0.0.1:'+port;
        if(verifiedPort!==port){await restoreAll();for(const client of clients.values())client.close();clients.clear();verifiedAt=0;}
        const response=await fetch(endpoint+'/json/list',{signal:AbortSignal.timeout(2500)});
        if(!response.ok)throw Error('Codex debug endpoint unavailable.');
        const targets=await response.json(); lastSeen=Date.now();
        if(Date.now()-verifiedAt>30000) {lastValidation=await validate(port);verifiedPort=port;verifiedAt=Date.now();}
        const eligible=targets.slice(0,24).filter(t=>(['page','webview','other'].includes(t.type)&&trustedApp(t.url)||t.type==='webview'&&trustedWork(t.url))&&t.webSocketDebuggerUrl);
        const petTargets=targets.slice(0,24).filter(t=>t.type==='page'&&trustedPet(t.url)&&t.webSocketDebuggerUrl);
        const ids=new Set([...eligible,...petTargets].map(t=>t.id));
        for(const [id,client] of clients)if(!ids.has(id)){client.close();clients.delete(id);}
        async function clientFor(target){let client=clients.get(target.id);if(!client){client=await connect(target.webSocketDebuggerUrl,port);await client.command('Runtime.enable');clients.set(target.id,client)}return client}
        if(petTargets.length===0){petObservation={status:'hidden',pets:[],reason:'No pet overlay target.'};lastPet=null}
        else if(petTargets.length!==1){petObservation={status:'unavailable',pets:[],reason:'Pet overlay selection was not unique.'}}
        else{
          try{
            const petClient=await clientFor(petTargets[0]);
            const output=await petClient.command('Runtime.evaluate',{expression:geometrySource+'\ncodexPetGeometry();',returnByValue:true});
            if(output.exceptionDetails||!output.result?.value)throw Error('Pet measurement failed.');
            petObservation=output.result.value;
            if(['visible','hidden'].includes(petObservation.status)){lastPet=petObservation;lastPetAt=Date.now()}
          }catch(error){
            clients.get(petTargets[0].id)?.close();clients.delete(petTargets[0].id);
            petObservation=lastPet&&Date.now()-lastPetAt<=1500?{...lastPet,cached:true}:{status:'unavailable',pets:[],reason:'Pet measurement temporarily unavailable.'};
          }
        }
        const nativeObservation=await nativePet.sample(settings().nativePetInstallation,lastValidation.ownerPids);
        petObservation={status:[petObservation,nativeObservation].some(p=>p.status==='visible')?'visible':[petObservation,nativeObservation].some(p=>p.status==='unavailable')?'unavailable':'hidden',sources:[petObservation,nativeObservation]};
        const results=[];
        for(const target of eligible) {
          try {
            const client=await clientFor(target);
            results.push(...await evaluate(client,'tick'));
          } catch(error) {clients.get(target.id)?.close();clients.delete(target.id);results.push({status:'error',reason:error.message.slice(0,1000)});}
        }
        report({status:results.some(x=>x?.status==='error')?'error':results.some(x=>x?.status==='active')?'active':results.some(x=>x?.status==='original')?'original-layout':'waiting-for-chat',activeInputs:results.filter(x=>x?.status==='active').length,version:lastValidation.version,debugPort:port,runtimeRevision:'dynamic-pet-7-attachment-reflow',pluginVersion:'1.4.6',clientRestartAllowed:false,pollIntervalMs:300,petMeasurement:petObservation,results});
      } catch(error) {
        nextDelay=2500;
        await restoreAll(); for(const client of clients.values())client.close();clients.clear(); verifiedAt=0;
        report({status:'waiting-for-codex',reason:error.message.includes('Command failed')?'Verified Codex debug connection unavailable.':error.message});
        if(Date.now()-lastSetup>30000){
          lastSetup=Date.now();
          try{
            const setup=await runFile('powershell.exe',['-NoLogo','-NoProfile','-ExecutionPolicy','RemoteSigned','-WindowStyle','Hidden','-File',path.join(__dirname,'ensure-connection.ps1')],{windowsHide:true,timeout:20000,maxBuffer:16000});
            const connection=JSON.parse(setup.stdout.replace(/^\uFEFF/,''));
            lastConnectionSetup=connection;
            report({status:'waiting-for-connection',connection,clientRestartAllowed:false});
          }catch(setupError){lastConnectionSetup={state:'unavailable',reason:setupError.message.slice(0,1200)};report({status:'waiting-for-connection',reason:'Connection detection failed; client left running.',clientRestartAllowed:false});}
        }
        // Wait briefly for a cold launch. Exit after Codex closes; no Windows login service.
        if(Date.now()-lastSeen>180000)return;
      }
      await pause(nextDelay);
    }
    await restoreAll(); report({status:'stopped',restored:true});
  } finally {nativePet.stop();for(const client of clients.values())client.close();guard.close();}
}
async function control(action,params={}) {
  if(action==='status')return status();
  if(action==='configure')return savePreferences(params);
  if(action==='open_settings'){
    const result=await runFile('powershell.exe',['-NoLogo','-NoProfile','-STA','-ExecutionPolicy','RemoteSigned','-WindowStyle','Hidden','-File',path.join(__dirname,'Settings.ps1'),'-HomeDirectory',configHome,'-NodePath',process.execPath,'-Launch'],{windowsHide:true,timeout:12000,maxBuffer:16000});
    return JSON.parse(result.stdout.replace(/^\uFEFF/,''));
  }
  if(action==='disable') {write(settingsFile,{...settings(),enabled:false});let startupRemoved=false;try{await runFile('powershell.exe',['-NoLogo','-NoProfile','-ExecutionPolicy','RemoteSigned','-WindowStyle','Hidden','-File',path.join(__dirname,'RegisterStartup.ps1'),'-Action','Remove'],{windowsHide:true,timeout:15000,maxBuffer:16000});startupRemoved=true;}catch{}return {status:'disabling',restoresOnNextTick:true,startupRemoved};}
  if(action==='enable') {write(settingsFile,{...settings(),enabled:true});startWatcher();return {status:'enabled',launcherRequired:false,clientClosed:false};}
  if(action==='reapply') {startWatcher();return status();}
  throw Error('Unknown operation.');
}
function serve() {
  const readline = require('node:readline').createInterface({input:process.stdin});
  const names=['status','enable','disable','reapply','configure','open_settings'];
  const descriptions={status:'Read the local right-clearance plugin status.',enable:'Enable bottom-input clearance based on the measured pet position and size.',disable:'Disable right clearance and restore the input box.',reapply:'Start or reconnect the automatic clearance worker.',configure:'Set automatic pet clearance with adjustable extra gap, or a manual bottom-input clearance in CSS pixels. Centered inputs stay unchanged.',open_settings:'Open the local clearance settings window so the user can adjust sliders without restarting the client.'};
  readline.on('line',async line=>{
    let request;
    try {
      if(line.length>1048576)throw Error('Request too large.');
      request=JSON.parse(line);if(request.id===undefined)return;
      let result;
      if(request.method==='initialize') {result={protocolVersion:request.params?.protocolVersion || '2024-11-05',capabilities:{tools:{}},serverInfo:{name:'codex-right-clearance',version:'1.4.6'}};startWatcher('mcp-initialize');}
      else if(request.method==='ping')result={};
      else if(request.method==='tools/list')result={tools:names.map(name=>({name,description:descriptions[name],inputSchema:name==='configure'?preferenceSchema:{type:'object',properties:{},additionalProperties:false},annotations:{readOnlyHint:name==='status',destructiveHint:false,openWorldHint:false}}))};
      else if(request.method==='tools/call') {if(!names.includes(request.params?.name))throw Error('Unknown tool.');result={content:[{type:'text',text:JSON.stringify(await control(request.params.name,request.params.arguments??{}))}]};}
      else {process.stdout.write(JSON.stringify({jsonrpc:'2.0',id:request.id,error:{code:-32601,message:'Method not found'}})+'\n');return;}
      process.stdout.write(JSON.stringify({jsonrpc:'2.0',id:request.id,result})+'\n');
    } catch(error) {if(request?.id!==undefined)process.stdout.write(JSON.stringify({jsonrpc:'2.0',id:request.id,error:{code:-32602,message:error.message}})+'\n');}
  });
}
module.exports={status,pluginEnabled,control};
if(require.main===module) {
  const action=process.argv[2]||'status';
  const settingsAt=process.argv.indexOf('--settings-base64');
  const params=settingsAt>=0?JSON.parse(Buffer.from(process.argv[settingsAt+1],'base64').toString('utf8')):{};
  (action==='serve'?Promise.resolve(serve()):action==='watch'?watch():control(action,params).then(value=>console.log(JSON.stringify(value,null,2))))
    .catch(error=>{console.error(error.message);process.exitCode=1;});
}
