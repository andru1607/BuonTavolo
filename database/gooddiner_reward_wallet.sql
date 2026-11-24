-- GoodDiner rewards: prepared for controlled launch; both gates stay off by default.
alter table gd_private.business_features add column if not exists rewards_enabled boolean not null default false;
create table gd_private.reward_offers (
 restaurant_id uuid primary key references public.restaurants(id) on delete cascade,
 percent integer not null check(percent between 1 and 100),
 enabled boolean not null default false,
 updated_at timestamptz not null default now()
);
alter table gd_private.reward_offers enable row level security;
revoke all on gd_private.reward_offers from public,anon,authenticated;
alter table public.vouchers add column reward_restaurant_id uuid references public.restaurants(id),
 add column discount_percent integer check(discount_percent between 1 and 100),
 add column claimed_at timestamptz,
 add column redeemed_at timestamptz,
 add column redeemed_visit_id uuid references public.visits(id),
 add constraint gd_reward_one_per_visit unique(redeemed_visit_id);
create or replace function gd_private.reward_positive_count(p_customer uuid)
returns bigint language sql stable security invoker set search_path='' as $$
 select count(*) from public.reviews where customer_id=p_customer and rating>=8 and status='published'
$$;
revoke all on function gd_private.reward_positive_count(uuid) from public,anon,authenticated;
create or replace function gd_private.reward_reconcile()
returns trigger language plpgsql security definer set search_path='' as $$
declare uid uuid:=new.customer_id; n bigint;
begin
 perform 1 from public.profiles where id=uid for update;
 n:=gd_private.reward_positive_count(uid);
 update public.vouchers set status='suspended' where customer_id=uid and milestone>n and status in ('pending','available');
 update public.vouchers set status='pending',reward_restaurant_id=null,discount_percent=null,claimed_at=null,
 voucher_code='GD-'||upper(replace(gen_random_uuid()::text,'-',''))
 where customer_id=uid and milestone<=n and status='suspended';
 return new;
