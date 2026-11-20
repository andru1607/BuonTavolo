'use strict';
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const root=path.resolve(__dirname,'..');
const read=x=>fs.readFileSync(path.join(root,x),'utf8');
const V=require('../visit-core-v710.js');
const store=()=>{const data={};return {getItem:key=>data[key]??null,setItem:(key,val)=>{data[key]=val;},dump:()=>data}};
const s=store();const day=V.isoDay(Date.now()),now=Date.now();
const visits=[
  {id:'V1',customerId:'GD-AAA',nickname:'Alice',restaurant:'Ristorante Uno',at:now-10e3,day,status:'confermata'},
  {id:'V2',customerId:'GD-BBB',nickname:'Bob',restaurant:'Ristorante Uno',at:now-30e3,day},
  {id:'V3',customerId:'GD-AAA',nickname:'Alice',restaurant:'Ristorante Due',at:now-50e3,day},
  {id:'V4',customerId:'GD-AAA',nickname:'Alice',restaurant:'Ristorante Uno',at:now-70e3,day,status:'annullata'}];
s.setItem(V.KEY,JSON.stringify(visits));s.setItem(V.VENUE_KEY,JSON.stringify({name:'Ristorante Uno',city:'Verona'}));
assert.equal(V.venue(s),'Ristorante Uno');
assert.equal(V.read(s).length,4);assert.equal(V.byCustomer(V.read(s),'GD-AAA').length,3);
assert.equal(V.byVenue(V.read(s),'Ristorante Uno').length,3);
assert.deepEqual(V.counts(V.byVenue(V.read(s),'Ristorante Uno'),now),{today:2,week:2,total:2,voided:1});
assert.equal(V.canCheckIn(V.read(s),'GD-AAA','Ristorante Uno',day),false);
assert.equal(V.canCheckIn(V.read(s),'GD-AAA','Ristorante Due',day),false);
assert.equal(V.canCheckIn(V.read(s),'GD-CCC','Ristorante Uno',day),true);
assert.equal(V.voidDemo(s,'V1','Ristorante Due',now),false,'no cross-venue edits');
assert.equal(V.voidDemo(s,'V1','Ristorante Uno',now),true);
assert.equal(V.canCheckIn(V.read(s),'GD-AAA','Ristorante Uno',day),true,'new visit can be registered after correction');
assert.equal(V.read(s).find(x=>x.id==='V1').status,'annullata');
assert.equal(V.voidDemo(s,'V1','Ristorante Uno',now),false,'cannot cancel twice');
s.setItem(V.KEY,'not json');assert.deepEqual(V.read(s),[]);
const client=read('v710-visits.js'),css=read('visits-v710.css'),home=read('index.html'),on=read('v76-onboarding.js');
assert.ok(home.includes('/visit-core-v710.js')&&home.includes('/visits-v710.css')&&home.includes('/v710-visits.js'));
assert.ok(client.includes('originalClientHome')&&client.includes('originalMerchantHome')&&client.includes('visitCard(row,true)')===false);
assert.ok(client.includes('Annulla presenza demo')&&client.includes('Storico delle mie presenze'));
assert.ok(css.includes('font-size:16px!important')&&css.includes('prefers-reduced-motion'));
assert.ok(on.includes('restaurant:venueName')&&on.includes('v.restaurant===venueName'));
console.log('PASS V7.10: visit history, distinct venues, duplicate check, correction with audit, mobile UI wiring');
const vm=require('node:vm');
const ev={};const db={activeCustomer:'GD-AAA',customers:[{id:'GD-AAA',nickname:'Alice'}]};const local=store();
local.setItem(V.KEY,JSON.stringify(visits));local.setItem(V.VENUE_KEY,JSON.stringify({name:'Ristorante Uno'}));
const ctx={console,Date,Intl,localStorage:local,db,state:{role:'customer',tab:'home'},
  esc:s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c])),
  icon:(name,size)=>`<svg data-icon="${name}"></svg>`,
  customer:id=>db.customers.find(c=>c.id===id),
  clientHome:()=>'<section class="reward-feature"></section>',
  clientProfile:()=>'<div class="section-heading"><h2>Privacy e dati</h2></div>',
  merchantHome:()=>'<section class="gd-scanner-section"><div class="gd-visit-title"><strong>Demo</strong></div><p class="gd-privacy-line">Solo questa sessione browser. Qui la demo.</p></section><section class="merchant-feature"></section>',
  document:{addEventListener:(type,handler)=>{ev[type]??=[];ev[type].push(handler);},getElementById:()=>null},
  notify:()=>{},window:null};
ctx.window=ctx;ctx.render=()=>{ctx.lastMarkup=ctx.state.role==='customer'?ctx.clientHome():ctx.merchantHome();};
vm.createContext(ctx);vm.runInContext(read('visit-core-v710.js'),ctx,{timeout:1000});vm.runInContext(client,ctx,{timeout:1000});
assert.ok(ctx.lastMarkup.includes('Ogni visita conta.')&&ctx.lastMarkup.includes('Ristorante Uno'));
assert.ok(!ctx.lastMarkup.includes('Ristorante Due')===false,'customer sees visits across venues');
ctx.state.role='restaurant';ctx.render();
assert.ok(ctx.lastMarkup.includes('Le presenze, in ordine.'));
assert.ok(!ctx.lastMarkup.includes('gd-visit-title'),'old stale merchant list replaced');
assert.ok(!ctx.lastMarkup.includes('Ristorante Due'),'merchant cannot see another venue');
assert.ok(ctx.lastMarkup.includes('2</strong><span>Oggi'));
console.log('PASS V7.10 VM: wrapper registration, venue isolation, customer timeline, replacement of legacy register');
const fullRegister=Array.from({length:100},(_,i)=>({...visits[0],id:'V'+i,at:now-i*1000}));
local.setItem(V.KEY,JSON.stringify(fullRegister));
assert.equal((ctx.merchantHome().match(/class="gd10-detail"/g)||[]).length,100);
assert.equal((ctx.clientProfile().match(/<article class="gd10-visit /g)||[]).length,100);
assert.equal((ctx.clientHome().match(/<article class="gd10-visit /g)||[]).length,3);
console.log('PASS V7.10: all 100 visits accessible in register and profile, latest three on home');
