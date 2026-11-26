-- Studio-managed cosmetic catalog. Paid entries are drafts, never purchasable.
alter table gd_private.dinerpass_catalog add column edition_kind text not null default 'achievement' check(edition_kind in ('achievement','paid'));
alter table gd_private.dinerpass_catalog add column price_cents integer;
alter table gd_private.dinerpass_catalog add constraint gd_edition_paid_draft check((edition_kind='achievement' and price_cents is null) or (edition_kind='paid' and price_cents between 99 and 9999 and not enabled));
create table gd_private.dinerpass_artwork (
 code text primary key references gd_private.dinerpass_catalog(code) on delete cascade,
 jpeg bytea not null check(octet_length(jpeg) between 100 and 150000 and substring(jpeg from 1 for 3)=decode('ffd8ff','hex') and substring(jpeg from octet_length(jpeg)-1 for 2)=decode('ffd9','hex')),
 revision uuid not null default gen_random_uuid()
);
alter table gd_private.dinerpass_artwork enable row level security;
revoke all on gd_private.dinerpass_artwork from public,anon,authenticated;
create function gd_studio_private.editions(p_action text,p_payload jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid(); c text; title text; kind text; th text; goal integer; price integer; publish boolean; old gd_private.dinerpass_catalog%rowtype; jpg bytea; encoded text;
begin
 if uid is null or not exists(select 1 from gd_studio_private.operators o join auth.users u on u.id=o.user_id where o.user_id=uid and u.email_confirmed_at is not null and not coalesce(u.is_anonymous,false)) then raise exception 'STUDIO_ACCESS_DENIED' using errcode='42501';end if;
 if p_action='list' then
 return coalesce((select jsonb_agg(jsonb_build_object('code',d.code,'name',d.name,'threshold',d.threshold,'theme',d.theme,'enabled',d.enabled,'kind',d.edition_kind,'price_cents',d.price_cents,'artwork_revision',a.revision,'unlocks',(select count(*) from gd_private.dinerpass_unlocks u where u.code=d.code)) order by d.enabled desc,d.threshold,d.code) from gd_private.dinerpass_catalog d left join gd_private.dinerpass_artwork a on a.code=d.code),'[]'::jsonb);
 end if;
 c:=p_payload->>'code';
 if c is null or c !~ '^[a-z0-9-]{1,40}$' then raise exception 'CODICE_EDIZIONE_NON_VALIDO';end if;
 if p_action='artwork' then return (select jsonb_build_object('jpeg',replace(encode(a.jpeg,'base64'),E'\n','')) from gd_private.dinerpass_artwork a where a.code=c);end if;
 if p_action<>'save' then raise exception 'STUDIO_ACTION_INVALID';end if;
 perform pg_catalog.pg_advisory_xact_lock(9432);
 select * into old from gd_private.dinerpass_catalog where code=c for update;
 title:=btrim(p_payload->>'name');kind:=p_payload->>'kind';th:=p_payload->>'theme';goal:=(p_payload->>'threshold')::integer;price:=(p_payload->>'price_cents')::integer;publish:=coalesce((p_payload->>'publish')::boolean,false);
 if title is null or char_length(title) not between 1 and 60 or kind is null or kind not in ('achievement','paid') or th is null or th not in ('original','explorer','connoisseur','icon','legend') or goal is null or goal not between 0 and 10000 then raise exception 'PARAMETRI_EDIZIONE_NON_VALIDI';end if;
 if kind='paid' then
 if price is null or price not between 99 and 9999 or publish then raise exception 'EDIZIONE_PAGAMENTO_SOLO_BOZZA';end if;
 goal:=0;
 else price:=null;end if;
 if old.code is null then
 if (select count(*) from gd_private.dinerpass_catalog)>=100 then raise exception 'CATALOGO_PIENO';end if;
 if kind='achievement' and goal=0 then raise exception 'TRAGUARDO_MINIMO_UNO';end if;
 else
 if old.enabled and (not publish or old.threshold<>goal or old.edition_kind<>kind) then raise exception 'REGOLA_EDIZIONE_PUBBLICATA_IMMUTABILE';end if;
 end if;
 encoded:=p_payload->>'jpeg';
 if encoded is not null then
 if char_length(encoded)>200000 or encoded !~ '^[A-Za-z0-9+/]+={0,2}$' then raise exception 'IMMAGINE_NON_VALIDA';end if;
 jpg:=decode(encoded,'base64');
 if octet_length(jpg) not between 100 and 150000 or substring(jpg from 1 for 3)<>decode('ffd8ff','hex') or substring(jpg from octet_length(jpg)-1 for 2)<>decode('ffd9','hex') then raise exception 'IMMAGINE_NON_VALIDA';end if;
 end if;
 insert into gd_private.dinerpass_catalog(code,name,threshold,theme,enabled,edition_kind,price_cents) values(c,title,goal,th,publish,kind,price)
 on conflict(code) do update set name=excluded.name,threshold=excluded.threshold,theme=excluded.theme,enabled=excluded.enabled,edition_kind=excluded.edition_kind,price_cents=excluded.price_cents;
 if jpg is not null then insert into gd_private.dinerpass_artwork(code,jpeg) values(c,jpg) on conflict(code) do update set jpeg=excluded.jpeg,revision=gen_random_uuid();end if;
 insert into gd_studio_private.audit(actor,action,target) values(uid,'edition_save',c);
 return jsonb_build_object('ok',true);
end $$;
revoke all on function gd_studio_private.editions(text,jsonb) from public,anon,authenticated;
grant execute on function gd_studio_private.editions(text,jsonb) to authenticated;
create function public.gooddiner_studio_editions(p_action text,p_payload jsonb default '{}'::jsonb)
returns jsonb language sql security invoker set search_path='' as $$ select gd_studio_private.editions(p_action,p_payload) $$;
revoke all on function public.gooddiner_studio_editions(text,jsonb) from public,anon,authenticated;
grant execute on function public.gooddiner_studio_editions(text,jsonb) to authenticated;
create or replace function public.my_dinerpass_collection()
returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid(); n integer; chosen text;
begin
 if uid is null or not exists(select 1 from public.profiles p where p.id=uid)
 or exists(select 1 from public.restaurants r where r.owner_id=uid) then raise exception 'ACCESSO_CLIENTE_RICHIESTO';end if;
 n:=gd_private.sync_dinerpass_unlocks(uid);
 select s.code into chosen from gd_private.dinerpass_selection s join gd_private.dinerpass_catalog c on c.code=s.code and c.enabled where s.customer_id=uid;
 return jsonb_build_object('progress',n,'selected',coalesce(chosen,'original'),'cards',
 (select jsonb_agg(jsonb_build_object('code',c.code,'name',c.name,'threshold',c.threshold,'theme',c.theme,'artwork_path',c.artwork_path,'artwork_revision',a.revision,'unlocked',u.code is not null) order by c.threshold,c.code)
 from gd_private.dinerpass_catalog c left join gd_private.dinerpass_artwork a on a.code=c.code left join gd_private.dinerpass_unlocks u on u.code=c.code and u.customer_id=uid where c.enabled));
end $$;
revoke all on function public.my_dinerpass_collection() from public,anon,authenticated;
grant execute on function public.my_dinerpass_collection() to authenticated;

create function public.my_dinerpass_artwork(p_code text,p_revision uuid)
returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('jpeg',replace(encode(a.jpeg,'base64'),E'\n','')) from gd_private.dinerpass_artwork a join gd_private.dinerpass_catalog c on c.code=a.code
 where auth.uid() is not null and exists(select 1 from public.profiles p where p.id=auth.uid())
 and c.enabled and a.code=p_code and a.revision=p_revision
$$;
revoke all on function public.my_dinerpass_artwork(text,uuid) from public,anon,authenticated;
grant execute on function public.my_dinerpass_artwork(text,uuid) to authenticated;
