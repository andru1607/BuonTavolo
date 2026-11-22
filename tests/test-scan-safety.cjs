'use strict';
const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const path=require('node:path');
const src=fs.readFileSync(path.join(__dirname,'..','official.js'),'utf8');
const start=src.indexOf('  function validateDinerPassToken('),end=src.indexOf('  async function claim(token)',start);
assert.ok(start>0&&end>start,'scanner helpers must be present');
const scope={};
vm.runInNewContext(src.slice(start,end)+';globalThis.GDScanTest={validateDinerPassToken,checkinError};',scope);
const {validateDinerPassToken,checkinError}=scope.GDScanTest;
const token='GD1:00000000-1111-4222-8333-444444444444';
assert.equal(validateDinerPassToken(' '+token+' '),token);
for(const bad of ['', 'GD1:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa','GD1:00000000-1111-4222-8333-44444444444z','invalid','GD1:00000000-1111-4222-8333-444444444444\\nwrong']){
 assert.throws(()=>validateDinerPassToken(bad),/Codice non valido/);
}
assert.match(checkinError({message:'QR_SCADUTO_O_UTILIZZATO'}),/scaduto/);
assert.match(checkinError({message:'VISITA_GIA_REGISTRATA'}),/già stata registrata/);
assert.match(checkinError({message:'gd_no_self_checkin'}),/tuo DinerPass/);
assert.doesNotMatch(checkinError({message:'internal error: secret SQL connection details'}),/secret|SQL/);
assert.match(src,/rejectedScanToken=code;rejectedScanUntil=Date\.now\(\)\+4000/);
assert.match(src,/value===rejectedScanToken&&Date\.now\(\)<rejectedScanUntil/);
console.log('PASS: QR syntax, localized server errors, duplicate camera retry cooldown');
