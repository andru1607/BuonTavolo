-- GoodDiner RLS/RPC transactional integration test.
-- IMPORTANT: The nested EXCEPTION subtransaction ALWAYS rolls back ALL fixture rows.
-- Every test account and restaurant is generated uniquely and NEVER persists.
-- Use ONLY on the dedicated GoodDiner Supabase project with a privileged SQL editor.
DO $gd_test$
DECLARE
  guest_a uuid := gen_random_uuid();
  guest_b uuid := gen_random_uuid();
  merchant_a uuid := gen_random_uuid();
  merchant_b uuid := gen_random_uuid();
  merchant_unverified uuid := gen_random_uuid();
  guest_anonymous uuid := gen_random_uuid();
  venue_a uuid;
  venue_b uuid;
  token_a text;
  token_b text;
  token_expired text;
  token_repeat text;
  token_extra text;
  token_self text;
  visit_a uuid;
  visit_b uuid;
  visit_extra uuid;
  review_a uuid;
  dispute_a uuid;
  privacy_request_a uuid;
  n integer;
  seen_error boolean;
  passed boolean := false;
BEGIN
  IF current_user <> 'postgres' THEN
    RAISE EXCEPTION 'Test must run from the restricted postgres SQL editor';
  END IF;
  BEGIN
    -- This fixture is a single rollback-only SQL statement run as postgres.
    -- It never opens registration for Supabase Auth API requests.
    PERFORM set_config('gooddiner.test_fixture','enabled',true);
    INSERT INTO auth.users(id,aud,role,email,raw_user_meta_data,email_confirmed_at,is_anonymous,created_at,updated_at)
    VALUES
      (guest_a,'authenticated','authenticated','test-guest-a-'||guest_a||'@example.invalid',jsonb_build_object('nickname','ProvaOspiteA','role','merchant'),now(),false,now(),now()),
      (guest_b,'authenticated','authenticated','test-guest-b-'||guest_b||'@example.invalid',jsonb_build_object('nickname','ProvaOspiteB'),now(),false,now(),now()),
      (merchant_a,'authenticated','authenticated','test-merchant-a-'||merchant_a||'@example.invalid',jsonb_build_object('nickname','ProvaGestoreA'),now(),false,now(),now()),
      (merchant_b,'authenticated','authenticated','test-merchant-b-'||merchant_b||'@example.invalid',jsonb_build_object('nickname','ProvaGestoreB'),now(),false,now(),now()),
      (merchant_unverified,'authenticated','authenticated','test-unverified-'||merchant_unverified||'@example.invalid',jsonb_build_object('nickname','GestoreNonVerificato'),now(),false,now(),now()),
      (guest_anonymous,'authenticated','authenticated',null,jsonb_build_object('nickname','OspiteProvvisorio'),null,true,now(),now());

    IF (SELECT role FROM public.profiles WHERE id=guest_a) <> 'customer' THEN
      RAISE EXCEPTION 'FAIL: untrusted user metadata promoted guest to merchant';
    END IF;

    INSERT INTO public.restaurants(owner_id,name,city,verified_at)
    VALUES (merchant_a,'Locale di prova A','Garda',now()) RETURNING id INTO venue_a;
    INSERT INTO public.restaurants(owner_id,name,city,verified_at)
    VALUES (merchant_b,'Locale di prova B','Verona',now()) RETURNING id INTO venue_b;

    -- Anonymous Auth accounts use the "authenticated" DB role. Their JWT
    -- is_anonymous claim must prevent merchant onboarding.
    PERFORM set_config('request.jwt.claim.sub',guest_anonymous::text,true);
    PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',guest_anonymous::text,'is_anonymous',true)::text,true);
    EXECUTE 'SET LOCAL ROLE authenticated';
    seen_error := false;
    BEGIN
      INSERT INTO public.merchant_applications(applicant_id,restaurant_name,city)
      VALUES (guest_anonymous,'Attivita non autorizzata','Garda');
    EXCEPTION WHEN OTHERS THEN seen_error := true;
    END;
    IF NOT seen_error THEN RAISE EXCEPTION 'FAIL: anonymous user submitted merchant request'; END IF;
    EXECUTE 'RESET ROLE';

    -- Guest A issues a one-time 90-second QR.
    PERFORM set_config('request.jwt.claim.sub',guest_a::text,true);
    PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',guest_a::text,'is_anonymous',false)::text,true);
    EXECUTE 'SET LOCAL ROLE authenticated';
    SELECT t.qr_token INTO token_a FROM public.issue_guest_qr() t;
    IF token_a !~ '^GD1:[0-9a-f-]{36}$' THEN RAISE EXCEPTION 'FAIL: invalid QR token'; END IF;
    EXECUTE 'RESET ROLE';

    -- An unverified account cannot claim it on any other person's restaurant.
    PERFORM set_config('request.jwt.claim.sub',merchant_unverified::text,true);
    PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',merchant_unverified::text,'is_anonymous',false)::text,true);
    EXECUTE 'SET LOCAL ROLE authenticated';
    seen_error := false;
    BEGIN
      PERFORM public.checkin_guest(token_a,venue_a);
    EXCEPTION WHEN OTHERS THEN seen_error := true;
    END;
    IF NOT seen_error THEN RAISE EXCEPTION 'FAIL: unverified merchant claimed venue A'; END IF;
    EXECUTE 'RESET ROLE';

    -- Verified merchant B must not claim on merchant A's venue.
    PERFORM set_config('request.jwt.claim.sub',merchant_b::text,true);
    PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',merchant_b::text,'is_anonymous',false)::text,true);
    EXECUTE 'SET LOCAL ROLE authenticated';
    seen_error := false;
    BEGIN
      PERFORM public.checkin_guest(token_a,venue_a);
    EXCEPTION WHEN OTHERS THEN seen_error := true;
    END;
    IF NOT seen_error THEN RAISE EXCEPTION 'FAIL: merchant B operated merchant A venue'; END IF;
    EXECUTE 'RESET ROLE';

    -- Genuine merchant A can record a verified visit.
    PERFORM set_config('request.jwt.claim.sub',merchant_a::text,true);
    PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',merchant_a::text,'is_anonymous',false)::text,true);
    EXECUTE 'SET LOCAL ROLE authenticated';
    SELECT t.visit_id INTO visit_a FROM public.checkin_guest(token_a,venue_a) t;
    IF visit_a IS NULL THEN RAISE EXCEPTION 'FAIL: no confirmed visit'; END IF;
    seen_error := false;
    BEGIN
      PERFORM public.checkin_guest(token_a,venue_a);
    EXCEPTION WHEN OTHERS THEN seen_error := true;
    END;
    IF NOT seen_error THEN RAISE EXCEPTION 'FAIL: replayed QR accepted'; END IF;
    EXECUTE 'RESET ROLE';

    -- A verified restaurant owner must not use their own DinerPass to
    -- fabricate a visit and earn a positive rating at their own venue.
    PERFORM set_config('request.jwt.claim.sub',merchant_a::text,true);
    PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',merchant_a::text,'is_anonymous',false)::text,true);
    EXECUTE 'SET LOCAL ROLE authenticated';
    SELECT t.qr_token INTO token_self FROM public.issue_guest_qr() t;
    seen_error := false;
    BEGIN
      PERFORM public.checkin_guest(token_self,venue_a);
    EXCEPTION WHEN check_violation THEN seen_error := true;
    END;
    IF NOT seen_error THEN RAISE EXCEPTION 'FAIL: owner checked in own DinerPass'; END IF;
    EXECUTE 'RESET ROLE';

    -- Issue an expired QR directly in an isolated, rolled-back database fixture.
    INSERT INTO gd_private.visit_tokens(customer_id,created_at,expires_at)
      VALUES (guest_b,now()-interval '3 minutes',now()-interval '1 minute')
      RETURNING 'GD1:'||id::text INTO token_expired;
    PERFORM set_config('request.jwt.claim.sub',merchant_a::text,true);
    PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',merchant_a::text,'is_anonymous',false)::text,true);
    EXECUTE 'SET LOCAL ROLE authenticated';
    seen_error := false;
    BEGIN
      PERFORM public.checkin_guest(token_expired,venue_a);
    EXCEPTION WHEN OTHERS THEN seen_error := true;
    END;
    IF NOT seen_error THEN RAISE EXCEPTION 'FAIL: expired QR accepted'; END IF;
    EXECUTE 'RESET ROLE';

    -- A second QR must not create a second confirmed visit in the same venue/day.
    PERFORM set_config('request.jwt.claim.sub',guest_a::text,true);
    PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',guest_a::text,'is_anonymous',false)::text,true);
    EXECUTE 'SET LOCAL ROLE authenticated';
    SELECT t.qr_token INTO token_repeat FROM public.issue_guest_qr() t;
    EXECUTE 'RESET ROLE';

    PERFORM set_config('request.jwt.claim.sub',merchant_a::text,true);
    PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',merchant_a::text,'is_anonymous',false)::text,true);
    EXECUTE 'SET LOCAL ROLE authenticated';
    seen_error := false;
    BEGIN
      PERFORM public.checkin_guest(token_repeat,venue_a);
    EXCEPTION WHEN OTHERS THEN seen_error := true;
    END;
    IF NOT seen_error THEN RAISE EXCEPTION 'FAIL: duplicate daily visit'; END IF;
    EXECUTE 'RESET ROLE';

    -- Verified merchant B records guest B's visit.
    PERFORM set_config('request.jwt.claim.sub',guest_b::text,true);
    PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',guest_b::text,'is_anonymous',false)::text,true);
    EXECUTE 'SET LOCAL ROLE authenticated';
    SELECT t.qr_token INTO token_b FROM public.issue_guest_qr() t;
    EXECUTE 'RESET ROLE';

    PERFORM set_config('request.jwt.claim.sub',merchant_b::text,true);
    PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',merchant_b::text,'is_anonymous',false)::text,true);
    EXECUTE 'SET LOCAL ROLE authenticated';
    SELECT t.visit_id INTO visit_b FROM public.checkin_guest(token_b,venue_b) t;
    EXECUTE 'RESET ROLE';

    -- Guest B cannot inspect guest A's profile, visit or reviews.
    PERFORM set_config('request.jwt.claim.sub',guest_b::text,true);
    PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',guest_b::text,'is_anonymous',false)::text,true);
    EXECUTE 'SET LOCAL ROLE authenticated';
    SELECT count(*) INTO n FROM public.profiles WHERE id=guest_a;
    IF n<>0 THEN RAISE EXCEPTION 'FAIL: exposed another customer profile'; END IF;
    SELECT count(*) INTO n FROM public.visits WHERE id=visit_a;
    IF n<>0 THEN RAISE EXCEPTION 'FAIL: exposed another customer visit'; END IF;
    EXECUTE 'RESET ROLE';

    PERFORM set_config('request.jwt.claim.sub',merchant_b::text,true);
    PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',merchant_b::text,'is_anonymous',false)::text,true);
    EXECUTE 'SET LOCAL ROLE authenticated';
    SELECT count(*) INTO n FROM public.visits WHERE id=visit_a;
    IF n<>0 THEN RAISE EXCEPTION 'FAIL: restaurant B read restaurant A visit'; END IF;
    seen_error := false;
    BEGIN
      PERFORM public.publish_guest_review(visit_a,9,'Commento altrui non autorizzato alla scrittura');
    EXCEPTION WHEN OTHERS THEN seen_error:=true;
    END;
    IF NOT seen_error THEN RAISE EXCEPTION 'FAIL: restaurant B rated restaurant A visit'; END IF;
    EXECUTE 'RESET ROLE';

    -- The database also rejects a forged self-rating, even if the caller
    -- bypasses the normal application RPC and uses a privileged SQL session.
    seen_error := false;
    BEGIN
      INSERT INTO public.reviews(visit_id,customer_id,restaurant_id,rater_id,rating,comment)
      VALUES (visit_a,guest_a,venue_a,guest_a,10,
        'Tentativo di auto-valutazione non consentito dal vincolo');
    EXCEPTION WHEN check_violation THEN seen_error := true;
    END;
    IF NOT seen_error THEN RAISE EXCEPTION 'FAIL: self-rating bypassed DB check'; END IF;

    PERFORM set_config('request.jwt.claim.sub',merchant_a::text,true);
    PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',merchant_a::text,'is_anonymous',false)::text,true);
    EXECUTE 'SET LOCAL ROLE authenticated';
    SELECT public.publish_guest_review(visit_a,9,'Ospite ha rispettato gli accordi di prenotazione')
      INTO review_a;
    seen_error:=false;
    BEGIN
      PERFORM public.publish_guest_review(visit_a,8,'Recensione duplicata volutamente errata');
    EXCEPTION WHEN OTHERS THEN seen_error:=true;
    END;
    IF NOT seen_error THEN RAISE EXCEPTION 'FAIL: duplicate review was accepted'; END IF;
    EXECUTE 'RESET ROLE';

    -- Guest B cannot open a dispute on guest A's review.
    PERFORM set_config('request.jwt.claim.sub',guest_b::text,true);
    PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',guest_b::text,'is_anonymous',false)::text,true);
    EXECUTE 'SET LOCAL ROLE authenticated';
    SELECT count(*) INTO n FROM public.reviews WHERE id=review_a;
    IF n<>0 THEN RAISE EXCEPTION 'FAIL: foreign customer review is visible'; END IF;
    seen_error:=false;
    BEGIN
      INSERT INTO public.disputes(review_id,customer_id,reason)
      VALUES (review_a,guest_b,'Contesto recensione di un altro cliente');
    EXCEPTION WHEN OTHERS THEN seen_error:=true;
    END;
    IF NOT seen_error THEN RAISE EXCEPTION 'FAIL: guest B disputed guest A review'; END IF;
    EXECUTE 'RESET ROLE';

    -- Guest A can contest; only a database operator can resolve it.
    PERFORM set_config('request.jwt.claim.sub',guest_a::text,true);
    PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',guest_a::text,'is_anonymous',false)::text,true);
    EXECUTE 'SET LOCAL ROLE authenticated';
    INSERT INTO public.disputes(review_id,customer_id,reason)
    VALUES (review_a,guest_a,'Motivazione argomentata per contestazione di prova')
    RETURNING id INTO dispute_a;
    IF (SELECT count(*) FROM public.disputes WHERE id=dispute_a)<>1
      THEN RAISE EXCEPTION 'FAIL: customer cannot see own dispute'; END IF;
    seen_error:=false;
    BEGIN
      PERFORM gd_private.resolve_guest_dispute(dispute_a,true,'collaudatore','Prova di permessi negati a cliente');
    EXCEPTION WHEN OTHERS THEN seen_error:=true;
    END;
    IF NOT seen_error THEN RAISE EXCEPTION 'FAIL: customer executed private moderation'; END IF;
    EXECUTE 'RESET ROLE';

    PERFORM gd_private.resolve_guest_dispute(
      dispute_a,true,'collaudo-interno','Test transazionale: contestazione approvata, dati fittizi eliminati'
    );
    IF (SELECT status FROM public.reviews WHERE id=review_a)<>'removed'
      THEN RAISE EXCEPTION 'FAIL: accepted dispute did not remove review'; END IF;
    IF (SELECT count(*) FROM gd_private.operator_audit WHERE target_id=dispute_a)<>1
      THEN RAISE EXCEPTION 'FAIL: private operator audit not written'; END IF;

    -- A newly recorded unreviewed visit can be voided by its own merchant.
    PERFORM set_config('request.jwt.claim.sub',guest_a::text,true);
    PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',guest_a::text,'is_anonymous',false)::text,true);
    EXECUTE 'SET LOCAL ROLE authenticated';
    SELECT t.qr_token INTO token_extra FROM public.issue_guest_qr() t;
    EXECUTE 'RESET ROLE';

    PERFORM set_config('request.jwt.claim.sub',merchant_b::text,true);
    PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',merchant_b::text,'is_anonymous',false)::text,true);
    EXECUTE 'SET LOCAL ROLE authenticated';
    SELECT t.visit_id INTO visit_extra FROM public.checkin_guest(token_extra,venue_b) t;
    IF NOT public.void_guest_visit(visit_extra,'Registrazione errata durante un test transazionale')
      THEN RAISE EXCEPTION 'FAIL: valid void rejected'; END IF;
    IF (SELECT status FROM public.visits WHERE id=visit_extra)<>'voided'
      THEN RAISE EXCEPTION 'FAIL: void status missing'; END IF;
    EXECUTE 'RESET ROLE';

    -- The same short-lived test fixtures exercise authenticated GDPR requests.
    PERFORM set_config('request.jwt.claim.sub',guest_a::text,true);
    PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',guest_a::text,'is_anonymous',false)::text,true);
    EXECUTE 'SET LOCAL ROLE authenticated';
    INSERT INTO public.privacy_requests(requester_id,request_kind,details)
      VALUES(guest_a,'erasure','Richiesta di cancellazione simulata nel test')
      RETURNING id INTO privacy_request_a;
    seen_error := false;
    BEGIN
      INSERT INTO public.privacy_requests(requester_id,request_kind,details)
        VALUES(guest_a,'erasure','Duplicato non consentito');
    EXCEPTION WHEN OTHERS THEN seen_error := true;
    END;
    IF NOT seen_error THEN RAISE EXCEPTION 'FAIL: duplicate open privacy request allowed'; END IF;
    EXECUTE 'RESET ROLE';

    PERFORM set_config('request.jwt.claim.sub',guest_b::text,true);
    PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',guest_b::text,'is_anonymous',false)::text,true);
    EXECUTE 'SET LOCAL ROLE authenticated';
    SELECT count(*) INTO n FROM public.privacy_requests WHERE id=privacy_request_a;
    IF n<>0 THEN RAISE EXCEPTION 'FAIL: guest B read guest A privacy request'; END IF;
    seen_error := false;
    BEGIN
      INSERT INTO public.privacy_requests(requester_id,request_kind,details)
        VALUES(guest_a,'access','Richiesta per dati di altro utente');
    EXCEPTION WHEN OTHERS THEN seen_error := true;
    END;
    IF NOT seen_error THEN RAISE EXCEPTION 'FAIL: guest B opened privacy request for A'; END IF;
    EXECUTE 'RESET ROLE';

    PERFORM gd_private.close_privacy_request(
      privacy_request_a,true,'collaudo-interno',
      'Test transazionale: il registro tutela la decisione senza cancellare dati reali'
    );
    IF (SELECT status FROM public.privacy_requests WHERE id=privacy_request_a)<>'resolved'
      THEN RAISE EXCEPTION 'FAIL: privacy request not resolved'; END IF;
    IF (SELECT count(*) FROM gd_private.operator_audit WHERE target_id=privacy_request_a)<>1
      THEN RAISE EXCEPTION 'FAIL: missing privacy operator audit'; END IF;

    -- RLS-invoker totals must be exact and non-guessable across accounts.
    PERFORM set_config('request.jwt.claim.sub',guest_a::text,true);
    PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',guest_a::text,'is_anonymous',false)::text,true);
    EXECUTE 'SET LOCAL ROLE authenticated';
    SELECT confirmed_visits INTO n FROM public.get_my_dinerpass_counts();
    IF n<>1 THEN RAISE EXCEPTION 'FAIL: guest A exact count after reviewed/voided visits: %',n; END IF;
    SELECT published_reviews INTO n FROM public.get_my_dinerpass_counts();
    IF n<>0 THEN RAISE EXCEPTION 'FAIL: removed review counted: %',n; END IF;
    SELECT count(*) INTO n FROM public.get_my_restaurant_counts(venue_a);
    IF n<>0 THEN RAISE EXCEPTION 'FAIL: non-owner saw merchant A totals'; END IF;
    EXECUTE 'RESET ROLE';

    PERFORM set_config('request.jwt.claim.sub',merchant_b::text,true);
    PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',merchant_b::text,'is_anonymous',false)::text,true);
    EXECUTE 'SET LOCAL ROLE authenticated';
    SELECT confirmed_visits INTO n FROM public.get_my_restaurant_counts(venue_b);
    IF n<>1 THEN RAISE EXCEPTION 'FAIL: merchant B count includes voided visit: %',n; END IF;
    SELECT count(*) INTO n FROM public.get_my_restaurant_counts(venue_a);
    IF n<>0 THEN RAISE EXCEPTION 'FAIL: merchant B could inspect merchant A totals'; END IF;
    EXECUTE 'RESET ROLE';

    -- All nested fixture mutations MUST roll back before leaving this DO block.
    passed := true;
    RAISE EXCEPTION 'GOODDINER_ROLLBACK_ALL_TEST_FIXTURES';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'GOODDINER_ROLLBACK_ALL_TEST_FIXTURES' THEN
      RAISE;
    END IF;
  END;
  IF NOT passed THEN
    RAISE EXCEPTION 'GoodDiner security integration test did not complete';
  END IF;
END $gd_test$;