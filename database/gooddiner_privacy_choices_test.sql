do $qa$
declare a uuid:=gen_random_uuid();b uuid:=gen_random_uuid();p jsonb;
begin
 begin
 perform set_config('gooddiner.test_fixture','enabled',true);
 insert into auth.users(id,aud,role,email,raw_user_meta_data,email_confirmed_at,is_anonymous,created_at,updated_at)
 values(a,'authenticated','authenticated','privacy-qa-'||a||'@example.invalid',jsonb_build_object('nickname','QA privacy','gd_privacy_choices',jsonb_build_object('version','pilot-2026-11-26-v1','terms',true,'privacy',true,'sharing',true)),now(),false,now(),now()),
 (b,'authenticated','authenticated','privacy-qa-'||b||'@example.invalid',jsonb_build_object('nickname','QA other'),now(),false,now(),now());
 if (select count(*) from gd_private.privacy_choice_events where user_id=a and terms_ack and privacy_ack and sharing_requested)<>1 then raise exception 'FAIL signup capture';end if;
 if exists(select 1 from gd_private.privacy_choice_events where user_id=b) then raise exception 'FAIL inferred acceptance';end if;
 perform set_config('request.jwt.claim.sub',b::text,true);
 execute 'set local role authenticated';
 p:=public.my_privacy_choices();
 if p->>'sharing_requested'<>'false' or p->>'signup_acknowledged'<>'false' then raise exception 'FAIL isolation';end if;
 execute 'reset role';
 perform set_config('request.jwt.claim.sub',a::text,true);
 execute 'set local role authenticated';
 p:=public.my_privacy_choices();
 if p->>'sharing_requested'<>'true' then raise exception 'FAIL preference read';end if;
 p:=public.set_my_sharing_preference(false);
 if p->>'sharing_requested'<>'false' then raise exception 'FAIL withdrawal';end if;
 execute 'reset role';
 if (select count(*) from gd_private.privacy_choice_events where user_id=a)<>2 then raise exception 'FAIL history';end if;
 raise exception 'ROLLBACK_PRIVACY_QA';
 exception when others then if sqlerrm<>'ROLLBACK_PRIVACY_QA' then raise;end if;end;
end $qa$;