'use strict';
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const read=x=>fs.readFileSync(path.join(__dirname,'..',x),'utf8');
const home=read('index.html');
const business=read('business.html');
const demo=read('demo.html');
const css=read('design-v2.css');
const demoCss=read('demo-design-v2.css');
const app=read('official.js');
const sw=read('sw.js');

for(const [page,markup] of [['official',home],['business',business]]){
 assert.match(markup,/<link rel="stylesheet" href="\/design-v2\.css">/,page+' must load shared design layer');
}
assert.match(home,/<body class="gooddiner-app">/);
assert.match(business,/class="business-body"/);
assert.match(demo,/<link rel="stylesheet" href="\/demo-design-v2\.css">/);
for(const selector of [
 '.gooddiner-app .mobile-nav','.gooddiner-app .pass-card',
 '.gooddiner-app .qr-space','.gooddiner-app .merchant-hero',
 '.gooddiner-app .stats','.gooddiner-app .client-banner',
 '.business-body .business-hero','.business-body .business-price-card'
])assert.ok(css.includes(selector),'missing design target: '+selector);
assert.match(css,/grid-template-columns:repeat\(4,minmax\(0,1fr\)\)/);
assert.match(css,/:has\(>button:nth-child\(3\):last-child\)/);
assert.match(css,/env\(safe-area-inset-bottom\)/);
assert.match(css,/@media\(max-width:360px\)/);
assert.match(css,/@media\(prefers-reduced-motion:reduce\)/);
assert.match(demoCss,/\.v73-app \.mobile-bottom/);
assert.match(demoCss,/\.v73-app \.sidebar/);
assert.match(app,/const navIcons=\{merchant:'store',pass:'scan',visits:'clock',reviews:'star',profile:'user'\}/);
assert.match(app,/\$\{navIcon\(s\)\}<span>\$\{label\}<\/span>/);
assert.match(app,/Il tuo pass personale per registrare una presenza al ristorante/);
assert.match(app,/Le valutazioni personali non sono attive durante il pilota/);
assert.match(sw,/const CACHE='gooddiner-real-v103'/);
assert.match(sw,/'\/design-v2\.css'/);
assert.match(sw,/'\/demo-design-v2\.css'/);
const lines=css.split('\n').filter(x=>!x.trim().startsWith('/*'));
const hexVar=name=>{
 const m=css.match(new RegExp('--'+name+':(#[0-9a-fA-F]{6})'));
 assert.ok(m,'missing hex theme color: '+name);return m[1];
};
function luminance(hex){
 const channels=[1,3,5].map(i=>parseInt(hex.slice(i,i+2),16)/255)
  .map(v=>v<=.04045?v/12.92:Math.pow((v+.055)/1.055,2.4));
 return channels[0]*.2126+channels[1]*.7152+channels[2]*.0722;
}
const contrast=(a,b)=>{
 const x=luminance(hexVar(a)),y=luminance(hexVar(b));
 return (Math.max(x,y)+.05)/(Math.min(x,y)+.05);
};
for(const [a,b] of [['ink','paper'],['teal','paper'],['muted','paper'],['paper','teal']]){
 assert.ok(contrast(a,b)>=4.5,a+' on '+b+' has insufficient WCAG AA contrast: '+contrast(a,b));
}
assert.equal(css.split('{').length-1,css.split('}').length-1,'main design CSS braces unbalanced');
assert.equal(demoCss.split('{').length-1,demoCss.split('}').length-1,'demo design CSS braces unbalanced');
console.log('PASS: design 2.0 pages, iPhone tabs, QR/dashboard styles, cache and readable palette');
