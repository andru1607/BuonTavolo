-- GoodDiner security hardening: verified restaurant owners must never check
-- themselves in or assign themselves a rating using their own DinerPass.
-- Applied ONLY to dedicated Supabase project ixczkhmvbjszgmlqznlk.
-- These constraints protect every write path, including privileged RPCs.

alter table public.visits
  add constraint gd_no_self_checkin check (customer_id <> scanned_by);

alter table public.reviews
  add constraint gd_no_self_rating check (customer_id <> rater_id);

comment on constraint gd_no_self_checkin on public.visits is
  'An owner cannot record their own DinerPass as a verified visit.';
comment on constraint gd_no_self_rating on public.reviews is
  'No user may rate themselves, including via a privileged server routine.';
