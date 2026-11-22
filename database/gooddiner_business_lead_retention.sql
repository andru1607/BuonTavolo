-- GoodDiner: daily removal of expired B2B pilot inquiry contact details.
-- Apply ONLY to Supabase project ixczkhmvbjszgmlqznlk.
-- No collection is authorized merely by creating this retention schedule.
-- Retention 90 days is a product default requiring owner/legal approval
-- before activating businessLeadIntakeEnabled in the browser.

create extension if not exists pg_cron with schema pg_catalog;
grant usage on schema cron to postgres;
grant all privileges on all tables in schema cron to postgres;

select cron.schedule(
  'gooddiner-pilot-lead-retention',
  '20 3 * * *',
  $job$delete from public.business_pilot_leads where delete_after < now();$job$
);

comment on table public.business_pilot_leads is
  'Business inquiry queue with zero client SELECT/INSERT grants. pg_cron removes expired entries every day; verify outcomes in cron.job_run_details.';
