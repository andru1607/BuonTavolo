-- Upgrade an existing confirmed account without creating a duplicate identity.
create or replace function gd_private.merchant_onboarding(p_name text,p_city text,p_code text)
returns uuid language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); code text:=lower(btrim(coalesce(p_code,''))); invite_id uuid; application_id uuid;
begin
 if actor is null or not gd_private.current_user_email_confirmed() then raise exception 'MERCHANT_EMAIL_REQUIRED' using errcode='42501'; end if;
 if p_name is null or char_length(btrim(p_name)) not between 3 and 100 or p_city is null or char_length(btrim(p_city)) not between 2 and 100 then raise exception 'MERCHANT_DETAILS_INVALID'; end if;
 perform 1 from public.profiles where id=actor for update;
 if not found then raise exception 'MERCHANT_PROFILE_REQUIRED'; end if;
 if exists(select 1 from public.merchant_applications where applicant_id=actor and status in ('pending','approved')) then raise exception 'MERCHANT_APPLICATION_EXISTS'; end if;
 if not gd_private.current_user_has_merchant_invite() then
  if code !~ '^[a-f0-9]{32}$' then raise exception 'MERCHANT_INVITE_REQUIRED'; end if;
  update gd_private.signup_invites i set used_at=now(),used_by=actor
   where i.secret_hash=encode(pg_catalog.sha256(pg_catalog.convert_to(code,'UTF8')),'hex')
   and i.purpose='merchant' and i.used_at is null and i.expires_at>now()
   returning i.id into invite_id;
  if invite_id is null then raise exception 'MERCHANT_INVITE_INVALID'; end if;
 end if;
 insert into public.merchant_applications(applicant_id,restaurant_name,city,source,status)
 values(actor,btrim(p_name),btrim(p_city),'manual','pending') returning id into application_id;
 return application_id;
end $$;
revoke all on function gd_private.merchant_onboarding(text,text,text) from public,anon,authenticated;
grant execute on function gd_private.merchant_onboarding(text,text,text) to authenticated;
create or replace function public.submit_merchant_onboarding(p_name text,p_city text,p_code text)
returns uuid language sql security invoker set search_path='' as $$ select gd_private.merchant_onboarding(p_name,p_city,p_code) $$;
revoke all on function public.submit_merchant_onboarding(text,text,text) from public,anon,authenticated;
grant execute on function public.submit_merchant_onboarding(text,text,text) to authenticated;
create or replace function public.get_my_merchant_invite_status()
returns boolean language sql stable security invoker set search_path='' as $$ select gd_private.current_user_has_merchant_invite() $$;
revoke all on function public.get_my_merchant_invite_status() from public,anon,authenticated;
grant execute on function public.get_my_merchant_invite_status() to authenticated;