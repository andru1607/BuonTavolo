// GoodDiner v1: production shell. Supabase API/auth data is NEVER cached.
// Legacy regression marker: gooddiner-demo-v710.
const CACHE='gooddiner-real-v106'; // upgraded from gooddiner-real-v100
const STATIC=['/','/index.html','/official.css','/design-v2.css','/official.js','/config.js','/manifest.webmanifest','/icons/icon.svg','/icons/mark.svg','/icons/mark-light.svg','/qr-core.js','/turnstile.js','/client-export.js','/auth-feedback.js'];
// Old UI assets remain available on /demo.html only, for regression testing.
const LEGACY=['/demo.html','/demo-design-v2.css','/v76-onboarding.css','/theme-v77.css','/ux-v78.css','/v79-boot.js','/personalize-v79.css','/v79-customize.js','/visit-core-v710.js','/v710-visits.js','/visits-v710.css','/v76-onboarding.js'];
self.addEventListener('install',event=>{event.waitUntil(caches.open(CACHE).then(cache=>cache.addAll(STATIC)).catch(()=>{}));self.skipWaiting();});
self.addEventListener('activate',event=>{event.waitUntil(caches.keys().then(keys=>Promise.all(keys.filter(key=>key.startsWith('gooddiner-')&&key!==CACHE).map(key=>caches.delete(key)))));self.clients.claim();});
self.addEventListener('fetch',event=>{
 const req=event.request;if(req.method!=='GET')return;const url=new URL(req.url);if(url.origin!==self.location.origin)return;
 // No store of user data, auth responses or requests bearing Authorization.
 if(url.pathname.startsWith('/api/')||req.headers.has('Authorization'))return;
 if(url.pathname==='/account.html'||url.pathname==='/account.js')return;
 event.respondWith(fetch(req).then(response=>{if(response.ok&&STATIC.some(p=>p===url.pathname)){const copy=response.clone();caches.open(CACHE).then(c=>c.put(req,copy)).catch(()=>{});}return response;}).catch(()=>caches.match(req).then(cached=>cached||new Response('Connessione necessaria per utilizzare GoodDiner.',{status:503,headers:{'Content-Type':'text/plain; charset=utf-8'}}))));
});