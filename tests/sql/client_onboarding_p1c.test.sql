-- tests/sql/client_onboarding_p1c.test.sql — live test of migration 0040 (always rolls back).
--   pass → "ALL PASS (rolled back)"   fail → "FAIL: ..."
-- Throwaway clients and logins only ('ZZtest …' / @example.com). Sign-ups are simulated by inserting
-- into auth.users (fires the real handle_new_user trigger). Staff steps run as the earliest admin
-- (switched to intern where noted); client steps impersonate the new logins.
do $$
declare
  adm uuid; adm_email text; c1 uuid; c2 uuid; c3 uuid; c4 uuid; c5 uuid; c6 uuid; c7 uuid; cu2 uuid; cu5 uuid;
  u1 uuid := gen_random_uuid(); u2 uuid := gen_random_uuid(); u3 uuid := gen_random_uuid();
  u5 uuid := gen_random_uuid(); u6 uuid := gen_random_uuid();
  t_sesame uuid; t_veg uuid; t_gluten uuid; t_peanut uuid; t_vegan uuid; t_dairy uuid; t_heart uuid; t_asian uuid;
  sup_staff uuid; tok uuid; tok3 uuid; tok4 uuid; tok5 uuid; res jsonb; d jsonb; n int; log text := '';
begin
  select id, email into adm, adm_email from profiles where role = 'admin' order by created_at limit 1;
  select id into t_sesame from tags where label = 'Sesame';
  select id into t_veg    from tags where label = 'Vegetarian';
  select id into t_gluten from tags where label = 'Gluten';
  select id into t_peanut from tags where label = 'Peanuts';
  select id into t_vegan  from tags where label = 'Vegan';
  select id into t_dairy  from tags where label = 'Dairy';
  select id into t_heart  from tags where label = 'Heart-healthy';
  select id into t_asian  from tags where label = 'Asian';
  perform set_config('request.jwt.claims', json_build_object('sub', adm, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', adm::text, true);

  -- T1 self sign-up (/join) → a fresh file of their own, linked, intake open, in the dietitian's queue
  insert into auth.users (id, email, raw_user_meta_data) values
    (u1, 'ZZ.Self@example.com', '{"account_type":"client","full_name":"ZZtest Sam Self","phone":"0400 000 001"}'::jsonb);
  select id into c1 from clients where user_id = u1;
  if (select role from profiles where id = u1) <> 'client' or c1 is null
     or (select source || '/' || status || '/' || email || '/' || phone from clients where id = c1) <> 'self_signup/new/zz.self@example.com/0400 000 001'
     or (select status from client_intake where client_id = c1) <> 'open' then raise exception 'FAIL T1 self sign-up file'; end if;
  if not exists (select 1 from jsonb_array_elements(client_signup_queue()) q where (q->>'client_id')::uuid = c1) then
    raise exception 'FAIL T1b not in queue'; end if;
  log := 'T1 /join → own file (self_signup, new), linked, intake open, in the sign-up queue';

  -- T2 the client fills in their intake
  perform set_config('request.jwt.claims', json_build_object('sub', u1, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', u1::text, true);
  execute 'set local role authenticated';
  d := my_intake();
  if not (d->>'ok')::boolean or d->>'status' <> 'open' or jsonb_array_length(d->'options'->'avoid') <> 12
     or not (d->'options'->'diet' @> jsonb_build_array(jsonb_build_object('tag_id', t_veg, 'label', 'Vegetarian')))
     or not (d->'options'->'prefer' @> jsonb_build_array(jsonb_build_object('tag_id', t_heart, 'label', 'Heart-healthy')))
     or not (d->'missing' ? 'Date of birth') or jsonb_array_length(d->'questions') < 30 then
    raise exception 'FAIL T2a my_intake %', d; end if;
  res := save_my_intake(jsonb_build_object(
    'about', jsonb_build_object('date_of_birth', '1990-05-01', 'sex', 'female', 'height_cm', 165, 'activity_level', 'lightly_active'),
    'weight_kg', 68.44,
    'goal', jsonb_build_object('goal_type', 'fat_loss', 'detail', 'Feel better in my clothes'),
    'requirements_add', jsonb_build_array(t_sesame, t_veg, t_asian),
    'supplements_add', jsonb_build_array(jsonb_build_object('name', 'Vitamin D', 'dose', '1000 IU')),
    'answers', jsonb_build_object('reasons', jsonb_build_array('Gut health', 'Gut health'), 'top_priorities', '  More energy  ',
                 'proteins_enjoyed', jsonb_build_array('Fish', 'Eggs'), 'stress', '3', 'medications', 'Metformin 500 mg',
                 'consent_privacy', true, 'not_a_question', 'ignored')));
  if not (res->>'ok')::boolean then raise exception 'FAIL T2b save %', res; end if;
  if (select count(*) from clients) <> 0 or (select count(*) from client_intake) <> 0 then
    raise exception 'FAIL T2c client can read tables directly'; end if;
  execute 'reset role';
  if (select date_of_birth::text || sex || height_cm::text || activity_level from clients where id = c1) <> '1990-05-01female165.0lightly_active'
     or (select weight_kg from client_weights where client_id = c1 and source = 'client') <> 68.4
     or (select set_by from client_goals where client_id = c1 and is_primary) <> u1
     or (select count(*) from client_requirements where client_id = c1 and added_by = u1) <> 2      -- 'Asian' isn't offered → ignored
     or (select added_by from client_supplements where client_id = c1) <> u1 then
    raise exception 'FAIL T2d core fields not saved'; end if;
  d := (select answers from client_intake where client_id = c1);
  if d->'reasons' <> '["Gut health"]'::jsonb or d->>'top_priorities' <> 'More energy' or d->'stress' <> '3'::jsonb
     or d ? 'not_a_question' or (select count(*) from client_intake_log where client_id = c1 and changed_by = u1) < 10 then
    raise exception 'FAIL T2e answers %', d; end if;
  -- bad input → friendly message, nothing kept
  execute 'set local role authenticated';
  res := save_my_intake('{"answers":{"top_priorities":"Changed","reasons":["Not an option"]}}'::jsonb);
  if (res->>'ok')::boolean or res->>'message' not like 'Please choose%' then raise exception 'FAIL T2f %', res; end if;
  res := save_my_intake('{"about":{"date_of_birth":"not a date"}}'::jsonb);
  if (res->>'ok')::boolean or res->>'message' <> 'Please check your date of birth.' then raise exception 'FAIL T2g %', res; end if;
  res := save_my_intake('{"weight_kg":900}'::jsonb);
  if (res->>'ok')::boolean then raise exception 'FAIL T2h silly weight accepted'; end if;
  execute 'reset role';
  if (select answers->>'top_priorities' from client_intake where client_id = c1) <> 'More energy' then
    raise exception 'FAIL T2i failed save half-applied'; end if;
  execute 'set local role authenticated';
  res := submit_my_intake();
  if not (res->>'ok')::boolean or res->>'status' <> 'submitted' then raise exception 'FAIL T2j submit %', res; end if;
  execute 'reset role';
  if (select status from client_intake where client_id = c1) <> 'submitted' then raise exception 'FAIL T2k'; end if;
  log := log || ' | T2 client saves about/weight/goal/needs/supplements/answers (validated, cleaned, logged; bad input refused with nothing kept; tables still closed) and sends it';

  -- T3 incomplete intake can't be sent
  insert into auth.users (id, email, raw_user_meta_data) values (u2, 'zz.two@example.com', '{"account_type":"client","full_name":"ZZtest Two"}'::jsonb);
  select id into cu2 from clients where user_id = u2;
  perform set_config('request.jwt.claims', json_build_object('sub', u2, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', u2::text, true);
  execute 'set local role authenticated';
  res := submit_my_intake();
  execute 'reset role';
  if (res->>'ok')::boolean or not (res->'missing' ? 'Date of birth')
     or not (res->'missing' ? 'I agree to Grams of Health collecting and storing my health information to provide my care.') then
    raise exception 'FAIL T3 %', res; end if;
  log := log || ' | T3 incomplete intake → "a few things still need an answer" + list';

  -- T4 what the dietitian set can't be removed by the client
  perform set_config('request.jwt.claims', json_build_object('sub', adm, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', adm::text, true);
  insert into client_requirements (client_id, tag_id) values (c1, t_gluten);
  insert into client_supplements (client_id, name) values (c1, 'Iron') returning id into sup_staff;
  perform set_config('request.jwt.claims', json_build_object('sub', u1, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', u1::text, true);
  execute 'set local role authenticated';
  res := save_my_intake(jsonb_build_object('requirements_remove', jsonb_build_array(t_gluten, t_sesame),
                                           'supplements_remove', jsonb_build_array(sup_staff)));
  d := my_intake();
  execute 'reset role';
  if not (res->>'ok')::boolean or res->>'message' not like '%Gluten%' or res->>'message' not like '%Iron%'
     or not exists (select 1 from client_requirements where client_id = c1 and tag_id = t_gluten)
     or exists (select 1 from client_requirements where client_id = c1 and tag_id = t_sesame)
     or not exists (select 1 from client_supplements where id = sup_staff)
     or not (d->'requirements' @> jsonb_build_array(jsonb_build_object('label', 'Gluten', 'mine', false))) then
    raise exception 'FAIL T4 %', res; end if;
  log := log || ' | T4 client removes own items only; dietitian''s stay (named in the message, shown as not theirs)';

  -- T5 review locks the form (adding a must-avoid still allowed); interns: no review, but (since 0044) every answer
  perform set_config('request.jwt.claims', json_build_object('sub', adm, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', adm::text, true);
  update profiles set role = 'intern' where id = adm;
  if (set_client_intake_status(c1, 'reviewed')->>'ok')::boolean then raise exception 'FAIL T5a intern reviewed'; end if;
  insert into client_staff_access (client_id, profile_id) values (c1, adm);
  d := client_intake_for_staff(c1);
  if (d->>'ok') is distinct from 'true'
     or not exists (select 1 from jsonb_array_elements(d->'questions') q where q->>'key' = 'medications' and jsonb_typeof(q->'answer') = 'string')
     or (d->>'hidden_clinical_count')::int <> 0 or jsonb_array_length(d->'changes') = 0 then
    raise exception 'FAIL T5b intern view (0044: interns see every answer) %', d; end if;
  update profiles set role = 'admin' where id = adm;
  res := set_client_intake_status(c1, 'reviewed');
  if not (res->>'ok')::boolean then raise exception 'FAIL T5c %', res; end if;
  perform set_config('request.jwt.claims', json_build_object('sub', u1, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', u1::text, true);
  execute 'set local role authenticated';
  res := save_my_intake('{"about":{"height_cm":170}}'::jsonb);
  if (res->>'ok')::boolean then raise exception 'FAIL T5d edited after review'; end if;
  res := save_my_intake(jsonb_build_object('requirements_add', jsonb_build_array(t_peanut, t_vegan)));
  if not (res->>'ok')::boolean or (my_intake()->>'can_edit')::boolean then raise exception 'FAIL T5e %', res; end if;
  execute 'reset role';
  if not exists (select 1 from client_requirements where client_id = c1 and tag_id = t_peanut)
     or exists (select 1 from client_requirements where client_id = c1 and tag_id = t_vegan) then
    raise exception 'FAIL T5f after review: avoid add should work, diet add shouldn''t'; end if;
  perform set_config('request.jwt.claims', json_build_object('sub', adm, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', adm::text, true);
  d := client_intake_for_staff(c1);
  if (d->>'changes_since_review')::int < 1 or not exists (select 1 from jsonb_array_elements(d->'questions') q where q->>'key' = 'medications' and q->>'answer' = 'Metformin 500 mg')
     or not exists (select 1 from jsonb_array_elements(d->'changes') x where (x->>'by_client')::boolean) then
    raise exception 'FAIL T5g staff view %', d; end if;
  res := set_client_intake_status(c1, 'open');
  if (select status from client_intake where client_id = c1) <> 'open' then raise exception 'FAIL T5h reopen'; end if;
  log := log || ' | T5 reviewed → form locked except adding a must-avoid; intern can''t review but sees every answer (0044); dietitian sees answers + client changes since review; reopen works';

  -- T6 dietitian first: create (name + email), invite, client signs up through the link → their info is there
  insert into clients (full_name, email, date_of_birth, height_cm) values ('ZZtest Dana Diet', 'zz.dana@example.com', '1985-02-02', 170) returning id into c2;
  insert into client_requirements (client_id, tag_id) values (c2, t_dairy);
  res := invite_client_to_app(c2);
  tok := (res->>'token')::uuid;
  if not (res->>'ok')::boolean or (res->>'account_exists')::boolean or res->>'first_name' <> 'ZZtest' or res->>'sender_name' is null then
    raise exception 'FAIL T6a %', res; end if;
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  perform set_config('request.jwt.claim.sub', '', true);
  execute 'set local role anon';
  d := get_client_invitation(tok);
  execute 'reset role';
  if not (d->>'found')::boolean or not (d->>'valid')::boolean or d->>'full_name' <> 'ZZtest Dana Diet' or (d->>'account_exists')::boolean then
    raise exception 'FAIL T6b %', d; end if;
  insert into auth.users (id, email, raw_user_meta_data) values
    (u3, 'zz.dana@example.com', jsonb_build_object('invitation_token', tok, 'account_type', 'client', 'full_name', 'Dana'));
  if (select user_id from clients where id = c2) is distinct from u3 or (select count(*) from clients where email = 'zz.dana@example.com') <> 1
     or (select accepted_at from invitations where token = tok) is null then raise exception 'FAIL T6c link'; end if;
  perform set_config('request.jwt.claims', json_build_object('sub', u3, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', u3::text, true);
  execute 'set local role authenticated';
  d := my_intake();
  execute 'reset role';
  if d->'about'->>'date_of_birth' <> '1985-02-02' or d->>'status' <> 'open'
     or not (d->'requirements' @> jsonb_build_array(jsonb_build_object('label', 'Dairy', 'mine', false))) then
    raise exception 'FAIL T6d prefilled %', d; end if;
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  perform set_config('request.jwt.claim.sub', '', true);
  execute 'set local role anon';
  d := get_client_invitation(tok);
  execute 'reset role';
  if (d->>'valid')::boolean or d->>'reason' <> 'used' then raise exception 'FAIL T6e used link still valid %', d; end if;
  log := log || ' | T6 dietitian creates (name+email) → invite → sign-up through link → linked, no duplicate, dietitian''s details prefilled; link then shows "used"';

  -- T7 the person already has an account (self sign-up with data) → signs in through the link → files merged
  perform set_config('request.jwt.claims', json_build_object('sub', adm, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', adm::text, true);
  insert into clients (full_name, email, height_cm) values ('ZZtest Samuel Self', 'zz.self@example.com', 180) returning id into c3;
  res := invite_client_to_app(c3);
  tok3 := (res->>'token')::uuid;
  if not (res->>'account_exists')::boolean or res->>'message' not like '%sign in%' then raise exception 'FAIL T7a %', res; end if;
  perform set_config('request.jwt.claims', json_build_object('sub', u1, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', u1::text, true);
  execute 'set local role authenticated';
  res := claim_client_invite(tok3);
  d := my_details();
  execute 'reset role';
  if not (res->>'ok')::boolean then raise exception 'FAIL T7b %', res; end if;
  if exists (select 1 from clients where id = c1) or (select user_id from clients where id = c3) is distinct from u1
     or (select height_cm from clients where id = c3) <> 180 or (select date_of_birth from clients where id = c3) <> '1990-05-01'
     or (select count(*) from client_requirements where client_id = c3) <> 3        -- veg, gluten, peanuts
     or (select count(*) from client_supplements where client_id = c3) <> 2
     or (select count(*) from client_weights where client_id = c3) <> 1
     or (select count(*) from client_goals where client_id = c3 and is_primary) <> 1
     or (select answers->>'medications' from client_intake where client_id = c3) <> 'Metformin 500 mg'
     or (select accepted_at from invitations where token = tok3) is null
     or d->>'full_name' <> 'ZZtest Samuel Self' then raise exception 'FAIL T7c merge'; end if;
  log := log || ' | T7 existing account + invite → sign in → own sign-up merged into the dietitian''s file (dietitian''s values win, blanks filled, needs/supplements/weight/goal/answers moved)';

  -- T8 claim refusals: staff account, used link, expired link, sign-up the dietitian already worked on
  perform set_config('request.jwt.claims', json_build_object('sub', adm, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', adm::text, true);
  insert into clients (full_name, email) values ('ZZtest Four', 'zz.four@example.com') returning id into c4;
  tok4 := (invite_client_to_app(c4)->>'token')::uuid;
  res := claim_client_invite(tok4);                                        -- as admin
  if (res->>'ok')::boolean or res->>'message' not like '%staff account%' then raise exception 'FAIL T8a %', res; end if;
  update invitations set expires_at = now() - interval '1 minute' where token = tok4;
  insert into client_targets (client_id, day_type, kcal, source) values (cu2, 'default', 1700, 'dietitian');
  insert into clients (full_name, email) values ('ZZtest Five', 'zz.five@example.com') returning id into c5;
  tok5 := (invite_client_to_app(c5)->>'token')::uuid;
  perform set_config('request.jwt.claims', json_build_object('sub', u2, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', u2::text, true);
  execute 'set local role authenticated';
  if (claim_client_invite(tok3)->>'message') not like '%already been used%' then raise exception 'FAIL T8b used'; end if;
  if (claim_client_invite(tok4)->>'message') not like '%expired%' then raise exception 'FAIL T8c expired'; end if;
  res := claim_client_invite(tok5);
  execute 'reset role';
  if (res->>'ok')::boolean or res->>'message' not like '%dietitian needs to connect%'
     or (select user_id from clients where id = cu2) is distinct from u2 then raise exception 'FAIL T8d %', res; end if;
  log := log || ' | T8 claim refused for staff accounts, used and expired links, and sign-ups a dietitian already worked on (nothing changed)';

  -- T9 privacy: a sign-up using an existing client's email is NOT attached to that client; the
  --    dietitian sees the possible match and merges it; interns can't merge
  perform set_config('request.jwt.claims', json_build_object('sub', adm, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', adm::text, true);
  insert into clients (full_name, email) values ('ZZtest Eve Existing', 'zz.eve@example.com') returning id into c6;
  insert into auth.users (id, email, raw_user_meta_data) values (u5, 'zz.eve@example.com', '{"account_type":"client","full_name":"Eve"}'::jsonb);
  select id into cu5 from clients where user_id = u5;
  if cu5 is null or cu5 = c6 or (select user_id from clients where id = c6) is not null then raise exception 'FAIL T9a attached by email'; end if;
  if not exists (select 1 from jsonb_array_elements(client_signup_queue()) q, jsonb_array_elements(q->'matches') m
                 where (q->>'client_id')::uuid = cu5 and (m->>'client_id')::uuid = c6 and m->'reasons' ? 'same email') then
    raise exception 'FAIL T9b match not shown'; end if;
  update profiles set role = 'intern' where id = adm;
  if (merge_client_into(cu5, c6)->>'ok')::boolean then raise exception 'FAIL T9c intern merged'; end if;
  if jsonb_array_length(client_signup_queue()) <> 0 then raise exception 'FAIL T9d intern sees queue'; end if;
  update profiles set role = 'admin' where id = adm;
  if (merge_client_into(c6, cu5)->>'ok')::boolean then raise exception 'FAIL T9e merged a staff file away'; end if;
  res := merge_client_into(cu5, c6);
  if not (res->>'ok')::boolean or (select user_id from clients where id = c6) is distinct from u5 or exists (select 1 from clients where id = cu5) then
    raise exception 'FAIL T9f merge %', res; end if;
  log := log || ' | T9 same-email sign-up gets its own file (never auto-attached), shows as "same email" match, dietitian merges (intern can''t; staff files can''t be merged away)';

  -- T10 invite checks; expired client link without account_type still makes a client (not "pending")
  insert into clients (full_name) values ('ZZtest No Email') returning id into c7;
  if invite_client_to_app(c7)->>'message' <> 'Add the client''s email address first.'
     or invite_client_to_app(c7, 'nope')->>'message' <> 'That email address doesn''t look right.'
     or invite_client_to_app(c7, adm_email)->>'message' not like '%staff login%' then raise exception 'FAIL T10a'; end if;
  res := invite_client_to_app(c7, 'ZZ.Seven@Example.com');
  if not (res->>'ok')::boolean or (select email from clients where id = c7) <> 'zz.seven@example.com' then raise exception 'FAIL T10b %', res; end if;
  insert into auth.users (id, email, raw_user_meta_data) values (u6, 'zz.four@example.com', jsonb_build_object('invitation_token', tok4));
  if (select role from profiles where id = u6) <> 'client' or not exists (select 1 from clients where user_id = u6 and source = 'self_signup')
     or (select user_id from clients where id = c4) is not null then raise exception 'FAIL T10c expired link sign-up'; end if;
  log := log || ' | T10 invite needs a real non-staff email (saved to the file); an expired client link still makes a client account with its own file';

  -- T11 areas + who may call what
  update client_areas set status = 'hidden' where key = 'community';
  perform set_config('request.jwt.claims', json_build_object('sub', u3, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', u3::text, true);
  execute 'set local role authenticated';
  d := my_areas();
  execute 'reset role';
  if jsonb_array_length(d) <> (select count(*) from client_areas where status <> 'hidden') or d @> '[{"key":"community"}]'::jsonb
     or d->0->>'status' <> 'coming_soon' then raise exception 'FAIL T11a areas %', d; end if;
  perform set_config('request.jwt.claims', json_build_object('sub', adm, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', adm::text, true);
  execute 'set local role authenticated';
  if jsonb_array_length(my_areas()) <> 0 or my_intake()->>'message' <> 'Client accounts only.'
     or save_my_intake('{}'::jsonb)->>'message' <> 'Client accounts only.' or submit_my_intake()->>'message' <> 'Client accounts only.' then
    raise exception 'FAIL T11b staff got client data'; end if;
  execute 'reset role';
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  perform set_config('request.jwt.claim.sub', '', true);
  execute 'set local role anon';
  begin perform my_intake(); raise exception 'FAIL T11c anon ran my_intake';
  exception when insufficient_privilege then null; end;
  begin perform _merge_client_records(c3, c2); raise exception 'FAIL T11d anon ran internal merge';
  exception when insufficient_privilege then null; end;
  execute 'reset role';
  perform set_config('request.jwt.claims', json_build_object('sub', u3, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', u3::text, true);
  execute 'set local role authenticated';
  begin perform _merge_client_records(c3, c2); raise exception 'FAIL T11e client ran internal merge';
  exception when insufficient_privilege then null; end;
  if (select count(*) from client_intake_log) + (select count(*) from intake_questions) + (select count(*) from intake_sections) + (select count(*) from client_areas) <> 0 then
    raise exception 'FAIL T11f client reads new tables'; end if;
  execute 'reset role';
  log := log || ' | T11 coming-soon areas (hidden ones left out); staff refused by client functions; anon/clients can''t run internal helpers or read the new tables';

  raise exception 'ALL PASS (rolled back): %', log;
end $$;
