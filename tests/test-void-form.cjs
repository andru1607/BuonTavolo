'use strict';
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const vm=require('node:vm');

async function testVoidForm(){
 const events={},app={innerHTML:'',classList:{toggle(){}}},toast={};
 const user={id:'operator-1',email:'operator@example.test',is_anonymous:false};
 const calls=[];
 const query={data:[],error:null,select(){return this;},eq(){return this;},order(){return this;},limit(){return this;},single(){return {data:{id:user.id,nickname:'Operatore',customer_code:'GD-TEST'},error:null};}};
 const sdk={createClient:()=>({auth:{onAuthStateChange(){},getUser:async()=>({data:{user},error:null})},from:()=>query,rpc:async(name,args)=>{if(name==='void_guest_visit')calls.push({name,args});return {data:true,error:null};}})};
 const context={sdk,window:{GOODDINER_PUBLIC_CONFIG:{supabaseUrl:'https://ixczkhmvbjszgmlqznlk.supabase.co',supabasePublishableKey:'sb_publishable_test'},scrollTo(){}},
   document:{getElementById:key=>key==='app'?app:key==='toast'?toast:null,addEventListener:(key,fn)=>events[key]=fn},
   sessionStorage:{getItem(){return null;}},setTimeout(){},clearTimeout(){}};
 const js=fs.readFileSync(path.join(__dirname,'../official.js'),'utf8');
 assert.ok(!js.includes("window.prompt('Motivo di annullamento"),'no iPhone native browser prompt');
 await vm.runInNewContext(js.replace(/import\('https:\/\/cdn\.jsdelivr\.net\/npm\/@supabase[^']+'\)/,'Promise.resolve(globalThis.sdk)'),context);
 const gd=context.window.GD;
 const visit={id:'visit-1',restaurant_id:'restaurant-1',customer_id:'guest-1',guest_nickname:'Ospite',guest_code:'GD-1234',checked_in_at:'2026-11-21T12:00:00Z',status:'confirmed'};
 gd.state.restaurants=[{id:'restaurant-1',owner_id:user.id,name:'Trattoria',verified_at:'2026-11-21T10:00:00Z'}];
 gd.state.visits=[visit];gd.state.reviews=[];gd.state.side='merchant';gd.state.section='visits';gd.state.view='app';gd.render();
 assert.match(app.innerHTML,/data-action="void" data-id="visit-1"/);
 await events.click({preventDefault(){},target:{closest:()=>({dataset:{action:'void',id:'visit-1'}})}});
 assert.match(app.innerHTML,/id="void-form"/);
 assert.match(app.innerHTML,/Motivo della correzione/);
 const submit=reason=>events.submit({preventDefault(){},target:{id:'void-form',elements:{reason:{value:reason}}}});
 await submit('breve');
 assert.equal(calls.length,0,'rejects a short explanation');
 assert.equal(toast.textContent,'Il motivo deve contenere tra 10 e 500 caratteri.');
 await submit('Presenza registrata due volte per un errore durante il servizio.');
 assert.equal(calls.length,1);
 assert.equal(calls[0].name,'void_guest_visit');
 assert.equal(calls[0].args.p_visit_id,'visit-1');
 assert.equal(gd.state.section,'visits');
 assert.equal(toast.textContent,'Visita annullata e motivazione registrata.');
 gd.state.restaurants=[{id:'restaurant-1',owner_id:user.id,name:'Trattoria',verified_at:'2026-11-21T10:00:00Z'}];
 gd.state.visits=[visit];gd.state.reviews=[{id:'review-1',visit_id:'visit-1'}];
 gd.state.voidVisitId='visit-1';gd.setView('void-compose');
 assert.doesNotMatch(app.innerHTML,/id="void-form"/);
 assert.match(app.innerHTML,/non è annullabile/);
 console.log('PASS: guided visit correction, mandatory reason, RPC payload and reviewed-visit guard');
}
testVoidForm().catch(err=>{console.error(err);process.exitCode=1;});
