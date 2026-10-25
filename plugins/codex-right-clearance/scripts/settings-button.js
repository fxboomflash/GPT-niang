// A visible entry point owned by this plugin; it never changes the composer tree.
function codexClearanceSettingsButton(action='tick',preferences={}) {
 const key='__codexClearanceSettingsButtonV1';
 let state=window[key];
 if(action==='restore'){
  state?.button.remove();state?.style.remove();delete window[key];
  return {visible:false};
 }
 const trees=[document,...[...(window.__codexClearanceShadowIndexV1?.trees.keys()||[])].filter(tree=>tree!==document&&tree.host?.isConnected)];
 const surfaces=[...new Set(trees.flatMap(tree=>[...tree.querySelectorAll('[data-composer-surface-variant]')]))].filter(element=>{
  const rect=element.getBoundingClientRect();return rect.width>0&&rect.height>0&&element.querySelector('[contenteditable="true"],[contenteditable="plaintext-only"],textarea');
 });
 const candidates=surfaces.filter(element=>!surfaces.some(parent=>parent!==element&&parent.contains(element)));
 if(document.visibilityState==='hidden'||candidates.length!==1||innerWidth<360){
  if(state)state.button.hidden=true;
  return {visible:false};
 }
 if(!state||!state.button.isConnected){
  state?.button.remove();state?.style.remove();
  const button=document.createElement('button'),style=document.createElement('style');
  button.type='button';button.id='codex-clearance-settings-button';button.textContent='⚙ 避让设置';
  button.setAttribute('aria-label','避让设置');button.title='点击调整间距 · 拖动更换位置并自动保存';
  style.textContent='#codex-clearance-settings-button{all:initial;position:fixed;z-index:2147483000;box-sizing:border-box;display:inline-flex;align-items:center;justify-content:center;width:104px;height:28px;padding:0 10px;border:1px solid #a9bcdc;border-radius:8px;background:light-dark(#f5f8ff,#273246);color:light-dark(#315582,#dae7ff);color-scheme:light dark;font:12px/1.2 system-ui,"Microsoft YaHei UI",sans-serif;cursor:pointer;box-shadow:0 2px 6px #00000012;white-space:nowrap}#codex-clearance-settings-button:hover{border-color:#6696dc;filter:brightness(.97)}#codex-clearance-settings-button:focus-visible{outline:2px solid #4d8bf5;outline-offset:2px}#codex-clearance-settings-button[hidden]{display:none}';
  state={button,style,pendingOpen:false,pendingPosition:null,position:null,savedPositionSignature:null,drag:null,suppressClick:false};window[key]=state;
  button.style.cursor='grab';button.style.touchAction='none';button.style.userSelect='none';
  function move(left,top){
   const width=Math.max(1,innerWidth-128),height=Math.max(1,innerHeight-52);
   left=Math.max(12,Math.min(innerWidth-116,left));top=Math.max(12,Math.min(innerHeight-40,top));
   state.position={xRatio:(left-12)/width,yRatio:(top-12)/height};
   button.style.left=left+'px';button.style.top=top+'px';
  }
  button.addEventListener('pointerdown',event=>{
   if(!event.isTrusted||event.button!==0)return;
   const rect=button.getBoundingClientRect();
   state.drag={id:event.pointerId,x:event.clientX,y:event.clientY,left:rect.left,top:rect.top,moved:false,previous:state.position};
   button.setPointerCapture(event.pointerId);
  });
  button.addEventListener('pointermove',event=>{
   const drag=state.drag;if(!drag||drag.id!==event.pointerId)return;
   const dx=event.clientX-drag.x,dy=event.clientY-drag.y;
   if(Math.hypot(dx,dy)>4)drag.moved=true;
   if(drag.moved){button.style.cursor='grabbing';move(drag.left+dx,drag.top+dy)}
  });
  button.addEventListener('pointerup',event=>{
   const drag=state.drag;if(!drag||drag.id!==event.pointerId)return;
   if(drag.moved){state.pendingPosition={...state.position};state.suppressClick=true;setTimeout(()=>{state.suppressClick=false},0)}
   state.drag=null;button.style.cursor='grab';
   if(button.hasPointerCapture(event.pointerId))button.releasePointerCapture(event.pointerId);
  });
  button.addEventListener('pointercancel',()=>{if(state.drag)state.position=state.drag.previous;state.drag=null;button.style.cursor='grab'});
  button.addEventListener('click',event=>{if(event.isTrusted&&!state.suppressClick)state.pendingOpen=true});
  document.head.append(style);document.body.append(button);
 }
 const saved=preferences.buttonPosition;
 const position=saved&&Number.isFinite(saved.xRatio)&&Number.isFinite(saved.yRatio)&&saved.xRatio>=0&&saved.xRatio<=1&&saved.yRatio>=0&&saved.yRatio<=1?{xRatio:saved.xRatio,yRatio:saved.yRatio}:null;
 const signature=JSON.stringify(position);
 if(!state.drag&&signature!==state.savedPositionSignature){state.position=position;state.savedPositionSignature=signature}
 state.button.hidden=false;
 if(!state.drag){
  state.button.style.left=(state.position?12+state.position.xRatio*Math.max(1,innerWidth-128):Math.max(12,innerWidth-116))+'px';
  state.button.style.top=(state.position?12+state.position.yRatio*Math.max(1,innerHeight-52):Math.max(12,Math.min(innerHeight-40,100)))+'px';
 }
 const requestOpen=state.pendingOpen;state.pendingOpen=false;
 const positionChanged=state.pendingPosition;state.pendingPosition=null;
 return {visible:true,label:'避让设置',requestOpen,positionChanged};
}
