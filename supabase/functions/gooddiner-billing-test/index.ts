// Test-only billing lab. No production entitlement or license writes.
const BASE=Deno.env.get('SUPABASE_URL')||'';
const PUB=Deno.env.get('SUPABASE_ANON_KEY')||'';
const SERVICE=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')||'';
const KEY=Deno.env.get('GOODDINER_STRIPE_TEST_KEY')||'';
const SIGN=Deno.env.get('GOODDINER_STRIPE_TEST_WEBHOOK_SECRET')||'';
const PRICE='price_1UfSKHI13uhJqTr1IhnRd2TO';
const PURPOSE='gooddiner_billing_lab';
const ORIGIN='https://andru1607.github.io';
const RETURN=ORIGIN+'/BuonTavolo/';
const VERSION='2026-11-18.endive';
const encoder=new TextEncoder();
const objId=(v:any)=>typeof v==='string'?v:v?.id||null;
const isTestKey=()=>KEY.startsWith('rk_test_')||KEY.startsWith('sk_test_');
const cors={'Access-Control-Allow-Origin':ORIGIN,'Access-Control-Allow-Methods':'POST, OPTIONS','Access-Control-Allow-Headers':'authorization, apikey, content-type, x-client-info','Vary':'Origin'};
function response(body:unknown,status=200){return new Response(JSON.stringify(body),{status,headers:{...cors,'Content-Type':'application/json','Cache-Control':'no-store'}});}
async function rpc(name:string,body:unknown,token:string,key=PUB){const r=await fetch(BASE+'/rest/v1/rpc/'+name,{method:'POST',headers:{'Content-Type':'application/json',apikey:key,Authorization:'Bearer '+token},body:JSON.stringify(body)});if(!r.ok)throw Error('BILLING_RPC_DENIED');return await r.json();}
const userRpc=(a:string,p:unknown,t:string)=>rpc('gooddiner_billing_lab',{p_action:a,p_payload:p},t);
const record=(p:unknown)=>rpc('gooddiner_billing_lab_record',{p},SERVICE,SERVICE);
async function stripe(path:string,params?:URLSearchParams,idempotency?:string){if(!isTestKey())throw Error('SANDBOX_KEY_REQUIRED');const headers:Record<string,string>={Authorization:'Bearer '+KEY,'Stripe-Version':VERSION};if(params)headers['Content-Type']='application/x-www-form-urlencoded';if(idempotency)headers['Idempotency-Key']=idempotency;const r=await fetch('https://api.stripe.com/v1/'+path,{method:params?'POST':'GET',headers,body:params});if(!r.ok)throw Error('STRIPE_REQUEST_FAILED');const o=await r.json();if(o.livemode!==false)throw Error('SANDBOX_ONLY');return o;}
function metaOK(o:any){return o?.livemode===false&&o?.metadata?.purpose===PURPOSE&&/^[0-9a-f-]{36}$/.test(o?.metadata?.run_id||'');}
async function snapshot(s:any,sub:any,event?:any){const m=sub?.metadata||s?.metadata;if(m?.purpose!==PURPOSE||!m?.run_id)return false;if(sub&&!metaOK(sub)||s&&!metaOK(s))return false;if(sub&&!sub.items?.data?.some((i:any)=>objId(i.price)===PRICE))return false;const end=sub?.items?.data?.map((i:any)=>i.current_period_end).filter((n:any)=>typeof n==='number').sort((a:number,b:number)=>b-a)[0];return await record({run_id:m.run_id,livemode:false,checkout_id:s?.id||null,subscription_id:sub?.id||objId(s?.subscription),customer_id:objId(sub?.customer)||objId(s?.customer),subscription_status:sub?.status||(s?.status==='expired'?'checkout_expired':null),payment_status:s?.payment_status||(sub?.latest_invoice?.status==='paid'?'paid':sub?.latest_invoice?.status==='open'?'unpaid':null),period_end:end?new Date(end*1000).toISOString():null,event_id:event?.id||null,event_type:event?.type||null,event_created:event?.created||Math.floor(Date.now()/1000)});}
async function subscription(id:string){if(!/^sub_[A-Za-z0-9]+$/.test(id))throw Error('INVALID_SUB');return stripe('subscriptions/'+id+'?expand%5B%5D=latest_invoice');}
async function checkout(id:string){if(!/^cs_test_[A-Za-z0-9]+$/.test(id))throw Error('INVALID_CHECKOUT');return stripe('checkout/sessions/'+id);}
async function signature(raw:string,header:string){if(!SIGN.startsWith('whsec_'))return false;const fields=header.split(',').map(v=>v.trim().split('='));const stamp=fields.find(v=>v[0]==='t')?.[1]||'';if(!/^\d+$/.test(stamp)||Math.abs(Date.now()/1000-Number(stamp))>300)return false;const key=await crypto.subtle.importKey('raw',encoder.encode(SIGN),{name:'HMAC',hash:'SHA-256'},false,['verify']);for(const [k,v] of fields){if(k!=='v1'||!/^[a-f0-9]{64}$/i.test(v||''))continue;const bytes=Uint8Array.from(v.match(/../g)!,h=>parseInt(h,16));if(await crypto.subtle.verify('HMAC',key,bytes,encoder.encode(stamp+'.'+raw)))return true;}return false;}
Deno.serve(async(req)=>{
 try{
  if(req.method==='OPTIONS')return new Response(null,{status:204,headers:cors});
  if(req.method!=='POST')return response({error:'METHOD'},405);
  const raw=await req.text();if(raw.length>200000)return response({error:'BODY'},413);
  const sig=req.headers.get('stripe-signature');
  if(sig!==null){
   if(!isTestKey()||!SIGN.startsWith('whsec_'))return response({error:'SANDBOX_NOT_CONFIGURED'},503);
   if(!await signature(raw,sig))return response({error:'INVALID_SIGNATURE'},400);
   const e=JSON.parse(raw);if(e.livemode!==false)return response({error:'SANDBOX_ONLY'},400);
   const o=e.data?.object||{};let s=null,sub=null;
   if(['checkout.session.completed','checkout.session.async_payment_succeeded','checkout.session.async_payment_failed','checkout.session.expired'].includes(e.type)){
    if(!metaOK(o))return response({received:true,ignored:true});s=await checkout(o.id);if(s.subscription)sub=await subscription(objId(s.subscription));
   }else if(['customer.subscription.created','customer.subscription.updated','customer.subscription.deleted','customer.subscription.paused','customer.subscription.resumed'].includes(e.type)){
    if(!metaOK(o))return response({received:true,ignored:true});sub=await subscription(o.id);
   }else if(['invoice.paid','invoice.payment_failed'].includes(e.type)){
    const sid=objId(o.parent?.subscription_details?.subscription)||objId(o.subscription);if(!sid)return response({received:true,ignored:true});sub=await subscription(sid);
   }else return response({received:true,ignored:true});
   await snapshot(s,sub,e);return response({received:true});
  }
  if(req.headers.get('origin')!==ORIGIN)return response({error:'ORIGIN'},403);
  const token=req.headers.get('authorization')?.replace(/^Bearer /i,'')||'';if(!token)return response({error:'LOGIN_REQUIRED'},401);
  const body=JSON.parse(raw||'{}');
  // Access verified by RLS-safe operator RPC with the caller's token, before Stripe calls.
  if(body.action==='status'){const rows=await userRpc('list',{},token);return response({configured:isTestKey()&&SIGN.startsWith('whsec_'),runs:rows});}
  if(!isTestKey()||!SIGN.startsWith('whsec_'))return response({error:'SANDBOX_NOT_CONFIGURED'},503);
  if(body.action==='checkout'){
   const plan=await stripe('prices/'+PRICE);if(!plan.active||plan.unit_amount!==2990||plan.currency!=='eur'||plan.recurring?.interval!=='month')throw Error('PRICE_MISMATCH');
   const r=await userRpc('prepare',{},token);const run=r.id;
   const q=new URLSearchParams({mode:'subscription','line_items[0][price]':PRICE,'line_items[0][quantity]':'1',success_url:RETURN,cancel_url:RETURN,'automatic_tax[enabled]':'false',client_reference_id:run,integration_identifier:'gooddiner-lab-qmtrvska','metadata[purpose]':PURPOSE,'metadata[run_id]':run,'subscription_data[metadata][purpose]':PURPOSE,'subscription_data[metadata][run_id]':run});
   const s=await stripe('checkout/sessions',q,'gd-lab-'+run);await snapshot(s,null);return response({url:s.url});
  }
  const r=await userRpc('get',{id:body.id},token);
  if(body.action==='sync'){const s=r.checkout_id?await checkout(r.checkout_id):null;const sid=r.subscription_id||objId(s?.subscription);const sub=sid?await subscription(sid):null;if(s||sub)await snapshot(s,sub);return response({runs:await userRpc('list',{},token)});}
  if(body.action==='portal'){if(!r.customer_id||!r.subscription_id)throw Error('SUBSCRIPTION_REQUIRED');const sub=await subscription(r.subscription_id);if(!metaOK(sub)||sub.metadata.run_id!==r.id||objId(sub.customer)!==r.customer_id)throw Error('BILLING_TEST_MISMATCH');const portal=await stripe('billing_portal/sessions',new URLSearchParams({customer:r.customer_id,return_url:RETURN}));return response({url:portal.url});}
  return response({error:'INVALID_ACTION'},400);
 }catch(e){const m=e instanceof Error?e.message:'';return response({error:['BILLING_RPC_DENIED','SANDBOX_NOT_CONFIGURED','SUBSCRIPTION_REQUIRED','SANDBOX_KEY_REQUIRED','PRICE_MISMATCH'].includes(m)?m:'BILLING_TEST_FAILED'},m==='BILLING_RPC_DENIED'?403:500);}
});