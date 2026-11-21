-- GoodDiner: enforce CLOSED registration on the server, not only in config.js.
-- Target: ixczkhmvbjszgmlqznlk ONLY. Must be reviewed before production.
-- Supabase Auth writes to auth.users as supabase_auth_admin. This BEFORE INSERT
-- trigger prevents direct API signups, including anonymous users, while closed.
-- Existing accounts can still sign in and recover passwords.

create table gd_private.registration_gate (
  singleton boolean primary key default true check (singleton),
  is_open boolean not null default false,
  updated_at timestamptz not null default now(),
  changed_by text not null default 'initial-install'
    check (char_length(btrim(changed_by)) between 3 and 100),
  reason text not null default 'Prelaunch: external Auth, CAPTCHA and GDPR not verified'
    check (char_length(btrim(reason)) between 10 and 500)
);
insert into gd_private.registration_gate(singleton,is_open)
values (true,false);

alter table gd_private.registration_gate enable row level security;
revoke all on gd_private.registration_gate from public, anon, authenticated;

-- GoTrue needs read-only access to the single switch; it cannot change it.
grant usage on schema gd_private to supabase_auth_admin;
grant select on gd_private.registration_gate to supabase_auth_admin;
create policy gd_registration_auth_admin_read on gd_private.registration_gate
  for select to supabase_auth_admin using (singleton=true);

create table gd_private.registration_gate_audit (
  id bigint generated always as identity primary key,
  is_open boolean not null,
  changed_by text not null,
  reason text not null,
  created_at timestamptz not null default now()
);
alter table gd_private.registration_gate_audit enable row level security;
revoke all on gd_private.registration_gate_audit from public,anon,authenticated;
revoke all on sequence gd_private.registration_gate_audit_id_seq from public,anon,authenticated;

create or replace function gd_private.audit_registration_gate()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.is_open is distinct from old.is_open then
    insert into gd_private.registration_gate_audit(is_open,changed_by,reason)
    values (new.is_open,btrim(new.changed_by),btrim(new.reason));
  end if;
  return new;
end;
$$;
revoke all on function gd_private.audit_registration_gate() from public,anon,authenticated;
create trigger gd_registration_gate_audit
after update on gd_private.registration_gate
for each row execute function gd_private.audit_registration_gate();

create or replace function gd_private.enforce_registration_gate()
returns trigger language plpgsql security invoker set search_path = '' as $$
declare
  allowed boolean := false;
begin
  -- The isolated rollback-only SQL fixture is executed as postgres and needs
  -- explicit opt-in; normal Supabase Auth never receives this exemption.
  if current_user='postgres'
    and current_setting('gooddiner.test_fixture',true)='enabled' then
    return new;
  end if;
  select g.is_open into allowed
  from gd_private.registration_gate g where g.singleton=true;
  if not coalesce(allowed,false) then
    raise exception 'GOODDINER_REGISTRATION_CLOSED'
      using errcode='P0001';
  end if;
  return new;
end;
$$;
revoke all on function gd_private.enforce_registration_gate() from public,anon,authenticated;
grant execute on function gd_private.enforce_registration_gate() to supabase_auth_admin;

create trigger gd_auth_registration_gate
before insert on auth.users
for each row execute function gd_private.enforce_registration_gate();

comment on table gd_private.registration_gate is
  'Server-side prelaunch gate: only postgres may enable signup after external Auth/CAPTCHA/GDPR approval.';
comment on function gd_private.enforce_registration_gate() is
  'Auth users insert gate, fail closed; existing sessions and password recovery are unaffected.';
