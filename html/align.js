(() => {
  'use strict';
  const $ = s => document.querySelector(s);
  const panel = $('#align');
  const controls = $('#alignControls');
  const exportPanel = $('#alignExportPanel');
  const jsonBox = $('#alignJson');
  const modelLabel = $('#alignModel');
  const savedLabel = $('#alignSaved');
  const stepSelect = $('#alignStep');
  let active = false;
  let current = null;
  let exportText = '';
  let work = Promise.resolve();
  let toastTimer;
  let resetArmedAt = 0;

  const fields = ['side','out','up','width','height','tilt'];
  const fieldInputs = Object.fromEntries(fields.map(k=>[k,$(`[data-align-field="${k}"]`)]));
  const step = () => Number(stepSelect.value) || 0.005;

  async function call(action,extra={}) {
    const resource = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'whip_banking';
    try {
      const response = await fetch(`https://${resource}/alignAction`,{
        method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({action,...extra})
      });
      return await response.json();
    } catch(_) {return {ok:false,error:'Could not contact the alignment editor'};}
  }

  function toast(message,bad=false) {
    const el=$('#alignToast');
    el.textContent=String(message);
    el.style.background=bad?'#60232a':'#174634';
    el.classList.remove('hidden');
    clearTimeout(toastTimer);
    toastTimer=setTimeout(()=>el.classList.add('hidden'),2250);
  }

  function render(data) {
    if(!data||typeof data!=='object')return;
    current=data;
    modelLabel.textContent=data.model||'ALL ATM MODELS · JSON EXPORT';
    savedLabel.textContent=`${Number(data.saved)||0} model(s) saved locally · Not applied server-wide yet`;
    for(const field of fields){
      const el=fieldInputs[field];
      if(el&&document.activeElement!==el)el.value=Number(data.spec?.[field]??0).toFixed(4);
    }
    if(!data.model)showExportPane(true);
  }

  function showExportPane(show){
    exportPanel.classList.toggle('hidden',!show);
    controls.classList.toggle('hidden',show||!current?.model);
  }

  function queue(action,extra={},message=''){
    work=work.then(async()=>{
      if(!active)return;
      const answer=await call(action,extra);
      if(!answer.ok){toast(answer.error||'Action failed',true);return;}
      if(answer.data)render(answer.data);
      if(action==='export'){
        try{exportText=JSON.stringify(JSON.parse(answer.json),null,2);}catch(_){exportText=answer.json||'';}
        jsonBox.value=exportText;
        showExportPane(true);
      }
      if(message)toast(message);
      if(action==='close'){active=false;panel.classList.add('hidden');}
    }).catch(()=>toast('Alignment action failed',true));
    return work;
  }

  function move(field,sign){queue('adjust',{field,value:sign*step()});}

  panel.addEventListener('click',e=>{
    const adjust=e.target.closest('[data-adjust]');
    if(adjust){const [field,dir]=adjust.dataset.adjust.split(':');move(field,dir==='-'?-1:1);}
  });
  for(const field of fields){
    const input=fieldInputs[field];
    input.addEventListener('change',()=>{
      const n=Number(input.value);
      if(!Number.isFinite(n))return toast('Enter a valid number',true);
      queue('set',{field,value:n});
    });
  }

  $('#alignClose').addEventListener('click',()=>queue('close'));
  $('#alignSide').addEventListener('click',()=>panel.classList.toggle('left'));
  $('#alignSave').addEventListener('click',()=>queue('save',{},'Saved this ATM model locally'));
  $('#alignNext').addEventListener('click',()=>queue('next',{},'Selected next nearby ATM'));
  $('#alignReset').addEventListener('click',()=>{
    if(Date.now()-resetArmedAt<3500){
      resetArmedAt=0;queue('reset',{},'Restored this model to defaults');
    }else{
      resetArmedAt=Date.now();toast('Click RESET MODEL again to confirm',true);
    }
  });
  $('#alignExport').addEventListener('click',()=>queue('export'));
  $('#alignBack').addEventListener('click',()=>showExportPane(false));
  $('#alignCopy').addEventListener('click',async()=>{
    let copied=false;
    try{await navigator.clipboard.writeText(exportText);copied=true;}catch(_){}
    if(!copied){
      jsonBox.focus();jsonBox.select();
      try{copied=document.execCommand('copy');}catch(_){}
    }
    toast(copied?'JSON copied — paste it into ChatGPT':'Select the JSON text and press Ctrl+C',!copied);
  });
  $('#alignDownload').addEventListener('click',()=>{
    if(!exportText)return;
    const url=URL.createObjectURL(new Blob([exportText],{type:'application/json'}));
    const a=document.createElement('a');a.href=url;a.download='whip_banking_atm_alignment.json';
    document.body.appendChild(a);a.click();a.remove();
    setTimeout(()=>URL.revokeObjectURL(url),3000);
    toast('If FiveM blocks the download, use Copy JSON instead');
  });

  document.addEventListener('keydown',event=>{
    if(!active)return;
    const editingField=['INPUT','SELECT','TEXTAREA'].includes(document.activeElement?.tagName);
    if(editingField){
      if(event.key==='Escape'){document.activeElement.blur();event.preventDefault();event.stopPropagation();}
      return;
    }
    const map={
      ArrowLeft:['side',-1],ArrowRight:['side',1],ArrowUp:['up',1],ArrowDown:['up',-1],
      PageUp:['out',-1],PageDown:['out',1],
      a:['side',-1],d:['side',1],w:['out',-1],s:['out',1],
      q:['up',-1],e:['up',1],z:['width',-1],x:['width',1],
      c:['height',-1],v:['height',1],r:['tilt',1],f:['tilt',-1],
    };
    const key=event.key.length===1?event.key.toLowerCase():event.key;
    if(map[key]&&current?.model&&!event.ctrlKey&&!event.altKey){
      event.preventDefault();event.stopPropagation();move(...map[key]);return;
    }
    if(key==='Enter'&&current?.model){event.preventDefault();event.stopPropagation();queue('save',{},'Saved model');return;}
    if(key==='Escape'){
      event.preventDefault();event.stopPropagation();
      if(!exportPanel.classList.contains('hidden')&&current?.model)showExportPane(false);
      else queue('close');
    }
  },true);

  window.addEventListener('message',event=>{
    const msg=event.data;
    if(!msg||typeof msg!=='object')return;
    if(msg.type==='alignOpen'){
      active=true;panel.classList.remove('hidden');render(msg.data);
      showExportPane(!msg.data?.model);
      if(!msg.data?.model)queue('export');
    }else if(msg.type==='alignUpdate'&&active){render(msg.data);}
    else if(msg.type==='alignClose'){
      active=false;panel.classList.add('hidden');exportText='';
    }
  });
})();
