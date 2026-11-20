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
}
testRecovery().catch(err => { console.error(err.message.slice(0,160)); process.exitCode = 1; });
