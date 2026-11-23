-- GoodDiner: rollback-only QA for free email customer registration and merchant invite security.
-- Must be executed as postgres against GoodDiner ONLY; no permanent users or applications.
do $gd$
declare
  guest_id uuid:=gen_random_uuid();
  merchant_id uuid:=gen_random_uuid();
  fake_id uuid:=gen_random_uuid();
  another_id uuid:=gen_random_uuid();
  anon_id uuid:=gen_random_uuid();
  merchant_code text:=replace(gen_random_uuid()::text,'-','');
  existing_users bigint;
  existing_invites bigint;
  existing_applications bigint;
  denied boolean;
begin
  if current_user<>'postgres' then raise exception 'TEST_REQUIRES_POSTGRES'; end if;
  if (select is_open from gd_private.registration_gate where singleton)
     or not (select invite_only_enabled from gd_private.registration_gate where singleton) then
    raise exception 'FAIL: unexpected onboarding gate flags';
  end if;
  select count(*) into existing_users from auth.users;
  select count(*) into existing_invites from gd_private.signup_invites;
  select count(*) into existing_applications from public.merchant_applications;
  begin
    perform set_config('gooddiner.test_fixture','',true);
    -- Customers do not need a personal invitation.
    insert into auth.users(id,aud,role,email,raw_user_meta_data,is_anonymous,email_confirmed_at,created_at,updated_at)
    values(guest_id,'authenticated','authenticated','free-guest-'||guest_id||'@example.invalid',
      '{"nickname":"ClienteLibero"}'::jsonb,false,now(),now(),now());
    if (select role from public.profiles where id=guest_id)<>'customer' then
      raise exception 'FAIL: free customer profile missing';
    end if;

    -- A forged "merchant" purpose without a valid invitation is rejected by Auth.
    denied:=false;
    begin
      insert into auth.users(id,aud,role,email,raw_user_meta_data,is_anonymous,created_at,updated_at)
      values(fake_id,'authenticated','authenticated','no-merchant-code-'||fake_id||'@example.invalid',
        jsonb_build_object('nickname','FalsoGestore','gd_invite_purpose','merchant'),false,now(),now());
    exception when others then
      if position('GOODDINER_INVITE_' in sqlerrm)>0 then denied:=true;
      else raise; end if;
    end;
    if not denied then raise exception 'FAIL: merchant signup without invite accepted'; end if;

    -- A genuine one-time merchant invite is consumed atomically and its secret removed.
    insert into gd_private.signup_invites(secret_hash,purpose,expires_at,created_by)
    values(encode(sha256(convert_to(merchant_code,'UTF8')),'hex'),'merchant',now()+interval '2 hours','gooddiner-qa');
    insert into auth.users(id,aud,role,email,raw_user_meta_data,is_anonymous,email_confirmed_at,created_at,updated_at)
    values(merchant_id,'authenticated','authenticated','real-merchant-'||merchant_id||'@example.invalid',
      jsonb_build_object('nickname','GestoreInvitato','gd_invite',merchant_code,
        'gd_invite_purpose','merchant'),false,now(),now(),now());
    if not exists(select 1 from gd_private.signup_invites where used_by=merchant_id
      and purpose='merchant' and used_at is not null) then
      raise exception 'FAIL: merchant invitation not consumed';
    end if;
    if exists(select 1 from auth.users where id=merchant_id
      and (raw_user_meta_data ? 'gd_invite' or raw_user_meta_data ? 'gd_invite_purpose')) then
      raise exception 'FAIL: merchant invitation secret retained in Auth metadata';
    end if;

    -- Reuse is forbidden even if attacker knows a legitimate merchant invite code.
    denied:=false;
    begin
      insert into auth.users(id,aud,role,email,raw_user_meta_data,is_anonymous,created_at,updated_at)
      values(another_id,'authenticated','authenticated','replayed-merchant-'||another_id||'@example.invalid',
        jsonb_build_object('nickname','TentativoReplay','gd_invite',merchant_code,
          'gd_invite_purpose','merchant'),false,now(),now());
    exception when others then
      if position('GOODDINER_INVITE_' in sqlerrm)>0 then denied:=true;
      else raise; end if;
    end;
    if not denied then raise exception 'FAIL: merchant invite replay accepted'; end if;

    -- Anonymous users cannot circumvent the email-only registration gate.
    denied:=false;
    begin
      insert into auth.users(id,aud,role,email,raw_user_meta_data,is_anonymous,created_at,updated_at)
      values(anon_id,'authenticated','authenticated',null,'{"nickname":"Anonimo"}'::jsonb,
        true,now(),now());
    exception when others then
      if position('GOODDINER_EMAIL_REQUIRED' in sqlerrm)>0 then denied:=true;
      else raise; end if;
    end;
    if not denied then raise exception 'FAIL: anonymous customer signup accepted'; end if;

    -- A confirmed-email customer cannot request a venue just by switching UI.
    perform set_config('request.jwt.claim.sub',guest_id::text,true);
    perform set_config('request.jwt.claims',jsonb_build_object('sub',guest_id::text,'is_anonymous',false)::text,true);
    execute 'SET LOCAL ROLE authenticated';
    if gd_private.current_user_has_merchant_invite() then
      raise exception 'FAIL: guest falsely recognized as invited merchant';
    end if;
    denied:=false;
    begin
      insert into public.merchant_applications(applicant_id,restaurant_name,city)
      values(guest_id,'Cliente Che Prova','Garda');
    exception when others then denied:=true;
    end;
    if not denied then raise exception 'FAIL: customer could apply without merchant invite'; end if;
    execute 'RESET ROLE';

    -- The verified merchant can submit its own application, but not self-approve.
    perform set_config('request.jwt.claim.sub',merchant_id::text,true);
    perform set_config('request.jwt.claims',jsonb_build_object('sub',merchant_id::text,'is_anonymous',false)::text,true);
    execute 'SET LOCAL ROLE authenticated';
    if not gd_private.current_user_has_merchant_invite() then
      raise exception 'FAIL: invited merchant not recognized';
    end if;
    insert into public.merchant_applications(applicant_id,restaurant_name,city)
    values(merchant_id,'Ristorante Con Invito','Garda');
    execute 'RESET ROLE';
    raise exception 'ROLLBACK_GOODDINER_ROLE_QA';
  exception when raise_exception then
    execute 'RESET ROLE';
    if sqlerrm<>'ROLLBACK_GOODDINER_ROLE_QA' then raise;end if;
  end;
  if (select count(*) from auth.users)<>existing_users
    or (select count(*) from gd_private.signup_invites)<>existing_invites
    or (select count(*) from public.merchant_applications)<>existing_applications then
    raise exception 'FAIL: test data persisted';
  end if;
end $gd$;
