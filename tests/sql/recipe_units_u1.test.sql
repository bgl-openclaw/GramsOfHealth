-- tests/sql/recipe_units_u1.test.sql — live test of migration 0036.
-- One DO block that always ends by raising, so everything rolls back.
--   pass → "ALL PASS (rolled back)"   fail → "FAIL: ..."
-- Uses a throwaway food zz_u1_test plus the live watermelon placeholder.
do $$
declare g numeric; e boolean; d text; p text; s text; n int; wm text; log text := '';
begin
  -- T0 migration facts
  select count(*) into n from ingredient_lines where unit = 'kg';
  if n <> 0 then raise exception 'FAIL T0a % kg lines', n; end if;
  select food_id into wm from foods where display_name = 'Watermelon';
  if not (select estimated from unit_conversions where food_id = wm and unit = 'each') then
    raise exception 'FAIL T0b watermelon each not estimated'; end if;
  if not exists (select 1 from recipe_verification where title = 'WATERMELON, MINT AND FETA SALAD'
                 and not ai_verified and 'Watermelon (each)' = any(estimated_ingredients)) then
    raise exception 'FAIL T0c watermelon salad not flagged'; end if;
  log := 'T0 no kg lines; watermelon each estimated; salad flagged';

  -- T1 a person typing a new weight replaces the estimate (logged)
  update unit_conversions set grams = 2000 where food_id = wm and unit = 'each';
  select estimated into e from unit_conversions where food_id = wm and unit = 'each';
  select summary into s from change_log where food_id = wm order by id desc limit 1;
  if e or s not like '%(estimate replaced)%' then raise exception 'FAIL T1 estimated=% log=%', e, s; end if;
  if not exists (select 1 from recipe_verification where title = 'WATERMELON, MINT AND FETA SALAD'
                 and estimated_line_count = 0) then raise exception 'FAIL T1b salad still flagged'; end if;
  log := log || ' | T1 edit grams → confirmed, logged, salad reason gone';

  -- T2 Confirm without changing grams (logged); re-marking as estimate also logged
  update unit_conversions set estimated = true where food_id = wm and unit = 'each';
  update unit_conversions set estimated = false where food_id = wm and unit = 'each';
  select summary into s from change_log where food_id = wm order by id desc limit 1;
  if s not like '%confirmed (no longer an estimate)%' then raise exception 'FAIL T2 log=%', s; end if;
  log := log || ' | T2 confirm logged';

  -- Throwaway food with two estimated sizes
  insert into foods (food_id, display_name, energy_kcal_100g, protein_100g, fat_100g, carb_avail_100g, fibre_100g, source, verified)
  values ('zz_u1_test', 'ZZ U1 test food', 10, 1, 0, 1, 1, 'custom', false);
  insert into unit_conversions (food_id, unit, grams, estimated) values
    ('zz_u1_test', 'small', 50, true), ('zz_u1_test', 'large', 80, true);

  -- T3 default size mirror copies the estimate, and switching sizes keeps it (machine copy ≠ confirm)
  update foods set default_size = 'small' where food_id = 'zz_u1_test';
  update foods set default_size = 'large' where food_id = 'zz_u1_test';
  select grams, estimated into g, e from unit_conversions where food_id = 'zz_u1_test' and unit = 'each';
  if g <> 80 or not e then raise exception 'FAIL T3 each=% estimated=%', g, e; end if;
  log := log || ' | T3 default-size each copies estimate (80 g, estimated)';

  -- T4 confirming the size row by editing it → each follows, confirmed
  update unit_conversions set grams = 85 where food_id = 'zz_u1_test' and unit = 'large';
  select grams, estimated into g, e from unit_conversions where food_id = 'zz_u1_test' and unit = 'each';
  if g <> 85 or e then raise exception 'FAIL T4 each=% estimated=%', g, e; end if;
  log := log || ' | T4 size edited → each 85 g confirmed';

  -- T5 unit names are normalised; built-in weight names refused
  insert into unit_conversions (food_id, unit, grams) values ('zz_u1_test', '  Medium   Head ', 300);
  if not exists (select 1 from unit_conversions where food_id = 'zz_u1_test' and unit = 'medium head') then
    raise exception 'FAIL T5a not normalised'; end if;
  begin insert into unit_conversions (food_id, unit, grams) values ('zz_u1_test', 'KG', 1000); raise exception 'FAIL T5b';
  exception when others then if sqlerrm like 'FAIL%' then raise; end if; end;
  begin insert into unit_conversions (food_id, unit, grams) values ('zz_u1_test', 'g', 1); raise exception 'FAIL T5c';
  exception when others then if sqlerrm like 'FAIL%' then raise; end if; end;
  log := log || ' | T5 "  Medium   Head " → "medium head"; KG and g refused';

  -- T6 Buy as: must exist, follows a rename, cleared on delete
  begin update foods set purchase_unit = 'crate' where food_id = 'zz_u1_test'; raise exception 'FAIL T6a';
  exception when others then if sqlerrm like 'FAIL%' then raise; end if; end;
  update foods set purchase_unit = 'medium head' where food_id = 'zz_u1_test';
  update unit_conversions set unit = 'head' where food_id = 'zz_u1_test' and unit = 'medium head';
  select purchase_unit into p from foods where food_id = 'zz_u1_test';
  if p is distinct from 'head' then raise exception 'FAIL T6b purchase_unit=%', p; end if;
  select summary into s from change_log where food_id = 'zz_u1_test' and entity = 'food' order by id desc limit 1;
  if s not like '%buy as%' then raise exception 'FAIL T6c log=%', s; end if;
  delete from unit_conversions where food_id = 'zz_u1_test' and unit = 'head';
  select purchase_unit into p from foods where food_id = 'zz_u1_test';
  if p is not null then raise exception 'FAIL T6d purchase_unit=%', p; end if;
  log := log || ' | T6 Buy as validated, follows rename, logged, cleared on delete';

  -- T7 deleting a food that has a Buy as still works
  update foods set purchase_unit = 'small' where food_id = 'zz_u1_test';
  delete from foods where food_id = 'zz_u1_test';
  if exists (select 1 from unit_conversions where food_id = 'zz_u1_test') then raise exception 'FAIL T7'; end if;
  log := log || ' | T7 food with Buy as deletes cleanly';

  -- T8 backfill sanity: carrot buys "each", iceberg not touched
  select purchase_unit into p from foods where food_id = 'carrot';
  if p is distinct from 'each' then raise exception 'FAIL T8 carrot=%', p; end if;
  log := log || ' | T8 carrot Buy as each';

  raise exception 'ALL PASS (rolled back): %', log;
end $$;
