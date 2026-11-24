'use strict';
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const vm=require('node:vm');

async function roleQueries(){
 const id='owner-1',queries=[],events={};
 const app={innerHTML:'',classList:{toggle(){}}},toast={};
 const ownVisit={id:'own-visit',customer_id:id,restaurant_id:'someone-elses-venue',status:'confirmed',checked_in_at:'2026-11-21T13:00:00Z',visited_on:'2026-11-21',guest_nickname:'Persona'};
 const sharedVisit={id:'shared-visit',customer_id:id,restaurant_id:'owned-venue',status:'confirmed',checked_in_at:'2026-11-21T12:00:00Z',visited_on:'2026-11-21',guest_nickname:'Persona'};
 const manyMerchantVisits=Array.from({length:250},(_,i)=>({id:'merchant-'+i,customer_id:'other-'+i,restaurant_id:'owned-venue',status:'confirmed',checked_in_at:'2026-11-21T14:00:00Z',visited_on:'2026-11-21',guest_nickname:'Cliente esterno '+i}));
 const ownReview={id:'review-self',customer_id:id,rater_id:'other-venue',visit_id:'own-visit',rating:9,status:'published',comment:'La mia esperienza è stata annotata.',created_at:'2026-11-21T10:00:00Z'};
 const merchantReview={id:'review-merchant',customer_id:'another',rater_id:id,visit_id:'merchant-1',rating:1,status:'published',comment:'Un cliente esterno.',created_at:'2026-11-21T10:00:00Z'};
 function from(table){
   const q={table,filter:null,error:null,
      select(){return this;},eq(field,value){this.filter={field,value};return this;},order(){return this;},limit(){return this;},
      single(){return {data:{id,nickname:'Titolare',customer_code:'GD-TEST'},error:null};},
      get data(){
       if(table==='restaurants')return [{id:'owned-venue',owner_id:id,name:'Locale gestito',verified_at:'2026-11-20T12:00:00Z'},{id:'someone-elses-venue',owner_id:'other',name:'Locale visitato',verified_at:'2026-11-20T12:00:00Z'}];
       if(table==='visits')return this.filter?.field==='customer_id'?[ownVisit,sharedVisit]:this.filter?.field==='scanned_by'?[...manyMerchantVisits,sharedVisit]:[];
       if(table==='reviews')return this.filter?.field==='customer_id'?[ownReview]:this.filter?.field==='rater_id'?[merchantReview]:[];
       return [];
      }
   };
   queries.push(q);
   return q;
 }
 const sdk={createClient:()=>({auth:{onAuthStateChange(){},getUser:async()=>({data:{user:{id,email:'owner@example.test',is_anonymous:false}},error:null})},from})};
 const context={
   sdk,window:{GOODDINER_PUBLIC_CONFIG:{supabaseUrl:'https://ixczkhmvbjszgmlqznlk.supabase.co',supabasePublishableKey:'sb_publishable_test'},scrollTo(){}},
   document:{getElementById:k=>k==='app'?app:k==='toast'?toast:null,addEventListener:(k,fn)=>events[k]=fn},
   sessionStorage:{getItem(){return null;}},setTimeout(){},clearTimeout(){}
 };
 const src=fs.readFileSync(path.join(__dirname,'../official.js'),'utf8');
 await vm.runInNewContext(src.replace(/import\('https:\/\/cdn\.jsdelivr\.net\/npm\/@supabase[^']+'\)/,'Promise.resolve(globalThis.sdk)'),context);
 const gd=context.window.GD;
 const filters=table=>queries.filter(x=>x.table===table).map(x=>x.filter).filter(Boolean);
 assert.deepEqual(JSON.parse(JSON.stringify(filters('visits'))),[{field:'customer_id',value:id},{field:'scanned_by',value:id}]);
 assert.deepEqual(JSON.parse(JSON.stringify(filters('reviews'))),[{field:'customer_id',value:id},{field:'rater_id',value:id}]);
 assert.deepEqual(JSON.parse(JSON.stringify(filters('vouchers'))),[{field:'customer_id',value:id}]);
 assert.deepEqual(JSON.parse(JSON.stringify(filters('disputes'))),[{field:'customer_id',value:id}]);
 assert.equal(gd.state.visits.length,252,'250 restaurant records plus 2 personal visits, overlap deduplicated');
 assert.equal(gd.state.reviews.length,2);
 assert.equal(gd.state.side,'merchant','merchant opens professional area by default');
 assert.match(app.innerHTML,/Passa al cliente/);
 await events.click({preventDefault(){},target:{closest:()=>({dataset:{action:'switch-side'}})}});
 assert.equal(gd.state.side,'customer');
 assert.match(app.innerHTML,/Locale visitato/);
 assert.doesNotMatch(app.innerHTML,/Cliente esterno 249/);
 gd.state.side='merchant';gd.state.section='visits';gd.render();
 assert.match(app.innerHTML,/Cliente esterno 249/);
 assert.doesNotMatch(app.innerHTML,/Locale visitato/);
 console.log('PASS: independently filtered merchant and personal timelines; overlap deduplicated');
}
roleQueries().catch(e=>{console.error(e);process.exitCode=1;});
