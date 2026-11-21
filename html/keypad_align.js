(() => {
  'use strict';
  const $=s=>document.querySelector(s);
  const root=$('#keypadAlign'),panel=$('#keypadAlignPanel'),guide=$('#keypadAlignGuideMove');
  const model=$('#kpAlignModel'),saveLabel=$('#kpAlignSaved'),alert=$('#kpAlignAlert');
  const stepSelect=$('#kpAlignStep'),exportBox=$('#kpAlignExportBox'),exportText=$('#kpAlignJson');
  const fields={left:$('#kpAlignLeftValue'),top:$('#kpAlignTopValue'),width:$('#kpAlignWidth'),height:$('#kpAlignHeight')};
  let active=false,current=null,layout=null,waiting=Promise.resolve(),lastExport='',resetAt=0,drag=null;
  const step=()=>Number(stepSelect.value)||0.005;
  const parent=()=>typeof GetParentResourceName==='function'?GetParentResourceName():'whip_banking';
  async function call(action,extra={}) {
    try{
      const response=await fetch(`https://${parent()}/keypadAlignAction`,{
        method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({action,...extra})
      });
      return await response.json();
    } catch (_) {return {ok:false,error:'Could not contact WHIP live keypad editor'};}
  }
  function toast(message,bad=false){
    alert.textContent=message;alert.style.background=bad?'#5f2630':'#21483f';
    alert.classList.remove('hidden');
  }
  function queue(action,extra={},message=''){
    waiting=waiting.then(async()=>{
      if(!active)return;
      const response=await call(action,extra);
      if(!response.ok){toast(response.error||'Could not make adjustment',true);return;}
      if(response.data)renderState(response.data);
      if(action==='export'){
        try{lastExport=JSON.stringify(JSON.parse(response.json),null,2);}catch(_){lastExport=String(response.json||'');}
        exportText.value=lastExport;exportBox.classList.remove('hidden');
      }
      if(message)toast(message);
      if(action==='close'||action==='test'){active=false;root.classList.add('hidden');}
    }).catch(()=>toast('Adjustment failed',true));
    return waiting;
  }
  function renderState(state){
    if(!state)return;
    current=state;model.textContent=state.model||'SELECT ATM';
    for(const field of Object.keys(fields)) fields[field].textContent=Number(state.spec?.[field]||0).toFixed(4);
    saveLabel.textContent=`${Number(state.saved)||0} saved locally. Copy/export JSON for permanent server-wide alignment.`;
  }
  function adjusted(field,direction,multiple=1){queue('adjust',{field,value:direction*step()*multiple});}
  function placement(coord){
    const x=Math.min(1,Math.max(0,Number(coord?.x)||0));
    const y=Math.min(1,Math.max(0,Number(coord?.y)||0));
    const w=Math.min(.25,Math.max(.002,Number(coord?.w)||.01));
    const h=Math.min(.25,Math.max(.002,Number(coord?.h)||.01));
    return `left:${(x*100).toFixed(3)}%;top:${(y*100).toFixed(3)}%;width:${(w*100).toFixed(3)}vw;height:${(h*100).toFixed(3)}vh;`;
  }
  const safe=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  function outline(part,side=false){
    const k=part.key;
    const kind=k==='CANCEL'?'cancel':k==='CLEAR'?'clear':k==='ENTER'?'enter':side?'side':'';
    const label=k==='CANCEL'?'X':k==='CLEAR'?'CLR':k==='ENTER'?'✓':k==='MINUS'?'−':k==='PLUS'?'+':k;
    return `<div class="keypad-align-guide ${kind}" style="${placement(part)}">${safe(label)}</div>`;
  }
  function paint(data){
    if(!active||drag)return;
    layout=data;
    if(!data?.keys?.length){guide.innerHTML='';return;}
    const boxes=data.keys.map(k=>({x:k.x- k.w/2,y:k.y-k.h/2,x2:k.x+k.w/2,y2:k.y+k.h/2}));
    const left=Math.min(...boxes.map(k=>k.x)),top=Math.min(...boxes.map(k=>k.y));
    const right=Math.max(...boxes.map(k=>k.x2)),bottom=Math.max(...boxes.map(k=>k.y2));
    // Drag handle is the bounding rectangle; the colour-coded keys are noninteractive.
    guide.style.transform='';
    guide.innerHTML=`<div id="keypadAlignDrag" class="keypad-align-drag" style="left:${(left*100).toFixed(3)}%;top:${(top*100).toFixed(3)}%;width:${((right-left)*100).toFixed(3)}%;height:${((bottom-top)*100).toFixed(3)}%"></div>`+
      data.keys.map(k=>outline(k)).join('') + (data.sides||[]).map(k=>outline(k,true)).join('');
  }
  $('#kpAlignUp').addEventListener('click',()=>adjusted('top',-1));
  $('#kpAlignDown').addEventListener('click',()=>adjusted('top',1));
  $('#kpAlignLeft').addEventListener('click',()=>adjusted('left',-1));
  $('#kpAlignRight').addEventListener('click',()=>adjusted('left',1));
  root.addEventListener('click',event=>{
    const action=event.target.closest('[data-kp-adjust]');if(!action)return;
    const [field,sign]=action.dataset.kpAdjust.split(':');
    adjusted(field,sign==='+'?1:-1);
  });
  $('#kpAlignSave').addEventListener('click',()=>queue('save',{},'Saved locally. Export JSON to update all players.'));
  $('#kpAlignTest').addEventListener('click',()=>queue('test',{},'Saved — verify the actual clickable keys on the ATM.'));
  $('#kpAlignClose').addEventListener('click',()=>queue('close'));
  $('#kpAlignSide').addEventListener('click',()=>panel.classList.toggle('right'));
  $('#kpAlignExport').addEventListener('click',()=>queue('export',{},'Copy this JSON and send it for the permanent update.'));
  $('#kpAlignReset').addEventListener('click',()=>{
    if(Date.now()-resetAt<3500){resetAt=0;queue('reset',{},'Restored original /whip settings for this model.');}
    else{resetAt=Date.now();toast('Press RESET again to confirm.',true);}
  });
  $('#kpAlignCopy').addEventListener('click',async()=>{
    let done=false;
    try{await navigator.clipboard.writeText(lastExport);done=true;}catch(_){}
    if(!done){exportText.focus();exportText.select();try{done=document.execCommand('copy');}catch(_){}}
    toast(done?'Copied — send JSON in chat.':'Select all JSON and press Ctrl+C.',!done);
  });
  // Dragging the dashed outline moves all keys, preserving the layout from the reference photo.
  // Screen-space drag is converted to fractions of the calibrated ATM screen basis.
  guide.addEventListener('pointerdown',event=>{
    if(!active||event.target.id!=='keypadAlignDrag'||!layout?.screenRight||!layout?.screenDown)return;
    drag={x:event.clientX,y:event.clientY,id:event.pointerId,dx:0,dy:0};
    try{event.target.setPointerCapture(event.pointerId);}catch(_){}
    event.preventDefault();
  });
  guide.addEventListener('pointermove',event=>{
    if(!drag||event.pointerId!==drag.id)return;
    drag.dx=event.clientX-drag.x;drag.dy=event.clientY-drag.y;
    guide.style.transform=`translate(${drag.dx}px, ${drag.dy}px)`;
  });
  function finishDrag(){
    if(!drag)return;
    const d=drag;drag=null;guide.style.transform='';
    if(!layout||Math.abs(d.dx)+Math.abs(d.dy)<2)return;
    const r=layout.screenRight,b=layout.screenDown;
    const a=Number(r[0]),c=Number(r[1]),e=Number(b[0]),f=Number(b[1]);
    const det=a*f-c*e;
    if(!Number.isFinite(det)||Math.abs(det)<0.0000001){toast('Could not determine screen projection. Use the arrows.',true);return;}
    const x=d.dx/window.innerWidth,y=d.dy/window.innerHeight;
    const deltaLeft=(x*f-y*e)/det,deltaTop=(a*y-c*x)/det;
    if(Number.isFinite(deltaLeft)&&Number.isFinite(deltaTop))queue('drag',{left:deltaLeft,top:deltaTop});
  }
  guide.addEventListener('pointerup',finishDrag);
  guide.addEventListener('pointercancel',finishDrag);
  document.addEventListener('keydown',event=>{
    if(!active||event.ctrlKey||event.altKey||event.metaKey)return;
    if(['INPUT','TEXTAREA','SELECT'].includes(document.activeElement?.tagName)){
      if(event.key==='Escape'){document.activeElement.blur();event.preventDefault();event.stopPropagation();}
      return;
    }
    const mapping={ArrowLeft:['left',-1],ArrowRight:['left',1],ArrowUp:['top',-1],ArrowDown:['top',1],a:['left',-1],d:['left',1],w:['top',-1],s:['top',1],z:['width',-1],x:['width',1],c:['height',-1],v:['height',1]};
    const k=event.key.length===1?event.key.toLowerCase():event.key;
    if(mapping[k]){event.preventDefault();event.stopPropagation();adjusted(mapping[k][0],mapping[k][1],event.shiftKey?5:1);return;}
    if(k==='Enter'){event.preventDefault();event.stopPropagation();queue('save',{},'Saved locally.');return;}
    if(k==='Escape'){event.preventDefault();event.stopPropagation();queue('close');}
  },true);
  window.addEventListener('message',event=>{
    const m=event.data;if(!m||typeof m!=='object')return;
    if(m.type==='keypadAlignOpen'){
      active=true;root.classList.remove('hidden');exportBox.classList.add('hidden');alert.classList.add('hidden');renderState(m.data);
    }else if(m.type==='keypadAlignUpdate'&&active){renderState(m.data);}
    else if(m.type==='keypadAlignLayout'&&active){paint(m.data);}
    else if(m.type==='keypadAlignClose'){
      active=false;root.classList.add('hidden');guide.innerHTML='';layout=null;drag=null;
    }
  });
})();
