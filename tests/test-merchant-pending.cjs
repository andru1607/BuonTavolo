'use strict';
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const vm=require('node:vm');
const authFeedback=require('../auth-feedback.js');

async function verifyMerchantPending(){
  const email='titolare@example.test';
  const saved=new Map([['gd_merchant_pending',JSON.stringify({name:'Trattoria Lago',city:'Garda',email})]]);
  const user={id:'merchant-1',email:'un-altro@example.test',email_confirmed_at:'2026-11-22T12:00:00Z',is_anonymous:false};
  const events={};
  const app={innerHTML:'',classList:{toggle(){}}},toast={};
  const attempts=[];
  let failInsert=true;
  const query={
    data:[],error:null,
    select(){return this;},eq(){return this;},order(){return this;},limit(){return this;},
    single(){return {data:{id:user.id,nickname:'Titolare',customer_code:'GD-TEST'},error:null};},
    insert(payload){attempts.push(payload);return Promise.resolve({error:failInsert?{message:'Rete temporaneamente assente'}:null});}
  };
  const sdk={createClient:()=>({
    auth:{onAuthStateChange(){},getUser:async()=>({data:{user},error:null})},
    from:()=>query
  })};
  const context={
    sdk,window:{GOODDINER_PUBLIC_CONFIG:{supabaseUrl:'https://ixczkhmvbjszgmlqznlk.supabase.co',supabasePublishableKey:'sb_publishable_local-test'},GoodDinerAuthUX:authFeedback,scrollTo(){}},
    document:{getElementById:id=>id==='app'?app:id==='toast'?toast:null,addEventListener:(k,fn)=>events[k]=fn},
    sessionStorage:{getItem:k=>saved.get(k)??null,setItem:(k,v)=>saved.set(k,v),removeItem:k=>saved.delete(k)},
    setTimeout(){},clearTimeout(){},location:{origin:'https://example.test'}
  };
  const js=fs.readFileSync(path.join(__dirname,'../official.js'),'utf8');
  assert.ok(js.includes("JSON.stringify({name,city,email})"),'merchant signup stores the email it belongs to');
  await vm.runInNewContext(js.replace(/import\('https:\/\/cdn\.jsdelivr\.net\/npm\/@supabase[^']+'\)/,'Promise.resolve(globalThis.sdk)'),context);
  assert.equal(attempts.length,0,'a pending registration must not be submitted for another signed-in user');
  assert.equal(saved.has('gd_merchant_pending'),false,'wrong-owner pending request is discarded');

  const retry=()=>events.click({preventDefault(){},target:{closest:()=>({dataset:{action:'retry'}})}});
  saved.set('gd_merchant_pending',JSON.stringify({name:'Trattoria Lago',city:'Garda',email}));
  user.email=email;
  user.email_confirmed_at=null;
  await retry();
  assert.equal(attempts.length,0,'unconfirmed email cannot submit a merchant application');
  assert.equal(saved.has('gd_merchant_pending'),true,'pending merchant request remains until email confirmation');
  user.email_confirmed_at='2026-11-22T12:00:00Z';
  await retry();
  assert.equal(attempts.length,1,'attempts only for the registered email');
  assert.equal(saved.has('gd_merchant_pending'),true,'a failed submission is recoverable');
  assert.match(toast.textContent,/Richiesta del locale da completare/);

  failInsert=false;
  await retry();
  assert.equal(attempts.length,2);
  assert.equal(attempts[1].applicant_id,'merchant-1');
  assert.equal(attempts[1].restaurant_name,'Trattoria Lago');
  assert.equal(saved.has('gd_merchant_pending'),false,'successful submissions clear pending state');
  await retry();
  assert.equal(attempts.length,2,'no duplicate submission on refresh');

  saved.set('gd_merchant_pending',JSON.stringify({name:'Richiesta vecchia',city:'Garda'}));
  await retry();
  assert.equal(attempts.length,2,'old pending registration without account email is not trusted');
  assert.equal(saved.has('gd_merchant_pending'),false);
  console.log('PASS: merchant application bound to correct email; network failure retained; duplicate avoided');
}
verifyMerchantPending().catch(e=>{console.error(e);process.exitCode=1;});
