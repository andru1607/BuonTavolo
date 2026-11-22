'use strict';
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const app=fs.readFileSync(path.join(__dirname,'..','official.js'),'utf8');
for(const snippet of [
 'let accountLoadGeneration=0;',
 'function clearAccountState(){',
 'resetScanner();clearTimeout(qrTimer);qrTimer=null;',
 'state.privacyRequests=[];',
 'state.merchantLicense=null;',
 'state.qr=null;',
 "const generation=++accountLoadGeneration;",
 'if(generation!==accountLoadGeneration)return;',
 "if(error||!data?.user){clearAccountState();",
 "if(error){await refresh();throw Error(authMessage(error));}clearAccountState();",
 "sessionStorage.removeItem('gd_merchant_pending')"
])assert.ok(app.includes(snippet),'missing session isolation control: '+snippet);
const count=app.split('if(generation!==accountLoadGeneration)return;').length-1;
assert.ok(count>=5,'check token after each awaited load to avoid stale-session data being rendered');
assert.ok(app.includes("if(!['signup','signup-customer','signup-merchant','signin','forgot','confirm'].includes(state.view))state.view='landing'"),'signed-out navigation may not be left in private account');
assert.ok(app.includes("state.view==='confirm'||!state.user"),'confirmed email prompt must be accessible to logged-in pending merchants');
console.log('PASS: pending async data cannot repopulate signed-out accounts; QR and old histories cleared');
