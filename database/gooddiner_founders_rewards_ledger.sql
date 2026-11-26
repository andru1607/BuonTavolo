begin;
create table gd_private.marketing_founders(restaurant_id uuid primary key references public.restaurants(id) on delete restrict,founder_number integer not null unique check(founder_number between 1 and 100),awarded_at timestamptz not null default now(),trial_until timestamptz not null);
create table gd_private.marketing_paid_referrals(invited_restaurant_id uuid primary key references public.restaurants(id) on delete restrict,inviter_restaurant_id uuid not null references public.restaurants(id) on delete restrict,invoice_ref text not null unique,verified_by uuid not null,verified_at timestamptz not null default now(),note text not null,check(inviter_restaurant_id<>invited_restaurant_id));
create table gd_private.marketing_reward_ledger(id uuid primary key default gen_random_uuid(),restaurant_id uuid not null references public.restaurants(id) on delete restrict,reward_key text not null,kind text not null check(kind in ('credit','month')),amount_cents integer not null check(amount_cents>0),status text not null default 'requested' check(status in ('requested','approved','rejected','delivered')),created_at timestamptz not null default now(),reviewed_at timestamptz,reviewed_by uuid,operator_note text,delivery_ref text unique,unique(restaurant_id,reward_key));
alter table gd_private.marketing_founders enable row level security;
alter table gd_private.marketing_paid_referrals enable row level security;
alter table gd_private.marketing_reward_ledger enable row level security;
revoke all on gd_private.marketing_founders,gd_private.marketing_paid_referrals,gd_private.marketing_reward_ledger from public,anon,authenticated;
create function gd_private.allocate_founder(rid uuid,verified timestamptz) returns integer language plpgsql security definer set search_path='' as $$
declare n integer;
begin
 perform pg_advisory_xact_lock(74391001);
 select founder_number into n from gd_private.marketing_founders where restaurant_id=rid;
 if found then return n;end if;
 select coalesce(max(founder_number),0)+1 into n from gd_private.marketing_founders;
 if n>100 then return null;end if;
 insert into gd_private.marketing_founders(restaurant_id,founder_number,trial_until) values(rid,n,verified+interval '90 days');
 return n;
end $$;
revoke all on function gd_private.allocate_founder(uuid,timestamptz) from public,anon,authenticated;
create or replace function gd_private.create_merchant_trial() returns trigger language plpgsql security definer set search_path='' as $$
declare n integer; until_at timestamptz; reason text;
begin
 if new.verified_at is not null and new.suspended_at is null then
 n:=gd_private.allocate_founder(new.id,new.verified_at);
 until_at:=case when n is not null then new.verified_at+interval '90 days' else now()+interval '14 days' end;
 reason:=case when n is not null then 'GoodDiner Founders: prova iniziale di 90 giorni' else 'Prova di 14 giorni dopo verifica manuale del ristorante' end;
 insert into gd_private.merchant_licenses(restaurant_id,status,active_until,changed_by,change_reason) values(new.id,'trialing',until_at,'gooddiner-system',reason) on conflict(restaurant_id) do nothing;
 if found then insert into gd_private.merchant_license_audit(restaurant_id,action,new_status,new_until,operator_label,reason) values(new.id,'trial_started','trialing',until_at,'gooddiner-system',reason);end if;
 end if;
 return new;
end $$;
do $$ declare r record; n integer; until_at timestamptz;begin
 for r in select id,verified_at from public.restaurants where verified_at is not null and suspended_at is null order by verified_at,id loop
 n:=gd_private.allocate_founder(r.id,r.verified_at);
 if n is not null then
 until_at:=r.verified_at+interval '90 days';
 update gd_private.merchant_licenses set active_until=until_at,changed_by='gooddiner-system',change_reason='Estensione Founders a 90 giorni',updated_at=now() where restaurant_id=r.id and status='trialing' and active_until>now() and active_until<until_at;
 if found then insert into gd_private.merchant_license_audit(restaurant_id,action,new_status,new_until,operator_label,reason) values(r.id,'license_changed','trialing',until_at,'gooddiner-system','Estensione Founders a 90 giorni');end if;
 end if;
 end loop;
