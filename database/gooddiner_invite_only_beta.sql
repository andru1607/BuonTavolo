-- GoodDiner pilot: allow only individually issued, one-time signup invitations.
-- Dedicated project only: ixczkhmvbjszgmlqznlk.
-- Public/open registrations remain CLOSED, with no Turnstile secret configured.
-- Invite-only email accounts are a narrow beta; merchant access still requires
-- independent human verification. No anonymous signups in this phase.
-- The existing auth.users trigger remains the only server-side creation gate.

alter table gd_private.registration_gate
  add column invite_only_enabled boolean not null default false;

create table gd_private.signup_invites (
  id uuid primary key default gen_random_uuid(),
  secret_hash text not null unique check (secret_hash ~ '^[a-f0-9]{64}$'),
  purpose text not null check (purpose in ('customer','merchant')),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  used_at timestamptz,
  used_by uuid,
  created_by text not null check (length(btrim(created_by)) between 3 and 100),
  check (expires_at > created_at),
  check ((used_at is null) = (used_by is null))
);
create index gd_signup_invites_expiry on gd_private.signup_invites(expires_at);
alter table gd_private.signup_invites enable row level security;
revoke all on gd_private.signup_invites from public, anon, authenticated, supabase_auth_admin;

create or replace function gd_private.create_signup_invite(
  p_purpose text,
  p_issued_by text,
  p_valid_hours integer default 168
)
returns text
language plpgsql security invoker set search_path = '' as $$
declare
  invite_code text := replace(pg_catalog.gen_random_uuid()::text,'-','');
begin
  if current_user <> 'postgres' then raise exception 'OPERATORE_NON_AUTORIZZATO'; end if;
  if p_purpose is null or p_purpose not in ('customer','merchant')
    or p_issued_by is null or length(btrim(p_issued_by)) not between 3 and 100
    or p_valid_hours is null or p_valid_hours not between 1 and 168 then
    raise exception 'PARAMETRI_INVITO_NON_VALIDI';
  end if;
  insert into gd_private.signup_invites(secret_hash,purpose,expires_at,created_by)
  values(encode(pg_catalog.sha256(pg_catalog.convert_to(invite_code,'UTF8')),'hex'),
    p_purpose,now()+make_interval(hours=>p_valid_hours),btrim(p_issued_by));
  return invite_code;
end;
$$;
revoke all on function gd_private.create_signup_invite(text,text,integer)
  from public, anon, authenticated, supabase_auth_admin;

-- Audit invitation-mode transitions too, not only the older public gate.
create or replace function gd_private.audit_registration_gate()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.is_open is distinct from old.is_open
    or new.invite_only_enabled is distinct from old.invite_only_enabled then
    insert into gd_private.registration_gate_audit(is_open,changed_by,reason)
    values(new.is_open,btrim(new.changed_by),btrim(new.reason));
  end if;
  return new;
end;
$$;
revoke all on function gd_private.audit_registration_gate()
  from public,anon,authenticated;

-- A SECURITY DEFINER function is needed because GoTrue cannot write private
-- invite rows. The only invoker with EXECUTE is Supabase's internal Auth role,
-- plus the database owner. Never expose this routine in public Data API.
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
  if coalesce(open_to_all,false) then return new; end if;

  if not coalesce(invite_mode,false) then
    raise exception 'GOODDINER_REGISTRATION_CLOSED' using errcode='P0001';
  end if;
  if new.email is null or btrim(new.email)=''
    or coalesce(new.is_anonymous,false)=true then
    raise exception 'GOODDINER_INVITE_EMAIL_REQUIRED' using errcode='P0001';
  end if;

  supplied_code := lower(btrim(coalesce(new.raw_user_meta_data->>'gd_invite','')));
  supplied_purpose := coalesce(new.raw_user_meta_data->>'gd_invite_purpose','');
  if supplied_code !~ '^[a-f0-9]{32}$'
    or supplied_purpose not in ('customer','merchant') then
    raise exception 'GOODDINER_INVITE_INVALID' using errcode='P0001';
  end if;

  -- The UPDATE lock and used_at null condition make token redemption
  -- atomic and race-safe. A failed signup rolls back this update too.
  update gd_private.signup_invites i
    set used_at=now(),used_by=new.id
    where i.secret_hash=encode(pg_catalog.sha256(pg_catalog.convert_to(supplied_code,'UTF8')),'hex')
      and i.purpose=supplied_purpose
      and i.used_at is null and i.expires_at>now()
    returning i.id into matching_invite;
  if matching_invite is null then
    raise exception 'GOODDINER_INVITE_INVALID_OR_USED' using errcode='P0001';
  end if;

  -- The one-time secret is not retained in auth.users or the profile; only
  -- a non-sensitive purpose marker survives for support diagnostics.
  new.raw_user_meta_data := coalesce(new.raw_user_meta_data,'{}'::jsonb)
    - 'gd_invite' - 'gd_invite_purpose';
  return new;
end;
$$;
revoke all on function gd_private.enforce_registration_gate()
  from public, anon, authenticated;
grant execute on function gd_private.enforce_registration_gate()
  to supabase_auth_admin;

comment on table gd_private.signup_invites is
  'One-time, hashed, seven-day maximum email signup invitations; no public API privileges.';
comment on function gd_private.enforce_registration_gate() is
  'Fail-closed signups, optional one-time invite-only beta; no anonymous identities and no client role elevation.';
