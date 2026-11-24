-- Unified reservation register, without fabricated customer accounts.
alter table gd_private.bookings alter column customer_id drop not null,add column source text not null default 'online' check(source in ('online','phone','walk_in','waitlist')),add constraint gd_booking_online_identity check((source='online' and customer_id is not null) or (source<>'online' and customer_id is null and voucher_id is null));
alter table gd_private.booking_settings add column auto_confirm boolean not null default false;
alter table gd_private.booking_notifications drop constraint booking_notifications_kind_check;
alter table gd_private.booking_notifications add constraint booking_notifications_kind_check check(kind in ('pending','confirmed','rejected','cancelled','expired','completed','no_show','modified'));
create table gd_private.booking_waitlist(
 id uuid primary key default gen_random_uuid(),restaurant_id uuid not null references public.restaurants(id),booking_name text not null check(char_length(btrim(booking_name)) between 2 and 80),
 desired_at timestamptz not null,party integer not null check(party between 1 and 30),status text not null default 'waiting' check(status in ('waiting','converted','cancelled')),booking_id uuid references gd_private.bookings(id),created_at timestamptz not null default now()
);
alter table gd_private.booking_waitlist enable row level security;
revoke all on gd_private.booking_waitlist from public,anon,authenticated;
create table gd_private.booking_changes(id bigint generated always as identity primary key,booking_id uuid not null references gd_private.bookings(id),actor_id uuid references auth.users(id) on delete set null,old_starts_at timestamptz,new_starts_at timestamptz,old_party integer,new_party integer,created_at timestamptz not null default now());
alter table gd_private.booking_changes enable row level security;
revoke all on gd_private.booking_changes from public,anon,authenticated;
create or replace function gd_private.booking_notice_trigger() returns trigger language plpgsql security definer set search_path='' as $$
declare owner uuid; k text;
begin
 if tg_op='UPDATE' and old.status=new.status then
  if old.starts_at=new.starts_at and old.party=new.party then return new;end if;k:='modified';
 else k:=new.status;end if;
 select owner_id into owner from public.restaurants where id=new.restaurant_id;
 if k<>'pending' and new.customer_id is not null then insert into gd_private.booking_notifications(recipient_id,booking_id,kind) values(new.customer_id,new.id,k);end if;
 if k in ('pending','cancelled','expired','modified') and owner is not null then insert into gd_private.booking_notifications(recipient_id,booking_id,kind) values(owner,new.id,k);end if;
 return new;
end $$;
drop trigger gd_booking_notice_trigger on gd_private.bookings;
create trigger gd_booking_notice_trigger after insert or update of status,starts_at,party on gd_private.bookings for each row execute function gd_private.booking_notice_trigger();
-- Modifications run the same capacity checks as creation, with the original seating duration.
create or replace function gd_private.booking_capacity_guard() returns trigger language plpgsql security definer set search_path='' as $$
declare s gd_private.booking_settings%rowtype;
begin
 if tg_op='INSERT' or (new.status='confirmed' and old.status='pending') or (new.status in ('pending','confirmed') and (new.starts_at is distinct from old.starts_at or new.party is distinct from old.party)) then
 select * into s from gd_private.booking_settings where restaurant_id=new.restaurant_id for update;
 if not found or new.party>s.max_party or gd_private.booking_remaining(new.restaurant_id,new.starts_at,new.id)<new.party then raise exception 'BOOKING_SLOT_FULL';end if;
 if tg_op='INSERT' then new.seating_minutes:=s.duration_minutes;end if;
 end if;return new;
end $$;
drop trigger gd_booking_capacity_guard on gd_private.bookings;
create trigger gd_booking_capacity_guard before insert or update of status,starts_at,party on gd_private.bookings for each row execute function gd_private.booking_capacity_guard();
-- Opt-in auto-confirmation: lock the same venue used by the room allocator, never confirm without a free compatible table.
create or replace function gd_private.booking_try_auto() returns trigger language plpgsql security definer set search_path='' as $$
declare tid uuid;
begin
 if new.source<>'online' or new.status<>'pending' or not exists(select 1 from gd_private.booking_settings where restaurant_id=new.restaurant_id and auto_confirm) then return new;end if;
 perform 1 from public.restaurants where id=new.restaurant_id for update;
 select t.id into tid from gd_private.room_tables t where t.restaurant_id=new.restaurant_id and t.active and t.seats>=new.party and gd_private.room_table_free(t.id,new.id,new.starts_at,new.starts_at+make_interval(mins=>new.seating_minutes)) order by t.seats,t.label limit 1;
 if found then
  insert into gd_private.room_assignments(booking_id,table_id) values(new.id,tid);
  update gd_private.bookings set status='confirmed',updated_at=now() where id=new.id;
 end if;return new;
