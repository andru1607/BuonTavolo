begin;
create table gd_private.marketing_signup_sources(user_id uuid primary key references auth.users(id) on delete cascade,restaurant_id uuid not null references public.restaurants(id) on delete cascade,channel text not null check(channel in ('flyer','social','merchant')),created_at timestamptz not null default now());
create table gd_private.marketing_public_cards(restaurant_id uuid primary key references public.restaurants(id) on delete cascade,published boolean not null default false,updated_at timestamptz not null default now());
create table gd_private.marketing_reward_requests(restaurant_id uuid not null references public.restaurants(id) on delete cascade,reward_code text not null check(reward_code in ('guest25','guest50','guest100','merchant1')),requested_at timestamptz not null default now(),primary key(restaurant_id,reward_code));
alter table gd_private.marketing_signup_sources enable row level security;
alter table gd_private.marketing_public_cards enable row level security;
alter table gd_private.marketing_reward_requests enable row level security;
revoke all on gd_private.marketing_signup_sources,gd_private.marketing_public_cards,gd_private.marketing_reward_requests from public,anon,authenticated;
create function gd_private.capture_marketing_source() returns trigger language plpgsql security definer set search_path='' as $$
declare m jsonb:=new.raw_user_meta_data; rid text; src text;
begin
 if exists(select 1 from gd_private.signup_invites i where i.used_by=new.id and i.purpose='merchant' and i.used_at is not null) then
 rid:=m->>'gd_merchant_referrer';src:='merchant';
 else rid:=m->>'gd_marketing_restaurant';src:=m->>'gd_marketing_channel';end if;
 if rid ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' and src in ('flyer','social','merchant') then
 insert into gd_private.marketing_signup_sources(user_id,restaurant_id,channel)
 select new.id,r.id,src from public.restaurants r where r.id=rid::uuid and r.owner_id<>new.id and r.verified_at is not null and r.suspended_at is null on conflict(user_id) do nothing;
 end if;
 return new;
end $$;
revoke all on function gd_private.capture_marketing_source() from public,anon,authenticated;
create trigger gd_capture_signup_marketing after insert on auth.users for each row execute function gd_private.capture_marketing_source();
create function gd_private.marketing_qualified(p_restaurant uuid) returns integer language sql stable security definer set search_path='' as $$
 select count(*)::integer from gd_private.marketing_referrals f join public.profiles p on p.id=f.customer_id and p.role='customer' join auth.users u on u.id=p.id and u.email_confirmed_at is not null and not u.is_anonymous
 where f.restaurant_id=p_restaurant and not exists(select 1 from public.restaurants own where own.owner_id=f.customer_id) and exists(select 1 from public.visits v where v.customer_id=f.customer_id and v.restaurant_id=f.restaurant_id and v.status='confirmed' and v.checked_in_at>=f.created_at);
