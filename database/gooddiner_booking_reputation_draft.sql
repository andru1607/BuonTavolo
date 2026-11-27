-- DRAFT: production schema inspected 27/11/2026. Do not apply or enable before final privacy review, global withdrawal integration and authorization tests.
-- Separate from QR sharing. Disabled by default; no changes to existing accounts or RLS.
begin;
create table gd_private.booking_reputation_release (
 singleton boolean primary key default true check(singleton),
 enabled boolean not null default false,
 approved_at timestamptz,
 notice_version text,
 check(not enabled or (approved_at is not null and notice_version is not null and notice_version='booking-reputation-v1'))
);
insert into gd_private.booking_reputation_release(singleton) values(true);
create table gd_private.booking_reputation_grants (
 booking_id uuid primary key references gd_private.bookings(id) on delete cascade,
 customer_id uuid not null references public.profiles(id) on delete cascade,
 notice_version text not null,
 granted_at timestamptz not null,
 revoked_at timestamptz
);
create table gd_private.booking_reputation_access (
 id bigint generated always as identity primary key,
 booking_id uuid not null references gd_private.bookings(id) on delete cascade,
 customer_id uuid not null references public.profiles(id) on delete cascade,
 restaurant_id uuid not null references public.restaurants(id) on delete cascade,
 actor_id uuid not null references public.profiles(id) on delete cascade,
 accessed_at timestamptz not null default clock_timestamp(),
 review_count integer not null check(review_count between 0 and 30)
);
create index gd_booking_reputation_actor_idx on gd_private.booking_reputation_access(actor_id,accessed_at desc);
create index gd_booking_reputation_customer_idx on gd_private.booking_reputation_access(customer_id,accessed_at desc);
alter table gd_private.booking_reputation_release enable row level security;
alter table gd_private.booking_reputation_grants enable row level security;
alter table gd_private.booking_reputation_access enable row level security;
revoke all on gd_private.booking_reputation_release,gd_private.booking_reputation_grants,gd_private.booking_reputation_access from public,anon,authenticated;
revoke all on sequence gd_private.booking_reputation_access_id_seq from public,anon,authenticated;

-- Explicit choice for one online reservation; preliminary signup choices are NOT consent.
create function public.set_booking_reputation_choice(p_booking_id uuid,p_allow boolean,p_notice_version text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid(); b gd_private.bookings%rowtype; g gd_private.booking_reputation_release%rowtype;
begin
 if uid is null or p_allow is null or not gd_private.current_user_email_confirmed() then raise exception 'BOOKING_PROFILE_FORBIDDEN'; end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(uid::text,9412));
 select * into b from gd_private.bookings where id=p_booking_id and customer_id=uid and source='online' for update;
 if not found then raise exception 'BOOKING_PROFILE_FORBIDDEN'; end if;
 if not p_allow then
  update gd_private.booking_reputation_grants set revoked_at=clock_timestamp() where booking_id=b.id and customer_id=uid and revoked_at is null;
  return jsonb_build_object('allowed',false);
 end if;
 select * into g from gd_private.booking_reputation_release where singleton and enabled and approved_at<=now();
 if not found or p_notice_version is distinct from g.notice_version then raise exception 'BOOKING_PROFILE_DISABLED'; end if;
 if b.status not in ('pending','confirmed') or b.starts_at<=now() then raise exception 'BOOKING_PROFILE_FORBIDDEN'; end if;
 if exists(select 1 from public.restaurants where owner_id=uid) then raise exception 'BOOKING_PROFILE_FORBIDDEN'; end if;
 insert into gd_private.booking_reputation_grants(booking_id,customer_id,notice_version,granted_at,revoked_at)
 values(b.id,uid,g.notice_version,clock_timestamp(),null)
 on conflict(booking_id) do update set notice_version=excluded.notice_version,granted_at=excluded.granted_at,revoked_at=null;
 return jsonb_build_object('allowed',true);
end $$;
revoke all on function public.set_booking_reputation_choice(uuid,boolean,text) from public,anon,authenticated;
grant execute on function public.set_booking_reputation_choice(uuid,boolean,text) to authenticated;

