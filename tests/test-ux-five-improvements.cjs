'use strict';
const fs=require('node:fs'),path=require('node:path');
function run(s,q){
 const passed=[];function check(x,msg){if(!x)throw Error(msg);passed.push(msg)}
 for(const role of ['merchant','customer']){
  const app={innerHTML:'',classList:{toggle(){}}},toast={textContent:''},nodes={},handlers={},doc={getElementById:id=>id==='app'?app:id==='toast'?toast:app.innerHTML.includes('id="'+id+'"')?(nodes[id]??={value:'',innerHTML:'',handlers:{},addEventListener(n,fn){this.handlers[n]=fn},focus(){}}):null,addEventListener:(n,fn)=>handlers[n]=fn};
  const win={location:{search:'?gd_preview='+role,origin:'https://buontavolo.vercel.app'},GOODDINER_PUBLIC_CONFIG:{personalReviewsEnabled:true},GoodDinerAuthUX:{emailConfirmed:()=>true},scrollTo(){}};
  new Function('window','globalThis',q)(win,win);new Function('window','document','setTimeout','clearTimeout',s)(win,doc,()=>0,()=>{});
  const gd=win.GD,click=(action,id)=>handlers.click({preventDefault(){},target:{closest:()=>({dataset:{action,id}})}});
  check(gd.client()===null,role+' isolated');click('profile');click('guide-open');check(app.innerHTML.includes(role==='merchant'?'Inizia con il tuo locale.':'Il tuo primo DinerPass.'),role+' guide');click('guide-done');check(gd.state.view==='app',role+' guide close');
  click('booking-notices');check(app.innerHTML.includes('1 non lette')&&app.innerHTML.includes('Prossime 24 ore'),role+' notifications');click('notice-filter','unread');check(!app.innerHTML.includes('Completata · Ristorante demo'),role+' unread filter');click('booking-notices-read');check(gd.state.bookingNotices.unread===0,role+' mark read');
  if(role==='merchant'){click('booking-merchant');click('room-open');check(app.innerHTML.includes('Pianta dei tavoli'),'table map');click('room-view-mode','list');check(app.innerHTML.includes('gd-room-list'),'table list');click('room-filter','free');check(app.innerHTML.includes('data-id="t1"')&&!app.innerHTML.includes('data-id="t2"'),'table state filter');click('room-table','t1');check(app.innerHTML.includes('Modifica T1'),'table details');}
  else{click('booking-open');check(app.innerHTML.includes('gd-booking-search'),'catalog search');const n=nodes['gd-booking-search'];n.value='Vérona';n.handlers.input();check(nodes['gd-booking-results'].innerHTML.includes('Ristorante demo 2')&&!nodes['gd-booking-results'].innerHTML.includes('Ristorante demo 1'),'accent insensitive search');click('booking-select','preview-venue-1');check(app.innerHTML.includes('booking-create-form'),'venue form');click('booking-open');check(app.innerHTML.includes('gd-booking-search'),'back to catalog');}
 }
 return passed;
}
module.exports=run;
if(require.main===module){const read=p=>fs.readFileSync(path.join(__dirname,'..',p),'utf8');const rows=run(read('official.js'),read('qr-core.js'));for(const r of rows)console.log('PASS '+r);console.log('PASS '+rows.length+' isolated UX scenarios');}
