-- Sala digitale: tavoli per zona, coordinate su griglia, assegnazioni multiple.
create table gd_private.room_tables(
 id uuid primary key default gen_random_uuid(),
 restaurant_id uuid not null references public.restaurants(id) on delete cascade,
 label text not null check(char_length(btrim(label)) between 1 and 30),
 zone text not null check(char_length(btrim(zone)) between 1 and 60),
 seats integer not null check(seats between 1 and 30),
 pos_x integer not null check(pos_x between 1 and 12),
 pos_y integer not null check(pos_y between 1 and 20),
 active boolean not null default true,
 unique(restaurant_id,label)
);
create unique index gd_room_table_position on gd_private.room_tables(restaurant_id,lower(zone),pos_x,pos_y) where active;
alter table gd_private.room_tables enable row level security;
revoke all on gd_private.room_tables from public,anon,authenticated;
create table gd_private.room_assignments(
 booking_id uuid not null references gd_private.bookings(id) on delete cascade,
 table_id uuid not null references gd_private.room_tables(id),
 primary key(booking_id,table_id)
);
create index gd_room_assignment_table on gd_private.room_assignments(table_id);
alter table gd_private.room_assignments enable row level security;
revoke all on gd_private.room_assignments from public,anon,authenticated;
alter table gd_private.bookings add column arrived_at timestamptz;
-- Lock venue before any allocation/arrival change. Prevent direct API bypass.
create or replace function gd_private.room_table_free(p_table uuid,p_booking uuid,p_start timestamptz,p_end timestamptz)
returns boolean language sql stable security invoker set search_path='' as $$
 select not exists(select 1 from gd_private.room_assignments a join gd_private.bookings b on b.id=a.booking_id
 where a.table_id=p_table and b.id is distinct from p_booking and b.status in ('pending','confirmed')
 and ((b.starts_at<p_end and b.starts_at+make_interval(mins=>b.seating_minutes)>p_start)
 or (b.arrived_at is not null and p_start<=now() and p_end>now())))
$$;
revoke all on function gd_private.room_table_free(uuid,uuid,timestamptz,timestamptz) from public,anon,authenticated;
create or replace function gd_private.room_action(p_action text,p_payload jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); venue uuid:=(p_payload->>'restaurant_id')::uuid; tid uuid; bid uuid; b gd_private.bookings%rowtype; t gd_private.room_tables%rowtype; ids uuid[]; chosen uuid; total integer; nm text; zn text; px integer; py integer; cnt integer; d date; active_flag boolean;
begin
 if actor is null or not gd_private.current_user_email_confirmed() then raise exception 'BOOKING_LOGIN_REQUIRED'; end if;
 perform gd_private.assert_merchant_access(venue,actor);
 -- All table edits and assignments serialized per restaurant.
 perform 1 from public.restaurants where id=venue for update;
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
   if not exists(select 1 from gd_private.room_assignments where booking_id=bid) then raise exception 'ROOM_ASSIGN_FIRST';end if;
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
end $$;
revoke all on function gd_private.room_action(text,jsonb) from public,anon,authenticated;
grant execute on function gd_private.room_action(text,jsonb) to authenticated;
create or replace function public.gooddiner_room(p_action text,p_payload jsonb default '{}'::jsonb)
returns jsonb language sql security invoker set search_path='' as $$select gd_private.room_action(p_action,p_payload)$$;
revoke all on function public.gooddiner_room(text,jsonb) from public,anon,authenticated;
grant execute on function public.gooddiner_room(text,jsonb) to authenticated;