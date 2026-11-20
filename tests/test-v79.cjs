'use strict';
const assert=require('node:assert/strict'),fs=require('fs'),vm=require('node:vm'),path=require('node:path');
const root=path.resolve(__dirname,'..'),read=p=>fs.readFileSync(path.join(root,p),'utf8');
const html=read('index.html'), css=read('personalize-v79.css'),js=read('v79-customize.js'),boot=read('v79-boot.js');
assert.match(html,/src="\/v79-boot\.js"/);
assert.match(html,/src="\/v79-customize\.js"/);
assert.match(html,/href="\/personalize-v79\.css"/);
assert.match(read('account.html'),/href="\/personalize-v79\.css"/);
assert.ok(html.indexOf('src="/v76-onboarding.js"')<html.indexOf('src="/v79-customize.js"'),'Customization should load after v76 role and QR layer');
assert.match(js,/const baseClientProfile=clientProfile/);
assert.match(js,/const baseMerchantManage=merchantManage/);
assert.match(js,/html\[data-gd-pass|appearance\.passes/);
assert.ok(!/navigator\.geolocation|fetch\(|service_role/i.test(js),'No contact, location or remote calls in preferences');
assert.match(css,/html\[data-gd-theme="sunset"\]/);
assert.match(css,/html\[data-gd-theme="night"\]/);
assert.match(css,/html\[data-gd-pass="coral"\]/);
assert.match(css,/html\[data-gd-venue="night"\]/);
assert.match(css,/prefers-reduced-motion/);
assert.match(js,/aria-pressed/);
assert.match(js,/localStorage\.setItem/);
assert.match(js,/aria-label="Personalizzazione del locale"/);
assert.match(js,/aria-label="Personalizza il DinerPass"/);
const sw=read('sw.js');assert.match(sw,/gooddiner-demo-v710/);
for(const s of ['v79-boot.js','personalize-v79.css','v79-customize.js'])assert.ok(sw.includes("'/"+s+"'"));
for(const p of ['v79-boot.js','v79-customize.js'])new vm.Script(read(p),{filename:p});
const doc={documentElement:{dataset:{gdTheme:'signature',gdDensity:'comfortable'}}};
vm.runInNewContext(boot,{document:doc,localStorage:{getItem:()=>JSON.stringify({theme:'night',density:'compact'})}});
assert.equal(doc.documentElement.dataset.gdTheme,'night');assert.equal(doc.documentElement.dataset.gdDensity,'compact');
vm.runInNewContext(boot,{document:doc,localStorage:{getItem:()=>JSON.stringify({theme:'invalid',density:'tiny'})}});
assert.equal(doc.documentElement.dataset.gdTheme,'signature');assert.equal(doc.documentElement.dataset.gdDensity,'comfortable');
assert.match(html,/POSITIVE_MIN=8/);
assert.match(html,/v76-onboarding.js/);
assert.match(html,/QR/);
assert.doesNotMatch(js,/\p{Emoji_Presentation}/u);
console.log('PASS V7.9: app themes, per-user DinerPass, merchant studio, local storage, accessibilità, no backend');
const choices = Object.fromEntries(Array.from({length:81},(_,i)=>['GD-TEST'+i,'coral']));
let stored = JSON.stringify({theme:'night',density:'compact',passes:choices,venue:'signature'});
let refuseWrite = true;
let onClick;
const studio = {
  db:{activeCustomer:'GD-TEST80'}, state:{role:'customer'}, document:{
    documentElement:{dataset:{}},addEventListener:(name,fn)=>{if(name==='click')onClick=fn},
    querySelectorAll:()=>[]
  },
  window:{addEventListener(){}},localStorage:{
    getItem:()=>stored,setItem:(_,v)=>{if(refuseWrite)throw Error('quota');stored=v}
  },notify(){},render(){},clientProfile(){},merchantManage(){},clientHome(){},merchantHome(){}
};
vm.runInNewContext(js,studio);
const attrs=studio.document.documentElement.dataset;
assert.equal(attrs.gdPass,'coral','Appearance survives reopening the 81st demo profile');
function reset(){onClick({target:{closest:()=>({dataset:{gdCustom:'reset',scope:'customer'}})}})}
reset();
studio.render();
assert.equal(attrs.gdTheme,'night','A failed reset must preserve the active theme after navigation');
assert.equal(attrs.gdPass,'coral');
refuseWrite=false;
reset();
assert.equal(attrs.gdTheme,'signature');
assert.equal(JSON.parse(stored).passes['GD-TEST79'],'coral','Reset only affects the current pass');
