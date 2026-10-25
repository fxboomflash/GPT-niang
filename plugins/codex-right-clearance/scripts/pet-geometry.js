// Read only geometry from the dedicated pet document. No IPC or app lifecycle calls.
function codexViewportGeometry() {
 return {screenX,screenY,outerWidth,outerHeight,innerWidth,innerHeight,devicePixelRatio,
  visible:document.visibilityState!=='hidden',sampledAt:Date.now()};
}
function codexPetGeometry() {
 const url=new URL(location.href);
 if(url.protocol!=='app:'||url.hostname!=='-'||url.pathname!=='/index.html'||url.searchParams.get('initialRoute')!=='/avatar-overlay')return {status:'unavailable',reason:'Not a pet document.'};
 const viewport=codexViewportGeometry();
 if(!viewport.visible)return {status:'hidden',viewport,pets:[]};
 function visible(e){
  const r=e.getBoundingClientRect();if(r.width<2||r.height<2)return false;
  for(let p=e;p;p=p.parentElement){const s=getComputedStyle(p);if(s.display==='none'||s.visibility==='hidden'||s.visibility==='collapse'||Number(s.opacity)===0)return false}
  return r.right>0&&r.bottom>0&&r.left<innerWidth&&r.top<innerHeight;
 }
 const roots=[...document.querySelectorAll('.codex-avatar-root')];
 const pets=roots.filter(visible).slice(0,8).map(e=>{const r=e.getBoundingClientRect();return {left:Math.max(0,r.left),top:Math.max(0,r.top),right:Math.min(innerWidth,r.right),bottom:Math.min(innerHeight,r.bottom)}});
 return {status:pets.length?'visible':roots.length||document.querySelector('.codex-avatar-button')?'hidden':'unavailable',viewport,pets,
  reason:pets.length?null:'No visible recognized pet container.'};
}
// Window positions use screen coordinates; page zoom is derived separately from viewport width.
// The vertical inset also covers the native toolbar above an embedded Chat document.
function codexScreenTransform(viewport) {
 if(!viewport||![viewport.screenX,viewport.screenY,viewport.outerWidth,viewport.outerHeight,viewport.innerWidth,viewport.innerHeight].every(Number.isFinite)||viewport.innerWidth<=0||viewport.innerHeight<=0)return null;
 const difference=viewport.outerWidth-viewport.innerWidth;
 const scale=Math.abs(difference)<=4?1:viewport.outerWidth/viewport.innerWidth;
 if(scale<0.25||scale>4)return null;
 const border=Math.abs(difference)<=4?Math.max(0,difference/2):0;
 return {x:viewport.screenX+border,y:viewport.screenY+Math.max(0,viewport.outerHeight-viewport.innerHeight*scale-border),scale};
}
function codexPetClearancePlan(input,observation,viewport,preferences={}) {
 const padding=Number.isInteger(preferences.gapCssPx)&&preferences.gapCssPx>=0&&preferences.gapCssPx<=80?preferences.gapCssPx:10;
 if(preferences.mode==='manual'){
  const reserve=Number.isInteger(preferences.manualClearanceCssPx)&&preferences.manualClearanceCssPx>=0&&preferences.manualClearanceCssPx<=600?preferences.manualClearanceCssPx:96;
  return {reserve,requestedReserve:reserve,mode:'manual',reason:'User-selected bottom-input clearance.'};
 }
 const fallback={reserve:96,requestedReserve:96,mode:'fallback',reason:'Pet geometry unavailable; keeping the previous fixed clearance.'};
 if(Array.isArray(observation?.sources)){
  const plans=observation.sources.map(source=>codexPetClearancePlan(input,source,viewport,preferences));
  const reserve=Math.max(0,...plans.map(p=>p.reserve));
  return {reserve,requestedReserve:reserve,mode:plans.some(p=>p.mode==='fallback')?'fallback':'dynamic',overlappingPets:plans.reduce((n,p)=>n+(p.overlappingPets||0),0),
   reason:plans.filter(p=>p.reserve===reserve).map(p=>p.reason).join(' '),providers:observation.sources.map(p=>p.provider||'builtin-avatar')};
 }
 if(!observation||observation.status==='unavailable')return fallback;
 if(observation.status==='hidden')return {reserve:0,requestedReserve:0,mode:'dynamic',reason:'Pet is hidden or absent.'};
 if(observation.status!=='visible'||!Array.isArray(observation.pets))return fallback;
 let local=codexScreenTransform(viewport),petFrame=codexScreenTransform(observation.viewport);
 if(observation.coordinateSpace==='screen-physical'){
  const h=observation.hostClient,f=observation.hostFrame,dpi=observation.hostDpi/96;
  if(!h||!f||!Number.isFinite(dpi)||dpi<=0)return fallback;
  // Bind physical HWND geometry to this host before converting CSS pixels.
  // Native Chat and Work share the main document. Embedded Chat has the same width,
  // with its top inset derived from its shorter viewport.
  const owned=viewport.outerWidth===0||Math.abs(viewport.screenX-f.left/dpi)<=20&&Math.abs(viewport.screenY-f.top/dpi)<=20;
  if(!owned)return {reserve:0,requestedReserve:0,mode:'dynamic',reason:'Native widget belongs to another host window.'};
  const hostWidth=viewport.outerWidth||viewport.innerWidth,scale=h.width/hostWidth;
  const zoom=viewport.outerWidth>0?viewport.outerWidth/viewport.innerWidth:1;
  const cssScale=scale*zoom,top=h.bottom-viewport.innerHeight*cssScale;
  if(cssScale<0.25||cssScale>8||top<h.top-4||top>h.bottom)return fallback;
  local={x:h.left,y:Math.max(h.top,top),scale:cssScale};petFrame={x:0,y:0,scale:1};
 }
 if(!local||!petFrame)return fallback;
 const box={left:local.x+input.left*local.scale,top:local.y+input.top*local.scale,right:local.x+input.right*local.scale,bottom:local.y+input.bottom*local.scale};
 let reserve=0,overlaps=0,valid=0;
 for(const r of observation.pets){
  if(!r||![r.left,r.top,r.right,r.bottom].every(Number.isFinite)||r.right<=r.left||r.bottom<=r.top)continue;
  valid++;
  const pet={left:petFrame.x+r.left*petFrame.scale,top:petFrame.y+r.top*petFrame.scale,right:petFrame.x+r.right*petFrame.scale,bottom:petFrame.y+r.bottom*petFrame.scale};
  if(pet.bottom<=box.top||pet.top>=box.bottom||pet.right<=box.left||pet.left>=box.right)continue;
  overlaps++;reserve=Math.max(reserve,(box.right-pet.left)/local.scale+padding);
 }
 if(!valid)return fallback;
 // Two-pixel steps suppress subpixel movement without following individual sprite frames.
 reserve=Math.ceil(reserve/2)*2;
 return {reserve,requestedReserve:reserve,mode:'dynamic',overlappingPets:overlaps,paddingCssPx:padding,
  reason:overlaps?'Measured pet overlaps the bottom input.':'Pet does not overlap the bottom input.'};
}
