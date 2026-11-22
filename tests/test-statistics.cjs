'use strict';
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const vm=require('node:vm');
const read=x=>fs.readFileSync(path.join(__dirname,'..',x),'utf8');
const schema=read('database/gooddiner_accurate_statistics.sql');
assert.ok(schema.includes('security invoker'),'never bypass RLS to compute aggregates');
for(const method of ['get_my_dinerpass_counts','get_my_restaurant_counts','get_my_merchant_license']){
 assert.ok(schema.includes('public.'+method),'aggregate missing: '+method);
 assert.ok(schema.includes('grant execute on function public.'+method),'function must be limited to authenticated callers');
}
assert.ok(schema.includes("r.owner_id=auth.uid()"),'merchant counts require exact owner');
assert.ok(schema.includes("r.verified_at is not null and r.suspended_at is null"),'unverified owners must not see merchant counts');

async function run(){
 const account='operator-1';
 const app={innerHTML:'',classList:{toggle(){}}},toast={},events={};
 const firstCustomer={id:'mine-1',customer_id:account,restaurant_id:'restaurant-elsewhere',checked_in_at:'2026-11-19T10:00:00Z',status:'confirmed',guest_nickname:'Io'};
 const venueRows=Array.from({length:250},(_,i)=>({id:'venue-'+i,customer_id:'guest-'+i,restaurant_id:'venue-owned',checked_in_at:'2026-11-20T10:00:00Z',guest_nickname:'Cliente '+i,status:'confirmed'}));
 const nextVenue=[{id:'venue-250',customer_id:'guest-new',restaurant_id:'venue-owned',guest_nickname:'Nuovo cliente 250',checked_in_at:'2026-11-01T10:00:00Z',status:'confirmed'}];
 const queryCalls=[],rpcCalls=[];
 const client={
   auth:{onAuthStateChange(){},getUser:async()=>({data:{user:{id:account,email:'person@example.test',is_anonymous:false}},error:null})},
   from(table){
     let filter=null;
     const q={
       table,filter:null,error:null,
       select(){return this;},
       eq(field,value){filter={field,value};this.filter=filter;return this;},
       order(){return this;},limit(){return this;},
       single(){return {data:{id:account,nickname:'Gestore',customer_code:'GD-TEST'},error:null};},
       get data(){
         if(table==='restaurants')return [{id:'venue-owned',owner_id:account,name:'Locale di Prova',verified_at:'2026-11-21T10:00:00Z'},{id:'restaurant-elsewhere',owner_id:'other',name:'Locale visitato',verified_at:'2026-11-21T10:00:00Z'}];
         if(table==='visits')return filter?.field==='customer_id'?[firstCustomer]:filter?.field==='scanned_by'?venueRows:[];
         return [];
       },
       async range(start,end){
         queryCalls.push({table,filter,start,end});
         if(table==='visits'&&filter?.field==='scanned_by'&&start===250)return {data:nextVenue,error:null};
         return {data:[],error:null};
       }
     };
     return q;
   },
   async rpc(name,args){
     rpcCalls.push({name,args});
     if(name==='get_my_dinerpass_counts')return {data:[{confirmed_visits:307,published_reviews:286,positive_reviews:272,pending_rewards:5}],error:null};
     if(name==='get_my_restaurant_counts')return {data:[{confirmed_visits:920,published_reviews:600,todays_visits:37}],error:null};
     if(name==='get_my_merchant_license')return {data:[{license_status:'trialing',active_until:'2026-12-08T10:00:00Z',is_usable:true}],error:null};
     return {error:{message:'unexpected RPC '+name}};
   }
 };
 const ctx={
   sdk:{createClient:()=>client},
   window:{GOODDINER_PUBLIC_CONFIG:{supabaseUrl:'https://ixczkhmvbjszgmlqznlk.supabase.co',supabasePublishableKey:'sb_publishable_test'},scrollTo(){}},
   document:{getElementById:k=>k==='app'?app:k==='toast'?toast:null,addEventListener:(k,v)=>events[k]=v},
   sessionStorage:{getItem(){return null;}},setTimeout(){},clearTimeout(){}
 };
 await vm.runInNewContext(read('official.js').replace(/import\('https:\/\/cdn\.jsdelivr\.net\/npm\/@supabase[^']+'\)/,'Promise.resolve(globalThis.sdk)'),ctx);
 const gd=ctx.window.GD;
 assert.equal(gd.state.visits.length,251,'client and merchant histories initially separated');
 assert.equal(gd.state.totals.customer.confirmed_visits,307);
 assert.deepEqual(JSON.parse(JSON.stringify(rpcCalls.map(r=>r.name))),['get_my_dinerpass_counts','get_my_restaurant_counts']);
 gd.state.side='customer';gd.state.section='pass';gd.render();
 assert.match(app.innerHTML,/<small>Visite confermate<\/small><strong>307<\/strong>/,'personal totals do not cap at 250');
 assert.match(app.innerHTML,/<small>Valutazioni positive<\/small><strong>272<\/strong>/);
 gd.state.side='merchant';gd.state.section='merchant';gd.render();
 assert.match(app.innerHTML,/<small>Presenti oggi<\/small><strong>37<\/strong>/);
 assert.match(app.innerHTML,/<small>Visite totali<\/small><strong>920<\/strong>/);
 assert.match(app.innerHTML,/<small>Recensioni pubblicate<\/small><strong>600<\/strong>/);
 gd.state.section='visits';gd.render();
 assert.match(app.innerHTML,/data-action="more-merchantVisits"/);
 await events.click({preventDefault(){},target:{closest:()=>({dataset:{action:'more-merchantVisits'}})}});
 assert.equal(gd.state.visits.length,252,'next page appended without duplicating customer data');
 assert.equal(gd.state.hasMore.merchantVisits,false,'short last page hides button');
 assert.ok(queryCalls.some(q=>q.table==='visits'&&q.filter.field==='scanned_by'&&q.start===250&&q.end===499));
 assert.match(app.innerHTML,/Nuovo cliente 250/);
 console.log('PASS: exact server totals over 250 and paginated merchant history');
}
run().catch(e=>{console.error(e);process.exitCode=1;});
