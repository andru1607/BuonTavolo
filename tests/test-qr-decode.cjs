'use strict';
const assert=require('node:assert/strict');
const {Resvg}=require('@resvg/resvg-js');
const jsQR=require('jsqr');
require('../qr-core.js');
const tokens=Array.from({length:24},()=> 'GD1:'+require('node:crypto').randomUUID());
tokens.push('GD1:00000000-0000-4000-8000-000000000000','x'.repeat(170));
for(const token of tokens){
 for(const width of [252,378,504]){
  const image=new Resvg(globalThis.GoodDinerQR.svg(token),{fitTo:{mode:'width',value:width}}).render();
  const decoded=jsQR(new Uint8ClampedArray(image.pixels),image.width,image.height,{inversionAttempts:'dontInvert'});
  assert.equal(decoded?.data,token,'branded QR must decode at '+width+' px');
 }
}
console.log('PASS: branded SVG decoded at 3 raster sizes, '+tokens.length+' payloads');
