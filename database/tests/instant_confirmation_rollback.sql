-- Run only on GoodDiner with the migration installed; the transaction rolls back all synthetic bookings.
begin;
do $qa$
declare v uuid; own uuid; cust uuid; d date; result jsonb; bid uuid; large_bid uuid; n int; t timestamptz;
begin
 select id,owner_id into strict v,own from public.restaurants where id='2c497189-d566-4d5c-83df-c325e85aae75';
 select p.id into strict cust from public.profiles p join auth.users a on a.id=p.id where a.email_confirmed_at is not null and not exists(select 1 from public.restaurants r where r.owner_id=p.id) limit 1;
 select day::date into strict d from generate_series((now() at time zone 'Europe/Rome')::date+10,(now() at time zone 'Europe/Rome')::date+60,interval '1 day') day where not exists(select 1 from gd_private.bookings b where b.restaurant_id=v and (b.starts_at at time zone 'Europe/Rome')::date=day::date) and not exists(select 1 from gd_private.booking_day_overrides o where o.restaurant_id=v and o.day=day::date) limit 1;
 update gd_private.booking_settings set enabled=true,capacity=18,duration_minutes=60,max_party=30,auto_confirm=false,service_windows=jsonb_build_array(jsonb_build_object('day',extract(isodow from d)::int,'from','11:00','to','14:00'),jsonb_build_object('day',extract(isodow from d)::int,'from','18:00','to','22:00')) where restaurant_id=v;
 perform set_config('request.jwt.claim.sub',cust::text,true);perform set_config('request.jwt.claims',jsonb_build_object('sub',cust,'role','authenticated')::text,true);
 for n in 1..3 loop
  t:=(d+case n when 1 then time '11:00' when 2 then time '12:00' else time '18:00' end) at time zone 'Europe/Rome';
  if n=3 then update gd_private.booking_settings set auto_confirm=true where restaurant_id=v;end if;
  result:=public.gooddiner_bookings('create',jsonb_build_object('restaurant_id',v,'name','QA rollback','starts_at',t,'party',case n when 1 then 1 when 2 then 8 else 9 end));
  bid:=(result->>'id')::uuid;
  if (result->>'status') is distinct from (case when n=3 then 'pending' else 'confirmed' end) then raise exception 'QA incorrect status %',result;end if;
  if not exists(select 1 from gd_private.booking_notifications where booking_id=bid and recipient_id=own and kind=(result->>'status')) then raise exception 'QA missing owner notification';end if;
  if n<3 and not exists(select 1 from gd_private.booking_notifications where booking_id=bid and recipient_id=cust and kind='confirmed') then raise exception 'QA missing customer notification';end if;
  if n=3 then large_bid:=bid;end if;
 end loop;
 result:=public.gooddiner_bookings('create',jsonb_build_object('restaurant_id',v,'name','QA rollback','starts_at',(d+time '18:30') at time zone 'Europe/Rome','party',8));
 if result->>'status'<>'confirmed' then raise exception 'QA auto flag changed policy';end if;
 begin
  perform public.gooddiner_bookings('create',jsonb_build_object('restaurant_id',v,'name','QA rollback','starts_at',(d+time '19:00') at time zone 'Europe/Rome','party',11));
  raise exception using errcode='P0003',message='QA capacity exceeded';
 exception when others then if sqlerrm<>'BOOKING_SLOT_FULL' then raise;end if;end;
 perform set_config('request.jwt.claim.sub',own::text,true);perform set_config('request.jwt.claims',jsonb_build_object('sub',own,'role','authenticated')::text,true);
 result:=public.gooddiner_bookings('confirm',jsonb_build_object('id',large_bid));
 if result->>'status'<>'confirmed' then raise exception 'QA merchant approval failed';end if;
end $qa$;
rollback;
