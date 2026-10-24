const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const root=path.join(__dirname,'..');
const {widgetPet}=require('../plugins/codex-right-clearance/scripts/native-pet.cjs');
function planner(){const context=vm.createContext({Number,Math,Date});vm.runInContext(fs.readFileSync(path.join(root,'plugins/codex-right-clearance/scripts/pet-geometry.js'),'utf8'),context);return context.codexPetClearancePlan;}
const snapshot={status:'visible',widget:{left:1000,top:600,width:472.5,height:472.5},hostClient:{left:200,top:30,right:1650,bottom:1072,width:1450,height:1042},hostFrame:{left:200,top:30,right:1650,bottom:1072},hostDpi:120};
const presence={sizing:{character:0.7,bubble:1},followHost:true};
const viewport={screenX:160,screenY:24,outerWidth:1160,outerHeight:834,innerWidth:1160,innerHeight:834};
const input={left:360,top:716,right:1100,bottom:814};
const external={...widgetPet(snapshot,presence,{side:'right'}),pets:[{left:1470,top:890,right:1650,bottom:1070}]};
test('the independent widget excludes its transparent canvas and follows character scale',()=>{
 const small=widgetPet(snapshot,presence,{side:'right'});assert.equal(small.pets[0].left,1273);assert.equal(small.pets[0].right-small.pets[0].left,182);
 const large=widgetPet({...snapshot,widget:{...snapshot.widget,left:811,width:661.5,height:661.5}},{...presence,sizing:{character:1.4,bubble:1}},{side:'right'});assert(large.pets[0].left<small.pets[0].left);
 assert.equal(widgetPet(snapshot,presence,{side:'left'}).pets[0].left,1017.5);
});
test('physical-screen coordinates reserve only the actual bottom overlap',()=>{
 const plan=planner();assert.equal(plan(input,external,viewport).reserve,94);
 assert.equal(plan(input,{...external,pets:[{left:1470,top:50,right:1650,bottom:200}]},viewport).reserve,0);
 assert.equal(plan(input,external,{...viewport,screenX:3000}).reserve,0);
 assert.equal(plan({left:288,top:572.8,right:880,bottom:651.2},external,{...viewport,innerWidth:928,innerHeight:667.2}).reserve,78);
 assert.equal(plan({left:360,top:700,right:1100,bottom:780},external,{...viewport,outerWidth:0,outerHeight:0,innerHeight:790}).reserve,94);
});
test('the visible independent widget is considered even if the builtin pet is absent',()=>{
 const plan=planner(),result=plan(input,{sources:[{status:'hidden',pets:[]},external]},viewport);
 assert.equal(result.reserve,94);assert.equal(result.overlappingPets,1);
 assert.equal(plan(input,{sources:[{status:'hidden',pets:[]},{status:'unavailable',pets:[]}]},viewport).reserve,96);
});
test('hidden, invalid and clipped widgets have bounded results',()=>{
 assert.equal(widgetPet({...snapshot,status:'hidden'},presence,{side:'right'}).status,'hidden');
 assert.equal(widgetPet(snapshot,{sizing:{character:NaN,bubble:1}},{side:'right'}).status,'unavailable');
 const result=widgetPet({...snapshot,hostFrame:{left:1000,top:600,right:1200,bottom:800}},presence,{side:'right'});assert.equal(result.status,'hidden');
});
test('native geometry reader has no window or process mutation calls',()=>{
 const source=fs.readFileSync(path.join(root,'plugins/codex-right-clearance/native/NativePetGeometry.cs'),'utf8');
 assert(!/SetWindowPos|ShowWindow|TerminateProcess|WriteProcessMemory|SendInput|CloseMainWindow/.test(source));
});
test('upstream credit and separate artwork license are retained',()=>{
 const notice=fs.readFileSync(path.join(root,'NOTICE.md'),'utf8');assert(notice.includes('T7moris'));assert(notice.includes('补充以及优化'));
 const license=fs.readFileSync(path.join(root,'vendor/GPT-Niang/LICENSE'),'utf8');assert(license.includes('Copyright (c) 2026 T7moris'));
 assert(fs.existsSync(path.join(root,'vendor/GPT-Niang/gpt-niang-usage/assets/CHARACTER-NOTICE.txt')));
});
