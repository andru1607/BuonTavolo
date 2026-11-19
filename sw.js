const CACHE='buontavolo-demo-v6';
const ASSETS=['/','/index.html','/manifest.webmanifest','/icons/icon.svg'];
self.addEventListener('install',event=>{
  event.waitUntil(caches.open(CACHE).then(cache=>cache.addAll(ASSETS)));
  self.skipWaiting();
});
self.addEventListener('activate',event=>{
  event.waitUntil(caches.keys().then(keys=>Promise.all(keys.filter(key=>key!==CACHE).map(key=>caches.delete(key)))));
  self.clients.claim();
});
self.addEventListener('fetch',event=>{
  const request=event.request,url=new URL(request.url);
  if(request.method!=='GET'||url.origin!==self.location.origin) return;
  // L'area autenticata e la configurazione devono essere lette dalla rete,
  // mai salvate nella cache della demo.
  if(['/account.html','/account.js','/config.js'].includes(url.pathname)) return;
  event.respondWith(fetch(request).then(res=>{
    if(res.ok) {const clone=res.clone();caches.open(CACHE).then(cache=>cache.put(request,clone)).catch(()=>{});}
    return res;
  }).catch(()=>caches.match(request).then(res=>res||caches.match('/index.html'))));
});