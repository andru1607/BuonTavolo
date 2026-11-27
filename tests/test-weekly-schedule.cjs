'use strict';
const fs=require('node:fs'),path=require('node:path');
function run(source){
 const anchor="return {init,render,state,client:()=>sb,setView,resetScanner,version:'1.0'};";
 if(!source.includes(anchor))throw Error('Controller export changed');
 const h=source.replace(anchor,"return {init,render,state,client:()=>sb,setView,resetScanner,version:'1.0',copyScheduleWeek,syncScheduleDay,scheduleWindows,scheduleForm,bookingVisibilityNotice,bookingCatalogRows};").replace(/GD\.init\(\);\s*$/,'');
 const app={innerHTML:'',classList:{toggle(){}}},doc={getElementById:id=>id==='app'?app:null,addEventListener(){}};
 const win={location:{search:'',origin:'https://buontavolo.vercel.app'},GOODDINER_PUBLIC_CONFIG:{},GoodDinerAuthUX:{emailConfirmed:()=>true},confirm:()=>true,scrollTo(){}};
 new Function('window','document','setTimeout','clearTimeout',h)(win,doc,()=>0,()=>{});
 const g=win.GD,s=g.state,passed=[],check=(ok,msg)=>{if(!ok)throw Error(msg);passed.push(msg)};
 const elements={},btn={disabled:false};for(let i=0;i<7;i++){elements['closed-'+i]={checked:false};for(let j=0;j<2;j++)for(const k of ['from','to'])elements[k+'-'+i+'-'+j]={value:'',disabled:false};}
 const form={elements,querySelector:()=>btn};elements['closed-1'].checked=true;elements['from-0-0'].value='11:30';elements['to-0-0'].value='14:30';elements['from-0-1'].value='18:00';elements['to-0-1'].value='22:00';
 g.syncScheduleDay(form,1);check(elements['from-1-0'].disabled&&btn.disabled,'Closed day controls disabled');
 check(g.copyScheduleWeek(form,0),'Copy accepted');check(elements['from-6-0'].value==='11:30'&&elements['to-6-1'].value==='22:00','Both shifts copied');check(!elements['from-1-0'].value,'Tuesday excluded');check(g.scheduleWindows(form).length===12&&g.scheduleWindows(form).every(w=>w.day!==2),'Save excludes closed day');
 elements['closed-1'].checked=false;g.syncScheduleDay(form,1);check(!elements['from-1-0'].disabled&&!btn.disabled,'Reopen editable');
 win.confirm=()=>false;elements['from-2-0'].value='12:00';check(!g.copyScheduleWeek(form,0)&&elements['from-2-0'].value==='12:00','Cancel preserves edits');
 win.confirm=()=>true;elements['to-0-1'].value='';let rejected=false;try{g.copyScheduleWeek(form,0)}catch{rejected=true}check(rejected,'Incomplete source rejected');
 s.bookingSchedule={capacity:8,duration:90,windows:[{day:1,from:'11:30',to:'14:30'}],overrides:[]};check(g.scheduleForm().includes('Applica a tutta settimana')&&g.scheduleForm().includes('name="closed-1" checked'),'Persisted closures rendered');
 Object.assign(s,{user:{id:'m1'},restaurants:[{id:'v1',owner_id:'m1',verified_at:'2026-01-01'}],merchantLicense:{is_usable:true},bookingSettings:{enabled:true},bookingSchedule:{capacity:0,windows:[]}});
 check(g.bookingVisibilityNotice().includes('Configurazione incompleta'),'Merchant sees actual catalog prerequisite');
 s.bookingCatalogUnavailable=true;check(g.bookingCatalogRows('cantina').includes('Impossibile caricare'),'Failed catalog not mistaken for missing restaurant');
 s.bookingCatalogUnavailable=false;s.bookingCatalog=[{id:'v1',name:'Osteria La Cantina',city:'Torri del Benaco'}];check(g.bookingCatalogRows('cantina torri').includes('Osteria La Cantina'),'Search matches terms across fields');
 return passed;
}
module.exports=run;
if(require.main===module)for(const r of run(fs.readFileSync(path.join(__dirname,'..','official.js'),'utf8')))console.log('PASS '+r);
