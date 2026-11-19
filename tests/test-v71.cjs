const fs=require('fs'),assert=require('node:assert/strict'),path=require('path');
const dir=path.join(__dirname,'..');const html=fs.readFileSync(path.join(dir,'index.html'),'utf8'),sw=fs.readFileSync(path.join(dir,'sw.js'),'utf8');const account=fs.readFileSync(path.join(dir,'account.html'),'utf8');
for(const x of ['media/sala.webp','media/tavola.webp','Fotografia illustrativa','Immagine illustrativa'])assert.ok(!html.includes(x),'Stock photos must not appear: '+x);
assert.ok(!sw.includes('media/'),'SW must not cache stock photos');assert.ok(!account.includes('media/'),'Account has no stock');
for(const x of ['PHOTO_KEY','merchantPhotoEditor','setMerchantPhoto','PHOTO_SLOTS','data-photo-slot','restaurantPreview','document.startViewTransition','prefers-reduced-motion:reduce','POSITIVE_MIN=8','view-transition-name'])assert.ok(html.includes(x),'Missing UX: '+x);
assert.ok(html.includes('Solo anteprima locale'),'local scope warning');assert.ok(!fs.existsSync(path.join(dir,'media')),'No photos distributed in demo');
console.log('PASS: V7.1 restaurant photo studio, stock-free branding, transitions and accessibility');