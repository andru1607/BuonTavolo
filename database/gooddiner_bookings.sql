-- Internal reservation requests; no invented availability or automatic confirmation.
create table gd_private.booking_settings (
 restaurant_id uuid primary key references public.restaurants(id) on delete cascade,
 enabled boolean not null default false,
 max_party integer not null default 8 check(max_party between 1 and 30),
 updated_at timestamptz not null default now()
);
alter table gd_private.booking_settings enable row level security;
revoke all on gd_private.booking_settings from public,anon,authenticated;
create table gd_private.bookings (
 id uuid primary key default gen_random_uuid(),
 restaurant_id uuid not null references public.restaurants(id),
 customer_id uuid not null references public.profiles(id),
 booking_name text not null check(char_length(btrim(booking_name)) between 2 and 80),
 starts_at timestamptz not null,
 party integer not null check(party between 1 and 30),
 status text not null default 'pending' check(status in ('pending','confirmed','rejected','cancelled','expired','completed','no_show')),
 voucher_id uuid references public.vouchers(id),
 discount_percent integer check(discount_percent between 1 and 100),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 check((voucher_id is null)=(discount_percent is null))
);
create unique index gd_booking_hold on gd_private.bookings(voucher_id) where status in ('pending','confirmed') and voucher_id is not null;
create unique index gd_booking_duplicate on gd_private.bookings(customer_id,restaurant_id,starts_at) where status in ('pending','confirmed');
create index gd_booking_customer on gd_private.bookings(customer_id,starts_at);
create index gd_booking_venue on gd_private.bookings(restaurant_id,starts_at);
alter table gd_private.bookings enable row level security;
revoke all on gd_private.bookings from public,anon,authenticated;
-- Enforce the hold even through the pre-existing rewards RPC.
create or replace function gd_private.booking_voucher_guard()
returns trigger language plpgsql security definer set search_path='' as $$
declare b gd_private.bookings%rowtype; v public.visits%rowtype;
begin
 if old.status='available' and (new.status='pending' or new.reward_restaurant_id is distinct from old.reward_restaurant_id) then
  if exists(select 1 from gd_private.bookings where voucher_id=old.id and status in ('pending','confirmed')) then
   raise exception 'BUONO_ASSOCIATO_PRENOTAZIONE';
  end if;
 end if;
 if new.status='redeemed' and old.status<>'redeemed' then
  select * into b from gd_private.bookings where voucher_id=old.id and status in ('pending','confirmed') for update;
  if found then
   select * into v from public.visits where id=new.redeemed_visit_id;
   if b.status<>'confirmed' or v.id is null or v.customer_id<>b.customer_id or v.restaurant_id<>b.restaurant_id or v.visited_on<>(b.starts_at at time zone 'Europe/Rome')::date then
    raise exception 'BUONO_ASSOCIATO_PRENOTAZIONE';
   end if;
   update gd_private.bookings set status='completed',updated_at=now() where id=b.id;
  end if;
 end if;
 return new;
