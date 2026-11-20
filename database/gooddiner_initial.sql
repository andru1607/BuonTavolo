-- GoodDiner · dedicated database baseline v1 (PostgreSQL 17 / Supabase).
-- NEVER RUN IN THE EASYGART PROJECT. Fresh GoodDiner project only.
-- Run only after confirming the Supabase organization, project, and potential cost.
-- No service_role keys in web clients. No real accounts until security/privacy review.

begin;

create schema if not exists gd_private;
revoke all on schema gd_private from public, anon, authenticated;

-- 1. Member identities. User-controlled metadata is NEVER used for authorization.
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  nickname text not null check (char_length(btrim(nickname)) between 3 and 30),
  customer_code text not null unique default ('GD-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 12))),
  role text not null default 'customer' check (role in ('customer', 'merchant')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index gd_profiles_nickname_idx on public.profiles (lower(nickname));

create or replace function gd_private.create_member_profile()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  candidate text;
begin
  candidate := btrim(coalesce(new.raw_user_meta_data->>'nickname', ''));
  if char_length(candidate) not between 3 and 30 then
    candidate := 'ospite_' || substr(replace(new.id::text, '-', ''), 1, 10);
  end if;
  -- Never trust new.raw_user_meta_data->>'role'. No merchant self-promotion.
  insert into public.profiles (id, nickname, role)
  values (new.id, candidate, 'customer');
  return new;
end;
$$;
revoke all on function gd_private.create_member_profile() from public, anon, authenticated;
create trigger gd_auth_user_created
  after insert on auth.users for each row execute function gd_private.create_member_profile();

-- 2. Business verification: only authorized administrators may accept applications.
create table public.merchant_applications (
  id uuid primary key default gen_random_uuid(),
  applicant_id uuid not null references auth.users(id) on delete cascade,
  restaurant_name text not null check (char_length(btrim(restaurant_name)) between 3 and 100),
  city text not null check (char_length(btrim(city)) between 2 and 100),
  source text not null default 'manual' check (source in ('manual','google_maps')),
  place_id text check (place_id is null or char_length(place_id) between 3 and 250),
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  reviewed_at timestamptz,
  created_at timestamptz not null default now()
);
create unique index gd_merchant_one_pending on public.merchant_applications(applicant_id) where status='pending';

create table public.restaurants (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id),
  application_id uuid unique references public.merchant_applications(id),
  name text not null check (char_length(btrim(name)) between 3 and 100),
  city text not null check (char_length(btrim(city)) between 2 and 100),
  source_place_id text,
  verified_at timestamptz,
  suspended_at timestamptz,
  created_at timestamptz not null default now()
);
create index gd_restaurants_owner_idx on public.restaurants(owner_id);

-- 3. QR capability only, not an ID or a password. No Data API access to this table.
create table gd_private.visit_tokens (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '90 seconds'),
  consumed_at timestamptz,
  consumed_by uuid references public.restaurants(id),
  check (expires_at > created_at)
);
create index gd_token_customer_time_idx on gd_private.visit_tokens(customer_id,created_at desc);
create index gd_token_expiry_idx on gd_private.visit_tokens(expires_at);
alter table gd_private.visit_tokens enable row level security;
revoke all on gd_private.visit_tokens from public,anon,authenticated;

-- 4. Presence, reviews, disputes and pre-commercial rewards.
create table public.visits (
  id uuid primary key default gen_random_uuid(),
  token_id uuid not null unique references gd_private.visit_tokens(id),
  customer_id uuid not null references public.profiles(id),
  restaurant_id uuid not null references public.restaurants(id),
  scanned_by uuid not null references auth.users(id),
  guest_nickname text not null,
  guest_code text not null,
  visited_on date not null,
  checked_in_at timestamptz not null default now(),
  status text not null default 'confirmed' check (status in ('confirmed','voided')),
  void_reason text check (void_reason is null or char_length(btrim(void_reason)) between 10 and 500),
  voided_at timestamptz
);
-- After voiding an erroneous check-in a new one may be created the same day.
create unique index gd_one_confirmed_visit_per_day
  on public.visits(customer_id,restaurant_id,visited_on) where status='confirmed';
create index gd_visits_customer_time on public.visits(customer_id,checked_in_at desc);
create index gd_visits_restaurant_time on public.visits(restaurant_id,checked_in_at desc);

