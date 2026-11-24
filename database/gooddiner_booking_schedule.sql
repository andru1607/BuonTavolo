-- Availability and internal notifications, GoodDiner only.
alter table gd_private.booking_settings add column capacity integer not null default 0 check(capacity between 0 and 500),
 add column duration_minutes integer not null default 90 check(duration_minutes between 30 and 240 and duration_minutes%30=0),
 add column service_windows jsonb not null default '[]'::jsonb;
create table gd_private.booking_day_overrides(
 restaurant_id uuid not null references public.restaurants(id) on delete cascade,
 day date not null, closed boolean not null default false,
 blocked_covers integer not null default 0 check(blocked_covers between 0 and 500),
 primary key(restaurant_id,day)
);
alter table gd_private.booking_day_overrides enable row level security;
revoke all on gd_private.booking_day_overrides from public,anon,authenticated;
create table gd_private.booking_notifications(
 id uuid primary key default gen_random_uuid(), recipient_id uuid not null references auth.users(id) on delete cascade,
 booking_id uuid not null references gd_private.bookings(id) on delete cascade,
 kind text not null check(kind in ('pending','confirmed','rejected','cancelled','expired','completed','no_show')),
 created_at timestamptz not null default now(), read_at timestamptz
);
create index gd_booking_notice_recipient on gd_private.booking_notifications(recipient_id,created_at desc);
alter table gd_private.booking_notifications enable row level security;
revoke all on gd_private.booking_notifications from public,anon,authenticated;
-- Capacity is calculated for every half-hour within the entire seating duration.
-- Pending future requests temporarily hold capacity; external bookings are blocked covers.
create or replace function gd_private.booking_remaining(p_venue uuid,p_start timestamptz,p_exclude uuid default null)
returns integer language plpgsql stable security invoker set search_path='' as $$
declare s gd_private.booking_settings%rowtype; local_start timestamp; local_end timestamp; d date; blocked integer; peak integer;
begin
 select * into s from gd_private.booking_settings where restaurant_id=p_venue;
 if not found or not s.enabled or s.capacity=0 then return 0; end if;
 local_start:=p_start at time zone 'Europe/Rome';local_end:=(p_start+make_interval(mins=>s.duration_minutes)) at time zone 'Europe/Rome';d:=local_start::date;
 if local_end::date<>d or extract(minute from local_start)::integer%30<>0 or extract(second from local_start)<>0 then return 0; end if;
 if not exists(select 1 from jsonb_array_elements(s.service_windows) w where (w->>'day')::integer=extract(isodow from d)::integer and local_start::time >= (w->>'from')::time and local_end::time <= (w->>'to')::time) then return 0; end if;
 if exists(select 1 from gd_private.booking_day_overrides x where x.restaurant_id=p_venue and x.day=d and x.closed) then return 0; end if;
 select coalesce((select blocked_covers from gd_private.booking_day_overrides where restaurant_id=p_venue and day=d),0) into blocked;
 select coalesce(max(used),0)::integer into peak from (
  select coalesce(sum(b.party),0) as used from generate_series(p_start,p_start+make_interval(mins=>s.duration_minutes)-interval '30 minutes',interval '30 minutes') slot
  left join gd_private.bookings b on b.restaurant_id=p_venue and b.id is distinct from p_exclude
  and (b.status='confirmed' or (b.status='pending' and b.starts_at>now()))
  and b.starts_at<slot+interval '30 minutes' and b.starts_at+make_interval(mins=>b.seating_minutes)>slot group by slot
 ) q;
 return greatest(0,s.capacity-blocked-peak);
end $$;
alter table gd_private.bookings add column seating_minutes integer not null default 90 check(seating_minutes between 30 and 240 and seating_minutes%30=0);
revoke all on function gd_private.booking_remaining(uuid,timestamptz,uuid) from public,anon,authenticated;
create or replace function gd_private.booking_capacity_guard()
returns trigger language plpgsql security definer set search_path='' as $$
declare s gd_private.booking_settings%rowtype;
begin
 if tg_op='INSERT' or (new.status='confirmed' and old.status='pending') then
  select * into s from gd_private.booking_settings where restaurant_id=new.restaurant_id for update;
  if not found or new.party>s.max_party or gd_private.booking_remaining(new.restaurant_id,new.starts_at,new.id)<new.party then raise exception 'BOOKING_SLOT_FULL'; end if;
  if tg_op='INSERT' then new.seating_minutes:=s.duration_minutes; end if;
 end if;
 return new;