end $$;
revoke all on function gd_private.booking_try_auto() from public,anon,authenticated;
create trigger gd_booking_try_auto after insert on gd_private.bookings for each row execute function gd_private.booking_try_auto();
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
   where s.enabled and s.capacity>0 and jsonb_array_length(s.service_windows)>0 and r.verified_at is not null and r.suspended_at is null and l.status in ('trialing','active') and l.active_until>now() and r.owner_id<>actor);
 elsif p_action='list' then
  mode:=p_payload->>'mode';
  if mode is null or mode not in ('customer','merchant') then raise exception 'BOOKING_INVALID'; end if;
  if mode='merchant' then
   venue:=(p_payload->>'restaurant_id')::uuid;
   if not exists(select 1 from public.restaurants where id=venue and owner_id=actor) then raise exception 'BOOKING_FORBIDDEN'; end if;
  end if;
  update gd_private.bookings x set status='expired',updated_at=now() where x.status='pending' and x.starts_at<=now() and ((mode='customer' and x.customer_id=actor) or (mode='merchant' and x.restaurant_id=venue));
  return (select coalesce(jsonb_agg(to_jsonb(q) order by q.starts_at desc),'[]'::jsonb) from (
   select x.id,x.restaurant_id,r.name as restaurant_name,x.booking_name,x.starts_at,x.party,x.status,x.discount_percent,x.arrived_at,x.source,
    case when x.voucher_id is null then null when x.status='completed' and vv.status='redeemed' then true
    else coalesce(active,false) and vv.status='available' and vv.reward_restaurant_id=x.restaurant_id and vv.discount_percent=x.discount_percent and gd_private.reward_positive_count(x.customer_id)>=vv.milestone end as discount_valid,
    case when mode='customer' then x.voucher_id else null end as voucher_id,x.created_at from gd_private.bookings x join public.restaurants r on r.id=x.restaurant_id left join public.vouchers vv on vv.id=x.voucher_id
   where (mode='customer' and x.customer_id=actor) or (mode='merchant' and x.restaurant_id=venue) order by x.starts_at desc limit 300) q);
 elsif p_action='create' then
  venue:=(p_payload->>'restaurant_id')::uuid; start_at:=(p_payload->>'starts_at')::timestamptz; size:=(p_payload->>'party')::integer; nm:=btrim(p_payload->>'name'); vid:=nullif(p_payload->>'voucher_id','')::uuid;
  if start_at is null or start_at<now()+interval '15 minutes' or start_at>now()+interval '90 days' or size is null or nm is null or char_length(nm) not between 2 and 80 then raise exception 'BOOKING_INVALID'; end if;
  perform 1 from public.profiles where id=actor for update;
  perform 1 from public.restaurants where id=venue for update;
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
  return (select jsonb_build_object('id',id,'status',status,'discount_percent',discount_percent) from gd_private.bookings where id=bid);
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
   if b.customer_id is distinct from actor and not exists(select 1 from public.restaurants where id=b.restaurant_id and owner_id=actor) then raise exception 'BOOKING_FORBIDDEN'; end if;
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
   if b.customer_id is not null and not exists(select 1 from public.visits vv where vv.customer_id=b.customer_id and vv.restaurant_id=b.restaurant_id and vv.status='confirmed' and vv.visited_on=(b.starts_at at time zone 'Europe/Rome')::date) then raise exception 'VISITA_NON_VALIDA'; end if;
   if b.customer_id is null and b.arrived_at is null then raise exception 'VISITA_NON_VALIDA';end if;
   next_status:='completed';
  else raise exception 'BOOKING_INVALID_STATUS'; end if;
  update gd_private.bookings set status=next_status,updated_at=now() where id=bid;
  return jsonb_build_object('status',next_status);
 else raise exception 'BOOKING_INVALID'; end if;
end $$;
revoke all on function gd_private.booking_action(text,jsonb) from public,anon,authenticated;
grant execute on function gd_private.booking_action(text,jsonb) to authenticated;

