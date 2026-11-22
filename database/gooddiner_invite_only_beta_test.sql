-- GoodDiner invite-only Auth gate integration checks.
-- Run exclusively as postgres. Everything rolls back, including test auth.users.
-- Requires migration gooddiner_invite_only_beta.sql.
do $gd$
declare
  first_user uuid := gen_random_uuid();
  second_user uuid := gen_random_uuid();
  invitation text := replace(gen_random_uuid()::text,'-','');
  initial_invites integer;
  initial_users integer;
  bad_blocked boolean;
  secret_stored boolean;
begin
  if current_user<>'postgres' then raise exception 'TEST_REQUIRES_POSTGRES'; end if;
  select count(*) into initial_invites from gd_private.signup_invites;
  select count(*) into initial_users from auth.users;
  begin
    update gd_private.registration_gate set invite_only_enabled=true,
      updated_at=now(),changed_by='gooddiner-qa',
      reason='Temporary invitation test inside a rollback-only transaction'
      where singleton=true and is_open=false;
    insert into gd_private.signup_invites(secret_hash,purpose,expires_at,created_by)
      values(encode(sha256(convert_to(invitation,'UTF8')),'hex'),
        'customer',now()+interval '2 hours','gooddiner-qa');

    -- The Auth hook must reject signup without a valid code.
    bad_blocked:=false;
    begin
      insert into auth.users(id,aud,role,email,raw_user_meta_data,is_anonymous,created_at,updated_at)
      values(second_user,'authenticated','authenticated',
        'no-invite-'||second_user||'@example.invalid',
        '{"nickname":"Blocked"}'::jsonb,false,now(),now());
    exception when others then
      if position('GOODDINER_INVITE' in sqlerrm)>0 then bad_blocked:=true;
      else raise;end if;
    end;
    if not bad_blocked then raise exception 'FAIL: signup without invite accepted';end if;

    insert into auth.users(id,aud,role,email,raw_user_meta_data,is_anonymous,created_at,updated_at)
    values(first_user,'authenticated','authenticated',
      'invited-'||first_user||'@example.invalid',
      jsonb_build_object('nickname','Tester','gd_invite',invitation,
        'gd_invite_purpose','customer'),false,now(),now());
    if not exists (select 1 from gd_private.signup_invites i where
      i.used_by=first_user and i.used_at is not null) then
      raise exception 'FAIL: invitation not atomically consumed';
    end if;
    select (raw_user_meta_data ? 'gd_invite') into secret_stored
      from auth.users where id=first_user;
    if secret_stored or secret_stored is null then
      raise exception 'FAIL: Auth user retains the one-time invitation secret';
    end if;

    -- Even valid code cannot be reused or changed to merchant access.
    bad_blocked:=false;
    begin
      insert into auth.users(id,aud,role,email,raw_user_meta_data,is_anonymous,created_at,updated_at)
      values(second_user,'authenticated','authenticated',
        'reused-'||second_user||'@example.invalid',
        jsonb_build_object('nickname','Replay','gd_invite',invitation,
          'gd_invite_purpose','customer'),false,now(),now());
    exception when others then
      if position('GOODDINER_INVITE' in sqlerrm)>0 then bad_blocked:=true;
      else raise;end if;
    end;
    if not bad_blocked then raise exception 'FAIL: invitation replay accepted';end if;

    raise exception 'ROLLBACK_GOODDINER_INVITE_QA';
  exception when raise_exception then
    if sqlerrm<>'ROLLBACK_GOODDINER_INVITE_QA' then raise;end if;
  end;
  if (select count(*) from auth.users)<>initial_users or
     (select count(*) from gd_private.signup_invites)<>initial_invites then
    raise exception 'FAIL: test data persisted';
  end if;
  if (select invite_only_enabled from gd_private.registration_gate where singleton)=true then
    raise exception 'FAIL: test left invitation mode switched on';
  end if;
end
$gd$;
