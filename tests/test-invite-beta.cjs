'use strict';
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const read=p=>fs.readFileSync(path.join(__dirname,'..',p),'utf8');
const gate=read('database/gooddiner_invite_only_beta.sql');
const test=read('database/gooddiner_invite_only_beta_test.sql');
const app=read('official.js');
const cfg=read('config.js');
for(const fragment of [
 'add column invite_only_enabled boolean not null default false',
 'create table gd_private.signup_invites',
 "purpose in ('customer','merchant')",
 'used_at timestamptz',
 'used_by uuid',
 'expires_at>now()',
 'returning i.id into matching_invite',
 'gd_invite_purpose',
 "'GOODDINER_INVITE_INVALID_OR_USED'",
 "'GOODDINER_INVITE_EMAIL_REQUIRED'",
 "new.raw_user_meta_data := coalesce",
 "- 'gd_invite' - 'gd_invite_purpose'",
 'pg_catalog.sha256',
 'create or replace function gd_private.enforce_registration_gate()',
 'revoke all on gd_private.signup_invites from public, anon, authenticated, supabase_auth_admin',
 "current_user <> 'postgres'"
])assert.ok(gate.includes(fragment),'missing backend invitation property: '+fragment);
assert.match(test,/FAIL: signup without invite accepted/);
assert.match(test,/FAIL: invitation replay accepted/);
assert.match(test,/FAIL: Auth user retains the one-time invitation secret/);
assert.match(test,/FAIL: test data persisted/);
assert.match(app,/registrationMode==='invite'/);
assert.doesNotMatch(app,/gd_invite:inviteCode,gd_invite_purpose:'customer'/);
assert.match(app,/data:\{nickname:nick\}/);
assert.match(app,/Nessun codice invito richiesto/);
assert.match(app,/gd_invite:inviteCode,gd_invite_purpose:'merchant'/);
assert.match(app,/name="inviteCode"/);
assert.match(app,/name="pilotAcknowledged"/);
assert.match(app,/captchaToken\(form,false\)/);
assert.match(app,/Conferma l.email/);
assert.match(cfg,/registrationEnabled:\s*true/);
assert.match(cfg,/registrationMode:\s*"invite"/);
assert.match(cfg,/turnstileSiteKey:\s*""/);
assert.ok(!cfg.includes('service_role')&&!cfg.includes('sk_live_'));
console.log('PASS: controlled beta signup with one-time server-checked email invitations and no client secrets');