end $$;
create function public.marketing_rewards(p_action text,p_restaurant uuid,p_key text default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid(); n integer; eligible jsonb; item jsonb; f gd_private.marketing_founders%rowtype;
begin
 if u is null or not exists(select 1 from public.restaurants r where r.id=p_restaurant and r.owner_id=u and r.verified_at is not null and r.suspended_at is null) then raise exception 'RISTORANTE_NON_VERIFICATO';end if;
 n:=gd_private.marketing_qualified(p_restaurant);
 select * into f from gd_private.marketing_founders where restaurant_id=p_restaurant;
 select coalesce(jsonb_agg(x),'[]'::jsonb) into eligible from (
 select jsonb_build_object('key',v.key,'label',v.label,'eligible',n>=v.threshold,'kind',v.kind,'amount_cents',v.cents) x
 from (values('guest25','25 ospiti verificati',25,'credit',500),('guest50','50 ospiti verificati',50,'credit',1000),('guest100','100 ospiti verificati',100,'month',3900)) v(key,label,threshold,kind,cents)
 union all
 select jsonb_build_object('key','merchant:'||pr.invited_restaurant_id,'label','Invito locale: '||r.name,'eligible',true,'kind','month','amount_cents',3900)
 from gd_private.marketing_paid_referrals pr join public.restaurants r on r.id=pr.invited_restaurant_id where pr.inviter_restaurant_id=p_restaurant
 ) q;
 if p_action='request' then
 select x into item from jsonb_array_elements(eligible) x where x->>'key'=p_key and (x->>'eligible')::boolean;
 if not found then raise exception 'TRAGUARDO_NON_RAGGIUNTO';end if;
 insert into gd_private.marketing_reward_ledger(restaurant_id,reward_key,kind,amount_cents) values(p_restaurant,p_key,item->>'kind',(item->>'amount_cents')::int) on conflict(restaurant_id,reward_key) do nothing;
 elsif p_action<>'stats' then raise exception 'AZIONE_NON_VALIDA';end if;
 return jsonb_build_object('founder_number',f.founder_number,'founder_trial_until',f.trial_until,'founder_remaining',100-(select count(*) from gd_private.marketing_founders),'eligible',eligible,'ledger',coalesce((select jsonb_agg(jsonb_build_object('key',reward_key,'status',status,'kind',kind,'amount_cents',amount_cents,'created_at',created_at,'note',operator_note) order by created_at desc) from gd_private.marketing_reward_ledger where restaurant_id=p_restaurant),'[]'::jsonb));
end $$;
create function public.marketing_rewards_operator(p_action text,p_payload jsonb default '{}'::jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid(); target uuid; src uuid; invoice text; note text; delivery text; rowdata gd_private.marketing_reward_ledger%rowtype; decision text;
begin
 if u is null or not exists(select 1 from gd_studio_private.operators o join auth.users a on a.id=o.user_id where o.user_id=u and a.email_confirmed_at is not null and not coalesce(a.is_anonymous,false)) then raise exception 'STUDIO_ACCESS_DENIED';end if;
 if p_action='verify_payment' then
 target:=(p_payload->>'restaurant_id')::uuid;invoice:=btrim(p_payload->>'invoice_ref');note:=btrim(p_payload->>'note');
 if invoice is null or invoice !~ '^in_[A-Za-z0-9]{8,100}$' or note is null or length(note) not between 10 and 500 or p_payload->>'live_verified'<>'true' or p_payload->>'live_verified' is null then raise exception 'LIVE_PAYMENT_EVIDENCE_REQUIRED';end if;
 if exists(select 1 from gd_private.stripe_test_invoices where invoice_id=invoice) then raise exception 'TEST_INVOICE_NOT_ALLOWED';end if;
 select s.restaurant_id into src from public.restaurants r join gd_private.marketing_signup_sources s on s.user_id=r.owner_id and s.channel='merchant' join gd_private.merchant_licenses l on l.restaurant_id=r.id and l.status='active' and l.active_until>now() where r.id=target and r.verified_at is not null and r.suspended_at is null and s.restaurant_id<>r.id;
 if not found then raise exception 'REFERRAL_NOT_ELIGIBLE';end if;
 insert into gd_private.marketing_paid_referrals(invited_restaurant_id,inviter_restaurant_id,invoice_ref,verified_by,note) values(target,src,invoice,u,note) on conflict(invited_restaurant_id) do nothing;
 elsif p_action='review' then
 target:=(p_payload->>'id')::uuid;decision:=p_payload->>'decision';note:=btrim(p_payload->>'note');
 if decision is null or decision not in ('approved','rejected') or note is null or length(note) not between 10 and 500 then raise exception 'DECISION_REQUIRED';end if;
 select * into rowdata from gd_private.marketing_reward_ledger where id=target and status='requested' for update;
 if not found then raise exception 'REWARD_NOT_PENDING';end if;
 if decision='approved' and not (case rowdata.reward_key when 'guest25' then gd_private.marketing_qualified(rowdata.restaurant_id)>=25 when 'guest50' then gd_private.marketing_qualified(rowdata.restaurant_id)>=50 when 'guest100' then gd_private.marketing_qualified(rowdata.restaurant_id)>=100 else exists(select 1 from gd_private.marketing_paid_referrals where inviter_restaurant_id=rowdata.restaurant_id and 'merchant:'||invited_restaurant_id::text=rowdata.reward_key) end) then raise exception 'REWARD_NO_LONGER_ELIGIBLE';end if;
 update gd_private.marketing_reward_ledger set status=decision,reviewed_by=u,reviewed_at=now(),operator_note=note where id=target;
 elsif p_action='record_delivery' then
 target:=(p_payload->>'id')::uuid;delivery:=btrim(p_payload->>'delivery_ref');note:=btrim(p_payload->>'note');
 if delivery is null or delivery !~ '^(cbtxn_|cn_|in_)[A-Za-z0-9]{8,100}$' or note is null or length(note) not between 10 and 500 or p_payload->>'live_verified' is distinct from 'true' then raise exception 'LIVE_DELIVERY_EVIDENCE_REQUIRED';end if;
 if exists(select 1 from gd_private.stripe_test_invoices where invoice_id=delivery) then raise exception 'TEST_INVOICE_NOT_ALLOWED';end if;
 update gd_private.marketing_reward_ledger set status='delivered',delivery_ref=delivery,reviewed_by=u,reviewed_at=now(),operator_note=note where id=target and status='approved';
 if not found then raise exception 'REWARD_NOT_APPROVED';end if;
 elsif p_action<>'list' then raise exception 'STUDIO_ACTION_INVALID';end if;
 return jsonb_build_object('founders',(select count(*) from gd_private.marketing_founders),'referred',coalesce((select jsonb_agg(to_jsonb(x)) from (select r.id,r.name,r.city,src.name inviter,l.status as license_status,(pr.invited_restaurant_id is not null) as payment_verified from gd_private.marketing_signup_sources s join public.restaurants r on r.owner_id=s.user_id join public.restaurants src on src.id=s.restaurant_id left join gd_private.merchant_licenses l on l.restaurant_id=r.id left join gd_private.marketing_paid_referrals pr on pr.invited_restaurant_id=r.id where s.channel='merchant' and r.verified_at is not null and r.suspended_at is null order by r.verified_at desc limit 200) x),'[]'::jsonb),'rewards',coalesce((select jsonb_agg(to_jsonb(x)) from (select l.id,r.name,l.reward_key,l.kind,l.amount_cents,l.status,l.operator_note,l.created_at,l.delivery_ref from gd_private.marketing_reward_ledger l join public.restaurants r on r.id=l.restaurant_id order by (l.status='requested') desc,l.created_at desc limit 200) x),'[]'::jsonb));
end $$;
revoke all on function public.marketing_rewards(text,uuid,text),public.marketing_rewards_operator(text,jsonb) from public,anon,authenticated;
grant execute on function public.marketing_rewards(text,uuid,text),public.marketing_rewards_operator(text,jsonb) to authenticated;
commit;