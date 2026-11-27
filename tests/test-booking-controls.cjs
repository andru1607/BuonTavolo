'use strict';
const fs=require('node:fs'),path=require('node:path');
function run(source,qr){
 const passed=[],check=(v,m)=>{if(!v)throw Error(m);passed.push(m)};
 const app={innerHTML:'',classList:{toggle(){}}},toast={textContent:''},handlers={},nodes={},doc={getElementById:id=>id==='app'?app:id==='toast'?toast:app.innerHTML.includes('id="'+id+'"')?(nodes[id]??={value:'',innerHTML:'',handlers:{},addEventListener(n,f){this.handlers[n]=f}}):null,addEventListener:(n,f)=>handlers[n]=f};
 const win={location:{search:'?gd_preview=merchant',origin:'https://buontavolo.vercel.app'},GOODDINER_PUBLIC_CONFIG:{personalReviewsEnabled:true},GoodDinerAuthUX:{emailConfirmed:()=>true},scrollTo(){},confirm:()=>true};
 new Function('window','globalThis',qr)(win,win);new Function('window','document','setTimeout','clearTimeout',source)(win,doc,()=>0,()=>{});
 const gd=win.GD,click=(action,id)=>handlers.click({preventDefault(){},target:{closest:()=>({dataset:{action,id}})}});
 click('booking-merchant');const before=gd.state.bookings.length;check(app.innerHTML.includes('Sospendi'),'Pause visible');
 click('booking-pause-toggle');check(gd.state.bookingSettings.online_paused&&app.innerHTML.includes('Riattiva')&&gd.state.bookings.length===before,'Pause preserves bookings');
 click('booking-pause-toggle');check(!gd.state.bookingSettings.online_paused,'Resume');
 click('booking-settings-panel');click('merchant-settings-tab','options');check(app.innerHTML.includes('Gestione tavoli'),'Room preference');
 click('booking-room-toggle');check(!gd.state.bookingSettings.room_enabled&&!app.innerHTML.includes('>Sala</')&&!app.innerHTML.includes('Assegnazione automatica tavoli'),'Room off hides room tools');
 click('booking-room-toggle');check(gd.state.bookingSettings.room_enabled&&app.innerHTML.includes('>Sala</'),'Room restored');
 check(gd.client()===null,'No real writes in demo');return passed;
}
module.exports=run;
if(require.main===module){const read=p=>fs.readFileSync(path.join(__dirname,'..',p),'utf8');for(const row of run(read('official.js'),read('qr-core.js')))console.log('PASS '+row);}
