'use strict';
const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const path=require('node:path');
const js=fs.readFileSync(path.join(__dirname,'..','official.js'),'utf8');
const start=js.indexOf('  function validateSignupPasswords(');
const end=js.indexOf('  async function signupCustomer(',start);
assert.ok(start!==-1&&end>start);
const scope={};
vm.runInNewContext(js.slice(start,end)+';globalThis.validateSignupPasswords=validateSignupPasswords;',scope);
const check=scope.validateSignupPasswords;
assert.doesNotThrow(()=>check('corretta-password123','corretta-password123'));
assert.throws(()=>check('123456789','123456789'),/10 a 128/);
assert.throws(()=>check('x'.repeat(129),'x'.repeat(129)),/10 a 128/);
assert.throws(()=>check('corretta-password123','corretta-password321'),/non coincidono/);
for (const id of ['customer-password', 'customer-confirm-password', 'merchant-password', 'merchant-confirm-password']) {
  const input = js.match(new RegExp('<input id="' + id + '"[^>]*>'));
  assert.ok(input, 'Missing signup field: ' + id);
  assert.match(input[0], /\srequired(?=[\s>])/, id + ' must use native required validation');
}
assert.match(js,/validateSignupPasswords\(password,confirmation\);const answer=await sb\.auth\.signUp/);
assert.match(js,/validateSignupPasswords\(password,confirmation\);if\(pilotInviteOnly/);
console.log('PASS: customer/merchant password confirmation and length validation before signup');
