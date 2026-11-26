-- Registration choices are evidence of a pilot notice, not a legal approval.
create table gd_private.privacy_choice_events (
 id bigint generated always as identity primary key,
 user_id uuid not null references auth.users(id) on delete cascade,
 notice_version text not null,
 event_kind text not null check(event_kind in ('signup','preference','withdrawal')),
 terms_ack boolean,
 privacy_ack boolean,
 sharing_requested boolean not null,
 recorded_at timestamptz not null default clock_timestamp(),
 check(event_kind<>'signup' or (terms_ack is true and privacy_ack is true))
);
create index gd_privacy_choice_user_idx on gd_private.privacy_choice_events(user_id,id desc);
alter table gd_private.privacy_choice_events enable row level security;
revoke all on gd_private.privacy_choice_events from public,anon,authenticated;
revoke all on sequence gd_private.privacy_choice_events_id_seq from public,anon,authenticated;
create function gd_private.capture_signup_privacy_choices()
returns trigger language plpgsql security definer set search_path='' as $$
declare m jsonb:=new.raw_user_meta_data->'gd_privacy_choices';
begin
 -- Backward-compatible with already cached registration pages and existing accounts.
 -- No record means no acknowledgement or sharing preference is established.
 if jsonb_typeof(m)='object' and m->>'version'='pilot-2026-11-26-v1'
 and m->'terms'='true'::jsonb and m->'privacy'='true'::jsonb
 and jsonb_typeof(m->'sharing')='boolean' then
  insert into gd_private.privacy_choice_events(user_id,notice_version,event_kind,terms_ack,privacy_ack,sharing_requested)
  values(new.id,'pilot-2026-11-26-v1','signup',true,true,m->'sharing'='true'::jsonb);
 end if;
 return new;
end $$;
revoke all on function gd_private.capture_signup_privacy_choices() from public,anon,authenticated;
create trigger gd_capture_signup_privacy_choices after insert on auth.users
 for each row execute function gd_private.capture_signup_privacy_choices();

create function public.my_privacy_choices()
returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('sharing_requested',coalesce((select e.sharing_requested from gd_private.privacy_choice_events e where e.user_id=auth.uid() order by id desc limit 1),false),
 'signup_acknowledged',exists(select 1 from gd_private.privacy_choice_events e where e.user_id=auth.uid() and e.event_kind='signup'),
 'notice_version',(select e.notice_version from gd_private.privacy_choice_events e where e.user_id=auth.uid() order by id desc limit 1),
 'recorded_at',(select e.recorded_at from gd_private.privacy_choice_events e where e.user_id=auth.uid() order by id desc limit 1))
$$;
revoke all on function public.my_privacy_choices() from public,anon,authenticated;
grant execute on function public.my_privacy_choices() to authenticated;
create function public.set_my_sharing_preference(p_requested boolean)
returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid();
begin
 if uid is null or p_requested is null or not exists(select 1 from public.profiles p where p.id=uid)
 or exists(select 1 from public.restaurants r where r.owner_id=uid) then raise exception 'ACCESSO_CLIENTE_RICHIESTO';end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(uid::text,9412));
 if not p_requested then perform public.revoke_dinerpass_sharing();end if;
 if not exists(select 1 from (select sharing_requested,notice_version from gd_private.privacy_choice_events where user_id=uid order by id desc limit 1) e where e.sharing_requested=p_requested and e.notice_version='pilot-2026-11-26-v1') then
 insert into gd_private.privacy_choice_events(user_id,notice_version,event_kind,sharing_requested)
 values(uid,'pilot-2026-11-26-v1',case when p_requested then 'preference' else 'withdrawal' end,p_requested);
 end if;
 return public.my_privacy_choices();
end $$;
revoke all on function public.set_my_sharing_preference(boolean) from public,anon,authenticated;
grant execute on function public.set_my_sharing_preference(boolean) to authenticated;
-- A final notice version must be explicitly approved before real disclosure.
alter table gd_private.reputation_release add column approved_notice_version text;
-- NOT VALID permits the historical synthetic fixture to exercise the old schema
-- only if it supplies an approved version; all future enabled rows require one.
alter table gd_private.reputation_release add constraint gd_reputation_final_notice_required check(not enabled or (approved_notice_version is not null and approved_notice_version <> 'pilot-2026-11-26-v1'));
