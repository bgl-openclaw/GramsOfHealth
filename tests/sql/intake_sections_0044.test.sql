-- tests/sql/intake_sections_0044.test.sql — live test of migration 0044 (always rolls back).
--   pass → "ALL PASS (rolled back)"   fail → "FAIL: ..."
-- Runs as the earliest admin, temporarily switched to dietitian / intern inside the transaction.
-- The client is a throwaway self sign-up ('ZZtest …' / @example.com).
do $$
declare
  adm uuid; u1 uuid := gen_random_uuid(); c1 uuid; d jsonb; res jsonb; n int; raised boolean; keys text; log text := '';
begin
  select id into adm from profiles where role = 'admin' order by created_at limit 1;
  perform set_config('request.jwt.claims', json_build_object('sub', adm, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', adm::text, true);

  -- T1 seed
  if (select string_agg(key || ':' || array_to_string(builtins, '+'), ',' order by position) from intake_sections)
     <> 'about:details,goals:goal,food:requirements,health:supplements,lifestyle:,consent:' then raise exception 'FAIL T1 sections'; end if;
  if exists (select 1 from intake_questions q where not exists (select 1 from intake_sections s where s.key = q.section))
     or not (select locked from intake_questions where key = 'consent_privacy') or (select count(*) from intake_questions where locked) <> 1
    then raise exception 'FAIL T1 questions'; end if;
  log := 'T1 6 sections with their fixed details; consent locked';

  -- T2 a dietitian edits the form
  update profiles set role = 'dietitian' where id = adm;
  execute 'set local role authenticated';
  insert into intake_sections (key, title, position) values ('travel', 'Travel', 70);
  insert into intake_questions (key, section, label, kind, position) values ('trips', 'travel', 'Trips coming up?', 'long_text', 10);
  update intake_sections set title = 'About you and your week' where key = 'about';
  update intake_questions set label = 'Anything else?' where key = 'anything_else';
  update intake_questions set key = key, locked = locked, active = active, required = required where key = 'consent_privacy';  -- whole-row save
  update intake_sections set active = false where key = 'lifestyle';
  if (select title from intake_sections where key = 'about') <> 'About you and your week'
     or (select active from intake_sections where key = 'lifestyle') then raise exception 'FAIL T2 edits'; end if;
  raised := false; begin delete from intake_questions where key = 'trips'; exception when others then raised := true; end;
  if not raised then raise exception 'FAIL T2 delete allowed'; end if;
  raised := false; begin update intake_sections set active = false where key = 'about'; exception when raise_exception then raised := true; end;
  if not raised then raise exception 'FAIL T2 about switched off'; end if;
  raised := false; begin update intake_sections set active = false where key = 'consent'; exception when raise_exception then raised := true; end;
  if not raised then raise exception 'FAIL T2 consent section switched off'; end if;
  raised := false; begin update intake_questions set active = false where key = 'consent_privacy'; exception when raise_exception then raised := true; end;
  if not raised then raise exception 'FAIL T2 consent question switched off'; end if;
  raised := false; begin update intake_questions set key = 'reasons2' where key = 'reasons'; exception when raise_exception then raised := true; end;
  if not raised then raise exception 'FAIL T2 key changed'; end if;
  raised := false; begin update intake_sections set builtins = '{goal}' where key = 'travel'; exception when raise_exception then raised := true; end;
  if not raised then raise exception 'FAIL T2 builtins moved'; end if;
  log := log || ' | T2 dietitian adds/renames/switches off; can''t delete, unlock, re-key or move fixed details';

  -- T3 an intern can read the form but not change it
  execute 'reset role';
  update profiles set role = 'intern' where id = adm;
  execute 'set local role authenticated';
  if (select count(*) from intake_sections) <> 7 then raise exception 'FAIL T3 intern read'; end if;
  raised := false; begin insert into intake_sections (key, title) values ('zz', 'ZZ'); exception when others then raised := true; end;
  if not raised then raise exception 'FAIL T3 intern inserted'; end if;
  update intake_questions set label = 'Changed by intern' where key = 'gp';
  if (select label from intake_questions where key = 'gp') = 'Changed by intern' then raise exception 'FAIL T3 intern updated'; end if;
  res := reorder_intake('["goals"]', null);
  if (res->>'ok')::boolean then raise exception 'FAIL T3 intern reordered'; end if;
  log := log || ' | T3 intern read-only';

  -- T4 reorder: sections and questions in one call; inactive questions sink
  execute 'reset role';
  update profiles set role = 'dietitian' where id = adm;
  execute 'set local role authenticated';
  update intake_questions set active = false where key = 'success';
  res := reorder_intake('["goals", "about", "food", "health", "lifestyle", "travel", "consent"]',
                        '[{"key": "success"}, {"key": "top_priorities"}, {"key": "reasons"}, {"key": "tried_before"}, {"key": "gp", "section": "lifestyle"}]');
  if not (res->>'ok')::boolean then raise exception 'FAIL T4 %', res; end if;
  if (select string_agg(key, ',' order by position) from intake_sections) <> 'goals,about,food,health,lifestyle,travel,consent'
     or (select string_agg(key, ',' order by position) from intake_questions where section = 'goals') <> 'top_priorities,reasons,tried_before,success'
     or (select section from intake_questions where key = 'gp') <> 'lifestyle' then raise exception 'FAIL T4 order'; end if;
  update intake_questions set section = 'health' where key = 'gp';   -- put it back for the next steps
  update intake_questions set active = true where key = 'success';
  res := reorder_intake('["about", "goals", "food", "health", "lifestyle", "travel", "consent"]', null);
  update intake_sections set active = true where key = 'lifestyle';
  log := log || ' | T4 reorder sections + questions, move a question, inactive last';

  -- T5 a client's own form: only the picked questions (+ the locked consent), sections that hold them or fixed details
  execute 'reset role';
  insert into auth.users (id, email, raw_user_meta_data) values
    (u1, 'ZZ.Form@example.com', '{"account_type":"client","full_name":"ZZtest Fay Form"}'::jsonb);
  select id into c1 from clients where user_id = u1;
  update profiles set role = 'dietitian' where id = adm;
  perform set_config('request.jwt.claims', json_build_object('sub', adm, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', adm::text, true);
  execute 'set local role authenticated';
  res := set_client_intake_questions(c1, array['reasons', 'gp', 'medications']);
  if not (res->>'ok')::boolean or res->'question_keys' <> '["consent_privacy", "gp", "medications", "reasons"]'::jsonb then raise exception 'FAIL T5a %', res; end if;
  res := set_client_intake_questions(c1, array['nope']);
  if (res->>'ok')::boolean then raise exception 'FAIL T5b unknown key accepted'; end if;
  execute 'reset role';
  perform set_config('request.jwt.claims', json_build_object('sub', u1, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', u1::text, true);
  execute 'set local role authenticated';
  d := my_intake();
  select string_agg(q->>'key', ',' order by o) into keys from jsonb_array_elements(d->'questions') with ordinality t(q, o);
  if keys <> 'reasons,medications,gp,consent_privacy' then raise exception 'FAIL T5c questions %', keys; end if;
  select string_agg(s->>'key', ',' order by o) into keys from jsonb_array_elements(d->'sections') with ordinality t(s, o);
  if keys <> 'about,goals,food,health,consent' then raise exception 'FAIL T5d sections %', keys; end if;
  if not (d->'missing' ? (select label from intake_questions where key = 'reasons'))
     or (d->'missing' ? (select label from intake_questions where key = 'top_priorities'))
     or not (d->'missing' ? (select label from intake_questions where key = 'consent_privacy')) then raise exception 'FAIL T5e missing %', d->'missing'; end if;
  log := log || ' | T5 client sees only their questions + consent; missing counts only those';

  -- T6 the client completes their cut-down form and submits (top_priorities isn't on it)
  res := save_my_intake(jsonb_build_object(
    'about', jsonb_build_object('date_of_birth', '1991-02-03', 'height_cm', 170),
    'weight_kg', 70,
    'answers', jsonb_build_object('reasons', jsonb_build_array('Gut health'), 'medications', 'None', 'consent_privacy', true)));
  if not (res->>'ok')::boolean then raise exception 'FAIL T6a save %', res; end if;
  res := submit_my_intake();
  if not (res->>'ok')::boolean then raise exception 'FAIL T6b submit %', res; end if;
  log := log || ' | T6 submit checks only the client''s own required questions';

  -- T7 an intern with access sees every answer, including health ones
  execute 'reset role';
  update profiles set role = 'intern' where id = adm;
  insert into client_staff_access (client_id, profile_id) values (c1, adm) on conflict do nothing;
  perform set_config('request.jwt.claims', json_build_object('sub', adm, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', adm::text, true);
  execute 'set local role authenticated';
  d := client_intake_for_staff(c1);
  if not (d->>'ok')::boolean or (d->>'hidden_clinical_count')::int <> 0
     or not exists (select 1 from jsonb_array_elements(d->'questions') q where q->>'key' = 'medications' and q->'answer' = '"None"'::jsonb)
     or d->'question_keys' <> '["consent_privacy", "gp", "medications", "reasons"]'::jsonb
     or (select count(*) from jsonb_array_elements(d->'questions') q where (q->>'selected')::boolean) <> 4
     or jsonb_array_length(d->'sections') <> 7 then raise exception 'FAIL T7 staff view %', d; end if;
  res := set_client_intake_questions(c1, null);
  if (res->>'ok')::boolean then raise exception 'FAIL T7b intern changed the form'; end if;
  log := log || ' | T7 intern sees health answers; selection shown; intern can''t change the form';

  -- T8 back to every question
  execute 'reset role';
  update profiles set role = 'dietitian' where id = adm;
  execute 'set local role authenticated';
  res := set_client_intake_questions(c1, null);
  if not (res->>'ok')::boolean or res->'question_keys' <> 'null'::jsonb then raise exception 'FAIL T8 %', res; end if;
  execute 'reset role';
  select count(*) into n from intake_client_questions(c1);
  if n <> (select count(*) from intake_questions q join intake_sections s on s.key = q.section where q.active and s.active) then raise exception 'FAIL T8b count'; end if;
  log := log || ' | T8 null = every active question';

  raise exception 'ALL PASS (rolled back): %', log;
end $$;
