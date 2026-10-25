function frameClearance(action='apply',options={}) {
 const key='__codexFrameClearanceV2',reserve=Number.isFinite(options.reserve)?Math.max(0,options.reserve):96,minWidth=360;
 function rect(e){const r=e.getBoundingClientRect();return{left:r.left,right:r.right,top:r.top,bottom:r.bottom,width:r.width,height:r.height}}
 function visible(e){const r=e.getBoundingClientRect();return r.width>0&&r.height>0}
 function bottomDocked(e){const r=e.getBoundingClientRect(),gap=innerHeight-r.bottom;return gap>=-1&&gap<=Math.min(96,innerHeight*.15)}
 function queryDeep(root,selector){
  // Query semantic markers directly, regardless of conversation length. Discover
  // shadow trees incrementally and inspect only newly added subtrees afterwards.
  const cacheKey='__codexClearanceShadowIndexV1';
  let index=window[cacheKey];
  if(!index){
   index={trees:new Map(),queue:[],queued:new Set(),visited:0};
   index.enqueue=node=>{if(node.nodeType!==1&&node.nodeType!==9&&node.nodeType!==11)return;if(!index.queued.has(node)){index.queued.add(node);index.queue.push({root:node,walker:null})}};
   index.observe=tree=>{if(index.trees.has(tree))return;const observer=new MutationObserver(records=>{for(const record of records)for(const node of record.addedNodes)index.enqueue(node)});observer.observe(tree,{childList:true,subtree:true});index.trees.set(tree,observer);index.enqueue(tree)};
   index.observe(document);window[cacheKey]=index;
  }
  for(const [tree,observer]of index.trees)if(tree!==document&&!tree.host.isConnected){observer.disconnect();index.trees.delete(tree)}
  // A large transcript never throws or blocks composer lookup. Pending shadow
  // discovery resumes on the next call instead of rescanning the entire page.
  let budget=1000;
  while(index.queue.length&&budget>0){
   const task=index.queue[0];
   if(!task.root.isConnected){index.queue.shift();index.queued.delete(task.root);continue}
   let element;
   if(!task.walker){task.walker=document.createTreeWalker(task.root,NodeFilter.SHOW_ELEMENT);element=task.root.nodeType===1?task.root:task.walker.nextNode()}
   else element=task.walker.nextNode();
   if(!element){index.queue.shift();index.queued.delete(task.root);continue}
   budget--;index.visited++;
   if(element.shadowRoot)index.observe(element.shadowRoot);
  }
  const found=[...root.querySelectorAll(selector)];
  for(const tree of index.trees.keys())if(tree!==root&&tree!==document&&(root===document||contains(root,tree.host)))found.push(...tree.querySelectorAll(selector));
  return found;
 }
 function contains(root,child){for(let e=child;e;){if(e===root)return true;e=e.parentElement||e.getRootNode()?.host}return false}
 function restore(){const s=window[key];if(!s)return{status:'not-needed'};s.style.remove();s.previous===null?s.target.removeAttribute('data-codex-clearance-v2'):s.target.setAttribute('data-codex-clearance-v2',s.previous);delete window[key];return{status:'restored'}}
 function verify(){
  const s=window[key];if(!s)return{status:'not-applied'};
  if(!s.target.isConnected){restore();return{status:'restored',reason:'Input was recreated.'}}
  if(!bottomDocked(s.target)){restore();return{status:'original',placement:'centered',reason:'Centered input keeps its original layout.'}}
  const after=rect(s.target);
  const result={status:'applied',clearanceCssPx:s.before.right-after.right,leftShiftCssPx:after.left-s.before.left,inputWidthCssPx:after.width,heightChangeCssPx:after.height-s.before.height,bottomShiftCssPx:after.bottom-s.before.bottom};
  // Width changes may naturally wrap attachment labels or editor text. Preserve
  // the bottom anchor instead of treating that intrinsic height as a failure.
  result.naturalHeightReflowVerified=Math.abs(result.heightChangeCssPx)>1&&Math.abs(result.bottomShiftCssPx)<=1;
  if(innerWidth!==s.viewport[0]||innerHeight!==s.viewport[1]||Math.abs(result.leftShiftCssPx)>1||Math.abs(result.clearanceCssPx-(s.reserve??96))>1||after.width<minWidth||Math.abs(result.bottomShiftCssPx)>1){restore();return{status:'restored',reason:'Layout changed outside the approved dimensions.',measured:result}}
  // Attachment close buttons exist in the DOM while intentionally transparent
  // and non-interactive. They must not fail the composer hit-test guard.
  function interactive(button){
   if(!visible(button))return false;
   const style=getComputedStyle(button);
   if(style.visibility==='hidden'||style.visibility==='collapse'||style.pointerEvents==='none')return false;
   for(let e=button;e;e=e.parentElement||e.getRootNode()?.host){const style=getComputedStyle(e);if(style.display==='none'||Number(style.opacity)===0)return false}
   return true;
  }
  // Offscreen cards in an attachment carousel are intentionally clipped by an
  // inner scroll area. Keep checking all toolbar buttons and visible cards.
  function clippedByInnerScroll(button){
   const r=button.getBoundingClientRect();
   for(let e=button.parentElement||button.getRootNode()?.host;e&&e!==s.target;e=e.parentElement||e.getRootNode()?.host){
    const style=getComputedStyle(e),box=e.getBoundingClientRect();
    if(['auto','scroll','hidden','clip'].includes(style.overflowX)&&e.scrollWidth>e.clientWidth+1&&(r.left<box.left-1||r.right>box.right+1))return true;
    if(['auto','scroll','hidden','clip'].includes(style.overflowY)&&e.scrollHeight>e.clientHeight+1&&(r.top<box.top-1||r.bottom>box.bottom+1))return true;
   }
   return false;
  }
  const interactiveButtons=queryDeep(s.target,'button').filter(interactive);
  const buttons=interactiveButtons.filter(button=>!clippedByInnerScroll(button));
  let blocked=0;
  for(const button of buttons){const r=button.getBoundingClientRect();let tree=button.getRootNode();const hit=typeof tree.elementFromPoint==='function'?tree.elementFromPoint(r.left+r.width/2,r.top+r.height/2):document.elementFromPoint(r.left+r.width/2,r.top+r.height/2);if(r.left<after.left-1||r.right>after.right+1||!hit||!contains(button,hit))blocked++}
  if(blocked){restore();return{status:'restored',reason:'A button was clipped or covered inside the page.',blockedButtons:blocked}}
  return{...result,visibleButtons:buttons.length,scrollClippedButtons:interactiveButtons.length-buttons.length,domButtonsUncovered:true,petOverlayVisuallyVerified:false};
 }
 if(action==='restore')return restore();
 if(action==='verify')return verify();
 if(!['apply','measure'].includes(action))return{status:'not-applied',reason:'Unknown operation.'};
 if(window[key]&&action==='apply'){const checked=verify();return checked.status==='applied'?{...checked,status:'already-applied'}:checked}
 const roots=queryDeep(document,'[data-codex-composer-root][data-composer-placement="thread"],[data-codex-composer-root][data-composer-placement="home"]').filter(visible);
 const chatPage=location.protocol==='https:'&&location.hostname==='chatgpt.com';
 const nativeChatPage=location.protocol==='app:'&&location.hostname==='-'&&location.pathname==='/index.html'&&roots.length===0;
 // Centered Chat/Work composers keep their original layout; reserve space only at the bottom.
 const surfaces=queryDeep(document,'[data-composer-surface-variant]').filter(e=>visible(e)&&(chatPage||nativeChatPage||roots.some(root=>contains(root,e)))&&queryDeep(e,'[contenteditable="true"],[contenteditable="plaintext-only"],textarea').some(visible));
 const candidates=[...new Set(surfaces)].filter(e=>!surfaces.some(p=>p!==e&&contains(p,e)));
 if(candidates.length!==1)return{status:'not-applied',reason:'Input selection was not unique.',candidateCount:candidates.length};
 const target=candidates[0],before=rect(target);
 if(action==='measure')return{status:'measured',rect:before,placement:bottomDocked(target)?'bottom':'centered'};
 if(!bottomDocked(target))return{status:'original',placement:'centered',reason:'Centered input keeps its original layout.'};
 if(reserve===0)return{status:'original',placement:'bottom',reason:'No pet overlap requires clearance.'};
 if(before.width-reserve<minWidth)return{status:'not-applied',reason:'Insufficient input width.'};
 const style=document.createElement('style');
 style.textContent='[data-codex-clearance-v2="active"]{box-sizing:border-box!important;width:calc(100% - '+reserve+'px)!important;max-width:calc(100% - '+reserve+'px)!important;margin-inline-start:0!important;margin-inline-end:'+reserve+'px!important;}';
 const previous=target.getAttribute('data-codex-clearance-v2');
 window[key]={target,before,previous,style,reserve,viewport:[innerWidth,innerHeight]};
 target.setAttribute('data-codex-clearance-v2','active');
 const tree=target.getRootNode();(tree===document?document.head:tree).append(style);
 return verify();
}
