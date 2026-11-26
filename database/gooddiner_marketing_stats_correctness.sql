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
 return jsonb_build_object('registrations',total,'qualified',qualified,'confirmed_requests',v,'pending',pending,'logo',a.logo,'photo',a.photo);
end $$;
