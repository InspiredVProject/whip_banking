(()=>{
 'use strict';
 const canvas=document.getElementById('card'),ctx=canvas.getContext('2d');
 const themes={fleeca:{name:'FLEECA BANK',tag:'THE NEIGHBOURHOOD BANK',base:'#278553',dark:'#12522f'},maze:{name:'MAZE BANK',tag:'OF LOS SANTOS',base:'#b92d3b',dark:'#671926'},pacific:{name:'PACIFIC STANDARD',tag:'PUBLIC DEPOSIT BANK',base:'#204d88',dark:'#112b4c'}};
 function rounded(x,y,w,h,r){ctx.beginPath();ctx.roundRect(x,y,w,h,r)}
 function draw(data){
  const bank=themes[data.bankKey]||themes.maze,style=['classic','black','metal'].includes(data.cardStyle)?data.cardStyle:'classic';
  ctx.clearRect(0,0,800,500);
  const grad=ctx.createLinearGradient(50,30,770,470);
  if(style==='metal'){grad.addColorStop(0,'#f1f4f3');grad.addColorStop(.48,'#9aa8aa');grad.addColorStop(.75,'#c6ced1');grad.addColorStop(1,'#72898e')}
  else if(style==='black'){grad.addColorStop(0,'#303438');grad.addColorStop(.7,'#10151a');grad.addColorStop(1,'#323b43')}
  else {grad.addColorStop(0,bank.base);grad.addColorStop(1,bank.dark)}
  rounded(0,0,800,500,30);ctx.fillStyle=grad;ctx.fill();
  ctx.save();rounded(0,0,800,500,30);ctx.clip();
  ctx.fillStyle=style==='metal'?'#ffffff19':'#ffffff0d';ctx.translate(380,200);ctx.rotate(-Math.PI/7);ctx.fillRect(-25,-440,160,1100);ctx.fillRect(275,-440,45,1100);ctx.restore();
  const ink=style==='metal'?'#15262d':'#f8f6ee';ctx.fillStyle=ink;
  ctx.font='italic bold 50px Arial';ctx.fillText(bank.name,40,82);
  ctx.font='bold 19px Arial';ctx.fillText(bank.tag,44,112);
  ctx.textAlign='right';ctx.font='bold 24px Arial';ctx.fillText((data.cardStyle==='metal'?'METAL':data.cardStyle==='black'?'CASH+':'EVERYDAY')+' · DEBIT',760,68);ctx.textAlign='left';
  // Chip with visible contact pads.
  rounded(51,165,100,80,12);const chip=ctx.createLinearGradient(50,165,145,245);chip.addColorStop(0,'#f5dca5');chip.addColorStop(1,'#ae8c49');ctx.fillStyle=chip;ctx.fill();ctx.strokeStyle='#8c6d3d';ctx.lineWidth=3;ctx.beginPath();ctx.moveTo(100,165);ctx.lineTo(100,245);ctx.moveTo(51,201);ctx.lineTo(151,201);ctx.stroke();
  ctx.strokeStyle=ink;ctx.lineWidth=7;ctx.lineCap='round';[17,30,43].forEach((radius,i)=>{ctx.beginPath();ctx.arc(675,197,radius,-.82,.82);ctx.stroke()});
  ctx.fillStyle=ink;ctx.font='bold 39px monospace';ctx.fillText('••••  ••••  ••••  '+String(data.last4||'0000').slice(-4),45,344);
  ctx.font='bold 16px Arial';ctx.globalAlpha=.7;ctx.fillText('CARDHOLDER',45,393);ctx.fillText('VALID THRU',560,393);ctx.globalAlpha=1;
  ctx.font='bold 25px Arial';ctx.fillText(String(data.holder||'CARDHOLDER').toUpperCase().slice(0,28),45,430);
  ctx.fillText(String(data.expires||'--/--').slice(0,5),560,430);
  ctx.textAlign='right';ctx.font='italic bold 35px Arial';ctx.fillText('LS PAY',747,454);ctx.textAlign='left';
 }
 window.addEventListener('message',e=>{if(e.data?.type==='cardFace')draw(e.data)});
 draw({bankKey:'maze',cardStyle:'classic',last4:'0000',expires:'--/--',holder:'CARDHOLDER'});
})()