create schema if not exists gd_studio_private;
revoke all on schema gd_studio_private from public,anon,authenticated;
grant usage on schema gd_studio_private to authenticated;
create table if not exists gd_studio_private.operators (
 user_id uuid primary key references auth.users(id) on delete cascade,
 created_at timestamptz not null default now()
);
alter table gd_studio_private.operators enable row level security;
revoke all on gd_studio_private.operators from public,anon,authenticated;
create table if not exists gd_studio_private.audit (
 id bigint generated always as identity primary key, actor uuid not null,
 action text not null, target text, created_at timestamptz not null default now()
);
alter table gd_studio_private.audit enable row level security;
revoke all on gd_studio_private.audit from public,anon,authenticated;
create or replace function gd_studio_private.run(p_action text,p_payload jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
 actor uuid := auth.uid();
 label text;
 target uuid;
 note text;
 code text;
 hours integer;
 decision boolean;
 outdata jsonb;
begin
 if actor is null or not exists(select 1 from gd_studio_private.operators o join auth.users u on u.id=o.user_id where o.user_id=actor and u.email_confirmed_at is not null and not coalesce(u.is_anonymous,false)) then
  raise exception 'STUDIO_ACCESS_DENIED' using errcode='42501';
 end if;
 label := 'Studio:'||actor::text;
 if p_action='dashboard' then
  return jsonb_build_object(
   'stats',jsonb_build_object('customers',(select count(*) from public.profiles where role='customer'),'merchants',(select count(*) from public.profiles where role='merchant'),'restaurants',(select count(*) from public.restaurants),'pending',(select count(*) from public.merchant_applications where status='pending'),'visits',(select count(*) from public.visits),'reviews',(select count(*) from public.reviews),'disputes',(select count(*) from public.disputes where status='pending'),'privacy',(select count(*) from public.privacy_requests where status in ('received','in_review')),'invites',(select count(*) from gd_private.signup_invites where purpose='merchant' and used_at is null and expires_at>now()),'new7',(select count(*) from public.profiles where created_at>=now()-interval '7 days')),
   'trend',(select coalesce(jsonb_agg(jsonb_build_object('day',d::date,'accounts',(select count(*) from public.profiles where created_at>=d and created_at<d+interval '1 day'),'visits',(select count(*) from public.visits where checked_in_at>=d and checked_in_at<d+interval '1 day')) order by d),'[]'::jsonb) from generate_series(date_trunc('day',now())-interval '13 days',date_trunc('day',now()),interval '1 day') d),
   'applications',(select coalesce(jsonb_agg(to_jsonb(q)),'[]'::jsonb) from (select a.id,a.restaurant_name,a.city,a.status,a.created_at,a.reviewed_at,(u.email_confirmed_at is not null) as email_verified from public.merchant_applications a join auth.users u on u.id=a.applicant_id order by (a.status='pending') desc,a.created_at desc limit 200) q),
   'invites',(select coalesce(jsonb_agg(to_jsonb(q)),'[]'::jsonb) from (select id,created_at,expires_at,used_at,case when used_at is not null then 'used' when expires_at<=now() then 'expired' else 'active' end status from gd_private.signup_invites where purpose='merchant' order by created_at desc limit 200) q),
   'restaurants',(select coalesce(jsonb_agg(to_jsonb(q)),'[]'::jsonb) from (select r.id,r.name,r.city,r.verified_at,r.suspended_at,l.status as license_status,l.active_until from public.restaurants r left join gd_private.merchant_licenses l on l.restaurant_id=r.id order by r.created_at desc limit 200) q),
   'disputes',(select coalesce(jsonb_agg(to_jsonb(q)),'[]'::jsonb) from (select id,review_id,reason,status,created_at from public.disputes order by (status='pending') desc,created_at desc limit 100) q),
   'privacy',(select coalesce(jsonb_agg(to_jsonb(q)),'[]'::jsonb) from (select id,request_kind,status,created_at from public.privacy_requests order by (status in ('received','in_review')) desc,created_at desc limit 100) q),
   'leads',(select coalesce(jsonb_agg(to_jsonb(q)),'[]'::jsonb) from (select id,restaurant_name,city,status,created_at,contact_requested from public.business_pilot_leads order by created_at desc limit 100) q),
   'audit',(select coalesce(jsonb_agg(to_jsonb(q)),'[]'::jsonb) from (select a.action,a.target,a.created_at from gd_studio_private.audit a order by a.id desc limit 100) q)
  );
 elsif p_action='invite_create' then
  hours := coalesce((p_payload->>'hours')::integer,168);
  code:=gd_private.create_signup_invite('merchant',label,hours);
  insert into gd_studio_private.audit(actor,action) values(actor,p_action);
  return jsonb_build_object('code',code);
 elsif p_action='invite_revoke' then
  target:=(p_payload->>'id')::uuid;
  update gd_private.signup_invites set expires_at=greatest(created_at+interval '1 microsecond',now()) where id=target and purpose='merchant' and used_at is null and expires_at>now();
  if not found then raise exception 'INVITO_NON_ATTIVO'; end if;
 elsif p_action in ('application_decide','dispute_decide','privacy_close','license_set') then
  target:=(p_payload->>'id')::uuid;
  note:=btrim(p_payload->>'note');
  if note is null or char_length(note) not between 10 and 500 then raise exception 'MOTIVAZIONE_OBBLIGATORIA'; end if;
  if p_action='license_set' then
   perform gd_private.set_merchant_license(target,p_payload->>'status',(p_payload->>'until')::timestamptz,label,note);
  else
   decision:=(p_payload->>'decision')::boolean;
   if decision is null then raise exception 'DECISIONE_OBBLIGATORIA'; end if;
   if p_action='application_decide' then perform gd_private.review_merchant_application(target,decision,label,note);
   elsif p_action='dispute_decide' then perform gd_private.resolve_guest_dispute(target,decision,label,note);
   else perform gd_private.close_privacy_request(target,decision,label,note); end if;
  end if;
 else raise exception 'STUDIO_ACTION_INVALID';
 end if;
 insert into gd_studio_private.audit(actor,action,target) values(actor,p_action,target::text);
 return jsonb_build_object('ok',true);
end $$;
revoke all on function gd_studio_private.run(text,jsonb) from public,anon,authenticated;
grant execute on function gd_studio_private.run(text,jsonb) to authenticated;
create or replace function public.gooddiner_studio(p_action text,p_payload jsonb default '{}'::jsonb)
returns jsonb language sql security invoker set search_path='' as $$ select gd_studio_private.run(p_action,p_payload) $$;
revoke all on function public.gooddiner_studio(text,jsonb) from public,anon,authenticated;
grant execute on function public.gooddiner_studio(text,jsonb) to authenticated;