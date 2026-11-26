begin;
create table gd_private.marketing_opens(customer_id uuid references public.profiles(id) on delete cascade,restaurant_id uuid references public.restaurants(id) on delete cascade,channel text check(channel in ('flyer','social')),created_at timestamptz not null default now(),primary key(customer_id,restaurant_id,channel));
alter table gd_private.marketing_opens enable row level security;
revoke all on gd_private.marketing_opens from public,anon,authenticated;
create or replace function public.marketing_customer(p_action text,p_restaurant uuid default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid(); r public.restaurants%rowtype; m jsonb; d date:=(now() at time zone 'Europe/Rome')::date; q gd_private.marketing_requests%rowtype;
begin
 if u is null or not exists(select 1 from public.profiles where id=u and role='customer') then raise exception 'ACCESSO_CLIENTE_RICHIESTO';end if;
 if not exists(select 1 from auth.users where id=u and email_confirmed_at is not null and not is_anonymous) then raise exception 'EMAIL_NON_CONFERMATA';end if;
 if p_action='attribute' then
 select raw_user_meta_data into m from auth.users where id=u and created_at>now()-interval '30 days';
 if m->>'gd_marketing_restaurant' ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' and m->>'gd_marketing_channel' in ('flyer','social') then
 insert into gd_private.marketing_referrals(customer_id,restaurant_id,channel) select u,id,m->>'gd_marketing_channel' from public.restaurants where id=(m->>'gd_marketing_restaurant')::uuid and owner_id<>u and verified_at is not null and suspended_at is null on conflict(customer_id) do nothing;
 end if; return jsonb_build_object('ok',true);
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
create or replace function public.marketing_merchant(p_action text,p_restaurant uuid,p_request uuid default null,p_logo text default null,p_photo text default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid(); q gd_private.marketing_requests%rowtype; tok uuid; total integer; qualified integer; v integer; pending jsonb; a gd_private.marketing_assets%rowtype;
begin
 if u is null or not exists(select 1 from public.restaurants where id=p_restaurant and owner_id=u and verified_at is not null and suspended_at is null) then raise exception 'RISTORANTE_NON_VERIFICATO';end if;
 if p_action='assets' then
 if (p_logo is not null and (length(p_logo)>350000 or p_logo !~ '^data:image/jpeg;base64,[A-Za-z0-9+/]+={0,2}$')) or (p_photo is not null and (length(p_photo)>650000 or p_photo !~ '^data:image/jpeg;base64,[A-Za-z0-9+/]+={0,2}$')) then raise exception 'IMMAGINE_NON_VALIDA';end if;
 insert into gd_private.marketing_assets(restaurant_id,logo,photo) values(p_restaurant,p_logo,p_photo) on conflict(restaurant_id) do update set logo=excluded.logo,photo=excluded.photo,updated_at=now();
 elsif p_action in ('confirm','decline') then
 perform gd_private.assert_merchant_access(p_restaurant,u);
 select * into q from gd_private.marketing_requests where id=p_request and restaurant_id=p_restaurant and status='pending' and requested_at>now()-interval '30 minutes' and visit_day=(now() at time zone 'Europe/Rome')::date for update;
 if not found then raise exception 'RICHIESTA_SCADUTA';end if;
 if p_action='confirm' then
 if q.customer_id=u then raise exception 'AUTO_VISITA_NON_AMMESSA';end if;
 if not exists(select 1 from public.visits where customer_id=q.customer_id and restaurant_id=p_restaurant and visited_on=q.visit_day and status='confirmed') then
 insert into gd_private.visit_tokens(customer_id) values(q.customer_id) returning id into tok;
 perform public.checkin_guest('GD1:'||tok::text,p_restaurant);
 end if;
 update gd_private.marketing_requests set status='confirmed' where id=q.id;
 else update gd_private.marketing_requests set status='declined' where id=q.id;end if;
 elsif p_action<>'stats' then raise exception 'AZIONE_NON_VALIDA';end if;
 select count(*) into total from gd_private.marketing_referrals where restaurant_id=p_restaurant;
 select count(*) into qualified from gd_private.marketing_referrals f where f.restaurant_id=p_restaurant and exists(select 1 from public.visits z where z.customer_id=f.customer_id and z.restaurant_id=p_restaurant and z.status='confirmed' and z.checked_in_at>=f.created_at);
 select count(*) into v from gd_private.marketing_requests req where req.restaurant_id=p_restaurant and req.status='confirmed' and exists(select 1 from public.visits z where z.customer_id=req.customer_id and z.restaurant_id=req.restaurant_id and z.visited_on=req.visit_day and z.status='confirmed');
 select coalesce(jsonb_agg(jsonb_build_object('id',s.id,'nickname',s.nickname,'requested_at',s.requested_at)),'[]'::jsonb) into pending from (select req.id,p.nickname,req.requested_at from gd_private.marketing_requests req join public.profiles p on p.id=req.customer_id where req.restaurant_id=p_restaurant and req.status='pending' and req.requested_at>now()-interval '30 minutes' and req.visit_day=(now() at time zone 'Europe/Rome')::date order by req.requested_at limit 100) s;
 select * into a from gd_private.marketing_assets where restaurant_id=p_restaurant;
 return jsonb_build_object('opens',(select count(*) from gd_private.marketing_opens where restaurant_id=p_restaurant),'flyer_registrations',(select count(*) from gd_private.marketing_referrals where restaurant_id=p_restaurant and channel='flyer'),'social_registrations',(select count(*) from gd_private.marketing_referrals where restaurant_id=p_restaurant and channel='social'),'registrations',total,'qualified',qualified,'confirmed_requests',v,'pending',pending,'logo',a.logo,'photo',a.photo);
end $$;

commit;