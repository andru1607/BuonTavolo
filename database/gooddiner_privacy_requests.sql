-- GoodDiner: self-service privacy request queue for authenticated data subjects.
-- Schema is deliberately limited: submitting a request NEVER deletes data automatically.
-- Run ONLY on project ixczkhmvbjszgmlqznlk after source review.

create table public.privacy_requests (
  id uuid primary key default gen_random_uuid(),
  requester_id uuid not null references auth.users(id) on delete cascade,
  request_kind text not null check (request_kind in
    ('access','rectification','erasure','restriction','objection')),
  details text check (details is null or char_length(btrim(details)) <= 500),
  status text not null default 'received' check (status in
    ('received','in_review','resolved','rejected')),
  created_at timestamptz not null default now(),
  resolved_at timestamptz
);
create index gd_privacy_requester_created on public.privacy_requests (requester_id, created_at desc);
create unique index gd_privacy_open_one_per_kind on public.privacy_requests (requester_id,request_kind)
  where status in ('received','in_review');

alter table public.privacy_requests enable row level security;
revoke all on public.privacy_requests from public,anon,authenticated;
grant select on public.privacy_requests to authenticated;
grant insert (requester_id,request_kind,details) on public.privacy_requests to authenticated;

create policy gd_privacy_self_select on public.privacy_requests for select to authenticated
  using (requester_id=(select auth.uid()));
create policy gd_privacy_self_insert on public.privacy_requests for insert to authenticated
  with check (requester_id=(select auth.uid()) and status='received' and resolved_at is null);

-- Include human rights-management decisions in the existing restricted audit.
alter table gd_private.operator_audit
  drop constraint operator_audit_action_type_check;
alter table gd_private.operator_audit
  add constraint operator_audit_action_type_check check (action_type in
    ('application_approved','application_rejected',
     'dispute_accepted','dispute_rejected',
     'privacy_request_resolved','privacy_request_rejected'));

create or replace function gd_private.close_privacy_request(
  p_request_id uuid, p_completed boolean, p_operator_label text, p_decision_note text
)
returns boolean language plpgsql security invoker set search_path = '' as $$
declare
  item public.privacy_requests%rowtype;
begin
  if current_user <> 'postgres' then raise exception 'OPERATORE_NON_AUTORIZZATO'; end if;
  if p_request_id is null or p_completed is null or
     p_operator_label is null or char_length(btrim(p_operator_label)) not between 3 and 100 or
     p_decision_note is null or char_length(btrim(p_decision_note)) not between 10 and 500 then
    raise exception 'PARAMETRI_PRIVACY_NON_VALIDI';
  end if;
  select * into item from public.privacy_requests r where r.id=p_request_id for update;
  if not found or item.status not in ('received','in_review') then
    raise exception 'RICHIESTA_PRIVACY_NON_IN_ATTESA';
  end if;

  -- Operator must actually review/fulfil the data subject's right BEFORE
  -- marking completed. This routine logs decisions but grants no blanket
  -- permission to delete another person's data.
  update public.privacy_requests
    set status=case when p_completed then 'resolved' else 'rejected' end,
        resolved_at=now()
  where id=item.id;
  insert into gd_private.operator_audit(action_type,target_id,operator_label,decision_note)
    values(case when p_completed then 'privacy_request_resolved'
                else 'privacy_request_rejected' end,
           item.id,btrim(p_operator_label),btrim(p_decision_note));
  return true;
end;
$$;
revoke all on function gd_private.close_privacy_request(uuid,boolean,text,text)
  from public,anon,authenticated;

comment on table public.privacy_requests is
  'Authenticated data-subject requests, visible only to requester; human resolution via protected SQL editor.';