create table gd_private.visit_audit (
  id bigint generated always as identity primary key,
  visit_id uuid not null references public.visits(id),
  actor_id uuid not null references auth.users(id),
  action text not null check (action in ('checkin','void')),
  reason text,
  created_at timestamptz not null default now()
);
alter table gd_private.visit_audit enable row level security;
revoke all on gd_private.visit_audit from public,anon,authenticated;

create table public.reviews (
  id uuid primary key default gen_random_uuid(),
  visit_id uuid not null unique references public.visits(id),
  customer_id uuid not null references public.profiles(id),
  restaurant_id uuid not null references public.restaurants(id),
  rater_id uuid not null references auth.users(id),
  rating integer not null check (rating between 1 and 10),
  comment text not null check (char_length(btrim(comment)) between 10 and 1200),
  status text not null default 'published' check (status in ('published','removed')),
  created_at timestamptz not null default now()
);
create index gd_reviews_customer_time on public.reviews(customer_id,created_at desc);
create index gd_reviews_restaurant_time on public.reviews(restaurant_id,created_at desc);

create table public.disputes (
  id uuid primary key default gen_random_uuid(),
  review_id uuid not null unique references public.reviews(id),
  customer_id uuid not null references public.profiles(id),
  reason text not null check (char_length(btrim(reason)) between 10 and 1000),
  status text not null default 'pending' check (status in ('pending','accepted','rejected')),
  created_at timestamptz not null default now(),
  resolved_at timestamptz
);

