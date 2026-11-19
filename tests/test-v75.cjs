const fs=require('fs'),assert=require('node:assert/strict'),path=require('path');
const root=path.resolve(__dirname,'..'),read=p=>fs.readFileSync(path.join(root,p),'utf8');
const icon=read('icons/icon.svg'),mark=read('icons/mark.svg'),h=read('index.html');
assert.ok(icon.includes('GoodDiner')&&icon.includes('simbolo GD intrecciato'));
assert.ok(mark.includes('fill="#153F32"')&&mark.includes('#D2A965'));
assert.ok(icon.includes('viewBox="0 0 512 512"')&&!icon.includes('gradient'));
assert.ok(read('icons/mark-light.svg').includes('fill="#F6EFE2"'));
assert.ok(h.includes('name===\'logo\'?`<svg')&&h.includes('viewBox="0 0 512 512"'));
assert.ok(h.includes('apple-touch-icon" href="/icons/icon-180.png"'));
for(const n of [180,192,512]){
 const b=fs.readFileSync(path.join(root,'icons',`icon-${n}.png`));
 assert.equal(b.subarray(0,8).toString('hex'),'89504e470d0a1a0a');
 assert.equal(b.readUInt32BE(16),n);assert.equal(b.readUInt32BE(20),n);
}
assert.ok(read('sw.js').includes('gooddiner-demo-v79'));
assert.ok(h.includes('const MAX_STARS=10, POSITIVE_MIN=8'));
assert.ok(h.includes("const KEY='buontavolo-preview-v4'"));
console.log('PASS V7.5: scelto GD intrecciato SVG, tre PNG PWA, app mark, cache, dati/8-10 invariati');