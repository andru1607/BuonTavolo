-- Cosmetic collection only; does not modify QR, review visibility or reward economics.
create table gd_private.dinerpass_catalog (
 code text primary key check(code ~ '^[a-z0-9-]{1,40}$'),
 name text not null check(char_length(name) between 1 and 60),
 threshold integer not null check(threshold>=0),
 theme text not null check(theme in ('original','explorer','connoisseur','icon','legend')),
 artwork_path text check(artwork_path is null or artwork_path ~ '^/icons/editions/[a-z0-9-]+\.(svg|png|webp)$'),
 enabled boolean not null default true
);
insert into gd_private.dinerpass_catalog(code,name,threshold,theme) values
 ('original','Original',0,'original'),('explorer','Explorer',10,'explorer'),
 ('connoisseur','Connoisseur',20,'connoisseur'),('icon','Icon',50,'icon'),('legend','Legend',100,'legend');
create table gd_private.dinerpass_unlocks (
 customer_id uuid not null references public.profiles(id) on delete cascade,
 code text not null references gd_private.dinerpass_catalog(code),
 unlocked_at timestamptz not null default now(),
 primary key(customer_id,code)
);
create table gd_private.dinerpass_selection (
 customer_id uuid primary key references public.profiles(id) on delete cascade,
 code text not null references gd_private.dinerpass_catalog(code),
 foreign key(customer_id,code) references gd_private.dinerpass_unlocks(customer_id,code)
);
alter table gd_private.dinerpass_catalog enable row level security;
alter table gd_private.dinerpass_unlocks enable row level security;
alter table gd_private.dinerpass_selection enable row level security;
revoke all on gd_private.dinerpass_catalog,gd_private.dinerpass_unlocks,gd_private.dinerpass_selection from public,anon,authenticated;
create function gd_private.dinerpass_progress(p_customer uuid)
returns integer language sql stable security definer set search_path='' as $$
 select count(distinct rv.restaurant_id)::integer from public.reviews rv
 join public.visits v on v.id=rv.visit_id and v.customer_id=rv.customer_id and v.restaurant_id=rv.restaurant_id
 join public.restaurants r on r.id=rv.restaurant_id
 where rv.customer_id=p_customer and rv.status='published' and v.status='confirmed'
 and r.verified_at is not null and rv.rater_id<>p_customer
 and not exists(select 1 from public.disputes d where d.review_id=rv.id and d.status in ('pending','accepted'))
$$;
revoke all on function gd_private.dinerpass_progress(uuid) from public,anon,authenticated;
create function gd_private.sync_dinerpass_unlocks(p_customer uuid)
returns integer language plpgsql security definer set search_path='' as $$
declare n integer;
begin
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_customer::text,9421));
 n:=gd_private.dinerpass_progress(p_customer);
 insert into gd_private.dinerpass_unlocks(customer_id,code)
 select p_customer,c.code from gd_private.dinerpass_catalog c where c.enabled and c.threshold<=n
 on conflict do nothing;
 return n;
end $$;
revoke all on function gd_private.sync_dinerpass_unlocks(uuid) from public,anon,authenticated;
create function gd_private.award_dinerpass_on_review()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.status='published' then perform gd_private.sync_dinerpass_unlocks(new.customer_id);end if;
 return new;
end $$;
revoke all on function gd_private.award_dinerpass_on_review() from public,anon,authenticated;
create trigger gd_award_dinerpass_on_review after insert on public.reviews
 for each row execute function gd_private.award_dinerpass_on_review();
create function public.my_dinerpass_collection()
returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid(); n integer; chosen text;
begin
 if uid is null or not exists(select 1 from public.profiles p where p.id=uid)
 or exists(select 1 from public.restaurants r where r.owner_id=uid) then raise exception 'ACCESSO_CLIENTE_RICHIESTO';end if;
 n:=gd_private.sync_dinerpass_unlocks(uid);
 select s.code into chosen from gd_private.dinerpass_selection s join gd_private.dinerpass_catalog c on c.code=s.code and c.enabled where s.customer_id=uid;
 return jsonb_build_object('progress',n,'selected',coalesce(chosen,'original'),'cards',
 (select jsonb_agg(jsonb_build_object('code',c.code,'name',c.name,'threshold',c.threshold,'theme',c.theme,'artwork_path',c.artwork_path,'unlocked',u.code is not null) order by c.threshold,c.code)
 from gd_private.dinerpass_catalog c left join gd_private.dinerpass_unlocks u on u.code=c.code and u.customer_id=uid where c.enabled));
end $$;
revoke all on function public.my_dinerpass_collection() from public,anon,authenticated;
grant execute on function public.my_dinerpass_collection() to authenticated;
create function public.select_my_dinerpass(p_code text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid();
begin
 perform public.my_dinerpass_collection();
 if not exists(select 1 from gd_private.dinerpass_unlocks u join gd_private.dinerpass_catalog c on c.code=u.code and c.enabled where u.customer_id=uid and u.code=p_code) then raise exception 'DINERPASS_NON_SBLOCCATO';end if;
 insert into gd_private.dinerpass_selection(customer_id,code) values(uid,p_code) on conflict(customer_id) do update set code=excluded.code;
 return public.my_dinerpass_collection();
end $$;
revoke all on function public.select_my_dinerpass(text) from public,anon,authenticated;
grant execute on function public.select_my_dinerpass(text) to authenticated;
