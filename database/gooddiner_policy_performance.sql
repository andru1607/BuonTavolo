-- GoodDiner migration: gooddiner_policy_performance_baseline
-- Applied to Supabase project ixczkhmvbjszgmlqznlk on 2026-11-20.
-- Secondary indexes for foreign keys and cached JWT evaluation in RLS.
create index if not exists gd_visit_audit_actor_idx on gd_private.visit_audit(actor_id);
create index if not exists gd_visit_audit_visit_idx on gd_private.visit_audit(visit_id);
create index if not exists gd_visit_tokens_consumed_idx on gd_private.visit_tokens(consumed_by);
create index if not exists gd_disputes_customer_idx on public.disputes(customer_id);
create index if not exists gd_reviews_rater_idx on public.reviews(rater_id);
create index if not exists gd_visits_scanner_idx on public.visits(scanned_by);
alter policy gd_applications_request on public.merchant_applications
with check (
  applicant_id=(select auth.uid()) and status='pending' and reviewed_at is null
  and coalesce(((select auth.jwt())->>'is_anonymous')::boolean,false)=false
);
