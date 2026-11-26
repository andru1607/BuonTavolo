-- Rollback-only acceptance test: no real customer data is read or persisted.
do $qa$
declare g uuid:=gen_random_uuid(); other_g uuid:=gen_random_uuid(); a uuid:=gen_random_uuid(); b uuid:=gen_random_uuid(); c uuid:=gen_random_uuid();
 va uuid; vb uuid; vc uuid; token text; v1 uuid; v2 uuid; v3 uuid; review2 uuid; payload jsonb; blocked boolean;
begin
 begin
  perform set_config('gooddiner.test_fixture','enabled',true);
  update gd_private.business_features set personal_reviews_enabled=true where singleton;
  update gd_private.reputation_release set enabled=true,approved_at=now()-interval '1 second' where singleton;
  insert into auth.users(id,aud,role,email,raw_user_meta_data,email_confirmed_at,is_anonymous,created_at,updated_at)
  select u,'authenticated','authenticated','reputation-test-'||u||'@example.invalid',jsonb_build_object('nickname','Test reputation'),now(),false,now(),now() from unnest(array[g,other_g,a,b,c]) u;
  insert into public.restaurants(owner_id,name,city,verified_at) values(a,'QA legacy','Garda',now()) returning id into va;
  insert into public.restaurants(owner_id,name,city,verified_at) values(b,'QA shared','Garda',now()) returning id into vb;
  insert into public.restaurants(owner_id,name,city,verified_at) values(c,'QA reader','Garda',now()) returning id into vc;
  perform set_config('request.jwt.claim.sub',g::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',g::text,'is_anonymous',false)::text,true);
  execute 'set local role authenticated';
  select qr_token into token from public.issue_guest_qr();
  execute 'reset role';
  perform set_config('request.jwt.claim.sub',a::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',a::text,'is_anonymous',false)::text,true);
  execute 'set local role authenticated';
  select visit_id into v1 from public.checkin_guest(token,va);
  perform public.publish_guest_review(v1,3,'Test private free text must not be shared');
  execute 'reset role';
  perform set_config('request.jwt.claim.sub',g::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',g::text,'is_anonymous',false)::text,true);
  execute 'set local role authenticated';
  select qr_token into token from public.issue_shared_dinerpass_qr();
  execute 'reset role';
  perform set_config('request.jwt.claim.sub',b::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',b::text,'is_anonymous',false)::text,true);
  execute 'set local role authenticated';
  select visit_id into v2 from public.checkin_guest(token,vb);
  review2:=public.publish_guest_review(v2,9,'Test shared free text must remain private');
  execute 'reset role';
  perform set_config('request.jwt.claim.sub',g::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',g::text,'is_anonymous',false)::text,true);
  execute 'set local role authenticated';
  select qr_token into token from public.issue_shared_dinerpass_qr();
  execute 'reset role';
  perform set_config('request.jwt.claim.sub',c::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',c::text,'is_anonymous',false)::text,true);
  execute 'set local role authenticated';
  select visit_id into v3 from public.checkin_guest(token,vc);
  if exists(select 1 from public.reviews where id=review2) then raise exception 'FAIL direct RLS disclosure'; end if;
  payload:=public.read_shared_dinerpass_reviews(v3);
  if payload->>'available' is distinct from 'true' or jsonb_array_length(payload->'reviews')<>1 or payload#>>'{reviews,0,rating}' is distinct from '9' or payload::text like '%free text%' then raise exception 'FAIL shared result: %',payload; end if;
  blocked:=false;begin perform public.read_shared_dinerpass_reviews(v3);exception when others then blocked:=sqlerrm='CONSULTAZIONE_GIA_ESEGUITA';end;
  if not blocked then raise exception 'FAIL replay'; end if;
  execute 'reset role';
  perform set_config('request.jwt.claim.sub',other_g::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',other_g::text,'is_anonymous',false)::text,true);
  execute 'set local role authenticated';
  blocked:=false;begin perform public.read_shared_dinerpass_reviews(v3);exception when others then blocked:=sqlerrm='ACCESSO_NON_AUTORIZZATO';end;
  if not blocked or jsonb_array_length(public.my_reputation_accesses())<>0 then raise exception 'FAIL unrelated customer access';end if;
  execute 'reset role';
  perform set_config('request.jwt.claim.sub',g::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',g::text,'is_anonymous',false)::text,true);
  execute 'set local role authenticated';
  if jsonb_array_length(public.my_reputation_accesses())<>1 then raise exception 'FAIL customer audit';end if;
  execute 'reset role';
  update gd_private.reputation_release set enabled=false where singleton;
  if public.read_shared_dinerpass_reviews(v3)->>'available' is distinct from 'false' then raise exception 'FAIL gate';end if;
  raise exception 'ROLLBACK_REPUTATION_QA';
 exception when others then
  if sqlerrm<>'ROLLBACK_REPUTATION_QA' then raise;end if;
 end;
end $qa$;