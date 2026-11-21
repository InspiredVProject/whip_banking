(() => {
  'use strict';
  const screen=document.getElementById('screen');
  const content=document.getElementById('content');
  const esc=x=>String(x??'').replace(/[&<>]/g,s=>({'&':'&amp;','<':'&lt;','>':'&gt;'}[s]));
  const amount=(n,sym)=>`${sym||'$'}${Math.floor(Number(n)||0).toLocaleString('en-GB')}`;
  const key=(n,t,right=false)=>`<div class="atm-choice ${right?'right':''}"><span class="key">${n}</span><span class="value">${esc(t)}</span></div>`;
  const option=(n,t,right=false)=>`<div class="atm-choice ${right?'right':''}"><span class="key">${n}</span><span>${esc(t)}</span></div>`;
  function render(msg) {
    const step=msg.screen||'idle';
    const paper=!['idle','pin','processing','complete','error','calibration'].includes(step);
    const bankCode=['fleeca','maze','pacific'].includes(msg.bankKey)?msg.bankKey:'maze';
    screen.className='screen bank-'+bankCode+' '+(paper?'light':step);
    const name=msg.brand||({fleeca:'FLEECA BANK',maze:'MAZE BANK',pacific:'PACIFIC STANDARD'}[bankCode]);
    const curr=msg.currency||'$';
    document.querySelector('.brand-mini div').firstChild.nodeValue=name;
    if(step==='calibration'){
      content.innerHTML=`<div class="calibration-guide"><span class="crosshair">+</span><strong>SCREEN ALIGNMENT</strong><small>${esc(msg.model||'Find an ATM nearby')}</small><small>Adjust this model in /whip → Settings → Banking</small></div>`;
    } else if(step==='idle'){
      content.innerHTML=`<div class="intro"><h1>INSERT OR TAP</h1><h2>${esc(name)} CASH MACHINE</h2><p>Insert your debit card or tap the contactless reader to get started. Your card stays with you when you tap.</p></div>`;
    } else if(step==='pin'){
      const pinCount=Math.max(0,Math.min(4,Number(msg.pinCount||0)));
      const pinVisual=Array.from({length:4},(_,i)=>i<pinCount?'●':'○').join(' ');
      content.innerHTML=`<div class="status"><h1>ENTER PIN</h1><p>Card ending ${esc(msg.last4||'••••')}</p><div class="pin-dots">${pinVisual}</div><p>Use the ATM keypad to enter your four-digit secure PIN, then press ENTER.</p></div>`;
    } else if(step==='menu'){
      content.innerHTML=`<div class="atmlist">${option('1','FAST CASH')}${option('5','CANCEL',true)}${option('2','WITHDRAW')}${option('6','',true)}${option('3','BALANCE')}${option('7','',true)}<div></div>${option('ESC','BACK',true)}</div>`;
    } else if(step==='fast'){
      content.innerHTML=`<div class="atm-middle"><h1 class="screen-title">FAST CASH</h1><p>Available</p><strong>${amount(msg.balance,curr)}</strong><p>Cash left today</p><strong>${amount(msg.limit||5000,curr)}</strong></div>
        <div class="atmlist">${key('1',amount(20,curr))}${key('5',amount(500,curr),true)}${key('2',amount(60,curr))}<div></div>${key('3',amount(100,curr))}${option('7','OTHER AMOUNT',true)}${key('4',amount(200,curr))}${option('ESC','BACK',true)}</div>`;
    } else if(step==='balance'){
      content.innerHTML=`<div class="status"><h1>YOUR BALANCE</h1><p>Everyday account ending ${esc(msg.last4||'')}</p><h1>${amount(msg.balance,curr)}</h1><p>Press the ATM's ENTER or CANCEL key to go back.</p></div>`;
    } else if(step==='amount'){
      content.innerHTML=`<div class="status"><h1>CASH WITHDRAWAL</h1><h1>${amount(msg.enteredAmount||0,curr)}</h1><p>Use the physical ATM keypad. ENTER confirms, CLEAR deletes, CANCEL goes back.</p></div>`;
    } else if(step==='processing'){
      content.innerHTML=`<div class="status"><h1>PROCESSING</h1><p>Please wait while we contact your bank.</p><p>${amount(msg.amount,curr)}</p></div>`;
    } else if(step==='complete'){
      content.innerHTML=`<div class="status"><h1>${esc(msg.message||'COMPLETE')}</h1><p>${amount(msg.amount,curr)}</p><p>Thank you for banking with ${esc(name)}. Press ENTER to continue.</p></div>`;
    } else {
      content.innerHTML=`<div class="status"><h1>TRANSACTION DECLINED</h1><p>${esc(msg.message||'Please try again.')}</p><p>Press ENTER to go back.</p></div>`;
    }
  }
  window.addEventListener('message',e=>{if(e.data&&typeof e.data==='object')render(e.data)});
  render({screen:'idle',bankKey:'maze'});
})();
