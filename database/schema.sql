-- GoodDiner (ex BuonTavolo) V5 · preparazione database dedicato (NON eseguito su EasyGart)
-- Applicare soltanto a un nuovo progetto Supabase GoodDiner.
-- I privilegi sono restrittivi: nessun utente può darsi il ruolo di ristoratore verificato.

create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  role text not null check (role in ('customer','merchant')),
  nickname text not null check (char_length(trim(nickname)) between 3 and 30),
  customer_code text not null unique default ('GD-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 10))),
  created_at timestamptz not null default now()
);
create unique index if not exists buontavolo_nickname_unique on public.profiles (lower(nickname));

create or replace function public.bt_new_user() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_nick text;
  v_role text;
begin
  v_nick := left(trim(coalesce(new.raw_user_meta_data->>'nickname','')),30);
  if char_length(v_nick)<3 then
    v_nick := 'utente_' || substr(replace(new.id::text,'-',''),1,8);
  end if;
  v_role := case when new.raw_user_meta_data->>'role' = 'merchant' then 'merchant' else 'customer' end;
  begin
    insert into public.profiles(id, nickname, role) values (new.id,v_nick,v_role);
  exception when unique_violation then
    insert into public.profiles(id,nickname,role)
    values(new.id, 'utente_' || substr(replace(new.id::text,'-',''),1,12),v_role)
    on conflict (id) do nothing;
  end;
  return new;
end $$;

-- La scelta "merchant" nei metadati di signup NON conferisce diritti professionali:
-- la verifica di un ristorante avviene esclusivamente su `verified_at` (server/admin).
drop trigger if exists bt_auth_user_created on auth.users;
create trigger bt_auth_user_created after insert on auth.users
for each row execute function public.bt_new_user();

create table if not exists public.restaurants (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null unique references auth.users(id) on delete cascade,
  name text not null check (char_length(trim(name)) between 3 and 100),
  vat_number text not null check (char_length(trim(vat_number)) between 8 and 25),
  verified_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists bt_restaurants_owner_idx on public.restaurants(owner_id);

create table if not exists public.visit_tokens (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '15 minutes'),
  claimed_at timestamptz
);
create index if not exists bt_visit_tokens_owner_idx on public.visit_tokens(customer_id);

create table if not exists public.visits (
  id uuid primary key default gen_random_uuid(),
  token_id uuid not null unique references public.visit_tokens(id),
  customer_id uuid not null references public.profiles(id),
  restaurant_id uuid not null references public.restaurants(id),
  customer_nickname text not null,
  customer_code text not null,
  visited_on date not null default current_date,
  created_at timestamptz not null default now(),
  unique(customer_id, restaurant_id, visited_on)
);
create index if not exists bt_visits_customer_idx on public.visits(customer_id);
create index if not exists bt_visits_restaurant_idx on public.visits(restaurant_id);

create table if not exists public.reviews (
  id uuid primary key default gen_random_uuid(),
  visit_id uuid not null unique references public.visits(id),
  customer_id uuid not null references public.profiles(id),
  restaurant_id uuid not null references public.restaurants(id),
  rater_id uuid not null references auth.users(id),
  rating integer not null check (rating between 1 and 10),
  comment text not null check (char_length(trim(comment)) between 10 and 1200),
  status text not null default 'published' check (status in ('published','removed')),
  created_at timestamptz not null default now()
);
create index if not exists bt_reviews_customer_idx on public.reviews(customer_id,created_at desc);
create index if not exists bt_reviews_restaurant_idx on public.reviews(restaurant_id,created_at desc);

create table if not exists public.disputes (
  id uuid primary key default gen_random_uuid(),
  review_id uuid not null unique references public.reviews(id) on delete cascade,
  customer_id uuid not null references public.profiles(id),
  reason text not null check (char_length(trim(reason)) between 10 and 1000),
  status text not null default 'pending' check (status in ('pending','accepted','rejected')),
  created_at timestamptz not null default now()
);

-- Le note inter-ristoratore non vengono esposte in questa fase.
-- Occorre definire base giuridica, informativa, retention e procedura di contestazione.

alter table public.profiles enable row level security;
alter table public.restaurants enable row level security;
alter table public.visit_tokens enable row level security;
alter table public.visits enable row level security;
alter table public.reviews enable row level security;
alter table public.disputes enable row level security;

-- Importantissimo: i grant predefiniti del Data API non bastano come protezione.
revoke all on table public.profiles,public.restaurants,public.visit_tokens,public.visits,public.reviews,public.disputes from anon, authenticated;
revoke all on function public.bt_new_user() from public, anon, authenticated;