$$;
create function gd_private.marketing_level(n integer) returns text language sql immutable set search_path='' as $$ select case when n>=1000 then 'Elite' when n>=500 then 'Platinum' when n>=250 then 'Gold' when n>=100 then 'Silver' when n>=50 then 'Bronze' when n>=10 then 'Partner' else 'Aderente' end $$;
revoke all on function gd_private.marketing_qualified(uuid),gd_private.marketing_level(integer) from public,anon,authenticated;
create function public.marketing_partner(p_action text,p_restaurant uuid,p_publish boolean default null,p_reward text default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid(); n integer; verified_n integer; active_n integer; invited_n integer; result jsonb;
begin
 if u is null or not exists(select 1 from public.restaurants r where r.id=p_restaurant and r.owner_id=u and r.verified_at is not null and r.suspended_at is null) then raise exception 'RISTORANTE_NON_VERIFICATO';end if;
 n:=gd_private.marketing_qualified(p_restaurant);
 select count(*) into invited_n from gd_private.marketing_signup_sources s join auth.users a on a.id=s.user_id and a.email_confirmed_at is not null where s.restaurant_id=p_restaurant and s.channel='merchant';
 select count(distinct s.user_id),count(distinct s.user_id) filter(where l.status='active' and l.active_until>now()) into verified_n,active_n
 from gd_private.marketing_signup_sources s join public.restaurants r on r.owner_id=s.user_id and r.verified_at is not null and r.suspended_at is null and r.id<>p_restaurant
 left join gd_private.merchant_licenses l on l.restaurant_id=r.id
 where s.restaurant_id=p_restaurant and s.channel='merchant';
 if p_action='publish' then
 if p_publish is null then raise exception 'SCELTA_RICHIESTA';end if;
 insert into gd_private.marketing_public_cards(restaurant_id,published) values(p_restaurant,p_publish) on conflict(restaurant_id) do update set published=excluded.published,updated_at=now();
 elsif p_action='request_reward' then
 if not coalesce((p_reward='guest25' and n>=25) or (p_reward='guest50' and n>=50) or (p_reward='guest100' and n>=100) or (p_reward='merchant1' and active_n>=1),false) then raise exception 'TRAGUARDO_NON_RAGGIUNTO';end if;
 insert into gd_private.marketing_reward_requests(restaurant_id,reward_code) values(p_restaurant,p_reward) on conflict do nothing;
 elsif p_action<>'stats' then raise exception 'AZIONE_NON_VALIDA';end if;
 return jsonb_build_object('qualified',n,'level',gd_private.marketing_level(n),'invited_merchants',invited_n,'verified_merchants',verified_n,'active_merchants',active_n,'published',coalesce((select published from gd_private.marketing_public_cards where restaurant_id=p_restaurant),false),'requested_rewards',coalesce((select jsonb_agg(reward_code order by requested_at) from gd_private.marketing_reward_requests where restaurant_id=p_restaurant),'[]'::jsonb));
end $$;
create function public.marketing_directory(p_query text default '') returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'LOGIN_RICHIESTO';end if;
 return coalesce((select jsonb_agg(jsonb_build_object('id',x.id,'name',x.name,'city',x.city,'level',gd_private.marketing_level(gd_private.marketing_qualified(x.id))) order by x.name,x.id) from (select r.id,r.name,r.city from public.restaurants r join gd_private.marketing_public_cards c on c.restaurant_id=r.id and c.published where r.verified_at is not null and r.suspended_at is null and (position(lower(left(coalesce(p_query,''),100)) in lower(r.name||' '||r.city))>0 or coalesce(p_query,'')='') order by r.name,r.id limit 100) x),'[]'::jsonb);
end $$;
revoke all on function public.marketing_partner(text,uuid,boolean,text),public.marketing_directory(text) from public,anon,authenticated;
grant execute on function public.marketing_partner(text,uuid,boolean,text),public.marketing_directory(text) to authenticated;
create or replace function public.marketing_customer(p_action text,p_restaurant uuid default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid(); r public.restaurants%rowtype; m jsonb; d date:=(now() at time zone 'Europe/Rome')::date; q gd_private.marketing_requests%rowtype;
begin
 if u is null or not exists(select 1 from public.profiles where id=u and role='customer') then raise exception 'ACCESSO_CLIENTE_RICHIESTO';end if;
 if not exists(select 1 from auth.users where id=u and email_confirmed_at is not null and not is_anonymous) then raise exception 'EMAIL_NON_CONFERMATA';end if;
 if p_action='attribute' then
 insert into gd_private.marketing_referrals(customer_id,restaurant_id,channel,created_at)
 select u,s.restaurant_id,s.channel,s.created_at from gd_private.marketing_signup_sources s join public.restaurants v on v.id=s.restaurant_id
 where s.user_id=u and s.channel in ('flyer','social') and v.verified_at is not null and v.suspended_at is null and v.owner_id<>u on conflict(customer_id) do nothing;
 return jsonb_build_object('ok',true);
 end if;
 select * into r from public.restaurants where id=p_restaurant and verified_at is not null and suspended_at is null and owner_id<>u;
 if not found then raise exception 'RISTORANTE_NON_DISPONIBILE';end if;
 if p_action in ('info','open_social') then insert into gd_private.marketing_opens(customer_id,restaurant_id,channel) values(u,r.id,case when p_action='info' then 'flyer' else 'social' end) on conflict do nothing; return jsonb_build_object('name',r.name,'city',r.city,'status',coalesce((select case when status='pending' and requested_at<=now()-interval '30 minutes' then 'expired' else status end from gd_private.marketing_requests where customer_id=u and restaurant_id=r.id and visit_day=d),'none'));end if;
 if p_action<>'request' then raise exception 'AZIONE_NON_VALIDA';end if;
 perform gd_private.assert_merchant_access(r.id,r.owner_id);
 if exists(select 1 from public.visits where customer_id=u and restaurant_id=r.id and visited_on=d and status='confirmed') then return jsonb_build_object('status','confirmed');end if;
 perform pg_advisory_xact_lock(hashtextextended(u::text,0));
 if (select count(*) from gd_private.marketing_requests where customer_id=u and requested_at>now()-interval '1 hour')>=5 then raise exception 'TROPPE_RICHIESTE';end if;
 insert into gd_private.marketing_requests(customer_id,restaurant_id,visit_day) values(u,r.id,d) on conflict(customer_id,restaurant_id,visit_day) do update set requested_at=now(),status='pending' where marketing_requests.status='pending' and marketing_requests.requested_at<=now()-interval '30 minutes';
 select * into q from gd_private.marketing_requests where customer_id=u and restaurant_id=r.id and visit_day=d;
 return jsonb_build_object('status',q.status,'expires_at',q.requested_at+interval '30 minutes');
end $$;

commit;