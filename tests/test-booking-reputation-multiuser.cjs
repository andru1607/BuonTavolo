'use strict';
// Runs actual browser controller with an isolated, synthetic RPC adapter.
// The adapter models expected policy; it is NOT PostgreSQL/RLS verification.
async function run(source){
 const anchor="return {init,render,state,client:()=>sb,setView,resetScanner,version:'1.0'};";
 if(!source.includes(anchor))throw Error('Update test hook for new controller export');
 const code=source.replace(anchor,"return {init,render,state,client:()=>sb,setView,resetScanner,version:'1.0',openBookingProfile,setBookingProfileChoice,showBookingReputationAccesses,events,setMock:x=>{sb=x},bump:()=>{accountLoadGeneration++}};").replace(/GD\.init\(\);\s*$/,'');
 const passed=[],check=(label,v)=>{if(!v)throw Error(label);passed.push(label)};
 const next=new Date(Date.now()+3600000).toISOString(),past=new Date(Date.now()-3600000).toISOString();
 const users=['c1','c2','c3'],venues=[{id:'v1',owner_id:'m1',name:'Locale A',verified_at:'2026-01-01'},{id:'v2',owner_id:'m2',name:'Locale B',verified_at:'2026-01-01'},{id:'v3',owner_id:'m3',name:'Locale C',verified_at:'2026-01-01'}];
 const bookings=[['b1','v1','c1','online','confirmed',next],['b2','v2','c1','online','pending',next],['b3','v1','c2','online','confirmed',next],['b4','v2','c3','online','confirmed',next],['b5','v1',null,'phone','confirmed',next],['b6','v1','c1','online','cancelled',next],['b7','v1','c1','online','confirmed',past],['b8','v3','c3','online','confirmed',next]].map(([id,restaurant_id,customer_id,source,status,starts_at])=>({id,restaurant_id,customer_id,source,status,starts_at,booking_name:'Ospite '+(customer_id||'manuale'),restaurant_name:venues.find(v=>v.id===restaurant_id).name,party:2}));
 const reviewData={c1:[{restaurant:'Locale storico A',rating:9,date:'2026-11-25'},{restaurant:'Locale storico B',rating:8,date:'2026-11-24'},{restaurant:'Voto contestato',rating:2,date:'2026-11-23',contested:true}],c2:[{restaurant:'Storico C2',rating:7,date:'2026-11-25'}],c3:[]};
 const grants=new Set(),audit=[],calls=[];let enabled=true;
 const eligible=b=>b&&b.source==='online'&&['pending','confirmed'].includes(b.status)&&Date.parse(b.starts_at)>Date.now();
 function session(uid,merchant=false,flag=true){
  const app={innerHTML:'',classList:{toggle(){}}},toast={textContent:''},handlers={},timers=new Map();let t=0;
  const doc={hidden:false,getElementById:id=>id==='app'?app:id==='toast'?toast:null,addEventListener:(n,fn)=>handlers[n]=fn};
  const win={location:{search:'',origin:'https://buontavolo.vercel.app'},GOODDINER_PUBLIC_CONFIG:{bookingReputationEnabled:flag,personalReviewsEnabled:true},GoodDinerAuthUX:{emailConfirmed:()=>true},scrollTo(){},confirm:()=>true};
  new Function('window','document','setTimeout','clearTimeout',code)(win,doc,(fn,ms)=>{timers.set(++t,{fn,ms});return t},id=>timers.delete(id));
  const gd=win.GD,st=gd.state,v=venues.find(x=>x.owner_id===uid);
  Object.assign(st,{user:{id:uid,email:uid+'@example.invalid',email_confirmed_at:'2026-01-01'},profile:{id:uid,nickname:uid,customer_code:'GD-TEST'},side:merchant?'merchant':'customer',section:merchant?'merchant':'profile',view:merchant?'booking-merchant':'app',restaurants:merchant?[v]:venues,merchantLicense:merchant?{is_usable:uid!=='m3'}:null,bookings:bookings.filter(b=>merchant?b.restaurant_id===v.id:b.customer_id===uid)});
  const rpc=async(n,p={})=>{calls.push({uid,n,p});const b=bookings.find(x=>x.id===p.p_booking_id);
   if(n==='set_booking_reputation_choice'){
    if(merchant||b?.customer_id!==uid||b.source!=='online'||(p.p_allow&&(!enabled||!eligible(b)||p.p_notice_version!=='booking-reputation-v1')))return {error:{message:'FORBIDDEN'}};
    if(p.p_allow)grants.add(b.id);else grants.delete(b.id);return {data:{allowed:p.p_allow}};
   }
   if(n==='read_booking_reputation'){
    if(!enabled)return {data:{available:false,reason:'disabled'}};
    if(!merchant||uid==='m3'||!eligible(b)||b.restaurant_id!==v.id)return {error:{message:'FORBIDDEN'}};
    if(!grants.has(b.id))return {data:{available:false,reason:'not_authorized'}};
    const reviews=(reviewData[b.customer_id]||[]).filter(r=>!r.contested).map(({restaurant,rating,date})=>({restaurant,rating,date}));
    audit.push({customer:b.customer_id,restaurant:v.name,accessed_at:new Date().toISOString(),review_count:reviews.length});
    return {data:{available:true,reviews}};
   }
   if(n==='my_booking_reputation_accesses')return {data:audit.filter(a=>a.customer===uid).map(({customer,...r})=>r)};
   throw Error('Unexpected RPC '+n);
  };
  gd.setMock({rpc});gd.events();return {gd,st,app,toast,doc,handlers,timers,rpc};
 }
 const [a,b,c]=users.map(x=>session(x)),m1=session('m1',true),m2=session('m2',true),m3=session('m3',true);
 async function read(m,id){m.gd.setView('booking-merchant');await m.gd.openBookingProfile(id)}
 await a.gd.setBookingProfileChoice('b1',true);check('C1 authorizes only reservation b1',grants.has('b1')&&!grants.has('b2'));
 await read(m1,'b1');check('M1 sees C1 authorized ratings',m1.st.sharedReputation?.reviews.length===2);
 check('Contested rating excluded by simulated policy',!m1.app.innerHTML.includes('Voto contestato'));
 await read(m2,'b2');check('M2 cannot reuse consent for other reservation',!m2.st.sharedReputation&&m2.toast.textContent.includes('non ha autorizzato'));
 const n=calls.length;await read(m2,'b1');await read(m1,'b5');await read(m1,'b6');await read(m1,'b7');check('Other venue, manual, cancelled and expired blocked before RPC',calls.length===n);
 await read(m1,'b3');check('C2 not authorized',!m1.st.sharedReputation);
 await b.gd.setBookingProfileChoice('b3',true);await read(m1,'b3');check('C2 distinct history',m1.st.sharedReputation?.reviews[0]?.restaurant==='Storico C2'&&!m1.app.innerHTML.includes('Locale storico A'));
 await c.gd.setBookingProfileChoice('b4',true);await read(m2,'b4');check('C3 authorized empty history is not negative reputation',m2.st.sharedReputation?.reviews.length===0&&m2.app.innerHTML.includes('Nessuna valutazione condivisibile'));
 await c.gd.setBookingProfileChoice('b8',true);const n2=calls.length;await read(m3,'b8');check('Expired merchant license blocks RPC',calls.length===n2&&!m3.st.sharedReputation);
 await a.gd.setBookingProfileChoice('b1',false);await read(m1,'b1');check('Revoked consent prevents subsequent read',!m1.st.sharedReputation);
 await a.gd.showBookingReputationAccesses();check('C1 sees only own audit',a.st.bookingReputationAccesses.length===1&&a.st.bookingReputationAccesses[0].restaurant==='Locale A');
 await c.gd.showBookingReputationAccesses();check('C3 audit isolated',c.st.bookingReputationAccesses.length===1&&c.st.bookingReputationAccesses[0].restaurant==='Locale B');
 await read(m1,'b3');m1.doc.hidden=true;m1.handlers.visibilitychange();check('Background clears consultation',m1.st.sharedReputation===null&&m1.st.view==='booking-merchant');m1.doc.hidden=false;
 await read(m1,'b3');const timer=[...m1.timers.values()].find(t=>t.ms>0&&t.ms<=120000);check('Temporary consultation timer set',!!timer);
 // Use the longest timer; toast may have a shorter timer.
 [...m1.timers.values()].sort((x,y)=>y.ms-x.ms)[0].fn();check('Timeout clears consultation',m1.st.sharedReputation===null);
 let resolve;m1.gd.setMock({rpc:()=>new Promise(r=>resolve=r)});m1.gd.setView('booking-merchant');const pending=m1.gd.openBookingProfile('b3');m1.st.user={id:'different-account'};m1.gd.bump();resolve({data:{available:true,reviews:[{restaurant:'Must not render',rating:9,date:'2026-11-25'}]}});await pending;check('Stale account response discarded',!m1.st.sharedReputation&&!m1.app.innerHTML.includes('Must not render'));
 const off=session('m2',true,false),n3=calls.length;await read(off,'b4');check('Production feature flag off prevents RPC',calls.length===n3&&!off.st.sharedReputation);
 enabled=false;await read(m2,'b4');check('Server gate off prevents disclosure',!m2.st.sharedReputation);
 const n4=calls.length;await a.gd.openBookingProfile('b1');check('Customer cannot invoke merchant controller',calls.length===n4);
 check('Only booking ID sent to read RPC',calls.filter(x=>x.n==='read_booking_reputation').every(x=>Object.keys(x.p).join(',')==='p_booking_id'));
 return passed;
}
module.exports=run;
if(require.main===module){const fs=require('node:fs'),path=require('node:path');run(fs.readFileSync(path.join(__dirname,'..','official.js'),'utf8')).then(rows=>{for(const row of rows)console.log('PASS '+row);console.log('PASS '+rows.length+' isolated controller scenarios; mock RPC only');}).catch(e=>{console.error(e);process.exitCode=1;});}
