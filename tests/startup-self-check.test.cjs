'use strict';
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const {runSelfCheck,inspect,INTERVAL_MS,key}=require('../plugins/codex-right-clearance/scripts/startup-self-check.cjs');
const origin=Date.UTC(2030,0,1),session={pid:424240,startedAt:new Date(origin).toISOString()};
const clone=value=>value==null?value:JSON.parse(JSON.stringify(value));
const validResult={status:'active',pageVisible:true,placement:'bottom',geometryVerified:true,clearanceCssPx:80,requestedClearanceCssPx:80,inputWidthCssPx:656,leftShiftCssPx:0,bottomShiftCssPx:0,heightChangeCssPx:16,naturalHeightReflowVerified:true,domButtonsUncovered:true};
const cases=[];
async function scenario(name,options={}){
 let now=origin+(options.nowOffset??0),cycle=0,detectCalls=0,repairs=0,isEnabled=true,saved=clone(options.saved??null),writes=0;
 const waits=[],released=[],acquired=[],states=[];
 const inputSession=options.session??session;
 const deps={
  now:()=>now,enabled:()=>isEnabled,
  async detect(){detectCalls++;const supplied=options.detect?.({cycle,detectCalls,now});if(supplied instanceof Error)throw supplied;return supplied??{state:'connected',...inputSession};},
  readWorker(){
   const standard={time:new Date(now).toISOString(),pid:424241,hostSession:inputSession,connectionSetup:{state:'connected'},status:'active',results:[clone(validResult)]};
   return options.worker?.({cycle,now,standard})??standard;
  },
  readState:()=>clone(saved),saveState(value){saved=clone(value);writes++;states.push(clone(value));},
  async startWorker(){repairs++;},
  async acquire(leaseKey){acquired.push(leaseKey);if(options.duplicate&&leaseKey!=='client-discovery')return null;return async()=>released.push(leaseKey);},
  async wait(ms){assert(ms>0&&ms<=60000);waits.push(ms);assert(waits.length<15,'Self-check did not stop in a bounded fixture');now+=ms;cycle++;if(options.disableAt===cycle)isEnabled=false;if(options.supersedeAt===cycle)saved={state:'completed',session:{pid:525250,startedAt:new Date(now).toISOString()},evidence:{geometryVerified:true,clearanceCssPx:80},marker:'new-session'};}
 };
 const result=await runSelfCheck(deps);
 if(!options.duplicate){assert(released.includes(key(inputSession)),'Session singleton was not released');}
 assert(released.includes('client-discovery'),'Discovery singleton was not released');
 options.verify?.({result,saved,writes,waits,repairs,states,detectCalls,now});
 if(result.state==='completed'){
  assert.equal(result.running,false);assert.equal(result.nextCheckAt,null);assert(result.evidence.clearanceCssPx>=1);
  assert.equal(result.clientRestartAllowed,false);
 }
 cases.push({name,passed:true,state:result.state,checkCount:result.checkCount??0,waitsMs:waits,workerRecoveryRequests:repairs,clientActions:0});
 return {result,saved,writes,waits,repairs,states,detectCalls,now};
}
(async()=>{
 assert.equal(INTERVAL_MS,60000);
 const pending=({standard})=>({...standard,status:'original-layout',results:[{status:'original',placement:'centered',requestedClearanceCssPx:0}]});
 await scenario('one-minute-cadence-until-actual-shrink',{worker:args=>args.cycle===1?pending(args):args.standard,verify:({result,waits})=>{assert.equal(result.checkCount,2);assert.deepEqual(waits,[60000,60000]);}});
 await scenario('hidden-pet-does-not-complete-check',{worker:args=>args.cycle<3?{...pending(args),results:[{status:'original',placement:'bottom',requestedClearanceCssPx:0}]}:args.standard,verify:({result})=>assert.equal(result.checkCount,3)});
 await scenario('disconnected-then-connected',{detect:({cycle})=>({state:cycle<4?'connection-unavailable':'connected',...session}),verify:({result,repairs,waits})=>{assert.equal(result.checkCount,4);assert.equal(repairs,3);assert.deepEqual(waits,[60000,60000,60000,60000]);}});
 await scenario('missing-startup-connection-keeps-minute-check-without-pointless-worker-starts',{detect:({cycle})=>({state:cycle<4?'connection-unavailable':'connected',requiresClientReopen:cycle<4,...session}),verify:({result,repairs,waits,states})=>{assert.equal(result.checkCount,4);assert.equal(repairs,0);assert.deepEqual(waits,[60000,60000,60000,60000]);assert(states.some(s=>s.lastReason==='startup-connection-missing'));}});
 await scenario('stale-worker-is-recovered',{worker:({cycle,now,standard})=>cycle<3?{...standard,time:new Date(now-60000).toISOString()}:standard,verify:({result,repairs})=>{assert.equal(result.checkCount,3);assert.equal(repairs,2);}});
 await scenario('background-page-does-not-complete-check',{worker:({cycle,standard})=>cycle===1?{...standard,results:[{...validResult,pageVisible:false}]}:standard,verify:({result})=>assert.equal(result.checkCount,2)});
 await scenario('different-host-observation-rejected',{worker:({cycle,standard})=>cycle===1?{...standard,hostSession:{...session,pid:414141}}:standard,verify:({result})=>assert.equal(result.checkCount,2)});
 await scenario('covered-buttons-do-not-complete-check',{worker:({cycle,standard})=>cycle===1?{...standard,results:[{...validResult,domButtonsUncovered:false}]}:standard,verify:({result})=>assert.equal(result.checkCount,2)});
 await scenario('zero-pixels-do-not-complete-check',{worker:({cycle,standard})=>cycle===1?{...standard,results:[{...validResult,clearanceCssPx:0,requestedClearanceCssPx:0}]}:standard,verify:({result})=>assert.equal(result.checkCount,2)});
 await scenario('fractional-layout-noise-does-not-complete-check',{worker:({cycle,standard})=>cycle===1?{...standard,results:[{...validResult,clearanceCssPx:.5,requestedClearanceCssPx:.5}]}:standard,verify:({result})=>assert.equal(result.checkCount,2)});
 await scenario('insufficient-editor-width-rejected',{worker:({cycle,standard})=>cycle===1?{...standard,results:[{...validResult,inputWidthCssPx:350}]}:standard,verify:({result})=>assert.equal(result.checkCount,2)});
 const complete=(await scenario('first-minute-success')).saved;
 await scenario('completed-check-does-not-restart-in-same-session',{saved:complete,verify:({result,writes,waits})=>{assert.equal(result.state,'completed');assert.equal(writes,0);assert.deepEqual(waits,[]);}});
 await scenario('new-process-rearms-check',{saved:complete,session:{pid:525250,startedAt:session.startedAt},verify:({result,waits})=>{assert.equal(result.checkCount,1);assert.deepEqual(waits,[60000]);}});
 await scenario('reused-pid-rearms-check',{saved:complete,nowOffset:1000,session:{pid:session.pid,startedAt:new Date(origin+1000).toISOString()},verify:({result,waits})=>{assert.equal(result.checkCount,1);assert.deepEqual(waits,[60000]);}});
 await scenario('client-closed-cancels-without-success',{detect:({cycle})=>cycle>=1?{state:'not-running'}:undefined,verify:({result,repairs})=>{assert.equal(result.state,'client-closed');assert.equal(result.checkCount,0);assert.equal(repairs,0);}});
 await scenario('plugin-disabled-cancels-without-success',{disableAt:1,verify:({result,repairs})=>{assert.equal(result.state,'paused');assert.equal(result.checkCount,0);assert.equal(repairs,0);}});
 await scenario('detection-error-retries-next-minute',{detect:({cycle})=>cycle===1?new Error('Fixture detection temporarily unavailable'):undefined,verify:({result,waits})=>{assert.equal(result.checkCount,2);assert.deepEqual(waits,[60000,60000]);}});
 await scenario('initial-detection-error-is-retried',{detect:({detectCalls})=>detectCalls===1?new Error('Fixture initial identity lookup unavailable'):undefined,verify:({result,waits})=>{assert.equal(result.checkCount,1);assert.deepEqual(waits,[60000]);}});
 await scenario('duplicate-process-does-not-run-checks',{duplicate:true,verify:({result,writes,waits})=>{assert.equal(result.state,'duplicate-checker');assert.equal(writes,0);assert.equal(waits.length,0);}});
 await scenario('old-checker-does-not-overwrite-new-session',{supersedeAt:1,detect:({cycle,now})=>cycle>=1?{state:'connected',pid:525250,startedAt:new Date(now).toISOString()}:undefined,verify:({saved})=>assert.equal(saved.marker,'new-session')});
 await scenario('install-during-open-session-checks-current-layout',{nowOffset:7*60000,verify:({result,waits})=>{assert.equal(result.checkCount,1);assert.deepEqual(waits,[]);}});
 await scenario('worker-reload-preserves-next-minute-deadline',{nowOffset:90000,saved:{schemaVersion:1,state:'waiting',session,checkCount:5,nextCheckAt:new Date(origin+120000).toISOString()},verify:({result,waits})=>{assert.equal(result.checkCount,6);assert.deepEqual(waits,[30000]);}});
 assert.equal(inspect({hostSession:null},null,origin).passed,false);
 const checkerSource=fs.readFileSync(path.join(__dirname,'../plugins/codex-right-clearance/scripts/startup-self-check.cjs'),'utf8');
 assert(!/\b(?:Stop-Process|taskkill|CloseMainWindow|Restart-Computer|TerminateProcess)\b/.test(checkerSource));
 assert(checkerSource.includes("'-Action','BootstrapWorker'"),'Recovery must only request the layout worker');
 const report={time:new Date().toISOString(),passed:true,productionSelfCheckLoopExecuted:true,intervalMs:60000,realClientTouched:false,clientRestarted:false,cases};

 console.log(JSON.stringify({passed:true,caseCount:cases.length,intervalMs:60000,clientActions:0}));
})().catch(error=>{console.error(error.stack);process.exitCode=1;});