end $$;
revoke all on function gd_private.booking_voucher_guard() from public,anon,authenticated;
create trigger gd_booking_voucher_guard before update on public.vouchers for each row execute function gd_private.booking_voucher_guard();
create or replace function gd_private.booking_action(p_action text,p_payload jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); venue uuid; bid uuid; vid uuid; start_at timestamptz; size integer; nm text; pct integer; v public.vouchers%rowtype; b gd_private.bookings%rowtype; settings gd_private.booking_settings%rowtype; active boolean; next_status text; mode text;
begin
 if actor is null or not gd_private.current_user_email_confirmed() or not exists(select 1 from public.profiles where id=actor) then raise exception 'BOOKING_LOGIN_REQUIRED'; end if;
 select personal_reviews_enabled and rewards_enabled into active from gd_private.business_features where singleton;
 if p_action in ('settings_get','settings_set') then
  venue:=(p_payload->>'restaurant_id')::uuid;
  perform gd_private.assert_merchant_access(venue,actor);
  if p_action='settings_set' then
   size:=(p_payload->>'max_party')::integer;
   if size is null or size not between 1 and 30 or p_payload->>'enabled' is null then raise exception 'BOOKING_INVALID'; end if;
   insert into gd_private.booking_settings(restaurant_id,enabled,max_party) values(venue,(p_payload->>'enabled')::boolean,size)
   on conflict(restaurant_id) do update set enabled=excluded.enabled,max_party=excluded.max_party,updated_at=now();
  end if;
  return coalesce((select jsonb_build_object('enabled',enabled,'max_party',max_party) from gd_private.booking_settings where restaurant_id=venue),'{"enabled":false,"max_party":8}'::jsonb);
 elsif p_action='catalog' then
  return (select coalesce(jsonb_agg(jsonb_build_object('id',r.id,'name',r.name,'city',r.city,'address',loc.address,'max_party',s.max_party,'percent',case when active and o.enabled then o.percent else null end) order by r.name),'[]'::jsonb)
   from public.restaurants r join gd_private.booking_settings s on s.restaurant_id=r.id join gd_private.merchant_licenses l on l.restaurant_id=r.id
   left join gd_private.reward_offers o on o.restaurant_id=r.id left join gd_private.reward_locations loc on loc.restaurant_id=r.id
   where s.enabled and r.verified_at is not null and r.suspended_at is null and l.status in ('trialing','active') and l.active_until>now() and r.owner_id<>actor);
 elsif p_action='list' then
  mode:=p_payload->>'mode';
  if mode is null or mode not in ('customer','merchant') then raise exception 'BOOKING_INVALID'; end if;
  if mode='merchant' then
   venue:=(p_payload->>'restaurant_id')::uuid;
   if not exists(select 1 from public.restaurants where id=venue and owner_id=actor) then raise exception 'BOOKING_FORBIDDEN'; end if;
  end if;
  update gd_private.bookings x set status='expired',updated_at=now() where x.status='pending' and x.starts_at<=now() and ((mode='customer' and x.customer_id=actor) or (mode='merchant' and x.restaurant_id=venue));
  return (select coalesce(jsonb_agg(to_jsonb(q) order by q.starts_at desc),'[]'::jsonb) from (
   select x.id,x.restaurant_id,r.name as restaurant_name,x.booking_name,x.starts_at,x.party,x.status,x.discount_percent,
    case when x.voucher_id is null then null when x.status='completed' and vv.status='redeemed' then true
    else coalesce(active,false) and vv.status='available' and vv.reward_restaurant_id=x.restaurant_id and vv.discount_percent=x.discount_percent and gd_private.reward_positive_count(x.customer_id)>=vv.milestone end as discount_valid,
    case when mode='customer' then x.voucher_id else null end as voucher_id,x.created_at from gd_private.bookings x join public.restaurants r on r.id=x.restaurant_id left join public.vouchers vv on vv.id=x.voucher_id
   where (mode='customer' and x.customer_id=actor) or (mode='merchant' and x.restaurant_id=venue) order by x.starts_at desc limit 300) q);
 elsif p_action='create' then
  venue:=(p_payload->>'restaurant_id')::uuid; start_at:=(p_payload->>'starts_at')::timestamptz; size:=(p_payload->>'party')::integer; nm:=btrim(p_payload->>'name'); vid:=nullif(p_payload->>'voucher_id','')::uuid;
  if start_at is null or start_at<now()+interval '15 minutes' or start_at>now()+interval '90 days' or size is null or nm is null or char_length(nm) not between 2 and 80 then raise exception 'BOOKING_INVALID'; end if;
  perform 1 from public.profiles where id=actor for update;
  update gd_private.bookings set status='expired',updated_at=now() where customer_id=actor and status='pending' and starts_at<=now();
  select s.* into settings from gd_private.booking_settings s join public.restaurants r on r.id=s.restaurant_id join gd_private.merchant_licenses l on l.restaurant_id=r.id where s.restaurant_id=venue and s.enabled and r.verified_at is not null and r.suspended_at is null and l.status in ('trialing','active') and l.active_until>now() and r.owner_id<>actor;
  if not found or size not between 1 and settings.max_party then raise exception 'BOOKING_UNAVAILABLE'; end if;
  if (select count(*) from gd_private.bookings where customer_id=actor and status in ('pending','confirmed') and starts_at>now())>=10 then raise exception 'BOOKING_LIMIT'; end if;
  if vid is not null then
   if not coalesce(active,false) then raise exception 'PREMI_NON_ATTIVI'; end if;
   select * into v from public.vouchers where id=vid and customer_id=actor for update;
   if not found or gd_private.reward_positive_count(actor)<v.milestone or exists(select 1 from gd_private.bookings where voucher_id=vid and status in ('pending','confirmed')) then raise exception 'BOOKING_VOUCHER_UNAVAILABLE'; end if;
   if v.status='pending' then
    perform gd_private.reward_action('claim',jsonb_build_object('voucher_id',vid,'restaurant_id',venue,'percent',(p_payload->>'percent')::integer));
    select * into v from public.vouchers where id=vid;
   end if;
   if v.status<>'available' or v.reward_restaurant_id is distinct from venue or v.discount_percent is null or v.discount_percent is distinct from (p_payload->>'percent')::integer then raise exception 'BOOKING_VOUCHER_UNAVAILABLE'; end if;
   pct:=v.discount_percent;
  end if;
  insert into gd_private.bookings(restaurant_id,customer_id,booking_name,starts_at,party,voucher_id,discount_percent) values(venue,actor,nm,start_at,size,vid,pct) returning id into bid;
  return jsonb_build_object('id',bid,'status','pending','discount_percent',pct);
 elsif p_action='redeem' then
  bid:=(p_payload->>'id')::uuid;
  select * into b from gd_private.bookings where id=bid;
  if not found or b.status<>'confirmed' or b.voucher_id is null then raise exception 'BOOKING_INVALID_STATUS'; end if;
  perform gd_private.assert_merchant_access(b.restaurant_id,actor);
  select * into v from public.vouchers where id=b.voucher_id and customer_id=b.customer_id;
  if not found or v.status<>'available' then raise exception 'BOOKING_VOUCHER_UNAVAILABLE'; end if;
  select x.id into vid from public.visits x where x.customer_id=b.customer_id and x.restaurant_id=b.restaurant_id and x.status='confirmed' and x.visited_on=(b.starts_at at time zone 'Europe/Rome')::date and x.visited_on=(now() at time zone 'Europe/Rome')::date for update;
  if not found then raise exception 'VISITA_NON_VALIDA'; end if;
  perform 1 from public.profiles where id=b.customer_id for update;
  select * into v from public.vouchers where id=b.voucher_id and customer_id=b.customer_id for update;
  if not found or v.status<>'available' then raise exception 'BOOKING_VOUCHER_UNAVAILABLE'; end if;
  select * into b from gd_private.bookings where id=bid for update;
  if b.status<>'confirmed' then raise exception 'BOOKING_INVALID_STATUS'; end if;
  return gd_private.reward_action('redeem',jsonb_build_object('restaurant_id',b.restaurant_id,'visit_id',vid,'code',v.voucher_code));
 elsif p_action in ('confirm','reject','cancel','complete','no_show') then
  bid:=(p_payload->>'id')::uuid;
  select * into b from gd_private.bookings where id=bid;
  if not found then raise exception 'BOOKING_FORBIDDEN'; end if;
  if p_action='cancel' then
   if b.customer_id<>actor and not exists(select 1 from public.restaurants where id=b.restaurant_id and owner_id=actor) then raise exception 'BOOKING_FORBIDDEN'; end if;
  else
   if not exists(select 1 from public.restaurants where id=b.restaurant_id and owner_id=actor) then raise exception 'BOOKING_FORBIDDEN'; end if;
  end if;
  perform 1 from public.profiles where id=b.customer_id for update;
  select * into b from gd_private.bookings where id=bid for update;
  if p_action='confirm' then
   perform gd_private.assert_merchant_access(b.restaurant_id,actor);
   if b.status<>'pending' or b.starts_at<=now() then raise exception 'BOOKING_INVALID_STATUS'; end if;
   if b.voucher_id is not null and (not coalesce(active,false) or not exists(select 1 from public.vouchers vv where vv.id=b.voucher_id and vv.status='available' and vv.reward_restaurant_id=b.restaurant_id and vv.discount_percent=b.discount_percent and gd_private.reward_positive_count(b.customer_id)>=vv.milestone)) then raise exception 'BOOKING_VOUCHER_UNAVAILABLE'; end if;
   next_status:='confirmed';
  elsif p_action='reject' and b.status='pending' then next_status:='rejected';
  elsif p_action='cancel' and b.status in ('pending','confirmed') and (b.starts_at>now() or b.status='pending') then next_status:='cancelled';
  elsif p_action='no_show' and b.status='confirmed' and b.starts_at+interval '30 minutes'<=now() then next_status:='no_show';
  elsif p_action='complete' and b.status='confirmed' and b.starts_at<=now() and b.voucher_id is null then
   if not exists(select 1 from public.visits v where v.customer_id=b.customer_id and v.restaurant_id=b.restaurant_id and v.status='confirmed' and v.visited_on=(b.starts_at at time zone 'Europe/Rome')::date) then raise exception 'VISITA_NON_VALIDA'; end if;
   next_status:='completed';
  else raise exception 'BOOKING_INVALID_STATUS'; end if;
  update gd_private.bookings set status=next_status,updated_at=now() where id=bid;
  return jsonb_build_object('status',next_status);
 else raise exception 'BOOKING_INVALID'; end if;
end $$;
revoke all on function gd_private.booking_action(text,jsonb) from public,anon,authenticated;
grant execute on function gd_private.booking_action(text,jsonb) to authenticated;
create or replace function public.gooddiner_bookings(p_action text,p_payload jsonb default '{}'::jsonb)
returns jsonb language sql security invoker set search_path='' as $$ select gd_private.booking_action(p_action,p_payload) $$;
revoke all on function public.gooddiner_bookings(text,jsonb) from public,anon,authenticated;
grant execute on function public.gooddiner_bookings(text,jsonb) to authenticated;