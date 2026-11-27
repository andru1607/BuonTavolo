-- Independent online pause and optional room management; existing bookings and table assignments preserved.
alter table gd_private.booking_settings add column if not exists online_paused boolean not null default false, add column if not exists room_enabled boolean not null default false;
update gd_private.booking_settings s set room_enabled=true where exists(select 1 from gd_private.room_tables t where t.restaurant_id=s.restaurant_id and t.active) or s.auto_confirm;
CREATE OR REPLACE FUNCTION gd_private.booking_action(p_action text, p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare actor uuid:=auth.uid(); venue uuid; bid uuid; vid uuid; start_at timestamptz; size integer; nm text; pct integer; v public.vouchers%rowtype; b gd_private.bookings%rowtype; settings gd_private.booking_settings%rowtype; active boolean; next_status text; mode text;
begin
 if actor is null or not gd_private.current_user_email_confirmed() or not exists(select 1 from public.profiles where id=actor) then raise exception 'BOOKING_LOGIN_REQUIRED'; end if;
 select personal_reviews_enabled and rewards_enabled into active from gd_private.business_features where singleton;
 if p_action in ('settings_get','settings_set','pause_set','room_set') then
  venue:=(p_payload->>'restaurant_id')::uuid;
  perform gd_private.assert_merchant_access(venue,actor);
  if p_action='settings_set' then
   size:=(p_payload->>'max_party')::integer;
   if size is null or size not between 1 and 30 or p_payload->>'enabled' is null then raise exception 'BOOKING_INVALID'; end if;
   insert into gd_private.booking_settings(restaurant_id,enabled,max_party) values(venue,(p_payload->>'enabled')::boolean,size)
   on conflict(restaurant_id) do update set enabled=excluded.enabled,max_party=excluded.max_party,updated_at=now();
  elsif p_action in ('pause_set','room_set') then
   if jsonb_typeof(p_payload->'enabled') is distinct from 'boolean' then raise exception 'BOOKING_INVALID';end if;
   perform 1 from public.restaurants where id=venue for update;
   insert into gd_private.booking_settings(restaurant_id) values(venue) on conflict do nothing;
   if p_action='pause_set' then update gd_private.booking_settings set online_paused=(p_payload->>'enabled')::boolean,updated_at=now() where restaurant_id=venue;
   else update gd_private.booking_settings set room_enabled=(p_payload->>'enabled')::boolean,auto_confirm=case when (p_payload->>'enabled')::boolean then auto_confirm else false end,updated_at=now() where restaurant_id=venue;end if;
  end if;
  return coalesce((select jsonb_build_object('enabled',enabled,'max_party',max_party,'online_paused',online_paused,'room_enabled',room_enabled) from gd_private.booking_settings where restaurant_id=venue),'{"enabled":false,"max_party":30,"online_paused":false,"room_enabled":false}'::jsonb);
 elsif p_action='catalog' then
  return (select coalesce(jsonb_agg(jsonb_build_object('id',r.id,'name',r.name,'city',r.city,'address',loc.address,'max_party',s.max_party,'percent',case when active and o.enabled then o.percent else null end) order by r.name),'[]'::jsonb)
   from public.restaurants r join gd_private.booking_settings s on s.restaurant_id=r.id join gd_private.merchant_licenses l on l.restaurant_id=r.id
   left join gd_private.reward_offers o on o.restaurant_id=r.id left join gd_private.reward_locations loc on loc.restaurant_id=r.id
   where s.enabled and not s.online_paused and s.capacity>0 and jsonb_array_length(s.service_windows)>0 and r.verified_at is not null and r.suspended_at is null and l.status in ('trialing','active') and l.active_until>now() and r.owner_id<>actor);
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
  select s.* into settings from gd_private.booking_settings s join public.restaurants r on r.id=s.restaurant_id join gd_private.merchant_licenses l on l.restaurant_id=r.id where s.restaurant_id=venue and s.enabled and not s.online_paused and r.verified_at is not null and r.suspended_at is null and l.status in ('trialing','active') and l.active_until>now() and r.owner_id<>actor;
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
end $function$;

CREATE OR REPLACE FUNCTION gd_private.booking_capacity_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare s gd_private.booking_settings%rowtype;
begin
 -- Mandatory confirmation policy for new online bookings; manual entries unchanged.
 if tg_op='INSERT' and new.source='online' then
  new.status:=case when new.party<=8 then 'confirmed' else 'pending' end;
 end if;
 if tg_op='INSERT' or (new.status='confirmed' and old.status='pending') or (new.status in ('pending','confirmed') and (new.starts_at is distinct from old.starts_at or new.party is distinct from old.party)) then
 select * into s from gd_private.booking_settings where restaurant_id=new.restaurant_id for update;
 if tg_op='INSERT' and new.source='online' and s.online_paused then raise exception 'BOOKING_UNAVAILABLE';end if;
 if not found or new.party>s.max_party or gd_private.booking_remaining(new.restaurant_id,new.starts_at,new.id)<new.party then raise exception 'BOOKING_SLOT_FULL';end if;
 if tg_op='INSERT' then new.seating_minutes:=s.duration_minutes;end if;
 end if;return new;
end $function$;

CREATE OR REPLACE FUNCTION gd_private.booking_schedule(p_action text, p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
  select bs.* into s from gd_private.booking_settings bs join public.restaurants r on r.id=bs.restaurant_id join gd_private.merchant_licenses l on l.restaurant_id=r.id where bs.restaurant_id=venue and bs.enabled and not bs.online_paused and r.verified_at is not null and r.suspended_at is null and l.status in ('trialing','active') and l.active_until>now() and r.owner_id<>actor;
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
end $function$;

CREATE OR REPLACE FUNCTION gd_private.booking_try_auto()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare tid uuid;
begin
 if new.source<>'online' or new.status<>'confirmed' or new.party>8 or not exists(select 1 from gd_private.booking_settings where restaurant_id=new.restaurant_id and room_enabled and auto_confirm) then return new;end if;
 perform 1 from public.restaurants where id=new.restaurant_id for update;
 -- Unallocated overlapping parties may still need any of the remaining tables.
 if exists(select 1 from gd_private.bookings b where b.restaurant_id=new.restaurant_id and b.id<>new.id and (b.status='confirmed' or (b.status='pending' and b.starts_at>now())) and b.starts_at<new.starts_at+make_interval(mins=>new.seating_minutes) and b.starts_at+make_interval(mins=>b.seating_minutes)>new.starts_at and not exists(select 1 from gd_private.room_assignments a where a.booking_id=b.id)) then return new;end if;
 select t.id into tid from gd_private.room_tables t where t.restaurant_id=new.restaurant_id and t.active and t.seats>=new.party and gd_private.room_table_free(t.id,new.id,new.starts_at,new.starts_at+make_interval(mins=>new.seating_minutes)) order by t.seats,t.label limit 1;
 if found then
  insert into gd_private.room_assignments(booking_id,table_id) values(new.id,tid);
  -- Confirmation is independent of assignment; do not change booking status.
 end if;return new;
end $function$;

CREATE OR REPLACE FUNCTION gd_private.manager_insights(p_action text, p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare actor uuid:=auth.uid(); venue uuid; w gd_private.online_waitlist%rowtype; wid uuid; d date; d2 date; n integer; nm text; st timestamptz; res jsonb;
begin
 if actor is null or not gd_private.current_user_email_confirmed() or not exists(select 1 from public.profiles where id=actor) then raise exception 'BOOKING_LOGIN_REQUIRED';end if;
 venue:=nullif(p_payload->>'restaurant_id','')::uuid;
 if p_action in ('merchant_list','offer','merchant_cancel','report') then perform gd_private.assert_merchant_access(venue,actor);end if;
 if p_action='join' then
  d:=(p_payload->>'day')::date;n:=(p_payload->>'party')::int;nm:=btrim(p_payload->>'name');
  if d is null or d<(now() at time zone 'Europe/Rome')::date or d>(now() at time zone 'Europe/Rome')::date+90 or n is null or n not between 1 and 30 or nm is null or char_length(nm) not between 2 and 80 then raise exception 'WAIT_INVALID';end if;
  perform 1 from public.profiles where id=actor for update;
  if not exists(select 1 from gd_private.booking_settings s join public.restaurants r on r.id=s.restaurant_id join gd_private.merchant_licenses l on l.restaurant_id=r.id where s.restaurant_id=venue and s.enabled and not s.online_paused and s.capacity>0 and n<=s.max_party and r.owner_id<>actor and r.verified_at is not null and r.suspended_at is null and l.status in ('active','trialing') and l.active_until>now()) then raise exception 'WAIT_INVALID';end if;
  update gd_private.online_waitlist set status='expired' where customer_id=actor and status in ('waiting','offered') and (desired_day<(now() at time zone 'Europe/Rome')::date or (status='offered' and offer_expires_at<=now()));
  if (select count(*) from gd_private.online_waitlist where customer_id=actor and status in ('waiting','offered'))>=10 then raise exception 'WAIT_LIMIT';end if;
  insert into gd_private.online_waitlist(restaurant_id,customer_id,booking_name,desired_day,party) values(venue,actor,nm,d,n);
 elsif p_action in ('offer','merchant_cancel','cancel','accept') then
  wid:=(p_payload->>'id')::uuid;
  if p_action='accept' then perform 1 from public.profiles where id=actor for update;end if;
  select * into w from gd_private.online_waitlist where id=wid and ((p_action in ('offer','merchant_cancel') and restaurant_id=venue) or (p_action in ('cancel','accept') and customer_id=actor)) for update;
  if not found or w.status not in ('waiting','offered') then raise exception 'WAIT_INVALID';end if;
  if p_action='offer' then
   st:=(p_payload->>'starts_at')::timestamptz;
   if exists(select 1 from gd_private.booking_settings where restaurant_id=venue and online_paused) or st is null or st<now()+interval '15 minutes' or st>now()+interval '90 days' or gd_private.booking_remaining(venue,st,null)<w.party then raise exception 'BOOKING_SLOT_FULL';end if;
   update gd_private.online_waitlist set status='offered',offered_at=st,offer_expires_at=least(now()+interval '2 hours',st-interval '15 minutes') where id=wid;
  elsif p_action='accept' then
   if w.status<>'offered' or w.offer_expires_at<=now() then raise exception 'WAIT_INVALID';end if;
   res:=gd_private.booking_action('create',jsonb_build_object('restaurant_id',w.restaurant_id,'starts_at',w.offered_at,'party',w.party,'name',w.booking_name,'voucher_id',p_payload->>'voucher_id','percent',p_payload->>'percent'));
   update gd_private.online_waitlist set status='booked',booking_id=(res->>'id')::uuid where id=wid;
   return res;
  else update gd_private.online_waitlist set status='cancelled' where id=wid;end if;
 elsif p_action='report' then
  d:=(p_payload->>'from')::date;d2:=(p_payload->>'to')::date;
  if d is null or d2 is null or d2<d or d2-d>366 then raise exception 'WAIT_INVALID';end if;
  return (select jsonb_build_object('total',count(*),'pending',count(*) filter(where status='pending' and starts_at>now()),'confirmed',count(*) filter(where status='confirmed'),'completed',count(*) filter(where status='completed'),'cancelled',count(*) filter(where status='cancelled'),'rejected',count(*) filter(where status='rejected'),'no_show',count(*) filter(where status='no_show'),'covers',coalesce(sum(party) filter(where status='completed'),0),'discounted',count(*) filter(where discount_percent is not null),'redeemed',count(*) filter(where status='completed' and voucher_id is not null and exists(select 1 from public.vouchers v where v.id=b.voucher_id and v.status='redeemed')),'online',count(*) filter(where source='online'),'phone',count(*) filter(where source='phone'),'walk_in',count(*) filter(where source='walk_in'),'waitlist',count(*) filter(where source='waitlist')) from gd_private.bookings b where restaurant_id=venue and starts_at>=d::timestamp at time zone 'Europe/Rome' and starts_at<(d2+1)::timestamp at time zone 'Europe/Rome');
 elsif p_action not in ('customer_list','merchant_list') then raise exception 'WAIT_INVALID';end if;
 if p_action in ('merchant_list','offer','merchant_cancel') then
  return (select coalesce(jsonb_agg(to_jsonb(q) order by q.created_at),'[]'::jsonb) from (select id,booking_name,desired_day,party,status,offered_at,offer_expires_at,created_at from gd_private.online_waitlist where restaurant_id=venue and status in ('waiting','offered') and desired_day>=(now() at time zone 'Europe/Rome')::date order by created_at limit 200) q);
 end if;
 return (select coalesce(jsonb_agg(to_jsonb(q) order by q.created_at desc),'[]'::jsonb) from (select a.id,a.restaurant_id,r.name as restaurant_name,a.desired_day,a.party,a.status,a.offered_at,a.offer_expires_at,a.created_at from gd_private.online_waitlist a join public.restaurants r on r.id=a.restaurant_id where a.customer_id=actor order by a.created_at desc limit 50) q);
end $function$;

CREATE OR REPLACE FUNCTION gd_private.manager_register(p_action text, p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare actor uuid:=auth.uid();venue uuid:=(p_payload->>'restaurant_id')::uuid;b gd_private.bookings%rowtype;w gd_private.booking_waitlist%rowtype;bid uuid;wid uuid;nm text;src text;st timestamptz;n integer;flag boolean;
begin
 if actor is null or not gd_private.current_user_email_confirmed() then raise exception 'BOOKING_LOGIN_REQUIRED';end if;
 perform gd_private.assert_merchant_access(venue,actor);
 perform 1 from public.restaurants where id=venue for update;
 if p_action='auto_set' then
 flag:=(p_payload->>'enabled')::boolean;if flag is null then raise exception 'BOOKING_INVALID';end if;
 if flag and (not exists(select 1 from gd_private.booking_settings where restaurant_id=venue and room_enabled) or not exists(select 1 from gd_private.room_tables where restaurant_id=venue and active)) then raise exception 'ROOM_ASSIGN_FIRST';end if;
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
end $function$;

CREATE OR REPLACE FUNCTION gd_private.room_action(p_action text, p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare actor uuid:=auth.uid(); venue uuid:=(p_payload->>'restaurant_id')::uuid; tid uuid; bid uuid; b gd_private.bookings%rowtype; t gd_private.room_tables%rowtype; ids uuid[]; chosen uuid; total integer; nm text; zn text; px integer; py integer; cnt integer; d date; active_flag boolean;
begin
 if actor is null or not gd_private.current_user_email_confirmed() then raise exception 'BOOKING_LOGIN_REQUIRED'; end if;
 perform gd_private.assert_merchant_access(venue,actor);
 -- All table edits and assignments serialized per restaurant.
 perform 1 from public.restaurants where id=venue for update;
 if p_action not in ('arrive','list') and not exists(select 1 from gd_private.booking_settings where restaurant_id=venue and room_enabled) then raise exception 'ROOM_DISABLED';end if;
 if p_action='table_save' then
  tid:=nullif(p_payload->>'id','')::uuid;nm:=btrim(p_payload->>'label');zn:=btrim(p_payload->>'zone');cnt:=(p_payload->>'seats')::integer;px:=(p_payload->>'x')::integer;py:=(p_payload->>'y')::integer;
  if nm is null or zn is null or char_length(nm) not between 1 and 30 or char_length(zn) not between 1 and 60 or cnt is null or cnt not between 1 and 30 or px is null or px not between 1 and 12 or py is null or py not between 1 and 20 then raise exception 'ROOM_INVALID'; end if;
  if tid is null then
   if (select count(*) from gd_private.room_tables where restaurant_id=venue)>=250 then raise exception 'ROOM_LIMIT';end if;
   insert into gd_private.room_tables(restaurant_id,label,zone,seats,pos_x,pos_y) values(venue,nm,zn,cnt,px,py);
  else
   select * into t from gd_private.room_tables where id=tid and restaurant_id=venue;
   if not found then raise exception 'ROOM_INVALID';end if;
   if cnt<>t.seats and exists(select 1 from gd_private.room_assignments a join gd_private.bookings bk on bk.id=a.booking_id where a.table_id=tid and bk.status in ('pending','confirmed')) then raise exception 'ROOM_TABLE_ASSIGNED';end if;
   update gd_private.room_tables set label=nm,zone=zn,seats=cnt,pos_x=px,pos_y=py where id=tid and restaurant_id=venue;
  end if;
 elsif p_action='table_active' then
  tid:=(p_payload->>'id')::uuid;active_flag:=(p_payload->>'active')::boolean;
  if active_flag is null or not exists(select 1 from gd_private.room_tables where id=tid and restaurant_id=venue) then raise exception 'ROOM_INVALID';end if;
  if not active_flag and exists(select 1 from gd_private.room_assignments a join gd_private.bookings bk on bk.id=a.booking_id where a.table_id=tid and bk.status in ('pending','confirmed')) then raise exception 'ROOM_TABLE_ASSIGNED';end if;
  update gd_private.room_tables set active=active_flag where id=tid and restaurant_id=venue;
 elsif p_action in ('assign','auto_assign','unassign','arrive') then
  bid:=(p_payload->>'booking_id')::uuid;
  select * into b from gd_private.bookings where id=bid and restaurant_id=venue for update;
  if not found or b.status not in ('pending','confirmed') then raise exception 'ROOM_BOOKING_INVALID';end if;
  if p_action='arrive' then
   if b.status<>'confirmed' or (b.starts_at at time zone 'Europe/Rome')::date<>(now() at time zone 'Europe/Rome')::date or b.starts_at>now()+interval '2 hours' then raise exception 'ROOM_BOOKING_INVALID';end if;
   -- An arrival never requires a physical table assignment.
   if exists(select 1 from gd_private.room_assignments a join gd_private.room_assignments aa on aa.table_id=a.table_id and aa.booking_id<>bid join gd_private.bookings bb on bb.id=aa.booking_id where a.booking_id=bid and bb.status='confirmed' and bb.arrived_at is not null) then raise exception 'ROOM_TABLE_BUSY';end if;
   update gd_private.bookings set arrived_at=coalesce(arrived_at,now()),updated_at=now() where id=bid;
  elsif p_action='unassign' then
   if b.arrived_at is not null then raise exception 'ROOM_BOOKING_INVALID';end if;
   delete from gd_private.room_assignments where booking_id=bid;
  else
   if b.arrived_at is not null then raise exception 'ROOM_BOOKING_INVALID';end if;
   if p_action='auto_assign' then
    select tt.id into chosen from gd_private.room_tables tt where tt.restaurant_id=venue and tt.active and tt.seats>=b.party and gd_private.room_table_free(tt.id,b.id,b.starts_at,b.starts_at+make_interval(mins=>b.seating_minutes)) order by tt.seats,tt.zone,tt.label limit 1;
    if not found then raise exception 'ROOM_TABLE_BUSY';end if;ids:=array[chosen];
   else
    if jsonb_typeof(p_payload->'table_ids') is distinct from 'array' or jsonb_array_length(p_payload->'table_ids') not between 1 and 10 then raise exception 'ROOM_INVALID';end if;
    select array_agg(distinct x::uuid) into ids from jsonb_array_elements_text(p_payload->'table_ids') x;
   end if;
   select count(*),coalesce(sum(seats),0) into cnt,total from gd_private.room_tables where restaurant_id=venue and active and id=any(ids);
   if cnt<>cardinality(ids) or total<b.party then raise exception 'ROOM_CAPACITY';end if;
   if exists(select 1 from unnest(ids) x where not gd_private.room_table_free(x,b.id,b.starts_at,b.starts_at+make_interval(mins=>b.seating_minutes))) then raise exception 'ROOM_TABLE_BUSY';end if;
   delete from gd_private.room_assignments where booking_id=bid;
   insert into gd_private.room_assignments(booking_id,table_id) select bid,x from unnest(ids) x;
  end if;
 elsif p_action<>'list' then raise exception 'ROOM_INVALID';end if;
 d:=coalesce(nullif(p_payload->>'day','')::date,(now() at time zone 'Europe/Rome')::date);
 return jsonb_build_object('tables',(select coalesce(jsonb_agg(to_jsonb(q) order by q.zone,q.label),'[]'::jsonb) from (select id,label,zone,seats,pos_x,pos_y,active from gd_private.room_tables where restaurant_id=venue) q),
 'bookings',(select coalesce(jsonb_agg(to_jsonb(q) order by q.starts_at),'[]'::jsonb) from (
 select bk.id,bk.booking_name,bk.starts_at,bk.party,bk.status,bk.seating_minutes,bk.arrived_at,bk.discount_percent,
 (select coalesce(jsonb_agg(a.table_id),'[]'::jsonb) from gd_private.room_assignments a where a.booking_id=bk.id) as table_ids
 from gd_private.bookings bk where bk.restaurant_id=venue and ((bk.starts_at at time zone 'Europe/Rome')::date=d or (bk.status='confirmed' and bk.arrived_at is not null)) and bk.status in ('pending','confirmed','completed','no_show','cancelled','rejected','expired')
 ) q));
end $function$;

CREATE OR REPLACE FUNCTION public.marketing_directory(p_query text DEFAULT ''::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 if auth.uid() is null then raise exception 'LOGIN_RICHIESTO';end if;
 return coalesce((select jsonb_agg(jsonb_build_object('id',x.id,'name',x.name,'city',x.city,'booking_available',exists(select 1 from gd_private.booking_settings s join gd_private.merchant_licenses l on l.restaurant_id=s.restaurant_id where s.restaurant_id=x.id and s.enabled and not s.online_paused and s.capacity>0 and jsonb_array_length(s.service_windows)>0 and l.status in ('trialing','active') and l.active_until>now()),'level',gd_private.marketing_level(gd_private.marketing_qualified(x.id)),'founder_number',(select founder_number from gd_private.marketing_founders where restaurant_id=x.id)) order by x.name,x.id) from (select r.id,r.name,r.city from public.restaurants r join gd_private.marketing_public_cards c on c.restaurant_id=r.id and c.published where r.verified_at is not null and r.suspended_at is null and (position(lower(left(coalesce(p_query,''),100)) in lower(r.name||' '||r.city))>0 or coalesce(p_query,'')='') order by r.name,r.id limit 100) x),'[]'::jsonb);
end $function$;
