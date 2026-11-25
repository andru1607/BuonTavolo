'use strict';
const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm'),path=require('node:path');
const read=p=>fs.readFileSync(path.join(__dirname,'..',p),'utf8');
const main=read('official.js'),studio=read('studio/studio.js'),html=read('studio/index.html');
assert.doesNotThrow(()=>new vm.Script(main));assert.doesNotThrow(()=>new vm.Script(studio));
assert.match(main,/async function init\(\)\{events\(\);const url/);assert.match(main,/await loadAccount\(\);\}/);assert.match(read('index.html'),/class="boot" role="status"/);
assert.match(html,/id="login" class="login" hidden/);assert.match(html,/id="launch"/);assert.match(studio,/grant_type=refresh_token/);assert.match(studio,/await ensureSession\(\);await openWorkspace\(\)/);assert.match(studio,/function reset\(\)\{forgetSession\(\)/);assert.match(studio,/await loadDashboard\(\)/);
assert.ok(!studio.includes('localStorage.setItem(SESSION_KEY,JSON.stringify({password'));
console.log('PASS: native startup syntax, initial splash and session lifecycle');
