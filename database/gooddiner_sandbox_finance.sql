-- Finance dashboard for integrated GoodDiner Sandbox runs only.
create table gd_private.stripe_test_invoices(
 invoice_id text primary key check(invoice_id like 'in_%'),
 run_id uuid not null references gd_private.stripe_test_runs(id) on delete cascade,
 subscription_id text not null, status text not null check(status in ('draft','open','paid','uncollectible','void')),
 currency text not null check(currency='eur'), amount_paid bigint not null check(amount_paid>=0),
 amount_due bigint not null check(amount_due>=0), amount_remaining bigint not null check(amount_remaining>=0),
 issued_at timestamptz not null, paid_at timestamptz, billing_reason text,
 synced_at timestamptz not null default now()
);
alter table gd_private.stripe_test_invoices enable row level security;
revoke all on gd_private.stripe_test_invoices from public,anon,authenticated;
create index gd_stripe_test_invoices_run on gd_private.stripe_test_invoices(run_id);
create or replace function public.gooddiner_billing_invoice_record(p jsonb) returns boolean language plpgsql security definer set search_path='' as $$
declare r gd_private.stripe_test_runs%rowtype; iid text:=p->>'invoice_id'; sid text:=p->>'subscription_id';
begin
 if p->>'livemode' is distinct from 'false' or p->>'currency' is distinct from 'eur' then raise exception 'BILLING_TEST_ONLY';end if;
 select * into r from gd_private.stripe_test_runs where id=(p->>'run_id')::uuid and subscription_id=sid for update;
 if not found then return false;end if;
 insert into gd_private.stripe_test_invoices(invoice_id,run_id,subscription_id,status,currency,amount_paid,amount_due,amount_remaining,issued_at,paid_at,billing_reason)
 values(iid,r.id,sid,p->>'status',p->>'currency',(p->>'amount_paid')::bigint,(p->>'amount_due')::bigint,(p->>'amount_remaining')::bigint,to_timestamp((p->>'created')::bigint),case when p->>'paid_at' is not null then to_timestamp((p->>'paid_at')::bigint) end,p->>'billing_reason')
 on conflict(invoice_id) do update set status=excluded.status,amount_paid=excluded.amount_paid,amount_due=excluded.amount_due,amount_remaining=excluded.amount_remaining,paid_at=excluded.paid_at,billing_reason=excluded.billing_reason,synced_at=now()
 where gd_private.stripe_test_invoices.run_id=excluded.run_id and gd_private.stripe_test_invoices.subscription_id=excluded.subscription_id
 and (gd_private.stripe_test_invoices.status not in ('paid','void') or gd_private.stripe_test_invoices.status=excluded.status);
 return found;
end $$;
revoke all on function public.gooddiner_billing_invoice_record(jsonb) from public,anon,authenticated;
grant execute on function public.gooddiner_billing_invoice_record(jsonb) to service_role;
create or replace function gd_private.billing_finance(p_days integer default 30) returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); since timestamptz;
begin
 if actor is null or not gd_private.current_user_email_confirmed() or not exists(select 1 from gd_studio_private.operators where user_id=actor) then raise exception 'STUDIO_ACCESS_DENIED';end if;
 if p_days is null or p_days not in (7,30,90,365) then raise exception 'BILLING_TEST_INVALID';end if;
 since:=now()-make_interval(days=>p_days);
 return jsonb_build_object('environment','sandbox','generated_at',now(),'days',p_days,'stats',(select jsonb_build_object(
 'active',count(*) filter(where subscription_status='active'),
 'paid_active',count(*) filter(where subscription_status='active' and payment_status='paid' and period_end>now()),
 'mrr_nominal_cents',2990*count(*) filter(where subscription_status='active' and payment_status='paid' and period_end>now()),
 'past_due',count(*) filter(where subscription_status in ('past_due','unpaid','incomplete')),
 'cancel_scheduled',count(*) filter(where cancel_at_period_end and subscription_status in ('active','trialing','past_due')),
 'cancelled',count(*) filter(where subscription_status='canceled'),
 'renewals_30d',count(*) filter(where subscription_status='active' and not cancel_at_period_end and period_end>now() and period_end<=now()+interval '30 days'),
 'total',count(*),'last_sync',max(last_sync)) from gd_private.stripe_test_runs),
 'invoices',(select jsonb_build_object('paid_cents',coalesce(sum(amount_paid) filter(where status='paid' and paid_at>=since),0),'paid_count',count(*) filter(where status='paid' and paid_at>=since),'open_cents',coalesce(sum(amount_remaining) filter(where status in ('open','uncollectible')),0),'open_count',count(*) filter(where status in ('open','uncollectible'))) from gd_private.stripe_test_invoices),
 'history',(select coalesce(jsonb_agg(to_jsonb(q) order by q.issued_at desc),'[]'::jsonb) from (select i.invoice_id,i.status,i.amount_paid,i.amount_due,i.amount_remaining,i.issued_at,i.paid_at,i.billing_reason,coalesce(r.name,'Laboratorio Studio') as label from gd_private.stripe_test_invoices i join gd_private.stripe_test_runs b on b.id=i.run_id left join public.restaurants r on r.id=b.restaurant_id where i.issued_at>=since or i.paid_at>=since order by i.issued_at desc limit 100) q),
 'subscriptions',(select coalesce(jsonb_agg(to_jsonb(q) order by q.created_at desc),'[]'::jsonb) from (select b.id,coalesce(r.name,'Laboratorio Studio') as label,b.created_at,b.subscription_status,b.payment_status,b.period_end,b.cancel_at_period_end,b.last_sync from gd_private.stripe_test_runs b left join public.restaurants r on r.id=b.restaurant_id order by b.created_at desc limit 100) q));
end $$;
revoke all on function gd_private.billing_finance(integer) from public,anon,authenticated;
grant execute on function gd_private.billing_finance(integer) to authenticated;
create or replace function public.gooddiner_billing_finance(p_days integer default 30) returns jsonb language sql security invoker set search_path='' as $$select gd_private.billing_finance(p_days)$$;
revoke all on function public.gooddiner_billing_finance(integer) from public,anon,authenticated;
grant execute on function public.gooddiner_billing_finance(integer) to authenticated;