-- Only the authenticated owner of the booking venue; no customer ID input.
create function public.read_booking_reputation(p_booking_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid(); b gd_private.bookings%rowtype; g gd_private.booking_reputation_release%rowtype; items jsonb;
begin
 if uid is null or not gd_private.current_user_email_confirmed() then raise exception 'BOOKING_PROFILE_FORBIDDEN'; end if;
 select * into g from gd_private.booking_reputation_release where singleton and enabled and approved_at<=now();
 if not found then return jsonb_build_object('available',false,'reason','disabled'); end if;
 select x.* into b from gd_private.bookings x join public.restaurants r on r.id=x.restaurant_id
 where x.id=p_booking_id and r.owner_id=uid and x.source='online' and x.customer_id<>uid;
 if not found then raise exception 'BOOKING_PROFILE_FORBIDDEN'; end if;
 perform gd_private.assert_merchant_access(b.restaurant_id,uid);
 -- Serialize with customer withdrawal and other reads. Re-check after taking lock.
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(b.customer_id::text,9412));
 select * into b from gd_private.bookings where id=p_booking_id and source='online' and status in ('pending','confirmed') and starts_at>now() for update;
 if not found or b.customer_id=uid then raise exception 'BOOKING_PROFILE_FORBIDDEN'; end if;
 perform gd_private.assert_merchant_access(b.restaurant_id,uid);
 if not exists(select 1 from gd_private.booking_reputation_grants a where a.booking_id=b.id and a.customer_id=b.customer_id and a.revoked_at is null and a.notice_version=g.notice_version and a.granted_at>=g.approved_at) then
  return jsonb_build_object('available',false,'reason','not_authorized');
 end if;
 -- Customer preference withdrawal (including the existing general privacy control) overrides grants.
 if exists(select 1 from gd_private.privacy_choice_events e where e.user_id=b.customer_id and e.event_kind='withdrawal' and e.recorded_at >= (select granted_at from gd_private.booking_reputation_grants where booking_id=b.id)) then
  return jsonb_build_object('available',false,'reason','not_authorized');
 end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(uid::text,9413));
 if (select count(*) from gd_private.booking_reputation_access a where a.actor_id=uid and a.accessed_at>now()-interval '1 minute')>=10 then raise exception 'BOOKING_PROFILE_RATE_LIMIT'; end if;
 -- Reuse the explicit source-visit sharing evidence; no legacy private reviews,
 -- no free text, identifiers, aggregate score or pending/accepted disputes.
 select coalesce(jsonb_agg(jsonb_build_object('restaurant',q.name,'rating',q.rating,'date',q.day) order by q.created_at desc),'[]'::jsonb) into items
 from (select r.name,rv.rating,(rv.created_at at time zone 'Europe/Rome')::date as day,rv.created_at
 from public.reviews rv join public.visits v on v.id=rv.visit_id and v.status='confirmed' and v.customer_id=rv.customer_id and v.restaurant_id=rv.restaurant_id
 join gd_private.reputation_token_choices c on c.token_id=v.token_id and c.revoked_at is null
 join gd_private.visit_tokens t on t.id=c.token_id and t.customer_id=v.customer_id and t.consumed_by=v.restaurant_id and t.consumed_at is not null and t.consumed_at<=t.expires_at
 join gd_private.reputation_release qr on qr.singleton and qr.enabled and qr.approved_at<=now() and qr.approved_notice_version=c.notice_version and c.chosen_at>=qr.approved_at
 join public.restaurants r on r.id=rv.restaurant_id
 where rv.customer_id=b.customer_id and rv.status='published'
 and rv.created_at>=greatest(g.approved_at,now()-interval '12 months') and c.chosen_at>=g.approved_at
 and not exists(select 1 from public.disputes d where d.review_id=rv.id and d.status in ('pending','accepted'))
 order by rv.created_at desc,rv.id limit 30) q;
 insert into gd_private.booking_reputation_access(booking_id,customer_id,restaurant_id,actor_id,review_count)
 values(b.id,b.customer_id,b.restaurant_id,uid,jsonb_array_length(items));
 return jsonb_build_object('available',true,'reviews',items);
end $$;
revoke all on function public.read_booking_reputation(uuid) from public,anon,authenticated;
grant execute on function public.read_booking_reputation(uuid) to authenticated;

-- Customer audit: no caller-supplied identity, includes booking reads only.
create function public.my_booking_reputation_accesses()
returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(jsonb_build_object('restaurant',q.name,'accessed_at',q.accessed_at,'review_count',q.review_count) order by q.accessed_at desc),'[]'::jsonb)
 from (select r.name,a.accessed_at,a.review_count from gd_private.booking_reputation_access a join public.restaurants r on r.id=a.restaurant_id
 where a.customer_id=auth.uid() and a.accessed_at>now()-interval '12 months' order by a.accessed_at desc limit 100) q
$$;
revoke all on function public.my_booking_reputation_accesses() from public,anon,authenticated;
grant execute on function public.my_booking_reputation_accesses() to authenticated;
commit;
