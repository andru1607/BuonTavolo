'use strict';
const fs=require('node:fs'),path=require('node:path');
function run(source,qr){
 const passed=[],check=(ok,msg)=>{if(!ok)throw Error(msg);passed.push(msg)};
 for(const party of [1,8,9,30]){
 const app={innerHTML:'',classList:{toggle(){}}},toast={textContent:''},handlers={},nodes={},doc={getElementById:id=>id==='app'?app:id==='toast'?toast:app.innerHTML.includes('id="'+id+'"')?(nodes[id]??={value:'',innerHTML:'',handlers:{},addEventListener(n,f){this.handlers[n]=f}}):null,addEventListener:(n,f)=>handlers[n]=f};
 const win={location:{search:'?gd_preview=customer',origin:'https://buontavolo.vercel.app'},GOODDINER_PUBLIC_CONFIG:{personalReviewsEnabled:true},GoodDinerAuthUX:{emailConfirmed:()=>true},scrollTo(){},confirm:()=>true};
 new Function('window','globalThis',qr)(win,win);new Function('window','document','setTimeout','clearTimeout',source)(win,doc,()=>0,()=>{});
 const gd=win.GD,click=(action,id)=>handlers.click({preventDefault(){},target:{closest:()=>({dataset:{action,id}})}});
 click('booking-open');click('booking-select','preview-venue-1');
 const form={id:'booking-create-form',elements:{day:{value:new Date(Date.now()+86400000).toISOString().slice(0,10)},party:{value:String(party)},name:{value:'Cliente demo'},voucher:{value:''},slot:{value:''}}};
 handlers.submit({preventDefault(){},target:form,submitter:{value:'slots'}});
 check(app.innerHTML.includes(party<=8?'Prenota ora':'Richiedi prenotazione'),'Correct CTA for '+party);
 form.elements.slot.value=gd.state.bookingSlots[0].starts_at;handlers.submit({preventDefault(){},target:form,submitter:{value:''}});
 check(gd.state.bookings[0].status===(party<=8?'confirmed':'pending')&&gd.state.customerBookingTab==='history'&&gd.client()===null,'Correct isolated booking status for '+party);
 }
 return passed;
}
module.exports=run;
if(require.main===module){const read=p=>fs.readFileSync(path.join(__dirname,'..',p),'utf8');for(const row of run(read('official.js'),read('qr-core.js')))console.log('PASS '+row);}
