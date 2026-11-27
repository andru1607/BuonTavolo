'use strict';
const fs=require('node:fs'),path=require('node:path');
function run(source,qr){
 const passed=[],check=(v,m)=>{if(!v)throw Error(m);passed.push(m)};
 for(const role of ['customer','merchant']){
 const app={innerHTML:'',classList:{toggle(){}}},toast={textContent:''},handlers={},nodes={},doc={getElementById:id=>id==='app'?app:id==='toast'?toast:app.innerHTML.includes('id="'+id+'"')?(nodes[id]??={value:'',innerHTML:'',handlers:{},addEventListener(n,f){this.handlers[n]=f},focus(){}}):null,addEventListener:(n,f)=>handlers[n]=f};
 const win={location:{search:'?gd_preview='+role,origin:'https://buontavolo.vercel.app'},GOODDINER_PUBLIC_CONFIG:{personalReviewsEnabled:true},GoodDinerAuthUX:{emailConfirmed:()=>true},scrollTo(){},confirm:()=>true};
 new Function('window','globalThis',qr)(win,win);new Function('window','document','setTimeout','clearTimeout',source)(win,doc,()=>0,()=>{});
 const gd=win.GD,click=(action,id)=>handlers.click({preventDefault(){},target:{closest:()=>({dataset:{action,id}})}}),nav=()=>app.innerHTML.split('<nav class="mobile-nav"')[1].split('</nav>')[0],sections=()=>[...nav().matchAll(/data-section="([^"]+)"/g)].map(m=>m[1]),active=(id)=>new RegExp('data-section="'+id+'" aria-current="page"').test(nav());
 check(sections().join(',')===(role==='merchant'?'merchant,bookings,visits,profile':'pass,bookings,visits,profile'),role+' four direct destinations');
 click('bookings');check(gd.state.view===(role==='merchant'?'booking-merchant':'booking-customer')&&active('bookings'),role+' booking tab routes and highlights');
 click('visits');check(active('visits')&&gd.state.view==='app',role+' visits');
 if(role==='customer'){click('reviews');check(active('visits')&&app.innerHTML.includes('Le valutazioni ricevute'),'Reviews reachable within activity');click('bookings');click('booking-select','preview-venue-1');check(active('bookings')&&app.innerHTML.includes('booking-create-form'),'Booking details remain highlighted');}
 click('profile');click('profile-panel','privacy');check(active('profile')&&app.innerHTML.includes('privacy-request-form')&&!app.innerHTML.includes('change-password-form'),role+' focused privacy panel');
 click('profile-panel','account');check(app.innerHTML.includes('change-password-form')&&!app.innerHTML.includes('privacy-request-form'),role+' focused security panel');
 click('profile-panel','tools');check(app.innerHTML.includes('Guida alle funzioni'),role+' tools panel');
 if(role==='merchant'){click('venue-tools');check(active('profile')&&app.innerHTML.includes('Posizione del locale')&&app.innerHTML.includes('data-action="profile"'), 'Venue settings and return');click('profile');click('profile-panel','tools');click('marketing-open');check(active('merchant')&&app.innerHTML.includes('data-gooddiner-watermark="true"'),'Marketing flyer has original watermark');const index=app.innerHTML.indexOf('data-gooddiner-watermark="true"');const after=app.innerHTML.slice(index);check(after.includes('opacity="0.085"')&&after.indexOf('opacity="0.085"')<after.indexOf('Inquadra il QR e registra la visita.'),'Watermark behind instructions');}
 else{click('collection-open');check(active('pass')&&app.innerHTML.includes('data-action="pass"'),'Collection has DinerPass return');}
 check(gd.client()===null,role+' isolated preview');
 }
 return passed;
}
module.exports=run;
if(require.main===module){const read=p=>fs.readFileSync(path.join(__dirname,'..',p),'utf8');for(const row of run(read('official.js'),read('qr-core.js')))console.log('PASS '+row);}
