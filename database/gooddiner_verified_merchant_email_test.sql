-- GoodDiner integration QA fixture. Execute only on project GoodDiner, as postgres.
-- Rolls back test users and applications; SQL gate migration must be present.
do $gd$
declare
  unverified_id uuid:=gen_random_uuid();
  verified_id uuid:=gen_random_uuid();
  blocked boolean:=false;
begin
  if current_user<>'postgres' then raise exception 'TEST_REQUIRES_POSTGRES'; end if;
  begin
    perform set_config('gooddiner.test_fixture','enabled',true);
    insert into auth.users(id,aud,role,email,raw_user_meta_data,email_confirmed_at,is_anonymous,created_at,updated_at)
    values
      (unverified_id,'authenticated','authenticated','unverified-'||unverified_id||'@example.invalid','{"nickname":"EmailPending"}'::jsonb,null,false,now(),now()),
      (verified_id,'authenticated','authenticated','verified-'||verified_id||'@example.invalid','{"nickname":"EmailVerified"}'::jsonb,now(),false,now(),now());
    perform set_config('request.jwt.claim.sub',unverified_id::text,true);
    perform set_config('request.jwt.claims',jsonb_build_object('sub',unverified_id::text,'is_anonymous',false)::text,true);
    execute 'SET LOCAL ROLE authenticated';
    if gd_private.current_user_email_confirmed() then raise exception 'FAIL: unconfirmed email verified'; end if;
    begin
      insert into public.merchant_applications(applicant_id,restaurant_name,city)
      values(unverified_id,'Locale Senza Conferma','Garda');
    exception when others then blocked:=true;
    end;
    execute 'RESET ROLE';
    if not blocked then raise exception 'FAIL: unconfirmed email could apply';end if;
    perform set_config('request.jwt.claim.sub',verified_id::text,true);
    perform set_config('request.jwt.claims',jsonb_build_object('sub',verified_id::text,'is_anonymous',false)::text,true);
    execute 'SET LOCAL ROLE authenticated';
    if not gd_private.current_user_email_confirmed() then raise exception 'FAIL: confirmed email rejected'; end if;
    insert into public.merchant_applications(applicant_id,restaurant_name,city)
    values(verified_id,'Locale Con Conferma','Garda');
    execute 'RESET ROLE';
    raise exception 'ROLLBACK_GOODDINER_EMAIL_QA';
  exception when raise_exception then
    execute 'RESET ROLE';
    if sqlerrm <> 'ROLLBACK_GOODDINER_EMAIL_QA' then raise;end if;
  end;
  if exists(select 1 from auth.users where id in(unverified_id,verified_id)) then
    raise exception 'FAIL: fixture auth.users persisted';
  end if;
end $gd$;