create table public.vouchers (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.profiles(id),
  milestone integer not null check (milestone >= 10 and milestone % 10=0),
  voucher_code text not null unique default ('GD-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,16))),
  status text not null default 'pending' check (status in ('pending','available','redeemed','suspended')),
  created_at timestamptz not null default now(),
  unique(customer_id,milestone)
);
-- Vouchers are pending only: real redemption awaits commercial/privacy controls.

-- 5. Grants and row-level security: no global customer directory.
alter table public.profiles enable row level security;
alter table public.merchant_applications enable row level security;
alter table public.restaurants enable row level security;
alter table public.visits enable row level security;
alter table public.reviews enable row level security;
alter table public.disputes enable row level security;
alter table public.vouchers enable row level security;

revoke all on public.profiles, public.merchant_applications, public.restaurants,
  public.visits, public.reviews, public.disputes, public.vouchers from anon,authenticated;
grant usage on schema public to authenticated;
grant select on public.profiles, public.merchant_applications, public.restaurants,
  public.visits, public.reviews, public.disputes, public.vouchers to authenticated;
grant update(nickname) on public.profiles to authenticated;
grant insert(applicant_id,restaurant_name,city,source,place_id) on public.merchant_applications to authenticated;
grant insert(review_id,customer_id,reason) on public.disputes to authenticated;

create policy gd_profiles_self_select on public.profiles for select to authenticated
  using (id=(select auth.uid()));
create policy gd_profiles_self_nickname on public.profiles for update to authenticated
  using (id=(select auth.uid())) with check (id=(select auth.uid()));

create policy gd_applications_self_select on public.merchant_applications for select to authenticated
  using (applicant_id=(select auth.uid()));
create policy gd_applications_request on public.merchant_applications for insert to authenticated
  with check (applicant_id=(select auth.uid()) and status='pending' and reviewed_at is null
    and coalesce((select (auth.jwt()->>'is_anonymous')::boolean),false)=false);

create policy gd_restaurants_verified_or_owner on public.restaurants for select to authenticated
  using ((verified_at is not null and suspended_at is null) or owner_id=(select auth.uid()));

create policy gd_visits_participants on public.visits for select to authenticated
  using (customer_id=(select auth.uid()) or exists (
    select 1 from public.restaurants r
    where r.id=restaurant_id and r.owner_id=(select auth.uid())
  ));

create policy gd_reviews_participants on public.reviews for select to authenticated
  using (customer_id=(select auth.uid()) or rater_id=(select auth.uid()));

create policy gd_disputes_participants on public.disputes for select to authenticated
  using (customer_id=(select auth.uid()) or exists (
    select 1 from public.reviews rv where rv.id=review_id and rv.rater_id=(select auth.uid())
  ));
create policy gd_disputes_customer_insert on public.disputes for insert to authenticated
  with check (customer_id=(select auth.uid()) and status='pending' and resolved_at is null
    and exists(select 1 from public.reviews rv where rv.id=review_id
      and rv.customer_id=(select auth.uid()) and rv.status='published'));

create policy gd_vouchers_self_select on public.vouchers for select to authenticated
  using (customer_id=(select auth.uid()));

-- 6. Trusted transaction to issue a short-lived QR.
-- SECURITY DEFINER is intentionally exposed only to authenticated callers and
-- checks auth.uid. All private-table access remains server-side.
create or replace function public.issue_guest_qr()
returns table(qr_token text, expires_at timestamptz)
language plpgsql security definer set search_path = '' as $$
declare
  uid uuid := auth.uid();
  created gd_private.visit_tokens%rowtype;
begin
  if uid is null or not exists(select 1 from public.profiles p
    where p.id=uid and p.role='customer') then
    raise exception 'ACCESSO_CLIENTE_RICHIESTO';
  end if;
  -- Simple per-user throttling; production also needs network CAPTCHA/rate limits.
  if (select count(*) from gd_private.visit_tokens t
    where t.customer_id=uid and t.created_at>now()-interval '1 minute') >= 5 then
    raise exception 'TROPPE_RICHIESTE_QR';
  end if;
  insert into gd_private.visit_tokens(customer_id) values(uid) returning * into created;
  return query select ('GD1:'||created.id::text), created.expires_at;
end;
$$;
revoke all on function public.issue_guest_qr() from public,anon,authenticated;
grant execute on function public.issue_guest_qr() to authenticated;

-- 7. Atomic check-in with verified ownership, expiry and anti-replay.
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
  -- Initial market: Italy. Configurable restaurant time zones are future scope.
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
revoke all on function public.checkin_guest(text,uuid) from public,anon,authenticated;
grant execute on function public.checkin_guest(text,uuid) to authenticated;

-- 8. A merchant can void an erroneous presence before review submission.
create or replace function public.void_guest_visit(p_visit_id uuid,p_reason text)
returns boolean language plpgsql security definer set search_path = '' as $$
declare
  uid uuid := auth.uid();
  row_visit public.visits%rowtype;
begin
  if uid is null or p_reason is null or char_length(btrim(p_reason)) not between 10 and 500 then
    raise exception 'RICHIESTA_NON_VALIDA';
  end if;
  select * into row_visit from public.visits v where v.id=p_visit_id for update;
  if not found or row_visit.status<>'confirmed' then raise exception 'VISITA_NON_ATTIVA'; end if;
  if not exists(select 1 from public.restaurants r where r.id=row_visit.restaurant_id
     and r.owner_id=uid and r.verified_at is not null and r.suspended_at is null) then
     raise exception 'NON_AUTORIZZATO';
  end if;
  if exists(select 1 from public.reviews rv where rv.visit_id=p_visit_id) then
     raise exception 'RECENSIONE_PRESENTE_RICHIEDE_MODERAZIONE';
  end if;
  update public.visits set status='voided',void_reason=btrim(p_reason),voided_at=now()
    where id=p_visit_id;
  insert into gd_private.visit_audit(visit_id,actor_id,action,reason)
    values(p_visit_id,uid,'void',btrim(p_reason));
  return true;
end;
$$;
revoke all on function public.void_guest_visit(uuid,text) from public,anon,authenticated;
grant execute on function public.void_guest_visit(uuid,text) to authenticated;

-- 9. A review can only be attached to an unreviewed confirmed visit.
-- Serialized per-customer to avoid issuing duplicate 10-review vouchers.
create or replace function public.publish_guest_review(p_visit_id uuid,p_rating integer,p_comment text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  uid uuid := auth.uid();
  visit_row public.visits%rowtype;
  new_review uuid;
  positive_count integer;
begin
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
  -- Serialize reviews for the same customer across different restaurants.
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
revoke all on function public.publish_guest_review(uuid,integer,text) from public,anon,authenticated;
grant execute on function public.publish_guest_review(uuid,integer,text) to authenticated;

-- Future moderation must reconcile pending vouchers after removals and disputes.
-- Do not treat voucher rows as redeemable until the commercial policy is approved.

commit;