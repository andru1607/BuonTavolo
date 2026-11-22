-- GoodDiner Business pilot: minimal restaurant lead queue, server inserts only.
-- Do not enable public lead intake until Turnstile + approved privacy notice.
-- Target only dedicated Supabase GoodDiner project ixczkhmvbjszgmlqznlk.

create table public.business_pilot_leads (
  id uuid primary key default gen_random_uuid(),
  restaurant_name text not null check (char_length(btrim(restaurant_name)) between 3 and 100),
  city text not null check (char_length(btrim(city)) between 2 and 100),
  contact_email text not null check (char_length(contact_email) between 5 and 254
    and position('@' in contact_email)>1),
  source_hash text not null check (char_length(source_hash)=64),
  contact_requested boolean not null default true check (contact_requested=true),
  status text not null default 'new' check (status in ('new','contacted','converted','rejected')),
  created_at timestamptz not null default now(),
  delete_after timestamptz not null default (now()+interval '90 days')
);
create unique index gd_pilot_leads_unique_email
  on public.business_pilot_leads(lower(contact_email));
create index gd_pilot_leads_source_time
  on public.business_pilot_leads(source_hash,created_at desc);
create index gd_pilot_leads_due_delete
  on public.business_pilot_leads(delete_after);
alter table public.business_pilot_leads enable row level security;
revoke all on public.business_pilot_leads from public,anon,authenticated;
comment on table public.business_pilot_leads is
  'Non-public prospect queue, only service-role server inserts after verified CAPTCHA. Human privacy and retention review required.';

-- The date is a review deadline, not proof automatic deletion. Operators must
-- run the retention job in the published runbook before enabling intake.