grant usage on schema public to authenticated;
grant select on table public.profiles,public.restaurants,public.visit_tokens,public.visits,public.reviews,public.disputes to authenticated;
grant update (nickname) on public.profiles to authenticated;
grant insert (owner_id,name,vat_number) on public.restaurants to authenticated;
grant insert (customer_id) on public.visit_tokens to authenticated;
grant insert (visit_id,customer_id,restaurant_id,rater_id,rating,comment) on public.reviews to authenticated;
grant insert (review_id,customer_id,reason) on public.disputes to authenticated;

create policy bt_profiles_own_read on public.profiles for select to authenticated
  using (id = (select auth.uid()));
create policy bt_profiles_own_nickname on public.profiles for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));

create policy bt_restaurant_own_read on public.restaurants for select to authenticated
  using (owner_id = (select auth.uid()));
-- Solo i ristoranti verificati sono consultabili dai clienti per mostrare il nome
-- dell'attività che ha recensito una visita (non i ristoranti in attesa).
create policy bt_restaurant_verified_read on public.restaurants for select to authenticated
  using (verified_at is not null);
create policy bt_restaurant_register on public.restaurants for insert to authenticated
  with check (
    owner_id = (select auth.uid())
    and verified_at is null
    and exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='merchant')
  );

create policy bt_visit_token_own_read on public.visit_tokens for select to authenticated
  using (customer_id=(select auth.uid()));
create policy bt_visit_token_own_create on public.visit_tokens for insert to authenticated
  with check (
    customer_id=(select auth.uid())
    and exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='customer')
  );

create policy bt_visits_participants_read on public.visits for select to authenticated
  using (customer_id=(select auth.uid())
  or exists(select 1 from public.restaurants r where r.id=restaurant_id and r.owner_id=(select auth.uid())));

create policy bt_reviews_participants_read on public.reviews for select to authenticated
  using (customer_id=(select auth.uid()) or rater_id=(select auth.uid()));
create policy bt_reviews_merchant_verified_create on public.reviews for insert to authenticated
  with check (
    rater_id=(select auth.uid())
    and status='published'
    and exists(
      select 1 from public.visits v
      join public.restaurants r on r.id=v.restaurant_id
      where v.id=visit_id and v.customer_id=customer_id and v.restaurant_id=restaurant_id
        and r.owner_id=(select auth.uid()) and r.verified_at is not null
    )
  );

create policy bt_disputes_participants_read on public.disputes for select to authenticated
  using (customer_id=(select auth.uid())
    or exists(select 1 from public.reviews rv where rv.id=review_id and rv.rater_id=(select auth.uid())));
create policy bt_disputes_customer_create on public.disputes for insert to authenticated
  with check (
    customer_id=(select auth.uid())
    and exists (select 1 from public.reviews rv where rv.id=review_id and rv.customer_id=(select auth.uid()))
  );

-- Solo il ristoratore VERIFICATO che riceve un token da un cliente può collegare una visita.
-- Il token UUID è monouso e scade dopo 15 minuti; non esiste ricerca globale di persone.
create or replace function public.claim_visit(p_token uuid, p_restaurant_id uuid)
returns table(visit_id uuid, guest_nickname text, guest_code text)
language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid := auth.uid();
  v_token public.visit_tokens%rowtype;
  v_profile public.profiles%rowtype;
  v_visit uuid;
begin
  if v_user is null then raise exception 'ACCESSO_RICHIESTO'; end if;
  if not exists (select 1 from public.restaurants r where r.id=p_restaurant_id
     and r.owner_id=v_user and r.verified_at is not null) then
    raise exception 'RISTORANTE_NON_VERIFICATO';
  end if;
  select * into v_token from public.visit_tokens t where t.id=p_token for update;
  if not found or v_token.claimed_at is not null or v_token.expires_at <= now() then
    raise exception 'CODICE_SCADUTO_O_UTILIZZATO';
  end if;
  select * into v_profile from public.profiles p
    where p.id=v_token.customer_id and p.role='customer';
  if not found then raise exception 'CLIENTE_NON_VALIDO'; end if;
  insert into public.visits(token_id,customer_id,restaurant_id,customer_nickname,customer_code)
  values(v_token.id,v_profile.id,p_restaurant_id,v_profile.nickname,v_profile.customer_code)
  returning id into v_visit;
  update public.visit_tokens set claimed_at=now() where id=v_token.id;
  return query select v_visit,v_profile.nickname,v_profile.customer_code;
end $$;
revoke all on function public.claim_visit(uuid,uuid) from public,anon;
grant execute on function public.claim_visit(uuid,uuid) to authenticated;

-- Nessun ristoratore può approvare la propria attività dal browser: verified_at è amministrativo.
-- Le recensioni 8-10 sono "positive" nel prodotto, 1-7 non concorrono al premio.
-- I buoni effettivi restano disabilitati in questa fase, fino ad accordi commerciali e controlli antiabuso.