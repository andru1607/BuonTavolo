-- GoodDiner: gated, customer-directed disclosure after a confirmed scan.
-- Existing RLS remains unchanged. Never enable before documented DPIA/legal approval.
create table gd_private.reputation_release (
 singleton boolean primary key default true check(singleton),
 enabled boolean not null default false,
 approved_at timestamptz,
 check(not enabled or approved_at is not null)
);
insert into gd_private.reputation_release(singleton) values(true);
create table gd_private.reputation_token_choices (
 token_id uuid primary key references gd_private.visit_tokens(id) on delete cascade,
 chosen_at timestamptz not null default now()
);
create table gd_private.reputation_access_log (
 visit_id uuid primary key references public.visits(id) on delete cascade,
 customer_id uuid not null references public.profiles(id) on delete cascade,
 restaurant_id uuid not null references public.restaurants(id) on delete cascade,
 actor_id uuid not null references public.profiles(id) on delete cascade,
 accessed_at timestamptz not null default now(),
 review_count integer not null check(review_count between 0 and 30)
);
create index reputation_access_customer_idx on gd_private.reputation_access_log(customer_id,accessed_at desc);
create index reputation_access_actor_idx on gd_private.reputation_access_log(actor_id,accessed_at desc);
alter table gd_private.reputation_release enable row level security;
alter table gd_private.reputation_token_choices enable row level security;
alter table gd_private.reputation_access_log enable row level security;
revoke all on gd_private.reputation_release,gd_private.reputation_token_choices,gd_private.reputation_access_log from public,anon,authenticated;

create function public.issue_shared_dinerpass_qr()
returns table(qr_token text, expires_at timestamptz)
language plpgsql security definer set search_path='' as $$
declare issued record; uid uuid:=auth.uid();
begin
 if uid is null or not exists(select 1 from gd_private.reputation_release g where g.singleton and g.enabled and g.approved_at<=now()) then
  raise exception 'CONDIVISIONE_NON_ATTIVA';
 end if;
 if exists(select 1 from public.restaurants r where r.owner_id=uid) then raise exception 'ACCESSO_CLIENTE_RICHIESTO'; end if;
 select * into issued from public.issue_guest_qr();
 insert into gd_private.reputation_token_choices(token_id) values(substring(issued.qr_token from 5)::uuid);
 return query select issued.qr_token,issued.expires_at;
end $$;
revoke all on function public.issue_shared_dinerpass_qr() from public,anon,authenticated;
grant execute on function public.issue_shared_dinerpass_qr() to authenticated;

create function public.read_shared_dinerpass_reviews(p_visit_id uuid)
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
 if not exists(select 1 from gd_private.reputation_token_choices c
 join gd_private.visit_tokens t on t.id=c.token_id
 where c.token_id=v.token_id and c.chosen_at>=cutoff
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
 and rv.created_at>=greatest(cutoff,now()-interval '12 months') and c.chosen_at>=cutoff
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

create function public.my_reputation_accesses()
returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(jsonb_build_object('restaurant',q.name,'accessed_at',q.accessed_at,'review_count',q.review_count) order by q.accessed_at desc),'[]'::jsonb)
 from (select r.name,a.accessed_at,a.review_count from gd_private.reputation_access_log a join public.restaurants r on r.id=a.restaurant_id
 where a.customer_id=auth.uid() and a.accessed_at>now()-interval '12 months' order by a.accessed_at desc limit 100) q
$$;
revoke all on function public.my_reputation_accesses() from public,anon,authenticated;
grant execute on function public.my_reputation_accesses() to authenticated;
