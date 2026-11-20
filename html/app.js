(() => {
  'use strict';
  const $ = s => document.querySelector(s);
  const bank = $('#bank'), atm = $('#atm'), modal = $('#modal'), toast = $('#toast');
  let data = null, activeTab = 'accounts', fromTeller = false, screen = 'idle';
  let atmData = null, chosenCard = null, activeCard = null, atmMessage = '';
  const preview = new URLSearchParams(location.search).has('preview');
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
    if(result.ok && result.data){data=result.data;draw();}
  }
  function openBank(payload,teller=false) {
    data=payload;fromTeller=!!teller;activeTab='accounts';
    atm.classList.add('hidden');bank.classList.remove('hidden');modal.classList.add('hidden');draw();
    if(fromTeller) showModal('WELCOME TO MAZE BANK',`<p style="font-size:17px;margin:0 0 16px">Good afternoon. What can I help you with today?</p>
      <div class="form-grid one"><button class="button red" data-teller-tab="accounts">CHECK MY ACCOUNTS</button>
      <button class="button" data-teller-tab="cards">BANK CARDS & PIN SERVICES</button>
      <button class="button" data-teller-tab="loans">DISCUSS A LOAN</button>
      <button class="button" data-teller-tab="transfer">SEND A BANK TRANSFER</button></div>`,null);
  }
  function closeBank() {bank.classList.add('hidden');modal.classList.add('hidden');post('close');}
  function primary() {return data?.accounts?.find(a=>a.accountId===data.primary)||data?.accounts?.[0]||{};}

  function renderSidebar() {
    $('#personName').textContent=data?.name||'YOUR ACCOUNTS';
    $('#accountNumber').textContent=primary().accountNumber||'MAZE BANK';
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
    return `<div class="page-head"><h2 class="title-condensed">YOUR CARDS</h2><button class="button red" data-do="newCard">ISSUE NEW CARD</button></div><p class="page-intro">Physical contactless cards, four-digit PINs and immediate freeze controls. Bring your card to an ATM.</p>
      <div class="cards-grid">${(data?.cards||[]).map(c=>`<div><div class="bankcard"><div class="card-head"><span>MAZE BANK</span><span>)))</span></div><span class="card-chip"></span><div class="card-number">•••• •••• •••• ${esc(c.last4)}</div><div class="card-bottom"><span>${esc(data?.name||'CARD HOLDER').toUpperCase()}</span><b>DEBIT</b></div></div>
      <div class="card-controls"><span class="pill ${c.status==='active'?'active':''}">${esc(c.status.toUpperCase())}</span>
      ${c.status!=='cancelled'?`<button class="smallbtn" data-card-toggle="${c.id}" data-status="${c.status==='active'?'frozen':'active'}">${c.status==='active'?'FREEZE':'UNFREEZE'}</button><button class="smallbtn" data-card-pin="${c.id}">CHANGE PIN</button><button class="smallbtn" data-card-toggle="${c.id}" data-status="cancelled">CANCEL</button>`:''}</div></div>`).join('')||'<div class="empty">No cards issued. Speak to a teller to get a physical card.</div>'}</div>`;
  }
  function creditPage() {
    const n=data?.credit||650;
    return `<div class="page-head"><h2 class="title-condensed">CREDIT PROFILE</h2></div><div class="credit-layout"><section class="panel"><div class="smallgray">Your Maze credit score</div><div class="score-large">${n}</div><div class="score-track"><i style="left:${(n-300)/550*100}%"></i></div><div class="smallgray">300 — Poor &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; 670 — Good &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; 850 — Excellent</div></section>
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
    return `<div class="page-head"><h2 class="title-condensed">YOUR DIGITAL BRANCH</h2></div><div class="panel"><h3>Welcome to Maze Bank</h3><p>Manage your money, cards, savings, scheduled transfers, bills, credit and loans in one place.</p><div class="form-actions"><button class="button red" data-tab="accounts">MY ACCOUNTS</button><button class="button ghost" data-tab="cards">BANK CARDS</button></div></div>
      <div class="panel"><h3>Visit us in person</h3><p>Our branch tellers can issue new debit cards and help with your account. At any city ATM, insert or tap a physical card and enter the four-digit PIN.</p><p>Eight public branch counters are available. All four standard GTA V ATM models are supported.</p></div>`;
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
      <button class="button red" type="submit">ISSUE PHYSICAL CARD</button></form>`,f=>run('issueCard',[Number(f.account),f.pin],'Card issued to your inventory'));
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
    const action=t.dataset.do;
    if(action==='savings'||action==='shared')accountModal(action);
    if(action==='newCard')cardModal();
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

  // ---------- Physical ATM reader and keypad ----------
  const terminal = $('#terminalContents');
  function atmFrame(next,extra={}) {
    screen=next;
    post('atmFrame',{screen,brand:atmData?.brand||'MAZE BANK',currency:currency(),
      last4:(activeCard||chosenCard)?.last4,name:atmData?.name,
      balance:activeCard?.balance,cash:activeCard?.cash,...extra});
  }
  function atmMenu() {
    $('#terminalTitle').textContent='ATM MENU';
    terminal.innerHTML='<p>Use the keys for the options displayed on the cash machine.</p><div class="atm-keyset"><button data-atm-choice="fast">1 — FAST CASH</button><button data-atm-choice="withdraw">2 — WITHDRAW</button><button data-atm-choice="balance">3 — BALANCE</button><button data-atm-choice="finish">CANCEL</button></div>';
    atmFrame('menu');
  }
  function atmCardSelector() {
    $('#terminalTitle').textContent='SELECT BANK CARD';
    const cards=(atmData?.cards||[]).filter(c=>c.status==='active');
    terminal.innerHTML=cards.length?`<p>Select the card you are inserting or tapping.</p><div class="atm-keyset">${cards.map(c=>`<button data-atm-card="${c.id}" style="width:100%">${esc(c.label||'Debit')} · •••• ${esc(c.last4)}</button>`).join('')}</div>`:
      '<p>No active debit card. Visit a branch teller to get one.</p>';
    atmFrame('idle');
  }
  function atmPin(id) {
    chosenCard=atmData.cards.find(x=>x.id===id);
    if(!chosenCard)return;
    $('#terminalTitle').textContent='ENTER PIN';
    terminal.innerHTML=`<p>Card ending <strong>${esc(chosenCard.last4)}</strong></p><form id="pinForm" class="field"><label>Four-digit secure PIN</label><input name="pin" type="password" inputmode="numeric" maxlength="4" pattern="[0-9]{4}" autocomplete="off" required autofocus><button class="button">CONTINUE</button></form>`;
    atmFrame('pin');
    terminal.querySelector('input')?.focus();
  }
  async function atmAuthenticate(pin) {
    const result=await post('request',{action:'atmAuth',args:[chosenCard.number,pin]});
    if(!result.ok){say(result.error||'PIN incorrect',true);atmFrame('pin',{message:result.error});return;}
    activeCard={...chosenCard,...result.data,cash:atmData.cash};
    atmData.dailyLimit=result.data?.limit??atmData.dailyLimit;atmMenu();
  }
  function atmFast() {
    $('#terminalTitle').textContent='FAST CASH';
    terminal.innerHTML='<p>Choose your cash amount.</p><div class="atm-keyset">'+[20,60,100,200,500].map((v,i)=>`<button data-fast="${v}">${i+1} — ${money(v)}</button>`).join('')+'<button data-atm-choice="other">OTHER AMOUNT</button><button data-atm-choice="back">BACK</button></div>';
    atmFrame('fast');
  }
  function atmAmount() {
    $('#terminalTitle').textContent='CASH WITHDRAWAL';
    terminal.innerHTML='<form id="amountForm" class="field"><label>Amount to withdraw</label><input name="amount" type="number" inputmode="numeric" min="1" step="1" required><button class="button">CONFIRM</button></form><button class="button ghost" data-atm-choice="back" style="margin-top:10px;width:100%">BACK</button>';
    terminal.dataset.kind='withdraw';atmFrame('amount',{message:'withdraw'});terminal.querySelector('input')?.focus();
  }
  async function atmMoney(n) {
    n=Number(n);
    if(!activeCard)return;
    if(!Number.isInteger(n)||n<1)return say('Enter a whole amount',true);
    if(n>Number(atmData.dailyLimit||5000))return say('Maximum amount per transaction exceeded',true);
    $('#terminalTitle').textContent='PROCESSING';terminal.innerHTML='<p>Please wait while we process your cash transaction...</p>';
    atmFrame('processing',{amount:n,message:'withdraw'});
    const result=await post('atmMoney',{kind:'withdraw',amount:n,accountId:activeCard.accountId});
    if(!result.ok){say(result.error||'Transaction declined',true);terminal.innerHTML=`<p>${esc(result.error||'Transaction declined')}</p><button class="button" data-atm-choice="back">BACK</button>`;atmFrame('error',{message:result.error});return;}
    activeCard.balance=result.data?.balance??activeCard.balance;activeCard.cash=result.data?.cash??activeCard.cash;
    if(result.data?.limit!==undefined) atmData.dailyLimit=result.data.limit;
    terminal.innerHTML=`<p>Please take your cash.<br>New balance: <strong>${money(activeCard.balance)}</strong></p><button class="button" data-atm-choice="back">CONTINUE</button>`;
    atmFrame('complete',{message:'PLEASE TAKE YOUR CASH',amount:n});
  }
  function atmChoice(action) {
    if(action==='fast')return atmFast();
    if(action==='withdraw'||action==='other')return atmAmount();
    if(action==='balance'){
      terminal.innerHTML=`<p>Available balance <strong>${money(activeCard?.balance)}</strong></p><button class="button" data-atm-choice="back">BACK</button>`;
      return atmFrame('balance');
    }
    if(action==='back')return atmMenu();
    if(action==='finish')return atmClose();
  }
  function atmOpen(payload) {
    atmData=payload;activeCard=null;chosenCard=null;bank.classList.add('hidden');atm.classList.remove('hidden');
    $('#terminalTitle').textContent='READY TO BANK';
    terminal.innerHTML='<p>Insert your Maze Bank card into the reader, or tap the contactless pad.</p>';
    atmFrame('idle');
  }
  function atmClose() {atm.classList.add('hidden');post('close');atmData=null;activeCard=null;chosenCard=null;}
  $('#reader').addEventListener('click',atmCardSelector);$('#tap').addEventListener('click',atmCardSelector);
  $('#terminalExit').addEventListener('click',atmClose);
  terminal.addEventListener('click',e=>{
    const card=e.target.closest('[data-atm-card]');if(card)return atmPin(Number(card.dataset.atmCard));
    const fast=e.target.closest('[data-fast]');if(fast)return atmMoney(Number(fast.dataset.fast));
    const choice=e.target.closest('[data-atm-choice]');if(choice)return atmChoice(choice.dataset.atmChoice);
  });
  terminal.addEventListener('submit',async e=>{
    e.preventDefault();const f=fields(e.target);
    if(e.target.id==='pinForm')return atmAuthenticate(f.pin);
    if(e.target.id==='amountForm')return atmMoney(Number(f.amount));
  });

  document.addEventListener('keydown',e=>{
    if(e.key==='Escape'){
      if(!modal.classList.contains('hidden'))modal.classList.add('hidden');
      else if(!bank.classList.contains('hidden'))closeBank();
      else if(!atm.classList.contains('hidden'))atmClose();
      return;
    }
    if(atm.classList.contains('hidden')||['INPUT','TEXTAREA','SELECT'].includes(document.activeElement?.tagName))return;
    const n=Number(e.key);
    if(screen==='menu'&&n>=1&&n<=3)return atmChoice(['','fast','withdraw','balance'][n]);
    if(screen==='fast'&&n>=1&&n<=5)return atmMoney([0,20,60,100,200,500][n]);
    if(screen==='fast'&&n===7)return atmAmount();
  });

  window.addEventListener('message',e=>{
    const m=e.data;if(!m||typeof m!=='object')return;
    if(m.type==='openBank')openBank(m.data,m.teller);
    if(m.type==='openAtm')atmOpen(m.data);
    if(m.type==='close'){bank.classList.add('hidden');atm.classList.add('hidden');modal.classList.add('hidden');}
  });
  if(preview)openBank(demo,false);
})();
