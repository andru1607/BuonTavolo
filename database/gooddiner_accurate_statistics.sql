-- GoodDiner: exact counts independent of the browser's 250-item history pages.
-- Security invoker uses existing RLS; exposed only to signed-in users.
create or replace function public.get_my_dinerpass_counts()
returns table (
  confirmed_visits bigint,
  published_reviews bigint,
  positive_reviews bigint,
  pending_rewards bigint
)
language sql stable security invoker set search_path = ''
as $$
  select
    (select count(*) from public.visits v
      where v.customer_id=auth.uid() and v.status='confirmed')::bigint,
    (select count(*) from public.reviews r
      where r.customer_id=auth.uid() and r.status='published')::bigint,
    (select count(*) from public.reviews r
      where r.customer_id=auth.uid() and r.status='published' and r.rating>=8)::bigint,
    (select count(*) from public.vouchers v
      where v.customer_id=auth.uid() and v.status='pending')::bigint
  where auth.uid() is not null;
$$;
revoke all on function public.get_my_dinerpass_counts() from public,anon,authenticated;
grant execute on function public.get_my_dinerpass_counts() to authenticated;

create or replace function public.get_my_restaurant_counts(p_restaurant_id uuid)
returns table (
  confirmed_visits bigint,
  published_reviews bigint,
  todays_visits bigint
)
language sql stable security invoker set search_path = ''
as $$
  select
    (select count(*) from public.visits v
      where v.restaurant_id=r.id and v.status='confirmed')::bigint,
    (select count(*) from public.reviews rv
      where rv.restaurant_id=r.id and rv.status='published')::bigint,
    (select count(*) from public.visits v
      where v.restaurant_id=r.id and v.status='confirmed'
        and v.visited_on=(now() at time zone 'Europe/Rome')::date)::bigint
  from public.restaurants r
  where r.id=p_restaurant_id and r.owner_id=auth.uid()
    and r.verified_at is not null and r.suspended_at is null;
$$;
revoke all on function public.get_my_restaurant_counts(uuid) from public,anon,authenticated;
grant execute on function public.get_my_restaurant_counts(uuid) to authenticated;
comment on function public.get_my_dinerpass_counts() is 'Exact personal counts from RLS, not a truncated browser list.';
comment on function public.get_my_restaurant_counts(uuid) is 'Verified owner-only counts for the requested restaurant, using RLS.';