end $$;
revoke all on function gd_private.booking_capacity_guard() from public,anon,authenticated;
create trigger gd_booking_capacity_guard before insert or update of status on gd_private.bookings for each row execute function gd_private.booking_capacity_guard();
create or replace function gd_private.booking_notice_trigger()
returns trigger language plpgsql security definer set search_path='' as $$
declare owner uuid;
begin
 if tg_op='UPDATE' and old.status=new.status then return new; end if;
 select owner_id into owner from public.restaurants where id=new.restaurant_id;
 if new.status<>'pending' then insert into gd_private.booking_notifications(recipient_id,booking_id,kind) values(new.customer_id,new.id,new.status); end if;
 if new.status in ('pending','cancelled','expired') and owner is not null then insert into gd_private.booking_notifications(recipient_id,booking_id,kind) values(owner,new.id,new.status); end if;
 return new;
end $$;
revoke all on function gd_private.booking_notice_trigger() from public,anon,authenticated;
create trigger gd_booking_notice_trigger after insert or update of status on gd_private.bookings for each row execute function gd_private.booking_notice_trigger();
create or replace function gd_private.booking_schedule(p_action text,p_payload jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); venue uuid; s gd_private.booking_settings%rowtype; d date; cap integer; dur integer; windows jsonb; w jsonb; n integer; blocked integer; close_day boolean; party_size integer; result jsonb;
begin
 if actor is null or not gd_private.current_user_email_confirmed() or not exists(select 1 from public.profiles where id=actor) then raise exception 'BOOKING_LOGIN_REQUIRED'; end if;
 if p_action in ('schedule_get','schedule_set','override_set','override_delete') then
  venue:=(p_payload->>'restaurant_id')::uuid;perform gd_private.assert_merchant_access(venue,actor);
  insert into gd_private.booking_settings(restaurant_id) values(venue) on conflict do nothing;
  select * into s from gd_private.booking_settings where restaurant_id=venue for update;
  if p_action='schedule_set' then
   cap:=(p_payload->>'capacity')::integer;dur:=(p_payload->>'duration')::integer;windows:=p_payload->'windows';
   if cap is null or cap not between 1 and 500 or dur is null or dur not between 30 and 240 or dur%30<>0 or windows is null or jsonb_typeof(windows)<>'array' or jsonb_array_length(windows)>14 then raise exception 'SCHEDULE_INVALID';end if;
   for w in select * from jsonb_array_elements(windows) loop
    if coalesce(w->>'day','') !~ '^[1-7]$' or coalesce(w->>'from','') !~ '^([01][0-9]|2[0-3]):(00|30)$' or coalesce(w->>'to','') !~ '^([01][0-9]|2[0-3]):(00|30)$' or (w->>'to')::time-(w->>'from')::time<make_interval(mins=>dur) then raise exception 'SCHEDULE_INVALID';end if;
   end loop;
   if exists(select 1 from jsonb_array_elements(windows) with ordinality a(w,i) join jsonb_array_elements(windows) with ordinality b(w,i) on a.i<b.i and a.w->>'day'=b.w->>'day' and (a.w->>'from')::time<(b.w->>'to')::time and (b.w->>'from')::time<(a.w->>'to')::time) then raise exception 'SCHEDULE_INVALID';end if;
   update gd_private.booking_settings set capacity=cap,duration_minutes=dur,service_windows=windows,updated_at=now() where restaurant_id=venue;
  elsif p_action in ('override_set','override_delete') then
   d:=(p_payload->>'day')::date;
   if d is null or d<(now() at time zone 'Europe/Rome')::date or d>(now() at time zone 'Europe/Rome')::date+90 then raise exception 'SCHEDULE_INVALID';end if;
   if p_action='override_delete' then delete from gd_private.booking_day_overrides where restaurant_id=venue and day=d;
   else blocked:=(p_payload->>'blocked')::integer;close_day:=(p_payload->>'closed')::boolean;
    if blocked is null or blocked not between 0 and 500 or close_day is null then raise exception 'SCHEDULE_INVALID';end if;
    insert into gd_private.booking_day_overrides(restaurant_id,day,closed,blocked_covers) values(venue,d,close_day,blocked) on conflict(restaurant_id,day) do update set closed=excluded.closed,blocked_covers=excluded.blocked_covers;
   end if;
  end if;
  select * into s from gd_private.booking_settings where restaurant_id=venue;
  return jsonb_build_object('capacity',s.capacity,'duration',s.duration_minutes,'windows',s.service_windows,'overrides',(select coalesce(jsonb_agg(jsonb_build_object('day',x.day,'closed',x.closed,'blocked',x.blocked_covers) order by x.day),'[]'::jsonb) from gd_private.booking_day_overrides x where x.restaurant_id=venue and x.day>=(now() at time zone 'Europe/Rome')::date));
 elsif p_action='slots' then
  venue:=(p_payload->>'restaurant_id')::uuid;d:=(p_payload->>'day')::date;party_size:=(p_payload->>'party')::integer;
  if d is null or d<(now() at time zone 'Europe/Rome')::date or d>(now() at time zone 'Europe/Rome')::date+90 or party_size is null or party_size not between 1 and 30 then raise exception 'SCHEDULE_INVALID';end if;
  select bs.* into s from gd_private.booking_settings bs join public.restaurants r on r.id=bs.restaurant_id join gd_private.merchant_licenses l on l.restaurant_id=r.id where bs.restaurant_id=venue and bs.enabled and r.verified_at is not null and r.suspended_at is null and l.status in ('trialing','active') and l.active_until>now() and r.owner_id<>actor;
  if not found or party_size>s.max_party then return '[]'::jsonb;end if;
  return (select coalesce(jsonb_agg(jsonb_build_object('starts_at',q.t,'label',to_char(q.t at time zone 'Europe/Rome','HH24:MI'),'remaining',q.remaining) order by q.t),'[]'::jsonb) from (
   select t,gd_private.booking_remaining(venue,t,null) remaining from generate_series(d::timestamp at time zone 'Europe/Rome',(d+1)::timestamp at time zone 'Europe/Rome'-interval '30 minutes',interval '30 minutes') t where t>=now()+interval '15 minutes' and t<=now()+interval '90 days'
  ) q where q.remaining>=party_size);
 elsif p_action='notices' then
  return jsonb_build_object('unread',(select count(*) from gd_private.booking_notifications where recipient_id=actor and read_at is null),'items',(select coalesce(jsonb_agg(to_jsonb(q) order by q.created_at desc),'[]'::jsonb) from (select n.id,n.kind,n.created_at,n.read_at,b.starts_at,b.party,r.name as restaurant_name from gd_private.booking_notifications n join gd_private.bookings b on b.id=n.booking_id join public.restaurants r on r.id=b.restaurant_id where n.recipient_id=actor order by n.created_at desc limit 50) q),'reminders',(select coalesce(jsonb_agg(jsonb_build_object('id',b.id,'restaurant_name',r.name,'starts_at',b.starts_at,'party',b.party) order by b.starts_at),'[]'::jsonb) from gd_private.bookings b join public.restaurants r on r.id=b.restaurant_id where b.customer_id=actor and b.status='confirmed' and b.starts_at between now() and now()+interval '24 hours'));
 elsif p_action='notices_read' then
  update gd_private.booking_notifications set read_at=now() where recipient_id=actor and read_at is null;return '{"ok":true}'::jsonb;
 elsif p_action='studio_stats' then
  if not exists(select 1 from gd_studio_private.operators where user_id=actor) then raise exception 'STUDIO_ACCESS_DENIED';end if;
  return jsonb_build_object('total',(select count(*) from gd_private.bookings),'pending',(select count(*) from gd_private.bookings where status='pending' and starts_at>now()),'confirmed',(select count(*) from gd_private.bookings where status='confirmed' and starts_at>now()),'completed',(select count(*) from gd_private.bookings where status='completed'),'no_show',(select count(*) from gd_private.bookings where status='no_show'),'discounted',(select count(*) from gd_private.bookings where discount_percent is not null),'covers',(select coalesce(sum(party),0) from gd_private.bookings where status='confirmed' and starts_at>now()),'venues',(select count(*) from gd_private.booking_settings where enabled and capacity>0));
 else raise exception 'BOOKING_INVALID';end if;
end $$;
revoke all on function gd_private.booking_schedule(text,jsonb) from public,anon,authenticated;
grant execute on function gd_private.booking_schedule(text,jsonb) to authenticated;
create or replace function public.gooddiner_booking_schedule(p_action text,p_payload jsonb default '{}'::jsonb)
returns jsonb language sql security invoker set search_path='' as $$select gd_private.booking_schedule(p_action,p_payload)$$;
revoke all on function public.gooddiner_booking_schedule(text,jsonb) from public,anon,authenticated;
grant execute on function public.gooddiner_booking_schedule(text,jsonb) to authenticated;