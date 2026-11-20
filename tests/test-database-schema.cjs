const assert=require('node:assert/strict');
const fs=require('node:fs');
const sql=fs.readFileSync(require('node:path').resolve(__dirname,'../database/gooddiner_initial.sql'),'utf8');
const docs=fs.readFileSync(require('node:path').resolve(__dirname,'../database/README.md'),'utf8');
const tables=['profiles','merchant_applications','restaurants','visits','reviews','disputes','vouchers'];
for(const name of tables){
 assert.match(sql,new RegExp(`create table public\\.${name} \\(`,'i'),`Missing ${name}`);
 assert.match(sql,new RegExp(`alter table public\\.${name} enable row level security`,'i'),`RLS disabled ${name}`);
}
for(const name of ['visit_tokens','visit_audit']){
 assert.match(sql,new RegExp(`create table gd_private\\.${name} \\(`,'i'));
 assert.match(sql,new RegExp(`alter table gd_private\\.${name} enable row level security`,'i'));
}
for(const fn of ['issue_guest_qr','checkin_guest','void_guest_visit','publish_guest_review']){
 assert.match(sql,new RegExp(`create or replace function public\\.${fn}\\(`,'i'));
 assert.match(sql,new RegExp(`grant execute on function public\\.${fn}\\(`,'i'));
}
assert.match(sql,/new\.raw_user_meta_data->>'role'/i);
assert.match(sql,/no merchant self-promotion/i);
assert.match(sql,/p_rating>=8/);
assert.match(sql,/positive_count%10=0/);
assert.match(sql,/values\(visit_row\.customer_id,positive_count,'pending'\)/);
assert.match(sql,/verified_at is not null and r\.suspended_at is null/i);
assert.match(sql,/token_row\.consumed_at is not null or token_row\.expires_at<=now\(\)/i);
assert.match(sql,/for update/);
assert.match(sql,/gd_one_confirmed_visit_per_day/);
assert.match(sql,/auth\.uid\(\)/);
assert.match(sql,/set search_path = ''/);
assert.match(sql,/revoke all on function public\.publish_guest_review/);
assert.doesNotMatch(sql,/grant (insert|update|delete) on public\.visits to authenticated/i);
assert.doesNotMatch(sql,/grant (insert|update|delete) on public\.reviews to authenticated/i);
assert.doesNotMatch(sql,/grant (insert|update|delete) on public\.restaurants to authenticated/i);
assert.match(docs,/NON applicato a Supabase/);
assert.match(docs,/easygart/);
console.log('PASS: GoodDiner database baseline isolated, RLS, owner checks, short-lived QR, 8-10 stars, 10-review pending vouchers');