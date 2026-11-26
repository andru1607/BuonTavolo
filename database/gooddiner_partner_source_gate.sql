create or replace function gd_private.capture_marketing_source() returns trigger language plpgsql security definer set search_path='' as $$
declare m jsonb:=new.raw_user_meta_data; rid text; src text;
begin
 if exists(select 1 from gd_private.signup_invites i where i.used_by=new.id and i.purpose='merchant' and i.used_at is not null) then
 rid:=m->>'gd_merchant_referrer';src:='merchant';
 else rid:=m->>'gd_marketing_restaurant';src:=m->>'gd_marketing_channel';if src is null or src not in ('flyer','social') then return new;end if;end if;
 if rid ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' and src in ('flyer','social','merchant') then
 insert into gd_private.marketing_signup_sources(user_id,restaurant_id,channel)
 select new.id,r.id,src from public.restaurants r where r.id=rid::uuid and r.owner_id<>new.id and r.verified_at is not null and r.suspended_at is null on conflict(user_id) do nothing;
 end if;
 return new;
end $$;
