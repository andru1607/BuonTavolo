-- Transactional fixture, never persists synthetic reviews or support requests.
begin;
do $qa$
declare u uuid; m uuid; v uuid; b uuid; tok uuid; vi uuid; rv uuid; d date; r jsonb; rejected boolean; n int; x uuid;
begin
 select id,owner_id into strict v,m from public.restaurants where verified_at is not null and suspended_at is null limit 1;
 select p.id into strict u from public.profiles p join auth.users a on a.id=p.id where a.email_confirmed_at is not null and not exists(select 1 from public.restaurants rr where rr.owner_id=p.id) limit 1;
 d:=(now() at time zone 'Europe/Rome')::date+20;
 update gd_private.booking_settings set enabled=true,online_paused=false,capacity=180,duration_minutes=60,max_party=30,service_windows=jsonb_build_array(jsonb_build_object('day',extract(isodow from d)::int,'from','11:00','to','15:00')) where restaurant_id=v;
 delete from gd_private.booking_day_overrides where restaurant_id=v and day=d;
 perform set_config('request.jwt.claim.sub',u::text,true);perform set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated')::text,true);
 r:=public.gooddiner_bookings('create',jsonb_build_object('restaurant_id',v,'name','QA reputation rollback','starts_at',(d+time '12:00') at time zone 'Europe/Rome','party',2));b:=(r->>'id')::uuid;
 rejected:=false;begin perform public.set_booking_reputation_choice(b,true,'booking-reputation-v1');exception when others then rejected:=sqlerrm='BOOKING_PROFILE_DISABLED';end;if not rejected then raise exception 'QA release not disabled';end if;
 update gd_private.booking_reputation_release set enabled=true,approved_at=now()-interval '1 day',notice_version='booking-reputation-v1';
 update gd_private.reputation_release set enabled=true,approved_at=now()-interval '1 day',approved_notice_version='sharing-v1';
 r:=public.set_booking_reputation_choice(b,true,'booking-reputation-v1');if r->>'allowed'<>'true' then raise exception 'QA grant';end if;
 insert into gd_private.visit_tokens(customer_id,created_at,expires_at,consumed_at,consumed_by) values(u,now()-interval '1 hour',now()-interval '59 minutes',now()-interval '59 minutes 30 seconds',v) returning id into tok;
 insert into gd_private.reputation_token_choices(token_id,chosen_at,notice_version) values(tok,now()-interval '1 hour','sharing-v1');
 insert into public.visits(token_id,customer_id,restaurant_id,scanned_by,guest_nickname,guest_code,visited_on,checked_in_at) values(tok,u,v,m,'QA guest','GD-QA',d-1,now()-interval '59 minutes 30 seconds') returning id into vi;
 insert into public.reviews(visit_id,customer_id,restaurant_id,rater_id,rating,comment,created_at) values(vi,u,v,m,8,'QA synthetic review',now()-interval '30 minutes') returning id into rv;
 rejected:=false;begin perform public.read_booking_reputation(b);exception when others then rejected:=sqlerrm='BOOKING_PROFILE_FORBIDDEN';end;if not rejected then raise exception 'QA unrelated caller allowed';end if;
 perform set_config('request.jwt.claim.sub',m::text,true);perform set_config('request.jwt.claims',jsonb_build_object('sub',m,'role','authenticated')::text,true);
 r:=public.read_booking_reputation(b);if r->>'available'<>'true' or not exists(select 1 from jsonb_array_elements(r->'reviews') a where a->>'rating'='8') or exists(select 1 from jsonb_array_elements(r->'reviews') a where a?'comment' or a?'customer_id') then raise exception 'QA projection %',r;end if;
 perform set_config('request.jwt.claim.sub',u::text,true);perform set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated')::text,true);
 r:=public.my_booking_reputation_accesses();if jsonb_array_length(r)<1 then raise exception 'QA audit';end if;
 perform public.revoke_dinerpass_sharing();
 perform set_config('request.jwt.claim.sub',m::text,true);perform set_config('request.jwt.claims',jsonb_build_object('sub',m,'role','authenticated')::text,true);
 r:=public.read_booking_reputation(b);if r->>'reason'<>'not_authorized' then raise exception 'QA global withdrawal';end if;
 perform set_config('request.jwt.claim.sub',u::text,true);perform set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated')::text,true);
 r:=public.gooddiner_support('create','{"category":"technical","message":"QA synthetic support request"}');select id into x from gd_private.support_requests where requester_id=u and message='QA synthetic support request';if x is null or not exists(select 1 from jsonb_array_elements(r) a where a->>'id'=x::text) then raise exception 'QA support creation';end if;
 perform set_config('request.jwt.claim.sub',m::text,true);perform set_config('request.jwt.claims',jsonb_build_object('sub',m,'role','authenticated')::text,true);
 r:=public.gooddiner_support('list','{}');if exists(select 1 from jsonb_array_elements(r) a where a->>'id'=x::text) then raise exception 'QA support cross-account leakage';end if;
 select user_id into strict m from gd_studio_private.operators limit 1;
 perform set_config('request.jwt.claim.sub',u::text,true);perform set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated')::text,true);
 if not exists(select 1 from gd_studio_private.operators where user_id=u) then
 rejected:=false;begin perform public.gooddiner_support('operator_list','{}');exception when others then rejected:=sqlerrm='SUPPORT_OPERATOR_FORBIDDEN';end;if not rejected then raise exception 'QA operator authorization failed';end if;
 end if;
 perform set_config('request.jwt.claim.sub',m::text,true);perform set_config('request.jwt.claims',jsonb_build_object('sub',m,'role','authenticated')::text,true);
 r:=public.gooddiner_support('operator_list','{}');if not exists(select 1 from jsonb_array_elements(r) a where a->>'id'=x::text) then raise exception 'QA operator missing ticket';end if;
 perform public.gooddiner_support('operator_resolve',jsonb_build_object('id',x,'reply','QA operator response'));
 perform set_config('request.jwt.claim.sub',u::text,true);perform set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated')::text,true);
 r:=public.gooddiner_support('list','{}');if not exists(select 1 from jsonb_array_elements(r) a where a->>'id'=x::text and a->>'status'='resolved' and a->>'reply'='QA operator response') then raise exception 'QA reply not visible';end if;
 if has_table_privilege('authenticated','gd_private.booking_reputation_grants','SELECT') or has_table_privilege('authenticated','gd_private.support_requests','SELECT') or has_function_privilege('anon','public.read_booking_reputation(uuid)','EXECUTE') then raise exception 'QA exposed private data';end if;
end $qa$;
rollback;
