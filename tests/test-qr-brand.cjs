'use strict';
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
require('../qr-core.js');
const mark=fs.readFileSync(path.join(__dirname,'../icons/mark.svg'),'utf8').match(/<svg[^>]*>([\s\S]*?)<\/svg>/)[1].trim();
for(const token of ['GD1:00000000-0000-4000-8000-000000000000','GD1:abcdef12-3456-4abc-8def-123456789012','x'.repeat(170)]){
 const svg=globalThis.GoodDinerQR.svg(token);
 assert.ok(svg.includes(mark),'original GoodDiner mark embedded');
 assert.match(svg,/data-brand="gooddiner"/);
 assert.match(svg,/width="5" height="5" fill="#fff"/);
 assert.doesNotMatch(svg,/dimostrativo/);
}
assert.throws(()=>globalThis.GoodDinerQR.svg('x'.repeat(171)));
console.log('PASS: locally branded real QR and bounded central logo');
