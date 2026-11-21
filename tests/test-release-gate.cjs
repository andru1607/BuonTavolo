'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const read = file => fs.readFileSync(path.join(__dirname, '..', file), 'utf8');

const index = read('index.html');
const config = read('config.js');
const js = read('official.js');
const helper = read('turnstile.js');
assert.ok(index.indexOf('<script src="/config.js">') < index.indexOf('<script src="/turnstile.js">'));
assert.ok(index.indexOf('<script src="/turnstile.js">') < index.indexOf('src="/official.js"'));
assert.match(config, /registrationEnabled:\s*false/,'public registration is blocked until operator enables it');
assert.match(config, /turnstileSiteKey:\s*""/,'no invented site key or secret');
assert.match(index, /noindex,nofollow/,'no SEO before approval');
assert.match(js, /registrationEnabled=cfg\.registrationEnabled===true/,'signup is gated, not merely hidden');
assert.match(js, /if\(!registrationEnabled\)throw Error\('Registrazioni non ancora disponibili/,'SDK signup calls must be blocked');
assert.ok(js.includes("captchaToken:captcha"),'signups and anonymous flow pass challenge token');
assert.ok(js.includes("captchaToken:captchaToken(form)"),'login/recovery pass challenge token');
assert.match(js,/GoodDinerCaptcha\?\.cleanup\(\)/,'widget removed before re-render');
assert.ok(!helper.includes('Secret key')&&!helper.includes('secretKey'),'client never embeds Turnstile server secret');

const noCaptcha = {window:{GOODDINER_PUBLIC_CONFIG:{}},document:{}};
vm.runInNewContext(helper,noCaptcha);
assert.equal(noCaptcha.window.GoodDinerCaptcha.enabled(),false);
assert.throws(()=>noCaptcha.window.GoodDinerCaptcha.token({},true),/Verifica anti-bot/);

let callback,rendered=0,reset=0,removed=0;
const field={value:''};
let form,slot;
slot={dataset:{gdCaptcha:'signup'},closest:()=>form};
form={querySelector:selector=>selector==='[data-gd-captcha]'?slot:selector==='[name="captchaToken"]'?field:null};
const fakeWindow={
  GOODDINER_PUBLIC_CONFIG:{turnstileSiteKey:'fake-sitekey-for-unit-test'},
  turnstile:{
    render(element,options){assert.equal(element,slot);assert.equal(options.sitekey,'fake-sitekey-for-unit-test');callback=options;rendered++;return 'widget-unit-1';},
    reset(id){assert.equal(id,'widget-unit-1');reset++;},
    remove(id){assert.equal(id,'widget-unit-1');removed++;}
  }
};
const dom={querySelectorAll:()=>[slot]};
vm.runInNewContext(helper,{window:fakeWindow,document:dom});
const adapter=fakeWindow.GoodDinerCaptcha;
adapter.mount();
assert.equal(rendered,1);
assert.throws(()=>adapter.token(form,true),/Completa la verifica anti-bot/);
callback.callback('a-temporary-token');
assert.equal(adapter.token(form,true),'a-temporary-token');
callback['expired-callback']();
assert.equal(field.value,'');
callback.callback('another-temporary-token');
adapter.resetFor(form);
assert.equal(field.value,'');
assert.equal(reset,1);
adapter.cleanup();
assert.equal(removed,1);
console.log('PASS: closed prelaunch registration, required and expiring Turnstile token, UI mount lifecycle');
