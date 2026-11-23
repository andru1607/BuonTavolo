-- GoodDiner: customers enroll with email + password without invitation.
-- Restaurant accounts still need a one-time merchant-purpose invite;
-- merchant applications additionally require the inviter's recorded identity.
-- Do NOT set is_open=true: this migration keeps existing invite mode and email confirmation.
create or replace function gd_private.enforce_registration_gate()
returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  open_to_all boolean := false;
  invite_mode boolean := false;
  supplied_code text;
  supplied_purpose text;
  matching_invite uuid;
begin
  -- The SQL test fixture can bypass only as postgres, with an explicit
  -- per-transaction flag. An API caller cannot acquire this database role.
  if current_user='postgres'
    and current_setting('gooddiner.test_fixture',true)='enabled' then
    return new;
  end if;

  select g.is_open,g.invite_only_enabled into open_to_all,invite_mode
  from gd_private.registration_gate g where g.singleton=true;
  if not coalesce(open_to_all,false) and not coalesce(invite_mode,false) then
    raise exception 'GOODDINER_REGISTRATION_CLOSED' using errcode='P0001';
  end if;
  if new.email is null or btrim(new.email)=''
    or coalesce(new.is_anonymous,false)=true then
    raise exception 'GOODDINER_EMAIL_REQUIRED' using errcode='P0001';
  end if;

  supplied_code := lower(btrim(coalesce(new.raw_user_meta_data->>'gd_invite','')));
  supplied_purpose := coalesce(new.raw_user_meta_data->>'gd_invite_purpose','');
  -- Customers create ordinary email accounts without needing any invite.
  -- Only the merchant signup path can redeem an invitation, and the
  -- invitation's USED_BY identity is persisted in a private table.
  if supplied_purpose='merchant' or supplied_code<>'' then
    if not coalesce(invite_mode,false) or supplied_purpose<>'merchant'
      or supplied_code !~ '^[a-f0-9]{32}$' then
      raise exception 'GOODDINER_INVITE_INVALID' using errcode='P0001';
    end if;
    update gd_private.signup_invites i
      set used_at=now(),used_by=new.id
      where i.secret_hash=encode(pg_catalog.sha256(pg_catalog.convert_to(supplied_code,'UTF8')),'hex')
        and i.purpose='merchant' and i.used_at is null and i.expires_at>now()
      returning i.id into matching_invite;
    if matching_invite is null then
      raise exception 'GOODDINER_INVITE_INVALID_OR_USED' using errcode='P0001';
    end if;
  elsif supplied_purpose not in ('','customer') then
    raise exception 'GOODDINER_INVITE_INVALID' using errcode='P0001';
  end if;
  new.raw_user_meta_data := coalesce(new.raw_user_meta_data,'{}'::jsonb)
    - 'gd_invite' - 'gd_invite_purpose';
  return new;
end;
$$;

revoke all on function gd_private.enforce_registration_gate() from public,anon,authenticated;
grant execute on function gd_private.enforce_registration_gate() to supabase_auth_admin;

-- Only the database-authenticated actor's own redeemed merchant invitation counts.
-- Checking auth.users raw_user_meta_data or a client-supplied role is NOT safe.
create or replace function gd_private.current_user_has_merchant_invite()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from gd_private.signup_invites i
    where i.used_by = (select auth.uid())
      and i.purpose = 'merchant' and i.used_at is not null
  );
$$;
revoke all on function gd_private.current_user_has_merchant_invite()
  from public, anon, authenticated;
grant usage on schema gd_private to authenticated;
grant execute on function gd_private.current_user_has_merchant_invite() to authenticated;

drop policy if exists gd_applications_request on public.merchant_applications;
create policy gd_applications_request on public.merchant_applications
  for insert to authenticated
  with check (
    applicant_id = (select auth.uid())
    and status='pending' and reviewed_at is null
    and coalesce((select (auth.jwt()->>'is_anonymous')::boolean),false)=false
    and (select gd_private.current_user_email_confirmed())
    and (select gd_private.current_user_has_merchant_invite())
  );
comment on function gd_private.enforce_registration_gate() is
  'Email signup is free for customers, merchants must redeem one-time invitation; anonymous signup remains closed.';
comment on function gd_private.current_user_has_merchant_invite() is
  'Self-only server-verified merchant invite redemption; used by merchant application insert RLS.';
