-- Stripe Sandbox lab; no production license mutations.
create table gd_private.stripe_test_runs(
 id uuid primary key default gen_random_uuid(), operator_id uuid not null references auth.users(id) on delete cascade,
 restaurant_id uuid references public.restaurants(id) on delete set null,created_at timestamptz not null default now(),
 checkout_id text unique check(checkout_id is null or checkout_id like 'cs_test_%'), subscription_id text unique,
 customer_id text, subscription_status text not null default 'not_started',payment_status text not null default 'unpaid',
 period_end timestamptz, last_sync timestamptz,last_event_created bigint not null default 0
);
alter table gd_private.stripe_test_runs enable row level security;
revoke all on gd_private.stripe_test_runs from public,anon,authenticated;
create table gd_private.stripe_test_events(event_id text primary key,run_id uuid not null references gd_private.stripe_test_runs(id) on delete cascade,event_type text not null,event_created bigint not null,received_at timestamptz not null default now());
alter table gd_private.stripe_test_events enable row level security;
revoke all on gd_private.stripe_test_events from public,anon,authenticated;
create or replace function gd_private.billing_lab(p_action text,p_payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid();rid uuid;venue uuid;r gd_private.stripe_test_runs%rowtype;
begin
 if actor is null or not gd_private.current_user_email_confirmed() or not exists(select 1 from gd_studio_private.operators where user_id=actor) then raise exception 'STUDIO_ACCESS_DENIED';end if;
 if p_action='prepare' then
  venue:=nullif(p_payload->>'restaurant_id','')::uuid;
  if venue is not null and not exists(select 1 from public.restaurants where id=venue and owner_id=actor and verified_at is not null and suspended_at is null) then raise exception 'BILLING_TEST_FORBIDDEN';end if;
  if (select count(*) from gd_private.stripe_test_runs where operator_id=actor and created_at>now()-interval '1 hour')>=5 then raise exception 'BILLING_TEST_LIMIT';end if;
  insert into gd_private.stripe_test_runs(operator_id,restaurant_id) values(actor,venue) returning id into rid;
  return jsonb_build_object('id',rid);
 elsif p_action='list' then
  return (select coalesce(jsonb_agg(to_jsonb(q) order by q.created_at desc),'[]'::jsonb) from (select id,restaurant_id,created_at,checkout_id,subscription_id,subscription_status,payment_status,period_end,last_sync from gd_private.stripe_test_runs where operator_id=actor order by created_at desc limit 30) q);
 elsif p_action='get' then
  select * into r from gd_private.stripe_test_runs where id=(p_payload->>'id')::uuid and operator_id=actor;
  if not found then raise exception 'BILLING_TEST_FORBIDDEN';end if;
  return jsonb_build_object('id',r.id,'checkout_id',r.checkout_id,'subscription_id',r.subscription_id,'customer_id',r.customer_id,'subscription_status',r.subscription_status);
 else raise exception 'BILLING_TEST_INVALID';end if;
end $$;
revoke all on function gd_private.billing_lab(text,jsonb) from public,anon,authenticated;
grant execute on function gd_private.billing_lab(text,jsonb) to authenticated;
create or replace function public.gooddiner_billing_lab(p_action text,p_payload jsonb default '{}'::jsonb) returns jsonb language sql security invoker set search_path='' as $$select gd_private.billing_lab(p_action,p_payload)$$;
revoke all on function public.gooddiner_billing_lab(text,jsonb) from public,anon,authenticated;
grant execute on function public.gooddiner_billing_lab(text,jsonb) to authenticated;
-- Server-only RPC. Accepts minimal verified Stripe snapshots, not card or invoice data.
create or replace function public.gooddiner_billing_lab_record(p jsonb) returns boolean language plpgsql security definer set search_path='' as $$
declare r gd_private.stripe_test_runs%rowtype;rid uuid:=(p->>'run_id')::uuid;eid text:=nullif(p->>'event_id','');ec bigint:=coalesce((p->>'event_created')::bigint,0);sid text:=nullif(p->>'checkout_id','');sub text:=nullif(p->>'subscription_id','');cust text:=nullif(p->>'customer_id','');ss text:=nullif(p->>'subscription_status','');ps text:=nullif(p->>'payment_status','');
begin
 if p->>'livemode' is distinct from 'false' then raise exception 'BILLING_TEST_ONLY';end if;
 select * into r from gd_private.stripe_test_runs where id=rid for update;
 if not found then return false;end if;
 if (sid is not null and (sid not like 'cs_test_%' or (r.checkout_id is not null and r.checkout_id<>sid))) or (sub is not null and (sub not like 'sub_%' or (r.subscription_id is not null and r.subscription_id<>sub))) or (cust is not null and (cust not like 'cus_%' or (r.customer_id is not null and r.customer_id<>cust))) then raise exception 'BILLING_TEST_MISMATCH';end if;
 if eid is not null then
  insert into gd_private.stripe_test_events(event_id,run_id,event_type,event_created) values(eid,rid,p->>'event_type',ec) on conflict do nothing;
  if not found then return true;end if;
 end if;
 update gd_private.stripe_test_runs set checkout_id=coalesce(sid,checkout_id),subscription_id=coalesce(sub,subscription_id),customer_id=coalesce(cust,customer_id) where id=rid;
 if ec>=r.last_event_created then
  update gd_private.stripe_test_runs set subscription_status=coalesce(ss,subscription_status),payment_status=coalesce(ps,payment_status),period_end=coalesce((p->>'period_end')::timestamptz,period_end),last_sync=now(),last_event_created=ec where id=rid;
 end if;
 return true;
end $$;
revoke all on function public.gooddiner_billing_lab_record(jsonb) from public,anon,authenticated;
grant execute on function public.gooddiner_billing_lab_record(jsonb) to service_role;