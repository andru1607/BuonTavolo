create or replace function gd_private.room_arrival_guard()
returns trigger language plpgsql security invoker set search_path='' as $$
begin
 if old.arrived_at is not null and new.status in ('no_show','cancelled','rejected','expired') and new.status is distinct from old.status then raise exception 'ROOM_ALREADY_ARRIVED';end if;
 return new;
end $$;
revoke all on function gd_private.room_arrival_guard() from public,anon,authenticated;
create trigger gd_room_arrival_guard before update of status on gd_private.bookings for each row execute function gd_private.room_arrival_guard();