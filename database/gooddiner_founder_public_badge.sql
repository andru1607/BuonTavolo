begin;
create or replace function public.marketing_partner(p_action text,p_restaurant uuid,p_publish boolean default null,p_reward text default null) returns jsonb language plpgsql security definer set search_path='' as $$
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
 elsif p_action='request_reward' then raise exception 'USA_REGISTRO_PREMI_AGGIORNATO';
 elsif p_action<>'stats' then raise exception 'AZIONE_NON_VALIDA';end if;
 return jsonb_build_object('qualified',n,'level',gd_private.marketing_level(n),'invited_merchants',invited_n,'verified_merchants',verified_n,'active_merchants',active_n,'published',coalesce((select published from gd_private.marketing_public_cards where restaurant_id=p_restaurant),false),'requested_rewards',coalesce((select jsonb_agg(reward_code order by requested_at) from gd_private.marketing_reward_requests where restaurant_id=p_restaurant),'[]'::jsonb));
end $$;
create or replace function public.marketing_directory(p_query text default '') returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'LOGIN_RICHIESTO';end if;
 return coalesce((select jsonb_agg(jsonb_build_object('id',x.id,'name',x.name,'city',x.city,'level',gd_private.marketing_level(gd_private.marketing_qualified(x.id)),'founder_number',(select founder_number from gd_private.marketing_founders where restaurant_id=x.id)) order by x.name,x.id) from (select r.id,r.name,r.city from public.restaurants r join gd_private.marketing_public_cards c on c.restaurant_id=r.id and c.published where r.verified_at is not null and r.suspended_at is null and (position(lower(left(coalesce(p_query,''),100)) in lower(r.name||' '||r.city))>0 or coalesce(p_query,'')='') order by r.name,r.id limit 100) x),'[]'::jsonb);
end $$;

commit;