alter table gd_private.stripe_test_runs add column plan_code text not null default 'monthly' check(plan_code in ('monthly','annual')),add column trial_requested boolean not null default false,add column trial_end timestamptz;
create or replace function gd_private.billing_pilot(p_action text,p_payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); venue uuid:=nullif(p_payload->>'restaurant_id','')::uuid; r gd_private.stripe_test_runs%rowtype; rid uuid;
begin
 if actor is null or not gd_private.current_user_email_confirmed() or not exists(select 1 from gd_studio_private.operators where user_id=actor) then raise exception 'BILLING_PILOT_FORBIDDEN';end if;
 if not exists(select 1 from public.restaurants where id=venue and owner_id=actor and verified_at is not null and suspended_at is null) then raise exception 'BILLING_PILOT_FORBIDDEN';end if;
 if p_action='list' then
 return (select coalesce(jsonb_agg(to_jsonb(q) order by q.created_at desc),'[]'::jsonb) from (select id,created_at,subscription_status,payment_status,period_end,last_sync,plan_code,trial_requested,trial_end,cancel_at_period_end, ((subscription_status='active' and payment_status='paid' and coalesce(period_end>now(),false)) or (subscription_status='trialing' and coalesce(trial_end>now(),false))) as test_access, (subscription_id is not null) as has_subscription, (subscription_status in ('active','trialing','past_due','unpaid','paused','incomplete') or (subscription_status='not_started' and created_at>now()-interval '35 minutes')) as blocks_checkout from gd_private.stripe_test_runs where operator_id=actor and restaurant_id=venue order by created_at desc limit 30) q);
 elsif p_action='prepare' then
 perform 1 from public.restaurants where id=venue and owner_id=actor and verified_at is not null and suspended_at is null for update;
 if not found then raise exception 'BILLING_PILOT_FORBIDDEN';end if;
 if exists(select 1 from gd_private.stripe_test_runs where operator_id=actor and restaurant_id=venue and (subscription_status in ('active','trialing','past_due','unpaid','paused','incomplete') or (subscription_status='not_started' and created_at>now()-interval '35 minutes'))) then raise exception 'BILLING_PILOT_ALREADY_OPEN';end if;
 if (select count(*) from gd_private.stripe_test_runs where operator_id=actor and created_at>now()-interval '1 hour')>=5 then raise exception 'BILLING_TEST_LIMIT';end if;
 perform 1 from auth.users where id=actor for update;
 if coalesce(p_payload->>'plan','monthly') not in ('monthly','annual') or coalesce(p_payload->>'trial_days','0') not in ('0','14') then raise exception 'BILLING_TEST_INVALID';end if;
 if coalesce(p_payload->>'trial_days','0')='14' and exists(select 1 from gd_private.stripe_test_runs where operator_id=actor and restaurant_id=venue and trial_requested and (subscription_id is not null or created_at>now()-interval '35 minutes')) then raise exception 'BILLING_TRIAL_USED';end if;
 insert into gd_private.stripe_test_runs(operator_id,restaurant_id,plan_code,trial_requested) values(actor,venue,coalesce(p_payload->>'plan','monthly'),coalesce(p_payload->>'trial_days','0')='14') returning id into rid;return jsonb_build_object('id',rid);
 elsif p_action='get' then
 select * into r from gd_private.stripe_test_runs where id=(p_payload->>'id')::uuid and operator_id=actor and restaurant_id=venue;
 if not found then raise exception 'BILLING_PILOT_FORBIDDEN';end if;
 return jsonb_build_object('id',r.id,'checkout_id',r.checkout_id,'subscription_id',r.subscription_id,'customer_id',r.customer_id,'subscription_status',r.subscription_status,'plan_code',r.plan_code,'trial_requested',r.trial_requested);
 else raise exception 'BILLING_TEST_INVALID';end if;
end $$;
revoke all on function gd_private.billing_pilot(text,jsonb) from public,anon,authenticated;
grant execute on function gd_private.billing_pilot(text,jsonb) to authenticated;
create or replace function public.gooddiner_billing_pilot(p_action text,p_payload jsonb default '{}'::jsonb) returns jsonb language sql security invoker set search_path='' as $$select gd_private.billing_pilot(p_action,p_payload)$$;
revoke all on function public.gooddiner_billing_pilot(text,jsonb) from public,anon,authenticated;
grant execute on function public.gooddiner_billing_pilot(text,jsonb) to authenticated;

