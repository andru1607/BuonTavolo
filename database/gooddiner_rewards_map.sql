-- Locations are entered by verified restaurant owners, never inferred from customer GPS.
create table gd_private.reward_locations (
 restaurant_id uuid primary key references public.restaurants(id) on delete cascade,
 address text not null check(char_length(btrim(address)) between 5 and 200),
 latitude double precision not null check(latitude between -85 and 85),
 longitude double precision not null check(longitude between -180 and 180),
 updated_at timestamptz not null default now()
);
alter table gd_private.reward_locations enable row level security;
revoke all on gd_private.reward_locations from public,anon,authenticated;
create or replace function gd_private.reward_map(p_action text,p_payload jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); venue uuid; addr text; lat double precision; lon double precision; active boolean;
begin
 if actor is null or not exists(select 1 from public.profiles where id=actor) then raise exception 'LOGIN_RICHIESTO'; end if;
 if p_action in ('location_get','location_set') then
  venue:=(p_payload->>'restaurant_id')::uuid;
  perform gd_private.assert_merchant_access(venue,actor);
  if p_action='location_set' then
   addr:=btrim(p_payload->>'address');lat:=(p_payload->>'latitude')::double precision;lon:=(p_payload->>'longitude')::double precision;
   if addr is null or char_length(addr) not between 5 and 200 or lat is null or lon is null or not(lat between -85 and 85 and lon between -180 and 180) then raise exception 'POSIZIONE_NON_VALIDA'; end if;
   insert into gd_private.reward_locations(restaurant_id,address,latitude,longitude) values(venue,addr,lat,lon)
   on conflict(restaurant_id) do update set address=excluded.address,latitude=excluded.latitude,longitude=excluded.longitude,updated_at=now();
  end if;
  return coalesce((select jsonb_build_object('address',address,'latitude',latitude,'longitude',longitude) from gd_private.reward_locations where restaurant_id=venue),'{}'::jsonb);
 elsif p_action='catalog' then
  select personal_reviews_enabled and rewards_enabled into active from gd_private.business_features where singleton;
  if not coalesce(active,false) then return '{"active":false,"offers":[]}'::jsonb; end if;
  return jsonb_build_object('active',true,'offers',(select coalesce(jsonb_agg(jsonb_build_object('id',r.id,'name',r.name,'city',r.city,'percent',o.percent,'address',loc.address,'latitude',loc.latitude,'longitude',loc.longitude) order by r.name),'[]'::jsonb)
   from gd_private.reward_offers o join public.restaurants r on r.id=o.restaurant_id
   join gd_private.merchant_licenses l on l.restaurant_id=r.id left join gd_private.reward_locations loc on loc.restaurant_id=r.id
   where o.enabled and r.verified_at is not null and r.suspended_at is null and l.status in ('trialing','active') and l.active_until>now() and r.owner_id<>actor));
 else raise exception 'AZIONE_NON_VALIDA'; end if;
end $$;
revoke all on function gd_private.reward_map(text,jsonb) from public,anon,authenticated;
grant execute on function gd_private.reward_map(text,jsonb) to authenticated;
create or replace function public.gooddiner_reward_map(p_action text,p_payload jsonb default '{}'::jsonb)
returns jsonb language sql security invoker set search_path='' as $$ select gd_private.reward_map(p_action,p_payload) $$;
revoke all on function public.gooddiner_reward_map(text,jsonb) from public,anon,authenticated;
grant execute on function public.gooddiner_reward_map(text,jsonb) to authenticated;