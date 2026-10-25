function autoClearance(action,observation,preferences={}) {
 const pluginKey='__codexRightClearancePlugin';
 if(action==='restore'){delete window[pluginKey];return frameClearance('restore')}
 let active=window.__codexFrameClearanceV2;
 if(active){
  const r=active.target.getBoundingClientRect(),parent=active.target.parentElement,width=parent?.getBoundingClientRect().width??null,previous=window[pluginKey];
  const changed=!active.target.isConnected||r.width===0||r.height===0||innerWidth!==active.viewport[0]||innerHeight!==active.viewport[1]||
   (previous&&(previous.parent!==parent||Math.abs(previous.parentWidth-width)>1||Math.abs(previous.left-r.left)>1));
  if(changed){frameClearance('restore');delete window[pluginKey];active=null}
 }
 const current=active?active.target.getBoundingClientRect():null;
 const measurement=active?{status:'measured',rect:{...active.before,top:current.top,bottom:current.bottom,height:current.height},
  placement:innerHeight-current.bottom>=-1&&innerHeight-current.bottom<=Math.min(96,innerHeight*.15)?'bottom':'centered'}:frameClearance('measure');
 const plan=measurement.status==='measured'&&typeof codexPetClearancePlan==='function'?
  codexPetClearancePlan(measurement.rect,observation,codexViewportGeometry(),preferences):{reserve:96,requestedReserve:96,mode:'fallback'};
 const finish=(result,naturalHeightChangeCssPx=0)=>{
  const state=window.__codexFrameClearanceV2;
  if(state){const parent=state.target.parentElement;window[pluginKey]={parent,parentWidth:parent?.getBoundingClientRect().width??null,left:state.target.getBoundingClientRect().left}}
  else delete window[pluginKey];
  return {...result,status:state&&['applied','already-applied'].includes(result.status)?'active':result.status==='original'?'original':'waiting',
   geometryVerified:Boolean(state&&['applied','already-applied'].includes(result.status)),naturalHeightChangeCssPx,
   clearanceMode:plan.mode,requestedClearanceCssPx:plan.requestedReserve,petReason:plan.reason,overlappingPets:plan.overlappingPets??0};
 };
 if(active){
  if(measurement.placement==='centered'||plan.reserve!==(active.reserve??96)){
   frameClearance('restore');delete window[pluginKey];
  }else{
   const naturalHeightChangeCssPx=current.height-active.before.height;active.before.height=current.height;
   return finish(frameClearance('verify'),naturalHeightChangeCssPx);
  }
 }
 return finish(frameClearance('apply',{reserve:plan.reserve}));
}
