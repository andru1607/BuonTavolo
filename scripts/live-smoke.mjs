// Live, public read-only smoke check. Run after setting GOODDINER_BASE_URL.
// NO signup, database writes, tokens or test users. Uses Node.js built-in fetch.
const raw=process.env.GOODDINER_BASE_URL;
if(!raw){
  console.error('GOODDINER_BASE_URL not configured. Live deployment was NOT tested.');
  process.exit(2);
}
let origin;
try{
  const url=new URL(raw);
  if(url.protocol!=='https:'||url.username||url.password||url.search||url.hash||url.pathname!=='/'){
    throw Error('Expected a public https origin without credentials or query');
  }
  origin=url.origin;
}catch(err){console.error('Invalid GOODDINER_BASE_URL: '+err.message);process.exit(2);}
const project='ixczkhmvbjszgmlqznlk';
async function check(path,expected){
  const url=origin+path;
  const controller=new AbortController();
  const timeout=setTimeout(()=>controller.abort(),12000);
  try{
    const res=await fetch(url,{redirect:'follow',signal:controller.signal,headers:{'Accept':'text/html,application/javascript,application/json'}});
    if(!res.ok)throw Error('HTTP '+res.status+' '+res.statusText);
    const final=new URL(res.url);
    if(final.origin!==origin)throw Error('unexpected cross-origin redirect to '+final.origin);
    if(path==='/'){
      const csp=res.headers.get('content-security-policy')||'';
      const hsts=res.headers.get('strict-transport-security')||'';
      const perms=res.headers.get('permissions-policy')||'';
      const robots=res.headers.get('x-robots-tag')||'';
      if(res.headers.get('x-content-type-options')!=='nosniff')throw Error('nosniff header missing');
      if(res.headers.get('x-frame-options')!=='DENY')throw Error('frame protection missing');
      if(!csp.includes("script-src 'self'")||!csp.includes("object-src 'none'")||
         !csp.includes('https://challenges.cloudflare.com')||
         !csp.includes('https://ixczkhmvbjszgmlqznlk.supabase.co'))
        throw Error('official Content-Security-Policy missing or incomplete');
      if(!hsts.includes('max-age='))throw Error('HTTPS transport protection missing');
      if(!perms.includes('camera=(self)'))throw Error('camera permissions policy missing');
      if(!robots.includes('noindex'))throw Error('prelaunch search-engine block missing');
    }
    const body=await res.text();
    if(!body.includes(expected))throw Error('content signature missing');
    console.log('PASS '+path+' HTTP '+res.status+' '+res.headers.get('content-type'));
    return body;
  } finally{clearTimeout(timeout);}
}
try{
  const html=await check('/','GoodDiner');
  if(!html.includes('src="/official.js"')||!html.includes('src="/turnstile.js"')){
    throw Error('Main page does not load verified GoodDiner official client');
  }
  if(!html.includes('noindex,nofollow'))throw Error('prelaunch meta noindex missing');
  const script=await check('/official.js',"issue_guest_qr");
  if(!script.includes('registrationEnabled'))throw Error('Release gating not deployed');
  const deployedConfig=await check('/config.js',project);
  const shouldBeOpen=process.env.GOODDINER_EXPECT_REGISTRATION_OPEN==='true';
  if(!new RegExp('registrationEnabled:\\s*'+String(shouldBeOpen)).test(deployedConfig))
    throw Error('deployed signup gate differs from approved release mode');
  if(shouldBeOpen&&!/turnstileSiteKey:\\s*["'][^"']{8,}["']/.test(deployedConfig))
    throw Error('signup opened without a public Turnstile site key');
  await check('/turnstile.js','GoodDinerCaptcha');
  await check('/client-export.js','GoodDinerDataExport');
  await check('/manifest.webmanifest','GoodDiner');
  console.log('PASS LIVE READ-ONLY SMOKE '+origin);
}catch(err){
  console.error('FAIL LIVE SMOKE '+origin+': '+err.message);
  process.exitCode=1;
}
