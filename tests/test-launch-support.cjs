'use strict';
const fs=require('node:fs'),path=require('node:path');
function run(source,qr){
 const passed=[],check=(v,m)=>{if(!v)throw Error(m);passed.push(m)};
 for(const role of ['customer','merchant']){
 const app={innerHTML:'',classList:{toggle(){}}},toast={textContent:''},handlers={},nodes={},doc={getElementById:id=>id==='app'?app:id==='toast'?toast:app.innerHTML.includes('id="'+id+'"')?(nodes[id]??={value:'',innerHTML:'',handlers:{},addEventListener(n,f){this.handlers[n]=f},focus(){}}):null,addEventListener:(n,f)=>handlers[n]=f};
 const win={location:{search:'?gd_preview='+role,origin:'https://buontavolo.vercel.app'},GOODDINER_PUBLIC_CONFIG:{personalReviewsEnabled:true},GoodDinerAuthUX:{emailConfirmed:()=>true},scrollTo(){},confirm:()=>true};
 new Function('window','globalThis',qr)(win,win);new Function('window','document','setTimeout','clearTimeout',source)(win,doc,()=>0,()=>{});
 const gd=win.GD,click=(action,id)=>handlers.click({preventDefault(){},target:{closest:()=>({dataset:{action,id}})}});
 click('help');check(app.innerHTML.includes('support-form')&&app.innerHTML.includes('Risposte rapide'),role+' help and request form');
 click('support-refresh');check(app.innerHTML.includes('Nessuna richiesta inviata'),role+' empty ticket history');
 click('privacy-rights');check(app.innerHTML.includes('privacy-request-form'),role+' dedicated privacy rights');
 click('privacy');check(app.innerHTML.includes('VERSIONE PILOTA')&&app.innerHTML.includes('Garante'),role+' accurate pilot privacy');
 click('terms');check(app.innerHTML.includes('Regole di utilizzo')&&app.innerHTML.includes('non condizioni commerciali definitive'),role+' terms accessible');
 check(gd.client()===null,role+' no live writes in preview');
 }
 return passed;
}
module.exports=run;
if(require.main===module){const read=p=>fs.readFileSync(path.join(__dirname,'..',p),'utf8');for(const row of run(read('official.js'),read('qr-core.js')))console.log('PASS '+row);}
