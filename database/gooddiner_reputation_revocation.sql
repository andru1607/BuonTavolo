-- Revocation covers all previously chosen shared visits and still-valid QR codes.
alter table gd_private.reputation_token_choices add column revoked_at timestamptz;
alter table gd_private.reputation_token_choices add column notice_version text not null default 'sharing-v1';
create or replace function public.issue_shared_dinerpass_qr()
returns table(qr_token text, expires_at timestamptz)
language plpgsql security definer set search_path='' as $$
declare issued record; uid uuid:=auth.uid();
begin
 if uid is null or not exists(select 1 from gd_private.reputation_release g where g.singleton and g.enabled and g.approved_at<=now()) then
  raise exception 'CONDIVISIONE_NON_ATTIVA';
 end if;
 if exists(select 1 from public.restaurants r where r.owner_id=uid) then raise exception 'ACCESSO_CLIENTE_RICHIESTO'; end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(uid::text,9412));
 select * into issued from public.issue_guest_qr();
 insert into gd_private.reputation_token_choices(token_id) values(substring(issued.qr_token from 5)::uuid);
 return query select issued.qr_token,issued.expires_at;
end $$;
revoke all on function public.issue_shared_dinerpass_qr() from public,anon,authenticated;
grant execute on function public.issue_shared_dinerpass_qr() to authenticated;


create or replace function public.read_shared_dinerpass_reviews(p_visit_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid(); v public.visits%rowtype; cutoff timestamptz; items jsonb; n integer;
begin
 if uid is null then raise exception 'ACCESSO_NON_AUTORIZZATO'; end if;
 select approved_at into cutoff from gd_private.reputation_release where singleton and enabled and approved_at<=now();
 if cutoff is null then return jsonb_build_object('available',false); end if;
 -- Caller must own the venue, have scanned the customer, have a current license,
 -- and hold a fresh, confirmed visit from an explicitly shared QR. No customer-ID lookup.
 select * into v from public.visits where id=p_visit_id and scanned_by=uid
 and status='confirmed' and checked_in_at>now()-interval '5 minutes' for update;
 if not found or v.customer_id=uid then raise exception 'ACCESSO_NON_AUTORIZZATO'; end if;
 perform gd_private.assert_merchant_access(v.restaurant_id,uid);
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v.customer_id::text,9412));
 if not exists(select 1 from gd_private.reputation_token_choices c
 join gd_private.visit_tokens t on t.id=c.token_id
 where c.token_id=v.token_id and c.chosen_at>=cutoff and c.revoked_at is null
 and t.customer_id=v.customer_id and t.consumed_by=v.restaurant_id
 and t.consumed_at is not null and t.consumed_at<=t.expires_at)
 then return jsonb_build_object('available',false); end if;
 if exists(select 1 from gd_private.reputation_access_log a where a.visit_id=v.id) then raise exception 'CONSULTAZIONE_GIA_ESEGUITA'; end if;
 if (select count(*) from gd_private.reputation_access_log a where a.actor_id=uid and a.accessed_at>now()-interval '1 minute')>=10 then raise exception 'TROPPE_CONSULTAZIONI'; end if;
 -- Only newly collected reviews from an explicitly share-enabled source visit.
 -- No legacy private reviews, free text, identifiers, pending/accepted disputes,
 -- aggregate person score, other visit details, or ratings older than 12 months.
 select coalesce(jsonb_agg(jsonb_build_object('restaurant',q.name,'rating',q.rating,'date',q.day) order by q.created_at desc),'[]'::jsonb)
 into items from (
 select r.name,rv.rating,(rv.created_at at time zone 'Europe/Rome')::date as day,rv.created_at
 from public.reviews rv join public.visits source on source.id=rv.visit_id and source.status='confirmed'
 join gd_private.reputation_token_choices c on c.token_id=source.token_id
 join public.restaurants r on r.id=rv.restaurant_id
 where rv.customer_id=v.customer_id and rv.status='published'
 and rv.created_at>=greatest(cutoff,now()-interval '12 months') and c.chosen_at>=cutoff and c.revoked_at is null
 and not exists(select 1 from public.disputes d where d.review_id=rv.id and d.status in ('pending','accepted'))
 order by rv.created_at desc,rv.id limit 30
 ) q;
 n:=jsonb_array_length(items);
 insert into gd_private.reputation_access_log(visit_id,customer_id,restaurant_id,actor_id,review_count)
 values(v.id,v.customer_id,v.restaurant_id,uid,n);
 return jsonb_build_object('available',true,'reviews',items);
end $$;
revoke all on function public.read_shared_dinerpass_reviews(uuid) from public,anon,authenticated;
grant execute on function public.read_shared_dinerpass_reviews(uuid) to authenticated;


create function public.revoke_dinerpass_sharing()
returns integer language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid(); n integer;
begin
 if uid is null then raise exception 'ACCESSO_CLIENTE_RICHIESTO'; end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(uid::text,9412));
 update gd_private.reputation_token_choices c set revoked_at=clock_timestamp()
 from gd_private.visit_tokens t where t.id=c.token_id and t.customer_id=uid and c.revoked_at is null;
 get diagnostics n=row_count;
 return n;
end $$;
revoke all on function public.revoke_dinerpass_sharing() from public,anon,authenticated;
grant execute on function public.revoke_dinerpass_sharing() to authenticated;
