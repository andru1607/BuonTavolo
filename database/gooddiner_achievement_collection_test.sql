do $qa$
declare g uuid:=gen_random_uuid(); other_g uuid:=gen_random_uuid(); owner_id uuid; venue uuid; token uuid; visit uuid; first_venue uuid; first_owner uuid; d jsonb; i integer; rejected boolean; gc text;
begin
 begin
 perform set_config('gooddiner.test_fixture','enabled',true);
 insert into auth.users(id,aud,role,email,raw_user_meta_data,email_confirmed_at,is_anonymous,created_at,updated_at)
 select u,'authenticated','authenticated','collection-qa-'||u||'@example.invalid',jsonb_build_object('nickname','QA collection'),now(),false,now(),now() from unnest(array[g,other_g]) u;
 select customer_code into gc from public.profiles where id=g;
 for i in 1..10 loop
 owner_id:=gen_random_uuid();
 insert into auth.users(id,aud,role,email,raw_user_meta_data,email_confirmed_at,is_anonymous,created_at,updated_at)
 values(owner_id,'authenticated','authenticated','collection-qa-'||owner_id||'@example.invalid',jsonb_build_object('nickname','QA venue'),now(),false,now(),now());
 insert into public.restaurants(owner_id,name,city,verified_at) values(owner_id,'QA venue '||i,'Garda',now()) returning id into venue;
 if i=1 then first_venue:=venue;first_owner:=owner_id;end if;
 insert into gd_private.visit_tokens(customer_id,consumed_at,consumed_by) values(g,now(),venue) returning id into token;
 insert into public.visits(token_id,customer_id,restaurant_id,scanned_by,guest_nickname,guest_code,visited_on) values(token,g,venue,owner_id,'QA collection',gc,current_date) returning id into visit;
 insert into public.reviews(visit_id,customer_id,restaurant_id,rater_id,rating,comment) values(visit,g,venue,owner_id,case when i=10 then 1 else 9 end,'Synthetic review for cosmetic unlock QA');
 if i=9 then
 if exists(select 1 from gd_private.dinerpass_unlocks where customer_id=g and code='explorer') then raise exception 'FAIL early unlock';end if;
 end if;
 end loop;
 insert into gd_private.visit_tokens(customer_id,consumed_at,consumed_by) values(g,now(),first_venue) returning id into token;
 insert into public.visits(token_id,customer_id,restaurant_id,scanned_by,guest_nickname,guest_code,visited_on) values(token,g,first_venue,first_owner,'QA collection',gc,current_date-1) returning id into visit;
 insert into public.reviews(visit_id,customer_id,restaurant_id,rater_id,rating,comment) values(visit,g,first_venue,first_owner,10,'Synthetic duplicate restaurant QA');
 perform set_config('request.jwt.claim.sub',g::text,true);execute 'set local role authenticated';
 d:=public.my_dinerpass_collection();
 if (d->>'progress')::int<>10 then raise exception 'FAIL distinct count';end if;
 d:=public.select_my_dinerpass('explorer');
 if d->>'selected'<>'explorer' then raise exception 'FAIL selection';end if;
 rejected:=false;begin perform public.select_my_dinerpass('icon');exception when others then rejected:=sqlerrm='DINERPASS_NON_SBLOCCATO';end;
 if not rejected then raise exception 'FAIL locked selected';end if;
 d:=public.select_my_dinerpass('original');
 if d->>'selected'<>'original' then raise exception 'FAIL switch back';end if;
 execute 'reset role';
 perform set_config('request.jwt.claim.sub',other_g::text,true);execute 'set local role authenticated';
 d:=public.my_dinerpass_collection();
 if (d->>'progress')::int<>0 or d->>'selected'<>'original' then raise exception 'FAIL isolation';end if;
 rejected:=false;begin perform public.select_my_dinerpass('explorer');exception when others then rejected:=sqlerrm='DINERPASS_NON_SBLOCCATO';end;
 if not rejected then raise exception 'FAIL other account unlock';end if;
 execute 'reset role';
 raise exception 'ROLLBACK_COLLECTION_QA';
 exception when others then if sqlerrm<>'ROLLBACK_COLLECTION_QA' then raise;end if;end;
end $qa$;