-- GoodDiner: fail closed merchant applications until an email is confirmed.
-- A customer account is still allowed, but may not request verified venue access.
create or replace function gd_private.current_user_email_confirmed()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from auth.users u
    where u.id = (select auth.uid())
      and u.email is not null and btrim(u.email) <> ''
      and u.email_confirmed_at is not null
      and u.is_anonymous is false
  );
$$;
revoke all on function gd_private.current_user_email_confirmed()
  from public,anon,authenticated;
grant usage on schema gd_private to authenticated;
grant execute on function gd_private.current_user_email_confirmed()
  to authenticated;
drop policy if exists gd_applications_request on public.merchant_applications;
create policy gd_applications_request on public.merchant_applications
  for insert to authenticated
  with check (
    applicant_id=(select auth.uid()) and status='pending' and reviewed_at is null
    and coalesce((select (auth.jwt()->>'is_anonymous')::boolean),false)=false
    and (select gd_private.current_user_email_confirmed())
  );
comment on function gd_private.current_user_email_confirmed() is
  'Self-only verified-email check used by merchant application RLS; never authorizes venue access.';
