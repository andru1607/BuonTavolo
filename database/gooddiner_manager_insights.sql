create table gd_private.online_waitlist(
 id uuid primary key default gen_random_uuid(),restaurant_id uuid not null references public.restaurants(id),customer_id uuid not null references public.profiles(id) on delete cascade,
 booking_name text not null check(char_length(btrim(booking_name)) between 2 and 80),desired_day date not null,party integer not null check(party between 1 and 30),
 status text not null default 'waiting' check(status in ('waiting','offered','booked','cancelled','expired')),
 offered_at timestamptz,offer_expires_at timestamptz,booking_id uuid references gd_private.bookings(id) on delete set null,created_at timestamptz not null default now()
);
create unique index gd_online_wait_unique on gd_private.online_waitlist(customer_id,restaurant_id,desired_day) where status in ('waiting','offered');
alter table gd_private.online_waitlist enable row level security;
revoke all on gd_private.online_waitlist from public,anon,authenticated;
create or replace function gd_private.manager_insights(p_action text,p_payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); venue uuid; w gd_private.online_waitlist%rowtype; wid uuid; d date; d2 date; n integer; nm text; st timestamptz; res jsonb;
begin
 if actor is null or not gd_private.current_user_email_confirmed() or not exists(select 1 from public.profiles where id=actor) then raise exception 'BOOKING_LOGIN_REQUIRED';end if;
 venue:=nullif(p_payload->>'restaurant_id','')::uuid;
 if p_action in ('merchant_list','offer','merchant_cancel','report') then perform gd_private.assert_merchant_access(venue,actor);end if;
 if p_action='join' then
  d:=(p_payload->>'day')::date;n:=(p_payload->>'party')::int;nm:=btrim(p_payload->>'name');
  if d is null or d<(now() at time zone 'Europe/Rome')::date or d>(now() at time zone 'Europe/Rome')::date+90 or n is null or n not between 1 and 30 or nm is null or char_length(nm) not between 2 and 80 then raise exception 'WAIT_INVALID';end if;
  perform 1 from public.profiles where id=actor for update;
  if not exists(select 1 from gd_private.booking_settings s join public.restaurants r on r.id=s.restaurant_id join gd_private.merchant_licenses l on l.restaurant_id=r.id where s.restaurant_id=venue and s.enabled and s.capacity>0 and n<=s.max_party and r.owner_id<>actor and r.verified_at is not null and r.suspended_at is null and l.status in ('active','trialing') and l.active_until>now()) then raise exception 'WAIT_INVALID';end if;
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
   if st is null or st<now()+interval '15 minutes' or st>now()+interval '90 days' or gd_private.booking_remaining(venue,st,null)<w.party then raise exception 'BOOKING_SLOT_FULL';end if;
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
end $$;
revoke all on function gd_private.manager_insights(text,jsonb) from public,anon,authenticated;
grant execute on function gd_private.manager_insights(text,jsonb) to authenticated;
create or replace function public.gooddiner_manager_insights(p_action text,p_payload jsonb default '{}'::jsonb) returns jsonb language sql security invoker set search_path='' as $$select gd_private.manager_insights(p_action,p_payload)$$;
revoke all on function public.gooddiner_manager_insights(text,jsonb) from public,anon,authenticated;
grant execute on function public.gooddiner_manager_insights(text,jsonb) to authenticated;