end $$;
revoke all on function gd_private.reward_reconcile() from public,anon,authenticated;
create trigger gd_reward_reconcile after insert or update of status on public.reviews for each row execute function gd_private.reward_reconcile();
create or replace function gd_private.reward_action(p_action text,p_payload jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); venue uuid; voucher public.vouchers%rowtype; pct integer; v_id uuid; active boolean; confirmed_visit public.visits%rowtype;
begin
 if actor is null or not exists(select 1 from public.profiles where id=actor) then raise exception 'LOGIN_RICHIESTO'; end if;
 select personal_reviews_enabled and rewards_enabled into active from gd_private.business_features where singleton=true;
 if p_action='offer_get' or p_action='offer_set' then
  venue:=(p_payload->>'restaurant_id')::uuid;
  perform gd_private.assert_merchant_access(venue,actor);
  if p_action='offer_set' then
   pct:=(p_payload->>'percent')::integer;
   if pct is null or pct not between 1 and 100 or p_payload->>'enabled' is null then raise exception 'OFFERTA_NON_VALIDA'; end if;
   insert into gd_private.reward_offers(restaurant_id,percent,enabled) values(venue,pct,(p_payload->>'enabled')::boolean)
   on conflict(restaurant_id) do update set percent=excluded.percent,enabled=excluded.enabled,updated_at=now();
  end if;
  return coalesce((select jsonb_build_object('percent',percent,'enabled',enabled) from gd_private.reward_offers where restaurant_id=venue),'{"percent":null,"enabled":false}'::jsonb)||jsonb_build_object('program_active',coalesce(active,false));
 end if;
 if not coalesce(active,false) then raise exception 'PREMI_NON_ATTIVI'; end if;
 if p_action='catalog' then
  return (select coalesce(jsonb_agg(jsonb_build_object('id',r.id,'name',r.name,'city',r.city,'percent',o.percent) order by r.name),'[]'::jsonb)
    from gd_private.reward_offers o join public.restaurants r on r.id=o.restaurant_id join gd_private.merchant_licenses l on l.restaurant_id=r.id
    where o.enabled and r.verified_at is not null and r.suspended_at is null and l.status in ('trialing','active') and l.active_until>now() and r.owner_id<>actor);
 elsif p_action='claim' then
  venue:=(p_payload->>'restaurant_id')::uuid;
  perform 1 from public.profiles where id=actor for update;
  select * into voucher from public.vouchers where id=(p_payload->>'voucher_id')::uuid and customer_id=actor for update;
  if not found or voucher.status<>'pending' or gd_private.reward_positive_count(actor)<voucher.milestone then raise exception 'PREMIO_NON_DISPONIBILE'; end if;
  select o.percent into pct from gd_private.reward_offers o join public.restaurants r on r.id=o.restaurant_id join gd_private.merchant_licenses l on l.restaurant_id=r.id
   where o.restaurant_id=venue and o.enabled and r.verified_at is not null and r.suspended_at is null and r.owner_id<>actor and l.status in ('trialing','active') and l.active_until>now();
  if not found then raise exception 'OFFERTA_NON_DISPONIBILE'; end if;
  if (p_payload->>'percent')::integer is distinct from pct then raise exception 'OFFERTA_MODIFICATA'; end if;
  update public.vouchers set status='available',reward_restaurant_id=venue,discount_percent=pct,claimed_at=now(),
   voucher_code='GD-'||upper(replace(gen_random_uuid()::text,'-','')) where id=voucher.id;
  return jsonb_build_object('ok',true);
 elsif p_action='cancel_claim' then
  perform 1 from public.profiles where id=actor for update;
  update public.vouchers set status='pending',reward_restaurant_id=null,discount_percent=null,claimed_at=null,
   voucher_code='GD-'||upper(replace(gen_random_uuid()::text,'-',''))
   where id=(p_payload->>'voucher_id')::uuid and customer_id=actor and status='available';
  if not found then raise exception 'PREMIO_NON_DISPONIBILE'; end if;
  return jsonb_build_object('ok',true);
 elsif p_action='redeem' then
  venue:=(p_payload->>'restaurant_id')::uuid;
  perform gd_private.assert_merchant_access(venue,actor);
  if coalesce(p_payload->>'code','') !~ '^GD-[0-9A-F]{32}$' then raise exception 'BUONO_NON_VALIDO'; end if;
  select * into confirmed_visit from public.visits where id=(p_payload->>'visit_id')::uuid and restaurant_id=venue and status='confirmed' and visited_on=(now() at time zone 'Europe/Rome')::date for update;
  if not found then raise exception 'VISITA_NON_VALIDA'; end if;
  perform 1 from public.profiles where id=confirmed_visit.customer_id for update;
  select * into voucher from public.vouchers where voucher_code=p_payload->>'code' and customer_id=confirmed_visit.customer_id and reward_restaurant_id=venue for update;
  if not found or voucher.status<>'available' or voucher.discount_percent is null or gd_private.reward_positive_count(confirmed_visit.customer_id)<voucher.milestone then raise exception 'BUONO_NON_VALIDO'; end if;
  if exists(select 1 from public.vouchers where redeemed_visit_id=confirmed_visit.id) then raise exception 'BUONO_GIA_USATO_PER_VISITA'; end if;
  update public.vouchers set status='redeemed',redeemed_at=now(),redeemed_visit_id=confirmed_visit.id where id=voucher.id;
  return jsonb_build_object('percent',voucher.discount_percent,'ok',true);
 else raise exception 'AZIONE_NON_VALIDA';
 end if;
end $$;
revoke all on function gd_private.reward_action(text,jsonb) from public,anon,authenticated;
grant execute on function gd_private.reward_action(text,jsonb) to authenticated;
create or replace function public.gooddiner_rewards(p_action text,p_payload jsonb default '{}'::jsonb)
returns jsonb language sql security invoker set search_path='' as $$ select gd_private.reward_action(p_action,p_payload) $$;
revoke all on function public.gooddiner_rewards(text,jsonb) from public,anon,authenticated;
grant execute on function public.gooddiner_rewards(text,jsonb) to authenticated;