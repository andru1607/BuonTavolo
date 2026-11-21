-- GoodDiner · Operator-only moderation baseline.
-- Apply to Supabase project ixczkhmvbjszgmlqznlk ONLY, as database owner.
-- No callable moderation functions in the public Data API.
-- An operator must verify evidence independently before invoking these functions.
-- Never store proof documents, sensitive personal data or secrets in audit notes.

create table if not exists gd_private.operator_audit (
  id bigint generated always as identity primary key,
  action_type text not null check (action_type in
    ('application_approved','application_rejected','dispute_accepted','dispute_rejected')),
  target_id uuid not null,
  operator_label text not null check (char_length(btrim(operator_label)) between 3 and 100),
  decision_note text not null check (char_length(btrim(decision_note)) between 10 and 500),
  created_at timestamptz not null default now()
);
alter table gd_private.operator_audit enable row level security;
revoke all on gd_private.operator_audit from public, anon, authenticated;
revoke all on sequence gd_private.operator_audit_id_seq from public, anon, authenticated;

create or replace function gd_private.review_merchant_application(
  p_application_id uuid,
  p_approve boolean,
  p_operator_label text,
  p_decision_note text
)
returns uuid
language plpgsql security invoker set search_path = '' as $$
declare
  app public.merchant_applications%rowtype;
  venue_id uuid;
begin
  if current_user <> 'postgres' then raise exception 'OPERATORE_NON_AUTORIZZATO'; end if;
  if p_application_id is null or p_approve is null or
     p_operator_label is null or char_length(btrim(p_operator_label)) not between 3 and 100 or
     p_decision_note is null or char_length(btrim(p_decision_note)) not between 10 and 500 then
    raise exception 'PARAMETRI_REVISIONE_NON_VALIDI';
  end if;
  select * into app from public.merchant_applications a
    where a.id=p_application_id for update;
  if not found or app.status <> 'pending' then
    raise exception 'RICHIESTA_NON_IN_ATTESA';
  end if;
  if p_approve then
    -- Email confirmation is necessary, but NOT sufficient to prove venue ownership.
    if not exists(select 1 from auth.users u where u.id=app.applicant_id
      and u.email_confirmed_at is not null and coalesce(u.is_anonymous,false)=false) then
      raise exception 'ACCOUNT_RISTORATORE_NON_VERIFICATO';
    end if;
    insert into public.restaurants(owner_id,application_id,name,city,verified_at)
      values(app.applicant_id,app.id,app.restaurant_name,app.city,now())
      returning id into venue_id;
  end if;
  update public.merchant_applications
    set status=(case when p_approve then 'approved' else 'rejected' end),
        reviewed_at=now()
    where id=app.id;
  insert into gd_private.operator_audit(action_type,target_id,operator_label,decision_note)
    values(case when p_approve then 'application_approved' else 'application_rejected' end,
      app.id,btrim(p_operator_label),btrim(p_decision_note));
  return venue_id; -- null for rejected applications
end;
$$;
revoke all on function gd_private.review_merchant_application(uuid,boolean,text,text)
  from public, anon, authenticated;

create or replace function gd_private.resolve_guest_dispute(
  p_dispute_id uuid,
  p_accept boolean,
  p_operator_label text,
  p_decision_note text
)
returns boolean
language plpgsql security invoker set search_path = '' as $$
declare
  item public.disputes%rowtype;
begin
  if current_user <> 'postgres' then raise exception 'OPERATORE_NON_AUTORIZZATO'; end if;
  if p_dispute_id is null or p_accept is null or
     p_operator_label is null or char_length(btrim(p_operator_label)) not between 3 and 100 or
     p_decision_note is null or char_length(btrim(p_decision_note)) not between 10 and 500 then
    raise exception 'PARAMETRI_MODERAZIONE_NON_VALIDI';
  end if;
  select * into item from public.disputes d where d.id=p_dispute_id for update;
  if not found or item.status <> 'pending' then
    raise exception 'CONTESTAZIONE_NON_IN_ATTESA';
  end if;
  update public.disputes
    set status=(case when p_accept then 'accepted' else 'rejected' end),
        resolved_at=now()
    where id=item.id;
  if p_accept then
    update public.reviews set status='removed' where id=item.review_id;
    -- Suspend only not-yet-redeemed milestones invalidated by the review removal.
    update public.vouchers v set status='suspended'
      where v.customer_id=item.customer_id
        and v.status in ('pending','available')
        and v.milestone > (
          select count(*) from public.reviews r
          where r.customer_id=item.customer_id and r.rating>=8
            and r.status='published'
            and not exists(select 1 from public.disputes d
              where d.review_id=r.id and d.status='accepted')
        );
  end if;
  insert into gd_private.operator_audit(action_type,target_id,operator_label,decision_note)
    values(case when p_accept then 'dispute_accepted' else 'dispute_rejected' end,
      item.id,btrim(p_operator_label),btrim(p_decision_note));
  return true;
end;
$$;
revoke all on function gd_private.resolve_guest_dispute(uuid,boolean,text,text)
  from public, anon, authenticated;

comment on table gd_private.operator_audit is
  'Restricted audit of explicit human GoodDiner moderation decisions; never accessed by the browser.';
comment on function gd_private.review_merchant_application(uuid,boolean,text,text) is
  'Only database owner via internal SQL editor; verify actual operator and business ownership evidence before approval.';
comment on function gd_private.resolve_guest_dispute(uuid,boolean,text,text) is
  'Only database owner via internal SQL editor; human-only review, atomic status update and pending voucher reconciliation.';
