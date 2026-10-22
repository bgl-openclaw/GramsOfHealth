-- tests/sql/clinical_reference_0051.test.sql — live test of migration 0051 (always rolls back).
--   pass → "ALL PASS (rolled back)"   fail → "FAIL: ..."
-- Throwaway reference rows (zz_…) and logins (@example.com): a dietitian, an intern and a self-signed-up client.
do $$
declare
  d1 uuid := gen_random_uuid(); i1 uuid := gen_random_uuid(); cl uuid := gen_random_uuid();
  n int; raised boolean; v numeric; s text; log text := '';
begin
  insert into auth.users (id, email, raw_user_meta_data) values
    (d1, 'zz.ref.diet@example.com', '{"full_name":"ZZtest Dee Ref"}'), (i1, 'zz.ref.intern@example.com', '{"full_name":"ZZtest Ivo Ref"}'),
    (cl, 'zz.ref.client@example.com', '{"account_type":"client","full_name":"ZZtest Cass Ref"}');
  update profiles set role = 'dietitian' where id = d1;
  update profiles set role = 'intern' where id = i1;
  -- the importer's rows (it writes with the service key; here as the owner)
  insert into clinical_markers (row_key, code, name, unit, ref, content_hash) values ('zz_ferritin', 'zz_ferritin', 'ZZ Ferritin', 'µg/L', '{"Marker":"ZZ Ferritin"}', 'h1');
  insert into marker_ranges (row_key, marker_code, population, sex, age_from_days, pregnancy, range_type, low, high, low_text, high_text, ref, content_hash)
  values ('zz_ferritin|Adult', 'zz_ferritin', 'Adult', 'any', 6575, false, 'Reference interval (national harmonised)', 30, 500, '30', '500', '{"Low":"30","High":"500"}', 'r1');
  insert into nutrient_reference_values (row_key, nutrient_code, nutrient, life_stage, sex, status, ear, rdi, ul, ul_applies_to, ref, content_hash)
  values ('zz_iron|Women 19-30 y|Female|General', 'zz_iron', 'ZZ Iron', 'Women 19-30 y', 'female', 'general', 8, 18, 45, 'Total intake', '{"RDI":"18"}', 'n1');

  -- T1 intern: comments yes, decisions no
  perform set_config('request.jwt.claims', json_build_object('sub', i1, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', i1::text, true);
  execute 'set local role authenticated';
  update marker_ranges set comments = 'Our lab prints 20 for women?' where row_key = 'zz_ferritin|Adult';
  get diagnostics n = row_count; if n <> 1 then raise exception 'FAIL T1a intern comment'; end if;
  raised := false; begin update marker_ranges set decision = 'agree' where row_key = 'zz_ferritin|Adult'; exception when raise_exception then raised := true; end;
  if not raised then raise exception 'FAIL T1b intern decided'; end if;
  execute 'reset role';
  if (select review_state from marker_ranges where row_key = 'zz_ferritin|Adult') <> 'proposed'
     or not exists (select 1 from reference_change_log where row_key = 'zz_ferritin|Adult' and field = 'comments' and by_id = i1)
    then raise exception 'FAIL T1c comment not logged, or counted as a decision'; end if;
  log := 'T1 interns comment (logged) but can''t decide';

  -- T2 dietitian: reference values and rows are import-only
  perform set_config('request.jwt.claims', json_build_object('sub', d1, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', d1::text, true);
  execute 'set local role authenticated';
  raised := false; begin update marker_ranges set low = 20 where row_key = 'zz_ferritin|Adult'; exception when raise_exception then raised := true; end;
  if not raised then raise exception 'FAIL T2a reference value edited'; end if;
  raised := false; begin insert into marker_ranges (row_key, marker_code, population, sex, range_type, content_hash) values ('zz_x', 'zz_ferritin', 'x', 'any', 'x', 'x'); exception when others then raised := true; end;
  if not raised then raise exception 'FAIL T2b app inserted a reference row'; end if;
  raised := false; begin delete from marker_ranges where row_key = 'zz_ferritin|Adult'; exception when others then raised := true; end;
  if not raised and exists (select 1 from marker_ranges where row_key = 'zz_ferritin|Adult') is false then raise exception 'FAIL T2c app deleted a reference row'; end if;
  raised := false; begin perform reference_log_change('marker_ranges', 'zz_ferritin|Adult', 'decision', null, 'agree', 'forged', 'x'); exception when raise_exception then raised := true; end;
  if not raised then raise exception 'FAIL T2d change log forged'; end if;
  log := log || ' | T2 reference values and rows are import-only; the change log can''t be written directly';

  -- T3 nothing is active until decided; agree → active, stamped, logged with the reason
  if exists (select 1 from active_marker_ranges where row_key = 'zz_ferritin|Adult') then raise exception 'FAIL T3a active before a decision'; end if;
  update marker_ranges set decision = 'agree', change_reason = 'Matches our usual lab' where row_key = 'zz_ferritin|Adult';
  if (select review_state from marker_ranges where row_key = 'zz_ferritin|Adult') <> 'decided'
     or (select decided_by_name from marker_ranges where row_key = 'zz_ferritin|Adult') <> 'ZZtest Dee Ref'
     or (select effective_low from active_marker_ranges where row_key = 'zz_ferritin|Adult') <> 30
     or not exists (select 1 from reference_change_log where row_key = 'zz_ferritin|Adult' and field = 'decision' and new_value = 'agree' and reason = 'Matches our usual lab')
    then raise exception 'FAIL T3b agree'; end if;
  log := log || ' | T3 inactive until decided; agree makes it active, stamped and logged with the reason';

  -- T4 edit needs a practice value, which then wins
  raised := false; begin update marker_ranges set decision = 'edit' where row_key = 'zz_ferritin|Adult'; exception when check_violation then raised := true; end;
  if not raised then raise exception 'FAIL T4a edit without a value'; end if;
  update marker_ranges set decision = 'edit', practice_low = 20 where row_key = 'zz_ferritin|Adult';
  select effective_low into v from active_marker_ranges where row_key = 'zz_ferritin|Adult';
  if v <> 20 then raise exception 'FAIL T4b practice value not used (%)', v; end if;
  log := log || ' | T4 edit needs a practice value, which then wins';

  -- T5 NRVs: check against RDI with the UL as ceiling; edit overrides
  update nutrient_reference_values set decision = 'agree', check_against = 'rdi', use_in_checks = true where row_key = 'zz_iron|Women 19-30 y|Female|General';
  if (select effective_target from active_nutrient_reference_values where row_key = 'zz_iron|Women 19-30 y|Female|General') <> 18
     or (select effective_ceiling from active_nutrient_reference_values where row_key = 'zz_iron|Women 19-30 y|Female|General') <> 45
    then raise exception 'FAIL T5a nrv'; end if;
  update nutrient_reference_values set decision = 'edit', practice_target = 32 where row_key = 'zz_iron|Women 19-30 y|Female|General';
  if (select effective_target from active_nutrient_reference_values where row_key = 'zz_iron|Women 19-30 y|Female|General') <> 32
    then raise exception 'FAIL T5b nrv edit'; end if;
  log := log || ' | T5 NRV target from the chosen column, UL as ceiling, practice value overrides';

  -- T6 stamps can't be forged
  update marker_ranges set review_state = 'proposed', decided_by_name = 'Someone else' where row_key = 'zz_ferritin|Adult';
  if (select review_state from marker_ranges where row_key = 'zz_ferritin|Adult') <> 'decided'
     or (select decided_by_name from marker_ranges where row_key = 'zz_ferritin|Adult') <> 'ZZtest Dee Ref' then raise exception 'FAIL T6 stamps forged'; end if;
  execute 'reset role';
  log := log || ' | T6 who/when stamps can''t be forged';

  -- T7 a re-import that changes the reference values sends a decided row back for review
  update marker_ranges set ref = '{"Low":"30","High":"600"}', high = 600, high_text = '600', content_hash = 'r2',
         previous_ref = '{"Low":"30","High":"500"}', review_state = 'changed' where row_key = 'zz_ferritin|Adult';
  if exists (select 1 from active_marker_ranges where row_key = 'zz_ferritin|Adult') then raise exception 'FAIL T7a changed row still active'; end if;
  perform set_config('request.jwt.claims', json_build_object('sub', d1, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', d1::text, true);
  execute 'set local role authenticated';
  update marker_ranges set decision = 'agree', practice_low = null, change_reason = 'New lab range is fine' where row_key = 'zz_ferritin|Adult';
  if (select effective_high from active_marker_ranges where row_key = 'zz_ferritin|Adult') <> 600 then raise exception 'FAIL T7b re-decided'; end if;
  execute 'reset role';
  log := log || ' | T7 a changed reference row is inactive until re-decided';

  -- T8 clients see none of it
  perform set_config('request.jwt.claims', json_build_object('sub', cl, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', cl::text, true);
  execute 'set local role authenticated';
  if (select count(*) from marker_ranges) + (select count(*) from active_marker_ranges) + (select count(*) from nutrient_reference_values)
     + (select count(*) from reference_change_log) + (select count(*) from clinical_markers) <> 0 then raise exception 'FAIL T8 client reads reference data'; end if;
  execute 'reset role';
  perform 1 from reference_review_progress;
  log := log || ' | T8 clients see nothing';

  raise exception 'ALL PASS (rolled back): %', log;
end $$;
