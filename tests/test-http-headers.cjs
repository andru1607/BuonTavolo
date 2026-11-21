'use strict';
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const read=p=>fs.readFileSync(path.join(__dirname,'..',p),'utf8');
const config=JSON.parse(read('vercel.json'));
const global=config.headers.find(x=>x.source==='/(.*)');
const headers=Object.fromEntries(global.headers.map(x=>[x.key.toLowerCase(),x.value]));
assert.equal(headers['x-content-type-options'],'nosniff');
assert.equal(headers['x-frame-options'],'DENY');
assert.match(headers['strict-transport-security'],/max-age=31536000/);
assert.match(headers['permissions-policy'],/camera=\(self\)/);
assert.match(headers['x-robots-tag'],/noindex/);
for(const source of ['/','/index.html']){
 const route=config.headers.find(x=>x.source===source);
 assert.ok(route,source+' header route missing');
 const csp=route.headers.find(x=>x.key==='Content-Security-Policy')?.value;
 assert.ok(csp,source+' CSP missing');
 for(const directive of ["default-src 'self'","script-src 'self'","object-src 'none'","frame-ancestors 'none'","base-uri 'self'","frame-src https://challenges.cloudflare.com","https://ixczkhmvbjszgmlqznlk.supabase.co","https://cdn.jsdelivr.net"]){
   assert.ok(csp.includes(directive),source+' missing '+directive);
 }
 assert.ok(!csp.includes("'unsafe-eval'"),'unsafe-eval must never be allowed');
 assert.ok(!csp.match(/script-src[^;]*'unsafe-inline'/),'inline scripts must not be allowed');
}
const workflow=read('.github/workflows/gooddiner-tests.yml');
const smoke=read('scripts/live-smoke.mjs');
assert.match(workflow,/workflow_dispatch:/);
assert.match(workflow,/GOODDINER_BASE_URL:/);
assert.match(workflow,/Live smoke not configured|Explain skipped live smoke/);
assert.match(smoke,/content-security-policy/);
assert.match(smoke,/strict-transport-security/);
assert.match(smoke,/registrationEnabled/);
assert.match(smoke,/noindex/);
console.log('PASS: prelaunch HTTP hardening, CSP and explicit read-only live smoke release check');
