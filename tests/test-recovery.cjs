const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');

// Exercise the real form handler with a local Auth adapter.
async function testRecovery() {
  const events = {};
  const app = {innerHTML: '', classList: {toggle() {}}};
  const toast = {};
  const user = {id: 'demo'};
  let fail = true;
  const query = {
    select() { return this; }, eq() { return this; }, order() { return this; },
    limit() { return this; }, single() { return {data: {id: 'demo', nickname: 'Ospite'}}; }
  };
  const context = {
    sdk: {createClient: () => ({
      auth: {
        onAuthStateChange(fn) { fn('PASSWORD_RECOVERY'); },
        getUser: async () => ({data: {user}}),
        updateUser: async () => ({error: fail ? {message: 'Errore di prova'} : null})
      },
      from: () => query
    })},
    window: {GOODDINER_PUBLIC_CONFIG: {supabaseUrl: 'https://ixczkhmvbjszgmlqznlk.supabase.co', supabasePublishableKey: 'sb_publishable_test'}},
    document: {getElementById: id => id === 'app' ? app : id === 'toast' ? toast : null,
      addEventListener: (name, handler) => { events[name] = handler; }},
    sessionStorage: {getItem: () => null}, setTimeout() {}, clearTimeout() {}
  };
  const js = fs.readFileSync(path.join(__dirname, '../official.js'), 'utf8');
  await vm.runInNewContext(js.replace(/import\('https:\/\/cdn\.jsdelivr\.net\/npm\/@supabase[^']+'\)/, 'Promise.resolve(globalThis.sdk)'), context);
  const submit = () => events.submit({preventDefault() {}, target: {id: 'reset-form', elements: {password: {value: 'solo-prova-locale'}}}});
  assert.match(app.innerHTML, /id="reset-form"/);
  await submit();
  assert.match(app.innerHTML, /id="reset-form"/);
  assert.equal(toast.textContent, 'Errore di prova');
  fail = false;
  await submit();
  assert.doesNotMatch(app.innerHTML, /id="reset-form"/);
  assert.equal(context.window.GD.state.view, 'app');
  assert.equal(toast.textContent, 'Password aggiornata.');

  // Account upgrade: the anonymous guest can attach an email, then set a password
  // only once the email is confirmed. No live account or real data is created.
  const gd = context.window.GD;
  gd.state.profile = {id:'demo', nickname:'Ospite', customer_code:'GD-TEST'};
  gd.state.user = {id:'demo', is_anonymous:true};
  gd.state.view = 'app';
  gd.state.side = 'customer';
  gd.state.section = 'profile';
  gd.render();
  assert.match(app.innerHTML, /id="link-email-form"/);
  assert.doesNotMatch(app.innerHTML, /id="change-password-form"/);

  gd.state.user = {id:'demo', is_anonymous:false, email:'demo@example.test', email_confirmed_at:null};
  gd.render();
  assert.doesNotMatch(app.innerHTML, /id="change-password-form"/);
  assert.match(app.innerHTML, /Conferma l.indirizzo email/);

  gd.state.user.email_confirmed_at = '2026-11-21T12:00:00Z';
  gd.render();
  assert.match(app.innerHTML, /id="change-password-form"/);
  assert.match(app.innerHTML, /id="gd-confirm-password"/);
  let resetCalled = false;
  const setPassword=(password,confirmPassword)=>events.submit({
    preventDefault(){},
    target:{id:'change-password-form',elements:{password:{value:password},confirmPassword:{value:confirmPassword}},
      reset(){resetCalled=true;}}
  });
  await setPassword('password-abbastanza-lunga','diversa-password');
  assert.equal(toast.textContent,'Le password non coincidono.');
  assert.equal(resetCalled,false);
  await setPassword('password-abbastanza-lunga','password-abbastanza-lunga');
  assert.equal(toast.textContent,'Password salvata. Ora puoi accedere con email e password.');
  assert.equal(resetCalled,true);

  // Server-issued token must be readable and selectable without BarcodeDetector.
  gd.state.section = 'pass';
  gd.state.qr = {qr_token:'GD1:aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa', expires_at:new Date(Date.now()+90000).toISOString()};
  gd.render();
  assert.match(app.innerHTML, /id="qr-manual-token"/);
  assert.match(app.innerHTML, /GD1:aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa/);
  assert.match(app.innerHTML, /Mostra codice manuale/);
  // An expired capability must disappear from the rendered pass, including the fallback.
  gd.state.qr.expires_at=new Date(Date.now()-1000).toISOString();
  gd.render();
  assert.doesNotMatch(app.innerHTML,/id="qr-manual-token"/);

  // Same account can act as a merchant and a customer. Never combine the
  // merchant's guests with this account's own DinerPass history or reviews.
  gd.state.qr=null;
  gd.state.user={id:'demo',is_anonymous:false,email:'me@example.test',email_confirmed_at:'2026-11-21T12:00:00Z'};
  gd.state.restaurants=[
    {id:'venue-own-visit',name:'Trattoria Esperienza',owner_id:'someone-else'},
    {id:'venue-managed',name:'Locale Gestito',owner_id:'demo',verified_at:'2026-11-20T12:00:00Z'}
  ];
  gd.state.visits=[
    {id:'visit-other',customer_id:'other-guest',restaurant_id:'venue-managed',guest_nickname:'Ospite Esterno',guest_code:'GD-OTHER',checked_in_at:'2026-11-20T10:00:00Z',status:'confirmed'},
    {id:'visit-self',customer_id:'demo',restaurant_id:'venue-own-visit',guest_nickname:'Ospite',checked_in_at:'2026-11-21T10:00:00Z',status:'confirmed'}
  ];
  gd.state.reviews=[
    {id:'review-other',customer_id:'other-guest',visit_id:'visit-other',comment:'RECENSIONE DI UN ALTRO OSPITE',rating:1,status:'published',created_at:'2026-11-20T11:00:00Z'},
    {id:'review-self',customer_id:'demo',visit_id:'visit-self',comment:'Commento della mia visita',rating:9,status:'published',created_at:'2026-11-21T11:00:00Z'}
  ];
  gd.state.vouchers=[
    {id:'voucher-other',customer_id:'other-guest',milestone:20,status:'pending'},
    {id:'voucher-self',customer_id:'demo',milestone:10,status:'pending'}
  ];
  gd.state.side='customer';gd.state.section='pass';gd.render();
  assert.match(app.innerHTML,/Trattoria Esperienza/);
  assert.doesNotMatch(app.innerHTML,/Locale Gestito/);
  gd.state.section='visits';gd.render();
  assert.match(app.innerHTML,/Trattoria Esperienza/);
  assert.doesNotMatch(app.innerHTML,/Locale Gestito/);
  gd.state.section='reviews';gd.render();
  assert.match(app.innerHTML,/Commento della mia visita/);
  assert.doesNotMatch(app.innerHTML,/RECENSIONE DI UN ALTRO OSPITE/);
  assert.match(app.innerHTML,/Traguardo: 10 recensioni positive/);
  assert.doesNotMatch(app.innerHTML,/Traguardo: 20 recensioni positive/);
  // Merchant register remains available to this verified operator.
  gd.state.side='merchant';gd.state.section='visits';gd.render();
  assert.match(app.innerHTML,/Ospite Esterno/);



}
testRecovery().catch(err => { console.error(err.message.slice(0,160)); process.exitCode = 1; });
