'use strict';
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const root=path.resolve(__dirname,'..');
const sql=fs.readFileSync(path.join(root,'database/gooddiner_operator_moderation.sql'),'utf8');
const guide=fs.readFileSync(path.join(root,'docs/operator-moderation.md'),'utf8');
assert.match(sql,/create table if not exists gd_private\.operator_audit/);
assert.match(sql,/alter table gd_private\.operator_audit enable row level security/);
assert.match(sql,/revoke all on gd_private\.operator_audit from public, anon, authenticated/);
assert.equal((sql.match(/current_user <> 'postgres'/g)||[]).length,2,'both actions require private SQL owner');
for(const name of ['review_merchant_application','resolve_guest_dispute']){
 assert.ok(sql.includes('gd_private.'+name),'operator routines stay in the private schema');
 const matches=sql.match(new RegExp('revoke all on function gd_private\\.'+name+'\\(uuid,boolean,text,text\\)[\\s\\S]*?from public, anon, authenticated'));
 assert.ok(matches,'public, anonymous and authenticated EXECUTE must be revoked for '+name);
}
assert.match(sql,/email_confirmed_at is not null/,'approval requires confirmed staff email');
assert.match(sql,/public\.restaurants\(owner_id,application_id,name,city,verified_at\)/,'approval creates a verified restaurant only server-side');
assert.match(sql,/update public\.reviews set status='removed'/,'accepted disputes remove the review');
assert.match(sql,/v\.status in \('pending','available'\)/,'unredeemed vouchers are reconciled');
assert.match(guide,/verifica.*umana/i);
assert.match(guide,/non.*autorizzano il lancio pubblico/i);
console.log('PASS: restricted SQL-editor moderation, audit trail, review removal and reward reconciliation');
