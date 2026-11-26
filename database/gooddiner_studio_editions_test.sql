do $qa$
declare op uuid:=gen_random_uuid(); guest uuid:=gen_random_uuid(); payload jsonb; rejected boolean; code text:='qa-'||substr(gen_random_uuid()::text,1,8); jpg text:=replace(encode(decode('ffd8ff'||repeat('00',100)||'ffd9','hex'),'base64'),E'\n','');
begin
 begin
 perform set_config('gooddiner.test_fixture','enabled',true);
 insert into auth.users(id,aud,role,email,raw_user_meta_data,email_confirmed_at,is_anonymous,created_at,updated_at)
 select u,'authenticated','authenticated','edition-qa-'||u||'@example.invalid',jsonb_build_object('nickname','QA editor'),now(),false,now(),now() from unnest(array[op,guest]) u;
 insert into gd_studio_private.operators(user_id) values(op);
 perform set_config('request.jwt.claim.sub',guest::text,true);execute 'set local role authenticated';
 rejected:=false;begin perform public.gooddiner_studio_editions('list');exception when insufficient_privilege then rejected:=true;end;
 if not rejected then raise exception 'FAIL guest studio access';end if;
 execute 'reset role';
 perform set_config('request.jwt.claim.sub',op::text,true);execute 'set local role authenticated';
 payload:=jsonb_build_object('code',code,'name','QA edition','kind','paid','theme','icon','threshold',0,'price_cents',199,'publish',false);
 perform public.gooddiner_studio_editions('save',payload);
 rejected:=false;begin perform public.gooddiner_studio_editions('save',payload||'{"publish":true}'::jsonb);exception when others then rejected:=sqlerrm='EDIZIONE_PAGAMENTO_SOLO_BOZZA';end;
 if not rejected then raise exception 'FAIL paid publication';end if;
 perform public.gooddiner_studio_editions('save',payload||jsonb_build_object('kind','achievement','threshold',5,'publish',true,'jpeg',jpg));
 rejected:=false;begin perform public.gooddiner_studio_editions('save',payload||jsonb_build_object('kind','achievement','threshold',1,'publish',true));exception when others then rejected:=sqlerrm='REGOLA_EDIZIONE_PUBBLICATA_IMMUTABILE';end;
 if not rejected then raise exception 'FAIL published threshold mutation';end if;
 execute 'reset role';
 perform set_config('request.jwt.claim.sub',guest::text,true);execute 'set local role authenticated';
 payload:=public.my_dinerpass_collection();
 if not exists(select 1 from jsonb_array_elements(payload->'cards') c where c->>'code'=code and c->>'unlocked'='false' and c->>'artwork_revision' is not null) then raise exception 'FAIL published edition visibility';end if;
 if public.my_dinerpass_artwork(code,(select (c->>'artwork_revision')::uuid from jsonb_array_elements(payload->'cards') c where c->>'code'=code))->>'jpeg' is distinct from jpg then raise exception 'FAIL artwork retrieval';end if;
 execute 'reset role';
 raise exception 'ROLLBACK_EDITION_QA';
 exception when others then if sqlerrm<>'ROLLBACK_EDITION_QA' then raise;end if;end;
end $qa$;