create or replace function gd_private.manager_register(p_action text,p_payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid();venue uuid:=(p_payload->>'restaurant_id')::uuid;b gd_private.bookings%rowtype;w gd_private.booking_waitlist%rowtype;bid uuid;wid uuid;nm text;src text;st timestamptz;n integer;flag boolean;
begin
 if actor is null or not gd_private.current_user_email_confirmed() then raise exception 'BOOKING_LOGIN_REQUIRED';end if;
 perform gd_private.assert_merchant_access(venue,actor);
 perform 1 from public.restaurants where id=venue for update;
 if p_action='auto_set' then
 flag:=(p_payload->>'enabled')::boolean;if flag is null then raise exception 'BOOKING_INVALID';end if;
 if flag and not exists(select 1 from gd_private.room_tables where restaurant_id=venue and active) then raise exception 'ROOM_ASSIGN_FIRST';end if;
 update gd_private.booking_settings set auto_confirm=flag where restaurant_id=venue;
 elsif p_action in ('manual_create','wait_add','wait_convert','modify') then
 st:=(p_payload->>'starts_at')::timestamptz;n:=(p_payload->>'party')::integer;nm:=btrim(p_payload->>'name');
 if p_action='wait_convert' then
 wid:=(p_payload->>'id')::uuid;select * into w from gd_private.booking_waitlist where id=wid and restaurant_id=venue and status='waiting' for update;
 if not found then raise exception 'BOOKING_INVALID_STATUS';end if;
 st:=coalesce(st,w.desired_at);n:=w.party;nm:=w.booking_name;
 end if;
 if st is null or st<now()-interval '30 minutes' or st>now()+interval '90 days' or n is null or n not between 1 and 30 or nm is null or char_length(nm) not between 2 and 80 then raise exception 'BOOKING_INVALID';end if;
 if p_action='wait_add' then
 insert into gd_private.booking_waitlist(restaurant_id,booking_name,desired_at,party) values(venue,nm,st,n);
 elsif p_action='modify' then
 bid:=(p_payload->>'id')::uuid;
 select * into b from gd_private.bookings where id=bid and restaurant_id=venue for update;
 if not found or b.status not in ('pending','confirmed') or b.arrived_at is not null or st<=now() then raise exception 'BOOKING_INVALID_STATUS';end if;
 -- A move releases prior table allocation, without releasing the voucher. All changes atomic.
 delete from gd_private.room_assignments where booking_id=bid;
 update gd_private.bookings set starts_at=st,party=n,booking_name=nm,updated_at=now() where id=bid;
 insert into gd_private.booking_changes(booking_id,actor_id,old_starts_at,new_starts_at,old_party,new_party) values(bid,actor,b.starts_at,st,b.party,n);
 else
 src:=case when p_action='wait_convert' then 'waitlist' else p_payload->>'source' end;
 if src is null or src not in ('phone','walk_in','waitlist') then raise exception 'BOOKING_INVALID';end if;
 insert into gd_private.bookings(restaurant_id,customer_id,booking_name,starts_at,party,status,source) values(venue,null,nm,st,n,'confirmed',src) returning id into bid;
 if p_action='wait_convert' then update gd_private.booking_waitlist set status='converted',booking_id=bid where id=wid;end if;
 end if;
 elsif p_action='wait_cancel' then
 update gd_private.booking_waitlist set status='cancelled' where id=(p_payload->>'id')::uuid and restaurant_id=venue and status='waiting';if not found then raise exception 'BOOKING_INVALID_STATUS';end if;
 elsif p_action<>'list' then raise exception 'BOOKING_INVALID';end if;
 return jsonb_build_object('auto_confirm',coalesce((select auto_confirm from gd_private.booking_settings where restaurant_id=venue),false),'waitlist',(select coalesce(jsonb_agg(to_jsonb(q) order by q.created_at),'[]'::jsonb) from (select id,booking_name,desired_at,party,status,created_at from gd_private.booking_waitlist where restaurant_id=venue and status='waiting' order by created_at limit 200) q));
end $$;
revoke all on function gd_private.manager_register(text,jsonb) from public,anon,authenticated;
grant execute on function gd_private.manager_register(text,jsonb) to authenticated;
create or replace function public.gooddiner_manager_register(p_action text,p_payload jsonb default '{}'::jsonb) returns jsonb language sql security invoker set search_path='' as $$select gd_private.manager_register(p_action,p_payload)$$;
revoke all on function public.gooddiner_manager_register(text,jsonb) from public,anon,authenticated;
grant execute on function public.gooddiner_manager_register(text,jsonb) to authenticated;