const fs=require('fs'),vm=require('vm'),crypto=require('crypto');
const html=fs.readFileSync(__dirname+'/../index.html','utf8');
const js=html.split('<script>')[1].split('</script>')[0];
const memory={};const app={innerHTML:'',classList:{add(){},remove(){}}};const toast={textContent:'',classList:{add(){},remove(){}}};
const ctx={console,crypto:crypto.webcrypto,localStorage:{getItem:k=>memory[k]||null,setItem:(k,v)=>memory[k]=v},document:{getElementById:k=>k==='app'?app:k==='toast'?toast:null,addEventListener:()=>{}},navigator:{},window:{scrollTo:()=>{}},setTimeout,clearTimeout,confirm:()=>true};
vm.createContext(ctx);vm.runInContext(js,ctx,{timeout:3000});
const run=s=>vm.runInContext(s,ctx,{timeout:3000});
const check=(x,msg)=>{if(!x)throw new Error(msg)};
check(run('stats("CL-10482").positive')===9,'9 positives seeded');
check(run('positive({status:"pubblicata",rating:7})')===false,'7 stars should not be positive');
check(run('positive({status:"pubblicata",rating:8})')===true,'8 stars should be positive');
check(run('positive({status:"pubblicata",rating:9})')===true,'9 stars should be positive');
check(run('positive({status:"pubblicata",rating:10})')===true,'10 stars should be positive');
check(run('positive({status:"contestata",rating:10})')===false,'contested should not be positive');
run('switchRole("restaurant")');run('changeTab("review")');run('state.wizard=2;render()');
check(app.innerHTML.includes('10 stelle'),'10-star rating label');
check((app.innerHTML.match(/data-action="rating"/g)||[]).length===10,'expected ten star buttons');
check(app.innerHTML.includes('8, 9 o 10'),'threshold explanation');
run('resetDraft("CL-10482");state.draft.confirmed=true;state.draft.text="Comportamento corretto, rispettoso e cortese durante tutta la visita.";state.draft.tags=["Cortesia"];state.draft.rating=7;state.wizard=3;doPublish()');
check(run('stats("CL-10482").positive')===9,'7 star review must not count');
check(run('db.vouchers.length')===0,'7 stars must not issue voucher');
run('resetDraft("CL-10482");state.draft.confirmed=true;state.draft.date=today(1);state.draft.text="Comportamento corretto, rispettoso e cortese durante tutta la visita.";state.draft.tags=["Cortesia"];state.draft.rating=8;state.wizard=3;doPublish()');
check(run('stats("CL-10482").positive')===10,'8-star review must count');
check(run('db.vouchers.length')===1,'8 stars should issue voucher at 10');
check(run('db.vouchers[0].status')==='disponibile','voucher should be available');
run('switchRole("customer");changeTab("rewards")');check(app.innerHTML.includes('BT-'),'voucher shown');
console.log('PASS: 1–10 scale, 7 not positive, 8/9/10 positive, voucher only at tenth positive, 10 clickable rating inputs');
// With ten positives only one reward is earned, even if the second ticket was redeemed first.
run(`db.vouchers = [
  {customerId:'CL-10482', code:'BT-FIRST', status:'disponibile'},
  {customerId:'CL-10482', code:'BT-SECOND', status:'riscattato'}
]; reconcileVouchers('CL-10482')`);
check(run("db.vouchers[0].status")==='sospeso','no second spend after a contestation');
check(run("db.vouchers[1].status")==='riscattato','redemption history preserved');
console.log('PASS: redeemed voucher deducted regardless of issue order');
