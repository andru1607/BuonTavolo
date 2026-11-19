const fs=require('fs'),assert=require('node:assert/strict'),path=require('path');
const root=path.resolve(__dirname,'..');
const index=fs.readFileSync(path.join(root,'index.html'),'utf8');
const account=fs.readFileSync(path.join(root,'account.html'),'utf8');
const serviceWorker=fs.readFileSync(path.join(root,'sw.js'),'utf8');
for(const image of ['sala','tavola']){
 const file=path.join(root,'media',image+'.webp');
 assert.ok(fs.existsSync(file),'Missing photo '+image);
 const bytes=fs.readFileSync(file);
 assert.equal(bytes.toString('ascii',0,4),'RIFF','WebP RIFF header');
 assert.ok(bytes.length<180000, 'Image must be compressed for mobile');
 assert.ok(index.includes('/media/'+image+'.webp'),'Image used in interface');
 assert.ok(serviceWorker.includes('/media/'+image+'.webp'),'Image included in PWA offline assets');
}
assert.ok(index.includes('experience-cover')&&index.includes('merchant-image-label')&&index.includes('reward-story'), 'Photos in customer/restaurant/rewards');
assert.ok(account.includes('account-visual'),'Account editorial photo');
assert.ok(index.includes('animation:btScreenIn'), 'Screen change has an entrance animation');
assert.ok(index.includes('screenFallbackMotion'),'Transition fallback available');
assert.ok(index.includes('prefers-reduced-motion:reduce'),'Accessible reduced motion');
assert.ok(index.includes('POSITIVE_MIN=8'),'Positive reviews still require eight stars');
assert.match(index, /@media\(prefers-reduced-motion:reduce\)\{\.screen-enter[^}]*animation:none!important/, 'Reduced motion disables screen entrance');
console.log('PASS: V7 photos, optimized delivery, transitions, reduced-motion, mobile PWA');
