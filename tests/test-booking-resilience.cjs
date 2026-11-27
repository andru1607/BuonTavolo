'use strict';
const fs=require('node:fs'),path=require('node:path');
async function run(source){
 const anchor="return {init,render,state,client:()=>sb,setView,resetScanner,version:'1.0'};";
 if(!source.includes(anchor))throw Error('Controller export changed');
 const h=source.replace(anchor,"return {init,render,state,client:()=>sb,setView,resetScanner,version:'1.0',openBookings,invalidateBookingSlots,events,setMock:x=>{sb=x},bump:()=>{accountLoadGeneration++}};").replace(/GD\.init\(\);\s*$/,'');
 const app={innerHTML:'',classList:{toggle(){}}},toast={textContent:''},handlers={},doc={getElementById:id=>id==='app'?app:id==='toast'?toast:null,addEventListener:(n,fn)=>handlers[n]=fn};
 const win={location:{search:'',origin:'https://buontavolo.vercel.app'},GOODDINER_PUBLIC_CONFIG:{personalReviewsEnabled:true},GoodDinerAuthUX:{emailConfirmed:()=>true},scrollTo(){}};
 new Function('window','document','setTimeout','clearTimeout',h)(win,doc,()=>0,()=>{});
 const gd=win.GD,st=gd.state,passed=[],check=(v,msg)=>{if(!v)throw Error(msg);passed.push(msg)};
 const venue={id:'v1',name:'Locale A',city:'Verona',max_party:6,owner_id:'m1',verified_at:'2026-01-01'},b={id:'b1',restaurant_id:'v1',restaurant_name:'Locale A',booking_name:'Cliente A',starts_at:new Date(Date.now()+3600000).toISOString(),party:2,status:'confirmed',source:'online'};
 Object.assign(st,{user:{id:'c1',email:'c1@example.invalid',email_confirmed_at:'2026-01-01'},profile:{id:'c1',nickname:'Cliente A',customer_code:'GD-A'},side:'customer',restaurants:[venue]});
 gd.setMock({rpc:async(n,p)=>p.p_action==='list'?{data:[b]}:p.p_action==='catalog'?{data:[venue]}:{error:{message:'OFFLINE'}}});
 await gd.openBookings();check(st.bookings.length===1&&st.bookingPartial&&app.innerHTML.includes('Alcune informazioni non sono disponibili'),'customer history survives waitlist failure');
 await gd.openBookings(false,'v1');check(st.bookingVenue?.id==='v1','venue selection');
 const form={elements:{day:{value:'2026-11-29'},party:{value:'4'},name:{value:'Cliente A'},voucher:{value:''}}};
 st.bookingDraft={day:'2026-11-28',party:2,name:'Cliente A',voucher:''};st.bookingSlots=[{starts_at:b.starts_at,label:'20:00'}];
 gd.invalidateBookingSlots(form);check(st.bookingSlots===null&&st.bookingDraft.party===4&&st.bookingDraft.day==='2026-11-29'&&app.innerHTML.includes('Vedi disponibilità'),'changed date and party clear stale slots');
 Object.assign(st,{user:{id:'m1',email:'m1@example.invalid',email_confirmed_at:'2026-01-01'},profile:{id:'m1',nickname:'Gestore',customer_code:'GD-M'},side:'merchant',restaurants:[venue],merchantLicense:{is_usable:true},view:'app',bookingAgendaPanel:'service'});
 gd.setMock({rpc:async(n,p)=>p.p_action==='list'&&n==='gooddiner_bookings'?{data:[b]}:p.p_action==='settings_get'?{data:{enabled:true,max_party:6}}:{error:{message:'OFFLINE'}}});
 await gd.openBookings(true);check(st.bookings.length===1&&st.bookingPartial&&app.innerHTML.includes('L’agenda caricata resta consultabile'),'merchant agenda survives optional failures');
 let release;gd.setMock({rpc:async(n,p)=>p.p_action==='list'?{data:[b]}:new Promise(r=>{if(!release)release=[];release.push(r)})});
 const pending=gd.openBookings(true);for(let i=0;i<8;i++)await Promise.resolve();
 if(!release)throw Error('pending requests missing');st.user={id:'other'};st.bookings=[];gd.bump();release.forEach(r=>r({data:{}}));await pending;check(st.bookings.length===0,'stale account data rejected');
 return passed;
}
module.exports=run;
if(require.main===module)run(fs.readFileSync(path.join(__dirname,'..','official.js'),'utf8')).then(rows=>{for(const row of rows)console.log('PASS '+row);console.log('PASS '+rows.length+' simulated booking resilience scenarios');}).catch(e=>{console.error(e);process.exitCode=1;});
