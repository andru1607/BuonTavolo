// Public business inquiry, not checkout. Strictly fail closed until configured.
// Runtime: Supabase Edge Functions; deploy with verify_jwt=false.
// Only the verified Turnstile challenge allows access to admin-key inserts.
// Never log business email, IP, request payload, payment data or server keys.
import { createClient } from 'npm:@supabase/supabase-js@2.119.1';

const projectRef='ixczkhmvbjszgmlqznlk';
const expectedUrl=`https://${projectRef}.supabase.co`;
const origin=String(Deno.env.get('GOODDINER_CANONICAL_ORIGIN')||'').replace(/\/$/,'');
const secret=String(Deno.env.get('GOODDINER_LEAD_TURNSTILE_SECRET')||'');
const salt=String(Deno.env.get('GOODDINER_LEAD_RATE_SALT')||'');
const serverUrl=String(Deno.env.get('SUPABASE_URL')||'');
const isReady=origin.startsWith('https://')&&
  serverUrl===expectedUrl&&secret.length>=10&&salt.length>=32;

function answer(status:number,payload:Record<string,string>,allowOrigin=false){
  const headers:Record<string,string>={
    'Content-Type':'application/json;charset=utf-8',
    'Cache-Control':'no-store',
    'X-Content-Type-Options':'nosniff'
  };
  if(allowOrigin){
    headers['Access-Control-Allow-Origin']=origin;
    headers['Vary']='Origin';
    headers['Access-Control-Allow-Methods']='POST, OPTIONS';
    headers['Access-Control-Allow-Headers']='apikey, content-type';
  }
  return new Response(JSON.stringify(payload),{status,headers});
}

Deno.serve(async req=>{
  if(!isReady)return answer(503,{error:'Le richieste commerciali non sono ancora attive.'});
  if(req.headers.get('origin')!==origin)return answer(403,{error:'Origine non autorizzata'});
  if(req.method==='OPTIONS')return new Response(null,{
    status:204,
    headers:{
      'Access-Control-Allow-Origin':origin,'Vary':'Origin',
      'Access-Control-Allow-Methods':'POST, OPTIONS',
      'Access-Control-Allow-Headers':'apikey, content-type',
      'Access-Control-Max-Age':'3600'
    }
  });
  if(req.method!=='POST')return answer(405,{error:'Metodo non disponibile'},true);
  if(!String(req.headers.get('content-type')||'').startsWith('application/json'))
    return answer(415,{error:'Formato non supportato'},true);
  try{
    const bodyText=await req.text();
    if(bodyText.length>2000)return answer(413,{error:'Richiesta troppo lunga'},true);
    const payload=JSON.parse(bodyText);
    const restaurant=String(payload?.restaurant_name||'').trim();
    const city=String(payload?.city||'').trim();
    const email=String(payload?.email||'').trim().toLowerCase();
    const captcha=String(payload?.captcha_token||'').trim();
    if(payload?.contact_requested!==true||restaurant.length<3||restaurant.length>100||
      city.length<2||city.length>100||email.length<5||email.length>254||
      !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)||
      captcha.length<10||captcha.length>2048){
      return answer(400,{error:'Controlla i dati inseriti.'},true);
    }

    const clientIp=String(req.headers.get('cf-connecting-ip')||
      req.headers.get('x-forwarded-for')?.split(',')[0]||'').trim();
    if(!clientIp||clientIp.length>70)return answer(503,{error:'Verifica richiesta non disponibile.'},true);

    const challenge=await fetch('https://challenges.cloudflare.com/turnstile/v0/siteverify',{
      method:'POST',
      headers:{'Content-Type':'application/x-www-form-urlencoded'},
      body:new URLSearchParams({secret,response:captcha,remoteip:clientIp})
    });
    if(!challenge.ok)return answer(503,{error:'Verifica anti-bot non disponibile.'},true);
    const verdict=await challenge.json();
    if(verdict?.success!==true||!Array.isArray(verdict?.['error-codes'])&&verdict?.success===false){
      return answer(403,{error:'Verifica anti-bot non riuscita.'},true);
    }
    if(verdict?.hostname!==new URL(origin).hostname){
      return answer(403,{error:'Verifica non valida per questo sito.'},true);
    }

    const hashBytes=await crypto.subtle.digest('SHA-256',
      new TextEncoder().encode(salt+':'+clientIp));
    const hash=[...new Uint8Array(hashBytes)].map(b=>b.toString(16).padStart(2,'0')).join('');
    const keys=JSON.parse(Deno.env.get('SUPABASE_SECRET_KEYS')||'{}');
    const adminKey=keys['default'];
    if(!adminKey)return answer(503,{error:'Servizio temporaneamente non disponibile.'},true);
    const admin=createClient(serverUrl,adminKey,{auth:{persistSession:false,autoRefreshToken:false}});
    const windowStart=new Date(Date.now()-24*60*60*1000).toISOString();
    const {count,error:countError}=await admin.from('business_pilot_leads')
      .select('id',{count:'exact',head:true}).eq('source_hash',hash).gte('created_at',windowStart);
    if(countError)return answer(503,{error:'Invio non disponibile.'},true);
    if((count??0)>=3)return answer(429,{error:'Limite richieste raggiunto.'},true);
    const {error}=await admin.from('business_pilot_leads').insert({
      restaurant_name:restaurant,city,contact_email:email,
      source_hash:hash,contact_requested:true
    });
    // Do not reveal whether this business email exists in the queue.
    if(error&&error.code!=='23505')return answer(503,{error:'Invio non disponibile.'},true);
    return answer(202,{status:'received'},true);
  }catch{
    return answer(400,{error:'Richiesta non valida o invio non disponibile.'},true);
  }
});
