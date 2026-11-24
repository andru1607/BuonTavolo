create or replace function gd_private.booking_try_auto() returns trigger language plpgsql security definer set search_path='' as $$
declare tid uuid;
begin
 if new.source<>'online' or new.status<>'pending' or not exists(select 1 from gd_private.booking_settings where restaurant_id=new.restaurant_id and auto_confirm) then return new;end if;
 perform 1 from public.restaurants where id=new.restaurant_id for update;
 -- Unallocated overlapping parties may still need any of the remaining tables.
 if exists(select 1 from gd_private.bookings b where b.restaurant_id=new.restaurant_id and b.id<>new.id and (b.status='confirmed' or (b.status='pending' and b.starts_at>now())) and b.starts_at<new.starts_at+make_interval(mins=>new.seating_minutes) and b.starts_at+make_interval(mins=>b.seating_minutes)>new.starts_at and not exists(select 1 from gd_private.room_assignments a where a.booking_id=b.id)) then return new;end if;
 select t.id into tid from gd_private.room_tables t where t.restaurant_id=new.restaurant_id and t.active and t.seats>=new.party and gd_private.room_table_free(t.id,new.id,new.starts_at,new.starts_at+make_interval(mins=>new.seating_minutes)) order by t.seats,t.label limit 1;
 if found then
  insert into gd_private.room_assignments(booking_id,table_id) values(new.id,tid);
  update gd_private.bookings set status='confirmed',updated_at=now() where id=new.id;
 end if;return new;
end $$;
revoke all on function gd_private.booking_try_auto() from public,anon,authenticated;
