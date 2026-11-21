(() => {
  'use strict';
  const $ = s => document.querySelector(s);
  const bank = $('#bank'), atm = $('#atm'), modal = $('#modal'), toast = $('#toast');
  const bankSelection = $('#bankSelection'), bankSelectionContent = $('#bankSelectionContent');
  const cardViewer = $('#cardViewer'), cardViewerStage=$('#cardViewerStage');
  let previewCard=null;
  let data = null, activeTab = 'accounts', fromTeller = false, screen = 'idle';
  let atmData = null, chosenCard = null, activeCard = null, atmMessage = '';
  let pinDigits='', amountDigits='', insertingCard=false, insertSequence=0, keypadCoords=null, keypadModeSent=false, processingCash=false;
  let keypadDebug=false; // Only toggled for a /w developer test session.
  const keypadLayer=$('#atmPhysicalKeypad');
  let pinBuffer = '', pinBusy = false;
  const preview = new URLSearchParams(location.search).has('preview');
  const BRANDS = {
    fleeca:{name:'FLEECA BANK',tag:'THE NEIGHBOURHOOD BANK',short:'FLEECA',description:'Everyday banking with the green bank.',
      colour:'#2b985c'},
    maze:{name:'MAZE BANK',tag:'OF LOS SANTOS',short:'MAZE',description:'The city bank for every ambition.',
      colour:'#c52e37'},
    pacific:{name:'PACIFIC STANDARD',tag:'PUBLIC DEPOSIT BANK',short:'PACIFIC',description:'A premium standard of banking.',
      colour:'#214d83'}
  };
  let bankChoice = 'fleeca', cardStyle = 'classic', switchingBanks = false;
  const brand = () => BRANDS[data?.bankKey] || BRANDS.maze;
  const bankName = () => brand().name;
  const CARD_STYLE_NAMES={classic:'EVERYDAY',black:'CASH+',metal:'METAL'};
  const chipSvg=`<svg viewBox="0 0 94 68" aria-hidden="true" focusable="false"><rect x="2" y="2" width="90" height="64" rx="11" fill="url(#chipg)" stroke="#9f7d44" stroke-width="2"/><defs><linearGradient id="chipg" x1="0" x2="1" y1="0" y2="1"><stop stop-color="#fff0c5"/><stop offset=".5" stop-color="#d7b878"/><stop offset="1" stop-color="#b18c49"/></linearGradient></defs><path d="M21 2v15h15l11 10v14L36 51H21v15M73 2v15H58L47 27v14l11 10h15v15M2 24h21l13 10-13 10H2M92 24H71L58 34l13 10h21M36 2v15M58 2v15M36 51v15M58 51v15" stroke="#9f7b41" stroke-width="2" fill="none"/></svg>`;
  const tapSvg=`<svg viewBox="0 0 50 50" aria-label="Contactless" role="img"><path d="M8 16q16 10 0 20M17 10q24 16 0 32M26 4q32 22 0 44" fill="none" stroke="currentColor" stroke-width="4" stroke-linecap="round"/></svg>`;
  function cardArtwork(bankKey,style,info={},reverse=false){
    const k=BRANDS[bankKey]?bankKey:'maze', b=BRANDS[k], tier=CARD_STYLE_NAMES[style]||'EVERYDAY', cardLogo=k==='maze'?'MAZE BANK':b.short;
    const holder=esc(String(info.holder||'CARDHOLDER NAME').toUpperCase().slice(0,32));
    const last4=esc(String(info.last4||'••••').slice(-4));
    const expires=esc(info.expires||'MM/YY');
    const identifier=esc(String(info.id||'').slice(0,12));
    const cardClass=`premium-card bankcard card-${k} card-${style||'classic'}${reverse?' premium-reverse':''}`;
    if(reverse) return `<div class="${cardClass}" aria-label="Reverse of ${esc(b.name)} ${esc(tier)} card">
      <div class="premium-backtop">${esc(b.name)} <small>CONTACTLESS DEBIT</small></div><div class="premium-stripe"></div>
      <div class="premium-signature"><span>${holder}</span><b>CVV •••</b></div>
      <div class="premium-backnote">This card remains the property of ${esc(b.name)}. If found, return to any bank branch. Your PIN must never be written on this card.</div>
      <div class="premium-backfooter"><span>24/7 BANKING SERVICES</span><b>LS PAY</b></div></div>`;
    return `<div class="${cardClass}" aria-label="${esc(b.name)} ${esc(tier)} debit card ending ${last4}">
      <div class="premium-foil"></div><div class="premium-head"><div class="premium-brand"><strong>${esc(cardLogo)}</strong><span>${esc(b.tag)}</span></div><div class="premium-edition"><small>DEBIT</small><b>${esc(tier)}</b></div></div>
      <div class="premium-chip-row"><span class="premium-chip">${chipSvg}</span><span class="premium-contactless">${tapSvg}</span></div>
      <div class="premium-number">•••• &nbsp;•••• &nbsp;•••• &nbsp;${last4}</div>
      <div class="premium-details"><span class="premium-holder"><small>CARDHOLDER</small><strong>${holder}</strong></span><span class="premium-expiry"><small>VALID THRU</small><strong>${expires}</strong></span><span class="premium-network">LS<span>PAY</span></span></div>
      ${identifier?`<span class="premium-tinyid">${identifier}</span>`:''}</div>`;
  }
  function applyBankTheme(key){
    const k=BRANDS[key]?key:'maze';
    bank.dataset.bank=k;atm.dataset.bank=k;modal.dataset.bank=k;
    $('#bank .brandname').textContent=BRANDS[k].name;
    $('#bank .logo small').textContent=BRANDS[k].tag;
    $('#atm .atm-title span').textContent=BRANDS[k].name;
  }
  function bankChoiceCard(key){
    const b=BRANDS[key]; const offer=(data?.bankOptions||[]).find(x=>x.key===key)||{};
    return `<article class="choice-bank choice-${key}">
      <div class="choice-top"><div class="choice-logo">${b.short}</div><small>${b.tag}</small></div>
      <p>${b.description}</p><div class="choice-card-preview-wrap">${cardArtwork(key,'classic',{holder:'YOUR NAME'})}</div>
      <div class="choice-offers"><strong>${Number(offer.savingsApr??0).toFixed(1)}% APR</strong><span>on eligible savings</span>
      <strong>${money(offer.atmDailyLimit??5000)}</strong><span>ATM cash per day</span></div>
      <button class="choice-pick" data-select-bank="${key}">CHOOSE ${b.short} <span>↗</span></button>
    </article>`;
  }
  function showChoice(shouldSwitch=false){
    if(!fromTeller && !preview){say('Visit a bank teller to change banks',true);return;}
    switchingBanks=shouldSwitch; bankChoice=(data?.bankKey&&shouldSwitch)?data.bankKey:'fleeca';cardStyle='classic';
    bank.classList.add('hidden');modal.classList.add('hidden');bankSelection.classList.remove('hidden');
    bankSelectionContent.innerHTML=`<header class="choice-header"><div><small>WELCOME TO YOUR BANKING FUTURE</small><h1>${shouldSwitch?'SWITCH BANK':'CHOOSE YOUR BANK'}</h1><p>${shouldSwitch?'Your WHIP balances, savings and loans stay with you. Existing debit cards will be cancelled and replaced.':'Choose the bank that fits you. Your choice follows your character across branches, ATMs and your phone.'}</p></div><button data-choice-back>ESC&nbsp; BACK</button></header>
      <div class="choice-grid">${['fleeca','maze','pacific'].map(bankChoiceCard).join('')}</div>`;
  }
  function showCardChoice(key){
    if(!BRANDS[key])return;
    bankChoice=key;
    const b=BRANDS[key];
    bankSelectionContent.innerHTML=`<header class="choice-header"><div><small>${switchingBanks?'SWITCH BANK':'NEW CUSTOMER'}</small><h1>YOUR ${b.short} CARD</h1><p>Pick your card finish and choose a secure four-digit PIN.</p></div><button data-choice-back>ESC&nbsp; BACK</button></header>
      <div class="choice-design"><div class="choice-design-preview"><div class="premium-showcase"><div><div class="premium-side-label">FRONT</div>${cardArtwork(key,cardStyle,{holder:data?.name||'YOUR NAME'})}</div><div><div class="premium-side-label">BACK</div>${cardArtwork(key,cardStyle,{holder:data?.name||'YOUR NAME'},true)}</div></div>
          <p>Preview only — your personalised number and expiry are assigned when the physical card is issued. Cards can be frozen, replaced or cancelled at a branch.</p></div>
        <div class="choice-design-form"><h2>CUSTOMISE YOUR CARD</h2><p>FINISH</p><div class="choice-finishes">
        ${Object.entries(CARD_STYLE_NAMES).map(([k,v])=>`<button data-card-style="${k}" class="${cardStyle===k?'selected':''}">${v}</button>`).join('')}
        </div><label>YOUR SECURE FOUR-DIGIT PIN<input id="choicePin" type="password" inputmode="numeric" pattern="[0-9]{4}" minlength="4" maxlength="4" placeholder="••••" autocomplete="off"></label>
        <div class="choice-disclaimer">${switchingBanks?'Switching replaces your existing bank cards.':'Your account and card are linked to your character.'} Savings and loans always use WHIP Core.</div>
        <button class="choice-pick" id="confirmBankChoice">${switchingBanks?'SWITCH TO':'OPEN WITH'} ${b.short} <span>ENTER ↗</span></button></div></div>`;
  }
  bankSelection.addEventListener('click',async event=>{
    const el=event.target.closest('button');if(!el)return;
    if(el.matches('[data-choice-back]')){if(bankSelectionContent.querySelector('.choice-design'))showChoice(switchingBanks);else{bankSelection.classList.add('hidden');if(data?.bankKey){bank.classList.remove('hidden');draw();}else post('close');}return;}
    if(el.dataset.selectBank){showCardChoice(el.dataset.selectBank);return;}
    if(el.dataset.cardStyle){cardStyle=el.dataset.cardStyle;const pin=$('#choicePin')?.value||'';showCardChoice(bankChoice);if($('#choicePin'))$('#choicePin').value=pin;return;}
    if(el.id==='confirmBankChoice'){
      const pin=$('#choicePin')?.value||'';
      if(!/^\d{4}$/.test(pin)){say('Choose a four-digit PIN',true);return;}
      el.disabled=true;
      const result=await post('request',{action:'selectBank',args:[bankChoice,pin,cardStyle]});
      if(!result.ok){say(result.error||'Bank choice refused',true);el.disabled=false;return;}
      const updated=await post('refresh');
      if(updated.ok&&updated.data){bankSelection.classList.add('hidden');openBank(updated.data,true);say('Welcome to '+BRANDS[bankChoice].name);}
      else{say('Your bank choice was saved. Please reopen the teller.',true);bankSelection.classList.add('hidden');post('close');}
    }
  });
  const tabs = ['accounts','transfer','history','cards','credit','loans','bills','scheduled','bank'];
  const esc = str => String(str ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const currency = () => data?.currency || atmData?.currency || '$';
  const money = (n,symbol=currency()) => symbol + Math.floor(Number(n)||0).toLocaleString('en-GB');
  const shortDate = n => n ? new Date(Number(n)*1000).toLocaleDateString('en-GB',{day:'numeric',month:'short'}) : '—';
  const fullDate = n => n ? new Date(Number(n)*1000).toLocaleString('en-GB',{day:'numeric',month:'short',year:'numeric'}) : '—';
  const fields = form => Array.from(form.querySelectorAll('input,select')).reduce((o,el)=>(o[el.name]=el.value,o),{});
  const choose = (list,selected,field='accountId') => (list||[]).map(x=>`<option value="${x[field]||x.accountId}" ${String(x[field]||x.accountId)===String(selected)?'selected':''}>${esc(x.label)} · ${esc(x.accountNumber)} (${money(x.balance)})</option>`).join('');

  const demo = {
    brand:'MAZE BANK',name:'DANI OKAFOR',currency:'$',primary:1,cash:1260,balance:24683,credit:702,
    accounts:[
      {accountId:1,accountNumber:'MZ 4821 0937',label:'Checking',balance:24683,type:'personal',isDefault:true,role:'owner'},
      {accountId:2,accountNumber:'MZ 4821 1011',label:'Car fund',balance:11250,type:'savings',role:'owner'},
      {accountId:3,accountNumber:'MZ 4821 1187',label:'Rainy day',balance:3400,type:'savings',role:'owner'},
      {accountId:4,accountNumber:'MZ 4821 3302',label:'Apartment 4B',balance:2140,type:'shared',role:'owner'},
      {accountId:5,accountNumber:'MZ 4821 9800',label:'Crew fund',balance:860,type:'shared',role:'member'},
      {accountId:6,accountNumber:'FL 6601 2345',label:'Hayes Autos',balance:48210,type:'job',role:'manager'}],
    cards:[{id:1,number:'5500891129030212',last4:'0212',label:'Fleeca Everyday',accountId:1,status:'active'}],
    loans:[{id:9,product:'vehicle',principal:12000,remaining:8350,installment:735,nextDue:Date.now()/1000+86400*9,status:'active',rate:6.2}],
    bills:[{id:1,title:'Rent',amount:900,category:'housing',dueAt:Date.now()/1000+86400*2,status:'unpaid'},{id:2,title:'Fleeca Cash+ minimum',amount:76,category:'credit',dueAt:Date.now()/1000+86400*2,status:'unpaid'}],
    schedules:[{id:4,label:'Car savings',amount:250,days:7,nextAt:Date.now()/1000+86400,status:'active'}],
    products:[{key:'personal',label:'Personal loan',max:15000,rate:8.5,months:6,minScore:540},{key:'vehicle',label:'Vehicle finance',max:50000,rate:6.2,months:12,minScore:620},{key:'business',label:'Business loan',max:100000,rate:9.8,months:18,minScore:710}],
    transactions:Array.from({length:24},(_,i)=>({amount:i%3?250: -[76,150,900][i%3],type:i%3?'deposit':'withdraw',message:['Salary','Fuel','Shopping','Bills'][i%4],createdAt:Date.now()/1000-i*86400}))
  };

  async function post(endpoint,payload={}) {
    if (preview) {
      if(endpoint==='request' && payload.action==='overview' || endpoint==='refresh') return {ok:true,data:demo};
      return {ok:true,data:{balance:Math.max(0,activeCard?.balance||24683),cash:1260}};
    }
    try {
      const resource = window.GetParentResourceName ? GetParentResourceName() : 'whip_banking';
      const response = await fetch(`https://${resource}/${endpoint}`,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(payload)});
      return await response.json();
    } catch(e) {return {ok:false,error:'Bank connection timed out'};}
  }

  let toastTimer;
  function say(message,bad=false) {
    toast.textContent=String(message||'Unable to complete the request');toast.classList.remove('hidden');
    toast.classList.toggle('bad',bad);clearTimeout(toastTimer);toastTimer=setTimeout(()=>toast.classList.add('hidden'),3500);
  }
  async function run(action,args=[],message='Done') {
    const result=await post('request',{action,args});
    if(!result.ok){say(result.error||'This action was refused',true);return false;}
    if(message)say(message);
    if(bank.classList.contains('hidden')===false) await refresh();
    return result.data||true;
  }
  async function refresh() {
    const result=await post('refresh');
    if(result.ok && result.data){data=result.data;applyBankTheme(data.bankKey);draw();}
  }
  function openBank(payload,teller=false) {
    data=payload;fromTeller=!!teller;activeTab='accounts';
    cardViewer.classList.add('hidden');
    atm.classList.add('hidden');modal.classList.add('hidden');
    applyBankTheme(data?.bankKey);
    if(fromTeller && !data.bankKey){showChoice(false);return;}
    bankSelection.classList.add('hidden');bank.classList.remove('hidden');draw();
    if(fromTeller) showModal('WELCOME TO '+bankName(),`<p style="font-size:17px;margin:0 0 16px">Good afternoon. What can I help you with today?</p>
      <div class="form-grid one"><button class="button red" data-teller-tab="accounts">CHECK MY ACCOUNTS</button>
      <button class="button" data-teller-tab="cards">BANK CARDS & PIN SERVICES</button>
      <button class="button" data-teller-tab="loans">DISCUSS A LOAN</button>
      <button class="button" data-teller-tab="transfer">SEND A BANK TRANSFER</button></div>`,null);
  }
  function closeBank() {bank.classList.add('hidden');bankSelection.classList.add('hidden');modal.classList.add('hidden');post('close');}
  function primary() {return data?.accounts?.find(a=>a.accountId===data.primary)||data?.accounts?.[0]||{};}

  function renderSidebar() {
    $('#personName').textContent=data?.name||'YOUR ACCOUNTS';
    $('#accountNumber').textContent=primary().accountNumber||bankName();
    $('#mainBalance').textContent=money(data?.balance||0);
    $('#cashCaption').textContent='Plus '+money(data?.cash)+' cash on you';
    const n=Number(data?.credit||650), rating=n<580?'POOR':n<670?'FAIR':n<740?'GOOD':n<800?'VERY GOOD':'EXCELLENT';
    $('#creditScore').textContent=n;$('#creditRating').textContent=rating;
    $('#creditDelta').textContent='Your credit standing';
    $('#scorePointer').style.left=`${Math.max(0,Math.min(100,(n-300)/550*100))}%`;
  }
  function renderTabs() {
    const unpaid=(data?.bills||[]).filter(b=>b.status==='unpaid').length;
    const planned=(data?.schedules||[]).filter(s=>s.status==='active').length;
    $('#tabs').innerHTML=tabs.map(tab=>`<button class="nav-tab ${tab===activeTab?'active':''}" data-tab="${tab}">${tab.toUpperCase()}${tab==='bills'&&unpaid?`<span class="badge">${unpaid}</span>`:''}${tab==='scheduled'&&planned?`<span class="badge">${planned}</span>`:''}</button>`).join('');
  }
  function chart() {
    const tx=(data?.transactions||[]).slice().reverse();
    let running=0;
    const vals=[0];
    tx.forEach(t=>{const a=Number(t.amount)||0;running+=(t.type==='withdraw' || t.type==='transfer_out' || (t.type==='transfer'&&Number(t.fromAccountId)===Number(data.primary)))?-Math.abs(a):Math.abs(a);vals.push(running);});
    if(vals.length<2)vals.push(0);
    const min=Math.min(...vals),max=Math.max(...vals),spread=(max-min)||1;
    const pts=vals.map((v,i)=>[10+((i)/(vals.length-1))*970,185-((v-min)/spread)*145]);
    const line=pts.map((p,i)=>`${i?'L':'M'}${p[0].toFixed(1)} ${p[1].toFixed(1)}`).join(' ');
    const change=vals[vals.length-1]-vals[0];
    return `<div class="chart-top"><span class="smallgray">Checking, last 30 days</span><div><b class="change">${change>=0?'+':''}${money(change)}</b> since 19 Sep</div></div>
      <div class="chart-box"><svg viewBox="0 0 1000 200" preserveAspectRatio="none" aria-label="Account balance movement over 30 days">
      <path d="${line} L980 200 L10 200 Z" fill="#c52e3720"/><path d="${line}" stroke="var(--red)" stroke-width="4" fill="none" stroke-linejoin="round" stroke-linecap="round"/>
      <circle cx="${pts.at(-1)[0]}" cy="${pts.at(-1)[1]}" r="7" fill="var(--red)" stroke="var(--paper)" stroke-width="2"/></svg></div>
      <div class="chart-labels"><span>19 Sep</span><span>26 Sep</span><span>3 Oct</span><span>10 Oct</span><span>Today</span></div>`;
  }
  function accountLine(a) {
    const detail=a.isDefault?a.accountNumber:(a.type==='savings'?'2% a year':a.type==='job'?'Business · '+a.accountNumber:a.type==='shared'?'Shared · '+a.accountNumber:a.accountNumber);
    const chip=a.type==='shared'?'OWNER':a.type==='job'?'MANAGER':'';
    return `<div class="account-row"><div><div class="account-name">${esc(a.label)}</div><div class="account-detail">${esc(detail||'')}</div>${a.type==='savings'?'<div class="account-progress"><b></b></div>':''}</div>
      <div>${chip?`<span class="chip">${chip}</span>`:''}<span class="moneyfont">${money(a.balance)}</span></div></div>`;
  }
  function upcoming() {
    const bills=(data?.bills||[]).filter(b=>b.status==='unpaid');
    const all=[...bills.map(b=>({...b,when:b.dueAt,name:b.title})),...(data?.schedules||[]).filter(s=>s.status==='active').map(s=>({...s,when:s.nextAt,name:s.label}))].sort((a,b)=>a.when-b.when).slice(0,4);
    return `<div class="coming-label">Coming up</div><div class="upcoming"><div><small class="late">${bills.filter(b=>b.dueAt<Date.now()/1000).length||0} overdue</small><div class="upcoming-title">${bills.length} bills to pay</div></div><span class="moneyfont">${money(bills.reduce((a,b)=>a+Number(b.amount||0),0))}</span></div>
      ${all.map(x=>`<div class="upcoming"><div><small>${x.when<Date.now()/1000?'Overdue':shortDate(x.when)}</small><div class="upcoming-title">${esc(x.name)}</div></div><span class="moneyfont">${money(x.amount)}</span></div>`).join('')}`;
  }
  function spend() {
    const outgoing=(data?.transactions||[]).filter(t=>t.type==='withdraw'||t.type==='transfer_out'||(t.type==='transfer'&&Number(t.fromAccountId)===Number(data.primary)));
    const sum=outgoing.reduce((s,t)=>s+Math.abs(Number(t.amount)||0),0);
    const sections=['Bills','Shopping','Fuel','Food','Other'], totals=[0,0,0,0,0];
    outgoing.forEach(t=>{const memo=String(t.message||'').toLowerCase();let cat=4;
      if(/bill|rent|tax|insurance|council|payment|fine|loan/.test(memo))cat=0;
      else if(/shop|store|clothes|purchase|market/.test(memo))cat=1;
      else if(/fuel|petrol|diesel|garage/.test(memo))cat=2;
      else if(/food|meal|burger|restaurant|cafe/.test(memo))cat=3;
      totals[cat]+=Math.abs(Number(t.amount)||0);
    });
    const percentages=totals.map(t=>sum?t/sum*100:20);
    return `<div class="spend-summary"><b>Spent this week</b><span>${money(sum)} over ${outgoing.length} payments</span></div>
      <div class="spend-track">${percentages.map(n=>`<div style="width:${n}%"></div>`).join('')}</div><div class="spend-labels">${sections.map((t,i)=>`<div>${t}<strong>${money(totals[i])}</strong></div>`).join('')}</div>`;
  }
  function accountsPage() {
    return chart()+`<div class="two-col"><section>${(data?.accounts||[]).map(accountLine).join('')||'<div class="empty">No bank accounts found</div>'}
      <div class="mini-actions"><button class="smallbtn" data-do="savings">NEW SAVINGS POT</button><button class="smallbtn" data-do="shared">NEW SHARED ACCOUNT</button></div></section>
      <section>${upcoming()}</section></div>`+spend();
  }
  function transferPage() {
    return `<div class="page-head"><h2 class="title-condensed">MOVE MONEY</h2><span class="smallgray">Secure bank transfer</span></div>
      <p class="page-intro">Transfer between your own accounts or send money to anyone by WHIP bank account number.</p>
      <div class="panel"><form id="transferForm"><div class="form-grid">
        <div class="field"><label>From account</label><select name="from">${choose(data.accounts,data.primary)}</select></div>
        <div class="field"><label>Recipient account number</label><input name="number" maxlength="32" placeholder="WB-123456" required></div>
        <div class="field"><label>Amount (${currency()})</label><input name="value" type="number" min="1" step="1" required placeholder="0"></div>
        <div class="field"><label>Transfer type</label><input value="Instant account transfer" readonly></div></div>
        <div class="form-actions"><button class="button red">SEND TRANSFER</button></div></form></div>
      <div class="notice">Account numbers are taken from WHIP's real bank ledger. Payments are checked on the server and cannot overdraw an account.</div>`;
  }
  function historyPage() {
    const list=data?.transactions||[];
    return `<div class="page-head"><h2 class="title-condensed">ACCOUNT HISTORY</h2><span class="smallgray">Latest ${list.length} transactions</span></div>
      <div class="panel"><table class="data-table"><thead><tr><th>Date</th><th>Transaction</th><th>Type</th><th style="text-align:right">Amount</th></tr></thead><tbody>
      ${list.map(t=>{const minus=t.type==='withdraw'||t.type==='transfer_out'||(t.type==='transfer'&&Number(t.fromAccountId)===Number(data.primary));return `<tr><td>${shortDate(t.createdAt||t.timestamp)}</td><td>${esc(t.message||'Bank movement')}</td><td>${esc(t.type||'transfer')}</td><td class="number ${minus?'negative':'positive'}">${minus?'-':'+'}${money(Math.abs(t.amount))}</td></tr>`}).join('')||'<tr><td colspan="4" class="muted">No transactions recorded yet</td></tr>'}</tbody></table></div>`;
  }
  function cardsPage() {
    return `<div class="page-head"><h2 class="title-condensed">YOUR DEBIT CARDS</h2><button class="button red" data-do="newCard">ISSUE NEW CARD</button></div><p class="page-intro">Your personalised physical cards, all connected to real WHIP bank accounts. Tap to see the reverse, change PIN or freeze a card instantly.</p>
      <div class="cards-grid premium-card-list">${(data?.cards||[]).map(c=>`<div class="premium-card-entry">
        <div class="premium-faces"><div class="premium-face-front">${cardArtwork(c.bankKey,c.cardStyle,{holder:data?.name||'CARDHOLDER',last4:c.last4,expires:c.expires,id:c.id})}</div>
        <div class="premium-face-back hidden">${cardArtwork(c.bankKey,c.cardStyle,{holder:data?.name||'CARDHOLDER',last4:c.last4,expires:c.expires,id:c.id},true)}</div></div>
        <div class="premium-verified"><span>● ${esc((BRANDS[c.bankKey]||BRANDS.maze).name)} · ${esc(CARD_STYLE_NAMES[c.cardStyle]||'EVERYDAY')}</span><span>•••• ${esc(c.last4)}</span></div>
        <div class="card-controls"><span class="pill ${c.status==='active'?'active':''}">${esc(c.status.toUpperCase())}</span><button class="smallbtn" data-flip-card="${c.id}">VIEW BACK</button>
        ${c.status!=='cancelled'?`<button class="smallbtn" data-card-toggle="${c.id}" data-status="${c.status==='active'?'frozen':'active'}">${c.status==='active'?'FREEZE':'UNFREEZE'}</button><button class="smallbtn" data-card-pin="${c.id}">CHANGE PIN</button><button class="smallbtn" data-card-toggle="${c.id}" data-status="cancelled">CANCEL</button>`:''}</div></div>`).join('')||'<div class="empty">No cards issued. Speak to a teller to get a personalised physical bank card.</div>'}</div>`;
  }
  function creditPage() {
    const n=data?.credit||650;
    return `<div class="page-head"><h2 class="title-condensed">CREDIT PROFILE</h2></div><div class="credit-layout"><section class="panel"><div class="smallgray">Your ${esc(bankName())} credit score</div><div class="score-large">${n}</div><div class="score-track"><i style="left:${(n-300)/550*100}%"></i></div><div class="smallgray">300 — Poor &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; 670 — Good &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; 850 — Excellent</div></section>
      <section class="panel"><h3>How credit works</h3><p>Scores start at ${data?.credit===undefined?650:650}. Timely loan repayments improve your score. Missed repayments reduce it.</p>
      <p>Higher scores unlock better borrowing products. Your score and eligibility are checked by the server whenever you apply.</p><button class="button red" data-tab="loans">VIEW LOANS</button></section></div>`;
  }
  function loansPage() {
    return `<div class="page-head"><h2 class="title-condensed">BORROWING & LOANS</h2><span class="smallgray">Credit score ${data?.credit}</span></div><p class="page-intro">All quotes show total repayments before you accept. Instalments are collected from your personal WHIP bank account.</p>
      <div class="offers">${(data?.products||[]).map(o=>`<article class="panel offer"><strong>${esc(o.label)}</strong><p>Up to ${money(o.max)} · ${o.rate}% flat interest · ${o.months} instalments</p><p>Minimum credit score ${o.minScore}</p><button class="button red" data-loan="${esc(o.key)}" ${data.credit<o.minScore?'disabled':''}>APPLY NOW</button></article>`).join('')}</div>
      <h3 class="section-title">Your loans</h3><div class="panel"><table class="data-table"><thead><tr><th>Loan</th><th>Balance left</th><th>Next due</th><th>Status</th><th></th></tr></thead><tbody>${(data?.loans||[]).map(l=>`<tr><td>${esc(l.product)} #${l.id}<small style="display:block;color:#777">Original ${money(l.principal)}</small></td><td>${money(l.remaining)}</td><td>${shortDate(l.nextDue)} · ${money(l.installment)}</td><td><span class="pill ${l.status==='active'?'active':l.status==='late'?'late':''}">${esc(l.status.toUpperCase())}</span></td><td>${l.status==='active'||l.status==='late'?`<button class="smallbtn" data-loanpay="${l.id}">REPAY</button>`:''}</td></tr>`).join('')||'<tr><td colspan="5">No loans yet</td></tr>'}</tbody></table></div>`;
  }
  function billsPage() {
    return `<div class="page-head"><h2 class="title-condensed">BILLS & INVOICES</h2><span class="smallgray">From the businesses and services in your city</span></div><p class="page-intro">Bills are sent securely by server resources. Pay outstanding balances from a bank account.</p>
      <div class="panel"><table class="data-table"><thead><tr><th>Bill</th><th>Due</th><th>Category</th><th>Amount</th><th>Status</th><th></th></tr></thead><tbody>${(data?.bills||[]).map(b=>`<tr><td>${esc(b.title)}</td><td class="${b.status==='unpaid'&&b.dueAt<Date.now()/1000?'negative':''}">${shortDate(b.dueAt)}</td><td>${esc(b.category)}</td><td class="moneyfont">${money(b.amount)}</td><td><span class="pill ${b.status==='paid'?'active':b.status==='unpaid'&&b.dueAt<Date.now()/1000?'late':''}">${esc(b.status)}</span></td><td>${b.status==='unpaid'?`<button class="smallbtn" data-bill="${b.id}">PAY</button>`:''}</td></tr>`).join('')||'<tr><td colspan="6">No bills issued to you.</td></tr>'}</tbody></table></div>`;
  }
  function scheduledPage() {
    return `<div class="page-head"><h2 class="title-condensed">SCHEDULED PAYMENTS</h2></div><p class="page-intro">Set up a recurring transfer every 7, 14 or 30 days. Insufficient funds keep the transfer pending.</p>
      <div class="panel"><h3>Create a standing order</h3><form id="scheduleForm"><div class="form-grid"><div class="field"><label>Pay from</label><select name="from">${choose(data.accounts,data.primary)}</select></div><div class="field"><label>Recipient account</label><input name="number" maxlength="32" placeholder="WB-123456" required></div>
        <div class="field"><label>Amount</label><input name="value" type="number" min="1" step="1" required></div><div class="field"><label>How often?</label><select name="days"><option value="7">Every 7 days</option><option value="14">Every 14 days</option><option value="30">Every 30 days</option></select></div>
        <div class="field"><label>Description</label><input name="label" maxlength="70" required placeholder="Rent, savings, etc."></div></div><div class="form-actions"><button class="button red">SET UP PAYMENT</button></div></form></div>
      <div class="panel"><h3>Existing standing orders</h3><table class="data-table"><thead><tr><th>Payment</th><th>Amount</th><th>Next payment</th><th>Status</th><th></th></tr></thead><tbody>${(data?.schedules||[]).map(s=>`<tr><td>${esc(s.label)}<small style="display:block;color:#777">Every ${s.days} days</small></td><td>${money(s.amount)}</td><td>${shortDate(s.nextAt)}</td><td><span class="pill ${s.status==='active'?'active':''}">${esc(s.status)}</span></td><td>${s.status==='active'?`<button class="smallbtn" data-cancel="${s.id}">CANCEL</button>`:''}</td></tr>`).join('')||'<tr><td colspan="5">No standing orders.</td></tr>'}</tbody></table></div>`;
  }
  function bankPage() {
    const b=brand();
    return `<div class="page-head"><h2 class="title-condensed">YOUR DIGITAL BRANCH</h2></div>
      <div class="panel"><h3>WELCOME TO ${esc(b.name)}</h3><p>Your checking and savings balances, transfers, loans and bills all use WHIP Core.</p>
      <div class="form-actions"><button class="button red" data-tab="accounts">MY ACCOUNTS</button><button class="button ghost" data-tab="cards">BANK CARDS</button></div></div>
      <div class="panel"><h3>BANK MEMBERSHIP</h3><p>Current bank: <b>${esc(b.name)}</b>. Savings APR: <b>${Number(data?.bank?.savingsApr||0).toFixed(1)}%</b>. ATM withdrawal cap: <b>${money(data?.bank?.atmDailyLimit||5000)}</b> per day.</p>
      ${fromTeller&&data?.bankSwitching?'<button class="button red" data-do="switchBank">COMPARE & SWITCH BANK</button>':
      '<p>To change banks, visit any bank teller. Your money stays in your existing WHIP accounts.</p>'}</div>`;
  }
  function draw() {
    if(!data)return;
    renderSidebar();renderTabs();
    const views={accounts:accountsPage,transfer:transferPage,history:historyPage,cards:cardsPage,credit:creditPage,loans:loansPage,bills:billsPage,scheduled:scheduledPage,bank:bankPage};
    $('#tabBody').innerHTML=(views[activeTab]||accountsPage)();$('#tabBody').scrollTop=0;
  }

  function showModal(title,content,submit) {
    $('#modalTitle').textContent=title;$('#modalContents').innerHTML=content;modal.classList.remove('hidden');
    const form=$('#modalContents form');
    if(form)form.addEventListener('submit',async ev=>{ev.preventDefault();const b=form.querySelector('[type=submit]');if(b)b.disabled=true;
      try {const ok=await submit(fields(form));if(ok)modal.classList.add('hidden');}
      finally {if(b)b.disabled=false;}
    });
  }
  function accountModal(kind) {
    showModal(kind==='shared'?'NEW SHARED ACCOUNT':'NEW SAVINGS POT',`<form class="form-grid"><div class="field"><label>Account name</label><input name="label" maxlength="40" placeholder="${kind==='shared'?'Crew fund':'Rainy day'}" required></div><button class="button red" type="submit">CREATE ACCOUNT</button></form>`,
      f=>run('accountCreate',[kind,f.label],'Account created'));
  }
  function cardModal() {
    showModal('ISSUE DEBIT CARD',`<form class="form-grid"><p style="margin:0">A bank teller must issue the card. The physical item will go into your WHIP inventory.</p>
      <div class="field"><label>Link to account</label><select name="account">${choose(data.accounts,data.primary)}</select></div><div class="field"><label>Choose four-digit PIN</label><input name="pin" type="password" inputmode="numeric" minlength="4" maxlength="4" pattern="[0-9]{4}" required></div>
      <div class="field"><label>Card style</label><select name="style"><option value="classic">Everyday</option><option value="black">Cash+</option><option value="metal">Metal</option></select></div><button class="button red" type="submit">ISSUE PHYSICAL CARD</button></form>`,f=>run('issueCard',[Number(f.account),f.pin,f.style],'Card issued to your inventory'));
  }
  function pinModal(id) {
    showModal('CHANGE CARD PIN',`<form class="form-grid"><div class="field"><label>Current PIN</label><input name="old" type="password" inputmode="numeric" maxlength="4" pattern="[0-9]{4}" required></div>
      <div class="field"><label>New PIN</label><input name="new" type="password" inputmode="numeric" maxlength="4" pattern="[0-9]{4}" required></div><button class="button red" type="submit">SAVE NEW PIN</button></form>`,
      f=>run('pinChange',[id,f.old,f.new],'PIN changed'));
  }
  function loanModal(kind) {
    const offer=data.products.find(x=>x.key===kind);
    if(!offer)return;
    const max=offer.max;
    showModal('APPLY FOR '+offer.label.toUpperCase(),`<form class="form-grid"><p style="margin:0">${offer.rate}% flat interest, repaid over ${offer.months} monthly instalments. Minimum score: ${offer.minScore}.</p>
      <div class="field"><label>Borrow amount</label><input name="value" min="100" max="${max}" type="number" step="1" required placeholder="Up to ${money(max)}"></div>
      <div class="field"><label>Personal account</label><select name="account">${choose(data.accounts.filter(a=>a.isDefault),data.primary)}</select></div>
      <div class="notice">After approval the loan is credited to your WHIP bank account, with repayment dates recorded in the Loans tab.</div><button class="button red" type="submit">ACCEPT LOAN TERMS</button></form>`,
      f=>run('loanApply',[Number(f.account),kind,Number(f.value)],'Loan accepted and funds credited'));
  }
  function repayModal(id) {
    const loan=data.loans.find(l=>l.id===id);if(!loan)return;
    showModal('LOAN REPAYMENT',`<form class="form-grid"><div>Outstanding: <strong>${money(loan.remaining)}</strong></div><div class="field"><label>Pay amount</label><input name="amount" min="1" max="${loan.remaining}" value="${Math.min(loan.installment,loan.remaining)}" type="number" step="1" required></div>
      <button class="button red" type="submit">MAKE REPAYMENT</button></form>`,f=>run('loanPay',[id,Number(f.amount)],'Repayment received'));
  }
  function billModal(id) {
    const bill=data.bills.find(b=>b.id===id);if(!bill)return;
    showModal('PAY BILL',`<form class="form-grid"><p>Pay <strong>${esc(bill.title)}</strong> — <strong>${money(bill.amount)}</strong></p><div class="field"><label>From account</label><select name="account">${choose(data.accounts,data.primary)}</select></div><button class="button red" type="submit">CONFIRM PAYMENT</button></form>`,
      f=>run('billPay',[id,Number(f.account)],'Bill paid'));
  }
  function confirmAction(title,body,fn) {
    showModal(title,`<p>${esc(body)}</p><div class="form-actions"><button class="button ghost" id="confirmNo">GO BACK</button><button class="button red" id="confirmYes">CONFIRM</button></div>`,null);
    $('#confirmNo').addEventListener('click',()=>modal.classList.add('hidden'));
    $('#confirmYes').addEventListener('click',async e=>{e.currentTarget.disabled=true;
      const result=await fn();if(result)modal.classList.add('hidden');else e.currentTarget.disabled=false;
    });
  }

  $('#tabs').addEventListener('click',e=>{const b=e.target.closest('[data-tab]');if(b){activeTab=b.dataset.tab;draw();}});
  $('#tabBody').addEventListener('click',async e=>{
    const t=e.target.closest('button');if(!t)return;
    if(t.dataset.tab){activeTab=t.dataset.tab;draw();return;}
    if(t.dataset.flipCard){
      const card=t.closest('.premium-card-entry');
      if(card){const front=card.querySelector('.premium-face-front'),back=card.querySelector('.premium-face-back');
        front.classList.toggle('hidden');back.classList.toggle('hidden');
        t.textContent=back.classList.contains('hidden')?'VIEW BACK':'VIEW FRONT';}
      return;
    }
    const action=t.dataset.do;
    if(action==='savings'||action==='shared')accountModal(action);
    if(action==='newCard')cardModal();
    if(action==='switchBank')showChoice(true);
    if(t.dataset.cardPin)pinModal(Number(t.dataset.cardPin));
    if(t.dataset.cardToggle){
      const go=()=>run('cardStatus',[Number(t.dataset.cardToggle),t.dataset.status],'Card updated');
      if(t.dataset.status==='cancelled')confirmAction('CANCEL DEBIT CARD','This card will stop authorising new ATM sessions. The cancellation cannot be undone.',go);
      else await go();
    }
    if(t.dataset.loan)loanModal(t.dataset.loan);
    if(t.dataset.loanpay)repayModal(Number(t.dataset.loanpay));
    if(t.dataset.bill)billModal(Number(t.dataset.bill));
    if(t.dataset.cancel)confirmAction('CANCEL STANDING ORDER','Future scheduled payments will stop. Previous transfers remain on your statement.',
      ()=>run('scheduleCancel',[Number(t.dataset.cancel)],'Standing order cancelled'));
  });
  $('#tabBody').addEventListener('submit',async e=>{
    e.preventDefault();const f=fields(e.target),b=e.target.querySelector('[type=submit]');if(b)b.disabled=true;
    if(e.target.id==='transferForm')await run('transfer',[Number(f.from),f.number,Number(f.value)],'Transfer completed');
    if(e.target.id==='scheduleForm')await run('scheduleCreate',[Number(f.from),f.number,Number(f.value),Number(f.days),f.label],'Standing order scheduled');
    if(b&&document.contains(b))b.disabled=false;
  });
  $('#closeBank').addEventListener('click',closeBank);
  $('#modalClose').addEventListener('click',()=>modal.classList.add('hidden'));
  modal.addEventListener('mousedown',e=>{if(e.target===modal)modal.classList.add('hidden');});
  $('#modalContents').addEventListener('click',e=>{
    const button=e.target.closest('[data-teller-tab]');
    if(button){activeTab=button.dataset.tellerTab;modal.classList.add('hidden');draw();}
  });

  // ---------- Minimal physical card preview from inventory (no banking actions) ----------
  function openCardPreview(card){
    if(!card || !BRANDS[card.bankKey])return;
    previewCard=card;
    modal.classList.add('hidden');bank.classList.add('hidden');
    bankSelection.classList.add('hidden');atm.classList.add('hidden');
    cardViewer.dataset.bank=card.bankKey;
    $('#cardViewerFront').innerHTML=cardArtwork(card.bankKey,card.cardStyle,
      {holder:card.holder,last4:card.last4,expires:card.expires,id:card.id});
    $('#cardViewerBack').innerHTML=cardArtwork(card.bankKey,card.cardStyle,
      {holder:card.holder,last4:card.last4,expires:card.expires,id:card.id},true);
    cardViewerStage.classList.remove('flipped');
    updateCardViewerFlip();
    cardViewer.classList.remove('hidden');
  }
  function updateCardViewerFlip(){
    const reversed=cardViewerStage.classList.contains('flipped');
    $('#cardViewerFlip').setAttribute('aria-pressed',String(reversed));
    cardViewerStage.setAttribute('aria-label',reversed?'View front of bank card':'View back of bank card');
  }
  function flipCardPreview(){
    if(cardViewer.classList.contains('hidden'))return;
    cardViewerStage.classList.toggle('flipped');updateCardViewerFlip();
  }
  function closeCardPreview(){
    cardViewer.classList.add('hidden');previewCard=null;post('close');
  }
  $('#cardViewerFlip').addEventListener('click',flipCardPreview);
  cardViewerStage.addEventListener('click',flipCardPreview);
  cardViewerStage.addEventListener('keydown',e=>{
    if(e.key==='Enter'||e.key===' '){e.preventDefault();flipCardPreview();}
  });

  // ---------- Real ATM controls: the hardware, not a floating PIN menu ----------
  const terminal = $('#terminalContents');
  const hardwareSteps=new Set(['pin','menu','fast','amount','balance','complete','error']);
  const hardwareCurrent=()=>hardwareSteps.has(screen) && !atm.classList.contains('hidden');
  function setHardwareListening(active){
    if(keypadModeSent===active)return;
    keypadModeSent=active;
    post('atmKeypadMode',{active});
  }
  function atmFrame(next,extra={}) {
    screen=next;
    setHardwareListening(hardwareSteps.has(next));
    // This player sees the brand of THEIR character's account at any machine.
    const bkey=atmData?.customerBankKey||atmData?.bankKey||'maze';
    const b=BRANDS[bkey]||BRANDS.maze;
    post('atmFrame',{screen,bankKey:bkey,brand:b.name,currency:currency(),
      last4:(activeCard||chosenCard)?.last4,name:atmData?.name,
      balance:activeCard?.balance,cash:activeCard?.cash,...extra});
    updateKeypadLayer();
  }
  function atmMenu(){
    terminal.innerHTML='';atmFrame('menu');
  }
  function atmCardSelector(){
    pinDigits='';insertingCard=false;amountDigits='';chosenCard=null;
    $('#terminalTitle').textContent='CHOOSE BANK CARD';
    const cards=(atmData?.cards||[]).filter(c=>c.status==='active');
    terminal.innerHTML=cards.length?`<p>Choose a physical debit card to insert.</p><div class="atm-keyset">${cards.map(c=>`<button data-atm-card="${c.id}" style="width:100%">${esc(c.label||'Debit')} · •••• ${esc(c.last4)}</button>`).join('')}</div>`:
      '<p>No active debit card. Visit a bank teller to obtain one.</p>';
    atmFrame('idle');
  }
  async function beginCardInsertion(id){
    if(insertingCard)return;
    const card=(atmData?.cards||[]).find(c=>Number(c.id)===Number(id));
    if(!card||card.status!=='active')return say('This card is unavailable',true);
    chosenCard=card;insertingCard=true;const serial=++insertSequence;
    $('#terminalTitle').textContent='INSERTING CARD';
    terminal.innerHTML='<p>Inserting your debit card into the physical ATM.</p>';
    const result=await post('atmInsertCard',{cardId:card.id});
    if(serial!==insertSequence||atm.classList.contains('hidden'))return;
    if(!result?.ok){insertingCard=false;say(result?.error||'Could not insert this card',true);return atmCardSelector();}
    await new Promise(done=>setTimeout(done,Number(result.duration)||1100));
    if(serial!==insertSequence||atm.classList.contains('hidden'))return;
    insertingCard=false;atmPin(card.id);
  }
  function updateKeypadLayer(){
    const active=hardwareCurrent()||keypadDebug;
    // Once a card has been inserted the transparent projection is the ONLY
    // input layer. In particular do not show a substitute keypad on the right.
    atm.classList.toggle('atm-hardware-mode',active);
    keypadLayer.classList.toggle('debug',keypadDebug);
    if(!active || !keypadCoords?.keys?.length){
      keypadLayer.classList.add('hidden');keypadLayer.innerHTML='';return;
    }
    keypadLayer.classList.remove('hidden');
    const hit=(k,side=false)=>`<button type="button" class="atm-key-hotspot atm-key-centred ${side?'atm-side-hotspot':''}" ${side?'data-side-key':'data-pin-key'}="${esc(k.key)}" aria-label="${side?'ATM side button':'ATM keypad button'} ${esc(k.key)}" style="left:${(Math.max(0,Math.min(1,Number(k.x)))*100).toFixed(3)}%;top:${(Math.max(0,Math.min(1,Number(k.y)))*100).toFixed(3)}%;width:${(Math.max(.004,Math.min(.12,Number(k.w)))*100).toFixed(3)}vw;height:${(Math.max(.008,Math.min(.12,Number(k.h)))*100).toFixed(3)}vh"></button>`;
    keypadLayer.innerHTML=keypadCoords.keys.map(k=>hit(k)).join('') + (keypadCoords.sides||[]).map(k=>hit(k,true)).join('');
  }
  function showPinState(message=''){
    if(screen!=='pin')return;
    terminal.innerHTML='';
    atmFrame('pin',{pinCount:pinDigits.length,message});
  }
  function atmPin(id){
    chosenCard=atmData.cards.find(x=>Number(x.id)===Number(id));if(!chosenCard)return;
    pinDigits='';atm.dataset.bank=atmData?.customerBankKey||atmData?.bankKey||'maze';
    $('#atm .atm-title span').textContent=(BRANDS[atm.dataset.bank]||BRANDS.maze).name;
    screen='pin';showPinState();
  }
  async function atmPinPress(key){
    if(screen!=='pin'||insertingCard||pinBusy)return;
    if(key==='CANCEL')return atmCardSelector();
    if(key==='CLEAR'||key==='BACKSPACE'){pinDigits=pinDigits.slice(0,-1);showPinState();return;}
    if(key==='ENTER'){
      if(pinDigits.length!==4){say('Enter all four PIN digits',true);return;}
      const value=pinDigits;pinDigits='';
      await atmAuthenticate(value);return;
    }
    if(/^[0-9]$/.test(key)&&pinDigits.length<4){pinDigits+=key;showPinState();}
  }
  async function atmAuthenticate(pin){
    if(pinBusy)return;
    pinBusy=true;
    const result=await post('request',{action:'atmAuth',args:[chosenCard.number,pin]});
    pinBusy=false;
    if(!result.ok){say(result.error||'PIN incorrect',true);screen='pin';pinDigits='';showPinState(result.error||'Incorrect PIN');return;}
    activeCard={...chosenCard,...result.data,cash:atmData.cash};
    atmData.dailyLimit=result.data?.limit??atmData.dailyLimit;
    pinDigits='';atmMenu();
  }
  function atmFast(){
    terminal.innerHTML='';atmFrame('fast',{limit:atmData?.dailyLimit});
  }
  function atmAmount(){
    amountDigits='';terminal.innerHTML='';atmFrame('amount',{enteredAmount:0});
  }
  async function atmMoney(n){
    n=Number(n);
    if(!activeCard||processingCash)return;
    if(!Number.isInteger(n)||n<1)return say('Enter a whole withdrawal amount',true);
    if(n>Number(atmData.dailyLimit||5000))return say('Maximum amount per transaction exceeded',true);
    processingCash=true;
    atmFrame('processing',{amount:n,message:'withdraw'});
    const result=await post('atmMoney',{kind:'withdraw',amount:n,accountId:activeCard.accountId});
    processingCash=false;
    if(atm.classList.contains('hidden'))return;
    if(!result.ok){say(result.error||'Transaction declined',true);atmFrame('error',{message:result.error});return;}
    activeCard.balance=result.data?.balance??activeCard.balance;
    activeCard.cash=result.data?.cash??activeCard.cash;
    if(result.data?.limit!==undefined)atmData.dailyLimit=result.data.limit;
    atmFrame('complete',{message:'PLEASE TAKE YOUR CASH',amount:n});
  }
  function atmChoice(action){
    if(action==='fast')return atmFast();
    if(action==='withdraw'||action==='other')return atmAmount();
    if(action==='balance')return atmFrame('balance');
    if(action==='back')return atmMenu();
    if(action==='finish')return atmClose();
  }
  function handlePhysicalKey(key){
    if(screen==='pin')return atmPinPress(key);
    if(screen==='menu'){
      if(key==='1')return atmChoice('fast');
      if(key==='2')return atmChoice('withdraw');
      if(key==='3')return atmChoice('balance');
      if(key==='CANCEL'||key==='5')return atmChoice('finish');
      return;
    }
    if(screen==='fast'){
      const quick={'1':20,'2':60,'3':100,'4':200,'5':500};
      if(quick[key])return atmMoney(quick[key]);
      if(key==='7')return atmAmount();
      if(key==='CANCEL'||key==='CLEAR')return atmMenu();
      return;
    }
    if(screen==='amount'){
      // The real keypad's bottom-left MINUS / bottom-right PLUS keys are not PIN digits.
      // On the amount screen they adjust the withdrawal in £10 increments.
      if(key==='MINUS'||key==='PLUS'){
        const next=Math.max(0,Math.min(9999999,(Number(amountDigits)||0)+(key==='PLUS'?10:-10)));
        amountDigits=next?String(next):'';
        atmFrame('amount',{enteredAmount:next});return;
      }
      if(key==='CANCEL')return atmMenu();
      if(key==='CLEAR'){amountDigits=amountDigits.slice(0,-1);atmFrame('amount',{enteredAmount:Number(amountDigits)||0});return;}
      if(key==='ENTER')return atmMoney(Number(amountDigits)||0);
      if(/^[0-9]$/.test(key)&&amountDigits.length<7){amountDigits+=key;atmFrame('amount',{enteredAmount:Number(amountDigits)||0});}
      return;
    }
    if(['balance','complete','error'].includes(screen)&&['CANCEL','ENTER','CLEAR'].includes(key))return atmMenu();
  }
  function handlePhysicalSide(key){
    if(screen==='menu'){
      if(key==='L1')return atmFast();
      if(key==='L2')return atmAmount();
      if(key==='L3')return atmFrame('balance');
      if(key==='R1'||key==='R4')return atmClose();
    }
    if(screen==='fast'){
      const quick={L1:20,L2:60,L3:100,L4:200,R1:500};
      if(quick[key])return atmMoney(quick[key]);
      if(key==='R3')return atmAmount();
      if(key==='R4')return atmMenu();
    }
    if(screen==='amount'&&key==='R4')return atmMenu();
    if(['balance','complete','error'].includes(screen)&&key==='R4')return atmMenu();
  }
  function atmOpen(payload) {
    keypadDebug=false;
    atmData=payload;activeCard=null;chosenCard=null;pinBuffer='';pinBusy=false;keypadCoords=null;pinDigits='';amountDigits='';insertingCard=false;processingCash=false;insertSequence++;keypadModeSent=false;
    keypadLayer.innerHTML='';keypadLayer.classList.add('hidden');atm.classList.remove('atm-pin-mode');bank.classList.add('hidden');
    cardViewer.classList.add('hidden');atm.classList.remove('hidden');
    atm.dataset.bank=payload?.customerBankKey||payload?.bankKey||'maze';
    $('#atm .atm-title span').textContent=(BRANDS[atm.dataset.bank]||BRANDS.maze).name;
    $('#terminalTitle').textContent='READY TO BANK';
    terminal.innerHTML='<p>Insert your debit card into the reader, or tap the contactless pad.</p>';
    atmFrame('idle');
    // A player using a physical debit-card item at the ATM has already chosen
    // their card in the inventory. Go straight to that card's PIN entry, with
    // the same server-side ownership and physical-item validation as normal.
    if (payload?.selectedNumber) {
      const card=(payload.cards||[]).find(c=>c.number===payload.selectedNumber);
      if (card?.status==='active') beginCardInsertion(card.id);
      else say('This bank card is frozen, cancelled or no longer valid.',true);
    }
  }
  function atmClose() {keypadDebug=false;setHardwareListening(false);insertSequence++;pinDigits='';amountDigits='';insertingCard=false;keypadCoords=null;keypadLayer.classList.add('hidden');atm.classList.remove('atm-pin-mode');atm.classList.add('hidden');post('close');atmData=null;activeCard=null;chosenCard=null;}
  $('#reader').addEventListener('click',atmCardSelector);$('#tap').addEventListener('click',atmCardSelector);
  $('#terminalExit').addEventListener('click',atmClose);
  terminal.addEventListener('click',e=>{
    const card=e.target.closest('[data-atm-card]');if(card)return beginCardInsertion(Number(card.dataset.atmCard));
    const fast=e.target.closest('[data-fast]');if(fast)return atmMoney(Number(fast.dataset.fast));
    const choice=e.target.closest('[data-atm-choice]');if(choice)return atmChoice(choice.dataset.atmChoice);
  });
  keypadLayer.addEventListener('click',e=>{
    const key=e.target.closest('[data-pin-key]');if(key){e.preventDefault();return handlePhysicalKey(key.dataset.pinKey);}
    const side=e.target.closest('[data-side-key]');if(side){e.preventDefault();return handlePhysicalSide(side.dataset.sideKey);}
  });
  terminal.addEventListener('submit',async e=>{
    e.preventDefault();const f=fields(e.target);
    if(e.target.id==='amountForm')return atmMoney(Number(f.amount));
  });

  document.addEventListener('keydown',e=>{
    if(e.key==='Escape'){
      if(!modal.classList.contains('hidden'))modal.classList.add('hidden');
      else if(!bankSelection.classList.contains('hidden')){bankSelection.classList.add('hidden');if(data?.bankKey){bank.classList.remove('hidden');draw();}else post('close');}
      else if(!cardViewer.classList.contains('hidden'))closeCardPreview();
      else if(!bank.classList.contains('hidden'))closeBank();
      else if(!atm.classList.contains('hidden'))atmClose();
      return;
    }
    if(atm.classList.contains('hidden'))return;
    if(/^[0-9]$/.test(e.key)&&hardwareSteps.has(screen)){
      e.preventDefault();return handlePhysicalKey(e.key);
    }
    if(e.key==='Backspace'&&hardwareSteps.has(screen)){
      e.preventDefault();return handlePhysicalKey('CLEAR');
    }
    if(e.key==='Enter'&&hardwareSteps.has(screen)){
      e.preventDefault();return handlePhysicalKey('ENTER');
    }

  });

  window.addEventListener('message',e=>{
    const m=e.data;if(!m||typeof m!=='object')return;
    if(m.type==='openCardPreview')openCardPreview(m.data);
    if(m.type==='openBank')openBank(m.data,m.teller);
    if(m.type==='openAtm')atmOpen(m.data);
    if(m.type==='atmKeypadDebug'){keypadDebug=m.active===true;updateKeypadLayer();}
    if(m.type==='atmKeypadLayout'){const next=m.data?.keys?.length?m.data:null;if(JSON.stringify(next)!==JSON.stringify(keypadCoords)){keypadCoords=next;updateKeypadLayer();}}
    if(m.type==='close'){bank.classList.add('hidden');bankSelection.classList.add('hidden');atm.classList.add('hidden');modal.classList.add('hidden');cardViewer.classList.add('hidden');previewCard=null;}
  });
  if(preview)openBank(demo,false);
})();
