-- tests/sql/ausnut_g1.test.sql — live test of migrations 0041 + 0042 (AUSNUT G1). Always rolls back.
--   pass → "ALL PASS (rolled back)"   fail → "FAIL: ..."
-- Uses throwaway rows only: AUSNUT keys F99999x, food zz_g1_food, recipe/client 'ZZ G1 …'.
do $$
declare
  adm uuid; c uuid; r uuid; t_sesame uuid; t_vegan uuid; v record; s text; n int; log text := '';
begin
  select id into adm from profiles where role = 'admin' order by created_at limit 1;
  select id into t_sesame from tags where label = 'Sesame';
  select id into t_vegan from tags where label = 'Vegan';
  perform set_config('request.jwt.claims', json_build_object('sub', adm, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', adm::text, true);

  insert into ausnut_master (public_food_key, survey_id, food_name, energy_kcal, protein_g, fat_g, carb_avail_without_sa_g, fibre_g)
  values ('F999990', 'ZZ999990', 'Zz test food, raw', 100, 10, 5, 4, 2);
  insert into ausnut_measures (measure_id, public_food_key, quantity, gram_amount, is_density, is_brand_pack)
  values (99999990, 'F999990', 1, 50, false, false);

  -- T1 a complete throwaway recipe whose only problem is one unverified food
  insert into foods (food_id, display_name, source, energy_kcal_100g, protein_100g, fat_100g, carb_avail_100g, fibre_100g, verified)
  values ('zz_g1_food', 'Zz test food', 'custom', 100, 10, 5, 4, 2, false);
  insert into recipes (title, servings, image_url_1) values ('ZZ G1 recipe', 1, 'https://example.com/zz.jpg') returning id into r;
  insert into ingredient_lines (recipe_id, food_id, position, quantity, unit) values (r, 'zz_g1_food', 0, 100, 'g');
  insert into method_steps (recipe_id, position, text) values (r, 0, 'Cook it.');
  select * into v from recipe_verification where recipe_id = r;
  if v.status <> 'needs_review' or v.unverified_food_count <> 1 or v.ai_verified_food_count <> 0 or v.food_note <> '1 unverified' then
    raise exception 'FAIL T1 %', row_to_json(v); end if;
  log := 'T1 unverified food → needs review ("1 unverified")';

  -- T2 the import sets AI verification (ai_verified_at in the same statement) with a change note
  perform set_config('goh.change_note', 'AUSNUT 2023 F999990', true);
  update foods set ausnut_key = 'F999990', ai_verified = true, ai_verified_at = now(), ai_match_confidence = 'exact_key',
         ai_evidence = 'AUSNUT 2023 F999990 Zz test food, raw; 100 kcal, P 10, F 5, C 4, fibre 2 per 100 g'
   where food_id = 'zz_g1_food';
  perform set_config('goh.change_note', '', true);
  select * into v from recipe_verification where recipe_id = r;
  if v.status <> 'ai_verified' or cardinality(v.reasons) <> 0 or v.ai_verified_food_count <> 1
     or v.food_note <> '1 food AI verified' or v.unverified_food_count <> 0 then raise exception 'FAIL T2a %', row_to_json(v); end if;
  select summary into s from change_log where food_id = 'zz_g1_food' and entity = 'food' and action = 'update' order by id desc limit 1;
  if s not like '%[AUSNUT 2023 F999990]' then raise exception 'FAIL T2b change note: %', s; end if;
  if not (select ready from recipe_readiness where recipe_id = r)
     or (select blocked_recipes from food_leverage where food_id = 'zz_g1_food') <> 0
     or (select awaiting_dietitian_recipes from food_leverage where food_id = 'zz_g1_food') <> 1 then raise exception 'FAIL T2c readiness/leverage'; end if;
  log := log || ' | T2 AI verified → recipe AI Verified, reasons empty, note "1 food AI verified", change log names the key, readiness + leverage agree';

  -- T3 the import re-writing numbers in the same statement as ai_verified_at keeps AI verification
  update foods set energy_kcal_100g = 101, ai_verified_at = clock_timestamp() where food_id = 'zz_g1_food';
  if not (select ai_verified from foods where food_id = 'zz_g1_food') then raise exception 'FAIL T3 import write cleared itself'; end if;
  log := log || ' | T3 import write keeps it';

  -- T4 a person changes the numbers → AI verification cleared and logged; recipe back to needs review
  update foods set protein_100g = 11 where food_id = 'zz_g1_food';
  select * into v from foods where food_id = 'zz_g1_food';
  if v.ai_verified or v.ai_evidence is not null or v.ai_match_confidence is not null or v.ai_verified_at is not null then
    raise exception 'FAIL T4a not cleared'; end if;
  select summary into s from change_log where food_id = 'zz_g1_food' and entity = 'food' order by id desc limit 1;
  if s not like '%AI verification removed%' then raise exception 'FAIL T4b %', s; end if;
  if (select status from recipe_verification where recipe_id = r) <> 'needs_review' then raise exception 'FAIL T4c'; end if;
  log := log || ' | T4 hand edit clears AI verification (logged)';

  -- T5 AI verified always carries key + evidence + date + confidence
  begin
    update foods set ai_verified = true, ai_verified_at = now() where food_id = 'zz_g1_food';
    raise exception 'FAIL T5 incomplete AI verification accepted';
  exception when check_violation then null; end;
  begin
    update foods set ai_match_confidence = 'guess' where food_id = 'zz_g1_food';
    raise exception 'FAIL T5b bad confidence accepted';
  exception when check_violation then null; end;
  log := log || ' | T5 incomplete/invalid AI verification refused';

  -- T6 a tag change clears AI verification; the tag trigger's own foods update isn't double-logged
  update foods set ai_verified = true, ai_verified_at = clock_timestamp(), ai_match_confidence = 'exact_key', ai_evidence = 'x'
   where food_id = 'zz_g1_food';
  select count(*) into n from change_log where food_id = 'zz_g1_food';
  insert into food_tags (food_id, tag_id) values ('zz_g1_food', t_sesame);
  if (select ai_verified from foods where food_id = 'zz_g1_food') then raise exception 'FAIL T6a'; end if;
  if (select count(*) from change_log where food_id = 'zz_g1_food') <> n + 1 then raise exception 'FAIL T6b double-logged'; end if;
  select summary into s from change_log where food_id = 'zz_g1_food' order by id desc limit 1;
  if s not like '%AI verification removed (tags changed)%' then raise exception 'FAIL T6c %', s; end if;
  delete from food_tags where food_id = 'zz_g1_food';
  log := log || ' | T6 tag change clears it, logged once';

  -- T7 removing dietitian verification clears AI verification too ("Mark as unverified")
  update foods set verified = true where food_id = 'zz_g1_food';
  update foods set ai_verified = true, ai_verified_at = clock_timestamp(), ai_match_confidence = 'checked_verified', ai_evidence = 'x'
   where food_id = 'zz_g1_food';
  update foods set protein_100g = protein_100g where food_id = 'zz_g1_food';     -- "Save & verify" re-sending the same numbers
  if not (select verified and ai_verified from foods where food_id = 'zz_g1_food') then raise exception 'FAIL T7a unchanged save cleared it'; end if;
  update foods set verified = false where food_id = 'zz_g1_food';
  if (select ai_verified from foods where food_id = 'zz_g1_food') then raise exception 'FAIL T7b'; end if;
  log := log || ' | T7 unchanged save keeps both; "Mark as unverified" clears AI too';

  -- T8 client screening ignores AI verification (stays on dietitian verification)
  update foods set ai_verified = true, ai_verified_at = clock_timestamp(), ai_match_confidence = 'exact_key', ai_evidence = 'x'
   where food_id = 'zz_g1_food';
  insert into clients (full_name) values ('ZZ G1 client') returning id into c;
  insert into client_requirements (client_id, tag_id) values (c, t_vegan);
  select status into s from client_recipe_screen(c) where recipe_id = r;
  if s <> 'unconfirmed' then raise exception 'FAIL T8 screen trusted AI verification: %', s; end if;
  log := log || ' | T8 client screen still "unconfirmed" for an AI-only food';

  -- T9 reference tables: staff read, nobody writes through the API, clients/pending/anon see nothing
  update profiles set role = 'intern' where id = adm;
  execute 'set local role authenticated';
  select count(*) into n from ausnut_master;
  if n < 1 then raise exception 'FAIL T9a staff can''t read'; end if;
  begin insert into ausnut_master (public_food_key, survey_id, food_name) values ('F999989', 'ZZ999989', 'x'); raise exception 'FAIL T9b staff wrote';
  exception when insufficient_privilege then null; end;
  execute 'reset role';
  foreach s in array array['pending', 'client'] loop
    update profiles set role = s where id = adm;
    execute 'set local role authenticated';
    if (select count(*) from ausnut_master) + (select count(*) from ausnut_measures) + (select count(*) from ausnut_classifications) <> 0 then
      raise exception 'FAIL T9c % reads AUSNUT', s; end if;
    execute 'reset role';
  end loop;
  update profiles set role = 'admin' where id = adm;
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  perform set_config('request.jwt.claim.sub', '', true);
  execute 'set local role anon';
  begin perform count(*) from ausnut_master; raise exception 'FAIL T9d anon read';
  exception when insufficient_privilege then null; end;
  execute 'reset role';
  log := log || ' | T9 AUSNUT tables: staff read-only, client/pending/anon none';

  -- T10 foreign key: ausnut_key must exist in ausnut_master
  begin update foods set ausnut_key = 'F000000' where food_id = 'zz_g1_food'; raise exception 'FAIL T10';
  exception when foreign_key_violation then null; end;
  log := log || ' | T10 unknown AUSNUT key refused';

  raise exception 'ALL PASS (rolled back): %', log;
end $$;
