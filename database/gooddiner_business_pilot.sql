-- GoodDiner BUSINESS PILOT. Project ixczkhmvbjszgmlqznlk ONLY.
-- Private, auditable time-limited merchant access. No client may grant access.
-- Payment is NEVER inferred from a form, URL return, user metadata or frontend.
-- A human operator must verify a real settled payment before marking active.
-- The early paid pilot uses existing verified-presence tools only.
-- Personal ratings are CLOSED until documented legal/product approval.

create table gd_private.merchant_licenses (
  restaurant_id uuid primary key references public.restaurants(id) on delete cascade,
  status text not null check (status in ('trialing','active','suspended')),
  active_until timestamptz not null,
  changed_by text not null check (char_length(btrim(changed_by)) between 3 and 100),
  change_reason text not null check (char_length(btrim(change_reason)) between 10 and 500),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index gd_merchant_licenses_expiry on gd_private.merchant_licenses(active_until);
alter table gd_private.merchant_licenses enable row level security;
revoke all on gd_private.merchant_licenses from public,anon,authenticated;

create table gd_private.merchant_license_audit (
  id bigint generated always as identity primary key,
  restaurant_id uuid not null,
  action text not null check (action in ('trial_started','license_changed')),
  new_status text not null,
  new_until timestamptz not null,
  operator_label text not null,
  reason text not null,
  created_at timestamptz not null default now()
);
alter table gd_private.merchant_license_audit enable row level security;
revoke all on gd_private.merchant_license_audit from public,anon,authenticated;
revoke all on sequence gd_private.merchant_license_audit_id_seq from public,anon,authenticated;

create table gd_private.business_features (
  singleton boolean primary key default true check (singleton),
  personal_reviews_enabled boolean not null default false,
  updated_at timestamptz not null default now()
);
insert into gd_private.business_features(singleton,personal_reviews_enabled)
values (true,false);
alter table gd_private.business_features enable row level security;
revoke all on gd_private.business_features from public,anon,authenticated;

-- A trial starts only after the restaurant is approved and created by the
-- protected human-review routine. Rejected applications create no venue.
create or replace function gd_private.create_merchant_trial()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.verified_at is not null and new.suspended_at is null then
    insert into gd_private.merchant_licenses(restaurant_id,status,active_until,changed_by,change_reason)
    values(new.id,'trialing',now()+interval '14 days','gooddiner-system',
      'Prova di 14 giorni dopo verifica manuale del ristorante');
    insert into gd_private.merchant_license_audit
      (restaurant_id,action,new_status,new_until,operator_label,reason)
    select new.id,'trial_started','trialing',m.active_until,'gooddiner-system',
      'Prova iniziale creata alla verifica del ristorante'
    from gd_private.merchant_licenses m where m.restaurant_id=new.id;
  end if;
  return new;
end;
$$;
revoke all on function gd_private.create_merchant_trial() from public,anon,authenticated;
create trigger gd_new_verified_merchant_trial
after insert on public.restaurants
for each row execute function gd_private.create_merchant_trial();

-- Called by the SECURITY DEFINER check-in RPC, never directly by users.
create or replace function gd_private.assert_merchant_access(
  p_restaurant_id uuid, p_owner_id uuid
)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if p_owner_id is null or p_restaurant_id is null
    or not exists (
      select 1 from public.restaurants r
      join gd_private.merchant_licenses m on m.restaurant_id=r.id
      where r.id=p_restaurant_id and r.owner_id=p_owner_id
        and r.verified_at is not null and r.suspended_at is null
        and m.status in ('trialing','active') and m.active_until>now()
    ) then
    raise exception 'ACCESSO_BUSINESS_NON_ATTIVO';
  end if;
end;
$$;
revoke all on function gd_private.assert_merchant_access(uuid,uuid)
  from public,anon,authenticated;

-- Read-only, authenticated self-service status. No billing or other merchant
-- info is returned. The owner predicate is *inside* this definer routine.
create or replace function public.get_my_merchant_license(p_restaurant_id uuid)
returns table (license_status text, active_until timestamptz, is_usable boolean)
language plpgsql stable security definer set search_path = '' as $$
declare uid uuid := auth.uid();
begin
  if uid is null or p_restaurant_id is null
    or not exists(select 1 from public.restaurants r
      where r.id=p_restaurant_id and r.owner_id=uid) then
    raise exception 'RISTORANTE_NON_AUTORIZZATO';
  end if;
  return query
  select m.status, m.active_until,
    (m.status in ('trialing','active') and m.active_until>now()
      and r.verified_at is not null and r.suspended_at is null)
  from public.restaurants r
  left join gd_private.merchant_licenses m on m.restaurant_id=r.id
  where r.id=p_restaurant_id;
end;
$$;
revoke all on function public.get_my_merchant_license(uuid)
  from public,anon,authenticated;
grant execute on function public.get_my_merchant_license(uuid) to authenticated;

-- Does not charge the restaurant: operator uses this only after a real
-- settled payment has been independently verified, or to suspend access.
create or replace function gd_private.set_merchant_license(
  p_restaurant_id uuid, p_status text, p_active_until timestamptz,
  p_operator_label text, p_reason text
)
returns boolean language plpgsql security invoker set search_path = '' as $$
declare verified boolean;
begin
  if current_user <> 'postgres' then raise exception 'OPERATORE_NON_AUTORIZZATO'; end if;
  if p_restaurant_id is null or p_status not in ('trialing','active','suspended')
    or p_status is null or p_active_until is null
    or p_operator_label is null or char_length(btrim(p_operator_label)) not between 3 and 100
    or p_reason is null or char_length(btrim(p_reason)) not between 10 and 500
    or p_active_until > now()+interval '2 years' then
    raise exception 'PARAMETRI_LICENZA_NON_VALIDI';
  end if;
  select (r.verified_at is not null and r.suspended_at is null)
    into verified from public.restaurants r
    where r.id=p_restaurant_id for update;
  if not found or not verified then raise exception 'RISTORANTE_NON_VERIFICATO'; end if;
  if p_status in ('trialing','active') and p_active_until<=now() then
    raise exception 'SCADENZA_LICENZA_NON_VALIDA';
  end if;
  insert into gd_private.merchant_licenses
    (restaurant_id,status,active_until,changed_by,change_reason)
  values(p_restaurant_id,p_status,p_active_until,btrim(p_operator_label),btrim(p_reason))
  on conflict (restaurant_id) do update
    set status=excluded.status,active_until=excluded.active_until,
        changed_by=excluded.changed_by,change_reason=excluded.change_reason,
        updated_at=now();
  insert into gd_private.merchant_license_audit
    (restaurant_id,action,new_status,new_until,operator_label,reason)
  values(p_restaurant_id,'license_changed',p_status,p_active_until,
    btrim(p_operator_label),btrim(p_reason));
  return true;
end;
$$;
revoke all on function gd_private.set_merchant_license(uuid,text,timestamptz,text,text)
  from public,anon,authenticated;

-- Fast path enforceable in the *already exposed* RPC. Do not trust client UI.
create or replace function public.checkin_guest(p_qr_token text, p_restaurant_id uuid)
returns table(visit_id uuid, guest_nickname text, guest_code text)
language plpgsql security definer set search_path = '' as $$
declare
  uid uuid := auth.uid();
  token_row gd_private.visit_tokens%rowtype;
  member_row public.profiles%rowtype;
  new_visit uuid;
  date_local date;
begin
  if uid is null then raise exception 'LOGIN_RICHIESTO'; end if;
  if not exists(select 1 from public.restaurants r where r.id=p_restaurant_id
    and r.owner_id=uid and r.verified_at is not null and r.suspended_at is null) then
    raise exception 'RISTORANTE_NON_VERIFICATO';
  end if;
  perform gd_private.assert_merchant_access(p_restaurant_id,uid);
  if p_qr_token is null or p_qr_token !~ '^GD1:[0-9a-fA-F-]{36}$' then
    raise exception 'QR_NON_VALIDO';
  end if;
  select * into token_row from gd_private.visit_tokens t
    where t.id=substring(p_qr_token from 5)::uuid for update;
  if not found or token_row.consumed_at is not null or token_row.expires_at<=now() then
    raise exception 'QR_SCADUTO_O_UTILIZZATO';
  end if;
  select * into member_row from public.profiles p where p.id=token_row.customer_id
    and p.role='customer';
  if not found then raise exception 'PROFILO_CLIENTE_NON_VALIDO'; end if;
  date_local := (now() at time zone 'Europe/Rome')::date;
  if exists(select 1 from public.visits v where v.customer_id=member_row.id
    and v.restaurant_id=p_restaurant_id and v.visited_on=date_local and v.status='confirmed') then
    raise exception 'VISITA_GIA_REGISTRATA';
  end if;
  insert into public.visits(token_id,customer_id,restaurant_id,scanned_by,
    guest_nickname,guest_code,visited_on)
  values(token_row.id,member_row.id,p_restaurant_id,uid,
    member_row.nickname,member_row.customer_code,date_local)
  returning id into new_visit;
  update gd_private.visit_tokens set consumed_at=now(),consumed_by=p_restaurant_id
    where id=token_row.id;
  insert into gd_private.visit_audit(visit_id,actor_id,action)
    values(new_visit,uid,'checkin');
  return query select new_visit,member_row.nickname,member_row.customer_code;
end;
$$;

-- Human scoring and comment publication is deferred. The guest-review RPC
-- enforces the same gate even if someone calls REST directly, bypassing UI.
create or replace function public.publish_guest_review(
 p_visit_id uuid,p_rating integer,p_comment text
)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  uid uuid := auth.uid();
  visit_row public.visits%rowtype;
  new_review uuid;
  positive_count integer;
begin
  if not coalesce((select f.personal_reviews_enabled
      from gd_private.business_features f where f.singleton=true),false) then
    raise exception 'RECENSIONI_PERSONALI_NON_ATTIVE';
  end if;
  if uid is null or p_rating is null or p_rating not between 1 and 10
     or p_comment is null or char_length(btrim(p_comment)) not between 10 and 1200 then
    raise exception 'RECENSIONE_NON_VALIDA';
  end if;
  select * into visit_row from public.visits v where v.id=p_visit_id for update;
  if not found or visit_row.status<>'confirmed' then
    raise exception 'VISITA_NON_CONFERMATA';
  end if;
  if not exists(select 1 from public.restaurants r where r.id=visit_row.restaurant_id
     and r.owner_id=uid and r.verified_at is not null and r.suspended_at is null) then
    raise exception 'RISTORANTE_NON_AUTORIZZATO';
  end if;
  perform gd_private.assert_merchant_access(visit_row.restaurant_id,uid);
  perform 1 from public.profiles p where p.id=visit_row.customer_id for update;
  if exists(select 1 from public.reviews rv where rv.visit_id=visit_row.id) then
    raise exception 'VISITA_GIA_RECENSITA';
  end if;
  insert into public.reviews(visit_id,customer_id,restaurant_id,rater_id,rating,comment)
  values(visit_row.id,visit_row.customer_id,visit_row.restaurant_id,uid,p_rating,btrim(p_comment))
  returning id into new_review;
  if p_rating>=8 then
    select count(*) into positive_count from public.reviews rv
      where rv.customer_id=visit_row.customer_id and rv.rating>=8 and rv.status='published'
      and not exists (select 1 from public.disputes d where d.review_id=rv.id
        and d.status='accepted');
    if positive_count>0 and positive_count%10=0 then
      insert into public.vouchers(customer_id,milestone,status)
      values(visit_row.customer_id,positive_count,'pending')
      on conflict (customer_id,milestone) do nothing;
    end if;
  end if;
  return new_review;
end;
$$;

comment on table gd_private.merchant_licenses is
  'Paid/pilot merchant access, private and time-limited; never trust frontend billing state.';
comment on table gd_private.business_features is
  'Human rating of guests remains off until explicit legal review and operator release.';
