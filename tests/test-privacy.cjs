'use strict';
const assert=require('node:assert/strict');
const vm=require('node:vm');
const fs=require('node:fs');
const path=require('node:path');
const read=x=>fs.readFileSync(path.join(__dirname,'..',x),'utf8');

const sql=read('database/gooddiner_privacy_requests.sql');
assert.match(sql,/alter table public\\.privacy_requests enable row level security/);
assert.match(sql,/revoke all on public\\.privacy_requests from public,anon,authenticated/);
assert.match(sql,/using \\(requester_id=\\(select auth\\.uid\\(\\)\\)\\)/);
assert.match(sql,/grant insert \\(requester_id,request_kind,details\\)/,'no client grant for status changes');
assert.match(sql,/current_user <> 'postgres'/,'private resolutions are administrator-only');
assert.match(sql,/revoke all on function gd_private\\.close_privacy_request/);

async function exercise(){
 const exportCode=read('client-export.js');
 const exportedWindow={};
 vm.runInNewContext(exportCode,{window:exportedWindow});
 const clientData=exportedWindow.GoodDinerDataExport;
 const user={id:'customer-1',email:'client@example.test',is_anonymous:false};
 const requested=[],pages=[];
 const sb={
  auth:{getUser:async()=>({data:{user},error:null})},
  from(table){
    let ownField=null,ownId=null;
    return {
      select(){return this;},eq(field,value){ownField=field;ownId=value;return this;},order(){return this;},
      async single(){return {data:{id:user.id,nickname:'Cliente',customer_code:'GD-OWN'},error:null};},
      async range(start,end){
        requested.push({table,ownField,ownId,start,end});
        if(ownId!==user.id)throw Error('Export not restricted to authenticated user');
        if(table!=='visits')return {data:[],error:null};
        const result=Array.from({length:501},(_,i)=>({id:'visit-'+i,customer_id:user.id})).slice(start,end+1);
        pages.push(result.length);
        return {data:result,error:null};
      }
    };
  }
 };
 const data=await clientData.collect(sb,user);
 assert.equal(data.visits.length,501,'all personal rows beyond 250 are exported');
 assert.deepEqual(pages,[500,1]);
 assert.equal(data.account.email,'client@example.test');
 assert.equal(requested.length,6,'two visits pages plus four additional personal tables');
 assert.ok(requested.every(item=>item.ownId===user.id));
 assert.equal(requested.find(item=>item.table==='privacy_requests').ownField,'requester_id');
 assert.ok(!JSON.stringify(data).includes('access_token'));
 await assert.rejects(clientData.collect({auth:{getUser:async()=>({data:{user:{id:'another'}}})}},user),/Sessione non valida/);

 const events={},app={innerHTML:'',classList:{toggle(){}}},toast={};
 const privacyRows=[];
 let insertCount=0;
 const context={
   sdk:{createClient:()=>({
     auth:{onAuthStateChange(){},getUser:async()=>({data:{user},error:null})},
     from(table){
       return {
        select(){return this;},eq(){return this;},order(){return this;},limit(){return this;},
        get data(){return table==='privacy_requests'?privacyRows:[];},get error(){return null;},
        single(){return {data:{id:user.id,nickname:'Cliente',customer_code:'GD-OWN'},error:null};},
        insert(payload){insertCount++;if(table==='privacy_requests')privacyRows.push({id:'req-1',...payload,status:'received',created_at:'2026-11-21T15:00:00Z'});return Promise.resolve({error:null});}
       };
     }
   })},
   window:{GOODDINER_PUBLIC_CONFIG:{supabaseUrl:'https://ixczkhmvbjszgmlqznlk.supabase.co',supabasePublishableKey:'sb_publishable_test'},scrollTo(){}},
   document:{getElementById:id=>id==='app'?app:id==='toast'?toast:null,addEventListener:(event,fn)=>events[event]=fn},
   sessionStorage:{getItem(){return null;}},setTimeout(){},clearTimeout(){}
 };
 vm.runInNewContext(read('official.js').replace(/import\('https:\/\/cdn\.jsdelivr\.net\/npm\/@supabase[^']+'\)/,'Promise.resolve(globalThis.sdk)'),context);
 const gd=context.window.GD;
 gd.state.section='profile';gd.state.view='app';gd.render();
 assert.match(app.innerHTML,/id="privacy-request-form"/);
 assert.match(app.innerHTML,/data-action="export-data"/);
 const send=(kind,details)=>events.submit({preventDefault(){},target:{id:'privacy-request-form',elements:{kind:{value:kind},details:{value:details}}}});
 await send('erasure','Desidero la valutazione della cancellazione del mio account.');
 assert.equal(insertCount,1);
 assert.equal(privacyRows[0].requester_id,user.id);
 assert.equal(privacyRows[0].request_kind,'erasure');
 assert.match(app.innerHTML,/Ricevuta/);
 await send('erasure','Un secondo invio non deve duplicare la richiesta.');
 assert.equal(insertCount,1,'same request cannot be sent twice while pending');
 assert.match(toast.textContent,/già una richiesta/);
 privacyRows[0].status='resolved';
 gd.state.privacyRequests=[...privacyRows];gd.render();
 assert.match(app.innerHTML,/Conclusa/);
 console.log('PASS: protected paginated personal export and privacy request submission/status');
}
exercise().catch(err=>{console.error(err);process.exitCode=1;});