create or replace function gd_private.billing_lab(p_action text,p_payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid();rid uuid;venue uuid;r gd_private.stripe_test_runs%rowtype;
begin
 if actor is null or not gd_private.current_user_email_confirmed() or not exists(select 1 from gd_studio_private.operators where user_id=actor) then raise exception 'STUDIO_ACCESS_DENIED';end if;
 if p_action='prepare' then
  venue:=null;
  if venue is not null and not exists(select 1 from public.restaurants where id=venue and owner_id=actor and verified_at is not null and suspended_at is null) then raise exception 'BILLING_TEST_FORBIDDEN';end if;
  if (select count(*) from gd_private.stripe_test_runs where operator_id=actor and created_at>now()-interval '1 hour')>=5 then raise exception 'BILLING_TEST_LIMIT';end if;
  perform 1 from auth.users where id=actor for update;
 if coalesce(p_payload->>'plan','monthly') not in ('monthly','annual') or coalesce(p_payload->>'trial_days','0') not in ('0','14') then raise exception 'BILLING_TEST_INVALID';end if;
 if coalesce(p_payload->>'trial_days','0')='14' and exists(select 1 from gd_private.stripe_test_runs where operator_id=actor and restaurant_id is null and trial_requested and (subscription_id is not null or created_at>now()-interval '35 minutes')) then raise exception 'BILLING_TRIAL_USED';end if;
 insert into gd_private.stripe_test_runs(operator_id,restaurant_id,plan_code,trial_requested) values(actor,venue,coalesce(p_payload->>'plan','monthly'),coalesce(p_payload->>'trial_days','0')='14') returning id into rid;
  return jsonb_build_object('id',rid);
 elsif p_action='list' then
  return (select coalesce(jsonb_agg(to_jsonb(q) order by q.created_at desc),'[]'::jsonb) from (select id,restaurant_id,created_at,checkout_id,subscription_id,subscription_status,payment_status,period_end,last_sync,plan_code,trial_requested,trial_end,cancel_at_period_end from gd_private.stripe_test_runs where operator_id=actor order by created_at desc limit 30) q);
 elsif p_action='get' then
  select * into r from gd_private.stripe_test_runs where id=(p_payload->>'id')::uuid and operator_id=actor;
  if not found then raise exception 'BILLING_TEST_FORBIDDEN';end if;
  return jsonb_build_object('id',r.id,'checkout_id',r.checkout_id,'subscription_id',r.subscription_id,'customer_id',r.customer_id,'subscription_status',r.subscription_status,'plan_code',r.plan_code,'trial_requested',r.trial_requested);
 else raise exception 'BILLING_TEST_INVALID';end if;
end $$;
revoke all on function gd_private.billing_lab(text,jsonb) from public,anon,authenticated;
grant execute on function gd_private.billing_lab(text,jsonb) to authenticated;
create or replace function public.gooddiner_billing_lab(p_action text,p_payload jsonb default '{}'::jsonb) returns jsonb language sql security invoker set search_path='' as $$select gd_private.billing_lab(p_action,p_payload)$$;
revoke all on function public.gooddiner_billing_lab(text,jsonb) from public,anon,authenticated;
grant execute on function public.gooddiner_billing_lab(text,jsonb) to authenticated;

create or replace function public.gooddiner_billing_lab_record(p jsonb) returns boolean language plpgsql security definer set search_path='' as $$
declare r gd_private.stripe_test_runs%rowtype;rid uuid:=(p->>'run_id')::uuid;eid text:=nullif(p->>'event_id','');ec bigint:=coalesce((p->>'event_created')::bigint,0);sid text:=nullif(p->>'checkout_id','');sub text:=nullif(p->>'subscription_id','');cust text:=nullif(p->>'customer_id','');ss text:=nullif(p->>'subscription_status','');ps text:=nullif(p->>'payment_status','');
begin
 if p->>'livemode' is distinct from 'false' then raise exception 'BILLING_TEST_ONLY';end if;
 select * into r from gd_private.stripe_test_runs where id=rid for update;
 if not found then return false;end if;
 if p->>'plan_code' is not null and p->>'plan_code'<>r.plan_code then raise exception 'BILLING_TEST_MISMATCH';end if;
 if (sid is not null and (sid not like 'cs_test_%' or (r.checkout_id is not null and r.checkout_id<>sid))) or (sub is not null and (sub not like 'sub_%' or (r.subscription_id is not null and r.subscription_id<>sub))) or (cust is not null and (cust not like 'cus_%' or (r.customer_id is not null and r.customer_id<>cust))) then raise exception 'BILLING_TEST_MISMATCH';end if;
 if eid is not null then
  insert into gd_private.stripe_test_events(event_id,run_id,event_type,event_created) values(eid,rid,p->>'event_type',ec) on conflict do nothing;
  if not found then return true;end if;
 end if;
 update gd_private.stripe_test_runs set checkout_id=coalesce(sid,checkout_id),subscription_id=coalesce(sub,subscription_id),customer_id=coalesce(cust,customer_id) where id=rid;
 if ec>=r.last_event_created then
  update gd_private.stripe_test_runs set subscription_status=coalesce(ss,subscription_status),payment_status=coalesce(ps,payment_status),period_end=coalesce((p->>'period_end')::timestamptz,period_end),last_sync=now(),last_event_created=ec,cancel_at_period_end=coalesce((p->>'cancel_at_period_end')::boolean,cancel_at_period_end),trial_end=case when p ? 'trial_end' and p->>'subscription_status' is not null then (p->>'trial_end')::timestamptz else trial_end end where id=rid;
 end if;
 return true;
end $$;
revoke all on function public.gooddiner_billing_lab_record(jsonb) from public,anon,authenticated;
grant execute on function public.gooddiner_billing_lab_record(jsonb) to service_role;
create or replace function gd_private.billing_finance(p_days integer default 30) returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); since timestamptz;
begin
 if actor is null or not gd_private.current_user_email_confirmed() or not exists(select 1 from gd_studio_private.operators where user_id=actor) then raise exception 'STUDIO_ACCESS_DENIED';end if;
 if p_days is null or p_days not in (7,30,90,365) then raise exception 'BILLING_TEST_INVALID';end if;
 since:=now()-make_interval(days=>p_days);
 return jsonb_build_object('environment','sandbox','generated_at',now(),'days',p_days,'stats',(select jsonb_build_object(
 'active',count(*) filter(where subscription_status='active'),'trialing',count(*) filter(where subscription_status='trialing'),
 'paid_active',count(*) filter(where subscription_status='active' and payment_status='paid' and period_end>now()),
 'mrr_nominal_cents',coalesce(round(sum(case when plan_code='annual' then 29900::numeric/12 else 2990 end) filter(where subscription_status='active' and payment_status='paid' and period_end>now())),0),
 'past_due',count(*) filter(where subscription_status in ('past_due','unpaid','incomplete')),
 'cancel_scheduled',count(*) filter(where cancel_at_period_end and subscription_status in ('active','trialing','past_due')),
 'cancelled',count(*) filter(where subscription_status='canceled'),
 'renewals_30d',count(*) filter(where subscription_status='active' and not cancel_at_period_end and period_end>now() and period_end<=now()+interval '30 days'),
 'total',count(*),'last_sync',max(last_sync)) from gd_private.stripe_test_runs),
 'invoices',(select jsonb_build_object('paid_cents',coalesce(sum(amount_paid) filter(where status='paid' and paid_at>=since),0),'paid_count',count(*) filter(where status='paid' and paid_at>=since),'open_cents',coalesce(sum(amount_remaining) filter(where status in ('open','uncollectible')),0),'open_count',count(*) filter(where status in ('open','uncollectible'))) from gd_private.stripe_test_invoices),
 'history',(select coalesce(jsonb_agg(to_jsonb(q) order by q.issued_at desc),'[]'::jsonb) from (select i.invoice_id,i.status,i.amount_paid,i.amount_due,i.amount_remaining,i.issued_at,i.paid_at,i.billing_reason,coalesce(r.name,'Laboratorio Studio') as label from gd_private.stripe_test_invoices i join gd_private.stripe_test_runs b on b.id=i.run_id left join public.restaurants r on r.id=b.restaurant_id where i.issued_at>=since or i.paid_at>=since order by i.issued_at desc limit 100) q),
 'subscriptions',(select coalesce(jsonb_agg(to_jsonb(q) order by q.created_at desc),'[]'::jsonb) from (select b.id,coalesce(r.name,'Laboratorio Studio') as label,b.created_at,b.subscription_status,b.payment_status,b.period_end,b.cancel_at_period_end,b.last_sync,b.plan_code,b.trial_end from gd_private.stripe_test_runs b left join public.restaurants r on r.id=b.restaurant_id order by b.created_at desc limit 100) q));
end $$;
revoke all on function gd_private.billing_finance(integer) from public,anon,authenticated;
grant execute on function gd_private.billing_finance(integer) to authenticated;
create or replace function public.gooddiner_billing_finance(p_days integer default 30) returns jsonb language sql security invoker set search_path='' as $$select gd_private.billing_finance(p_days)$$;
revoke all on function public.gooddiner_billing_finance(integer) from public,anon,authenticated;
grant execute on function public.gooddiner_billing_finance(integer) to authenticated;