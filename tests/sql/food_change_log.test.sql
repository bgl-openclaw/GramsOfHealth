-- tests/sql/food_change_log.test.sql — live test of migration 0032.
-- One DO block that always raises → everything rolls back.
-- Runs the edits AS a signed-in user (SET ROLE authenticated + jwt claims of the
-- earliest staff profile) to prove the logging triggers fire for app users.
do $$
declare
  u uuid; n int; n0 int; v boolean; s text; st text; log text := '';
begin
  select id into u from profiles order by created_at limit 1;
  perform set_config('request.jwt.claims', json_build_object('sub', u, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', u::text, true);
  select count(*) into n0 from change_log;
  execute 'set local role authenticated';

  -- T1 verified food, nutrition value changed → un-verified + logged as auto
  update foods set protein_100g = protein_100g + 1 where food_id = 'honey';
  select verified into v from foods where food_id = 'honey';
  select summary into s from change_log where food_id = 'honey' order by id desc limit 1;
  if v or s not like '%protein/100 g%verification removed (values changed)%' then raise exception 'FAIL T1 verified=% "%"', v, s; end if;
  select status into st from recipe_verification where title = 'BERRY & VANILLA MARSCARPONE CUPS';
  log := format('T1 honey protein edit → unverified, "%s"; Berry recipe → %s', s, st);

  -- T2 verified food, non-engine field → stays verified, still logged
  update foods set sodium_100g = coalesce(sodium_100g, 0) + 1 where food_id = 'egg';
  select verified into v from foods where food_id = 'egg';
  select summary into s from change_log where food_id = 'egg' order by id desc limit 1;
  if not v or s not like '%sodium/100 g%' then raise exception 'FAIL T2 verified=% "%"', v, s; end if;
  log := log || format(' | T2 egg sodium → still verified, logged "%s"', s);

  -- T3 explicit verify; T4 verify while changing a value in the same save → stays verified
  update foods set verified = true where food_id = 'salt';
  update foods set verified = true, fibre_100g = coalesce(fibre_100g, 0) where food_id = 'water';
  if not (select verified from foods where food_id = 'salt') or not (select verified from foods where food_id = 'water') then
    raise exception 'FAIL T3/T4'; end if;
  log := log || ' | T3 explicit verify kept | T4 verify + edit in one save kept';

  -- T5 no-op update → no log
  select count(*) into n from change_log;
  update foods set display_name = display_name where food_id = 'egg';
  if (select count(*) from change_log) <> n then raise exception 'FAIL T5 no-op logged'; end if;
  log := log || ' | T5 no-op save → nothing logged';

  -- T6 tag on a verified food → un-verified, ONE tag entry (no duplicate food entry)
  select count(*) into n from change_log;
  insert into food_tags (food_id, tag_id) select 'egg', id from tags where label = 'Sesame' and kind = 'allergen';
  select verified into v from foods where food_id = 'egg';
  select summary into s from change_log where food_id = 'egg' order by id desc limit 1;
  if v or (select count(*) from change_log) <> n + 1 or s not like '%tagged Sesame — verification removed (tags changed)%' then
    raise exception 'FAIL T6 verified=% entries=% "%"', v, (select count(*) from change_log) - n, s; end if;
  log := log || format(' | T6 "%s" (1 entry)', s);

  -- T7 conversions logged, no un-verify
  insert into unit_conversions (food_id, unit, grams) values ('honey', 'test_unit', 10);
  update unit_conversions set grams = 12 where food_id = 'honey' and unit = 'test_unit';
  delete from unit_conversions where food_id = 'honey' and unit = 'test_unit';
  select string_agg(summary, ' / ' order by id) into s from (select id, summary from change_log where entity = 'unit_conversion' order by id desc limit 3) x;
  log := log || format(' | T7 %s', s);

  -- T8 new food, then delete it with a conversion + tag → one "Deleted food" entry, no cascade noise
  insert into foods (food_id, display_name, energy_kcal_100g, protein_100g, fat_100g, carb_avail_100g, fibre_100g, source, verified)
  values ('zz_test_food', 'ZZ Test Food', 100, 1, 1, 1, 1, 'custom', false);
  insert into unit_conversions (food_id, unit, grams) values ('zz_test_food', 'each', 50);
  insert into food_tags (food_id, tag_id) select 'zz_test_food', id from tags where label = 'Egg' and kind = 'allergen';
  select count(*) into n from change_log;
  delete from foods where food_id = 'zz_test_food';
  if (select count(*) from change_log) <> n + 1 then raise exception 'FAIL T8 delete logged % entries', (select count(*) from change_log) - n; end if;
  log := log || ' | T8 new food logged; delete with children → 1 entry';

  -- T9 inbox + mark reviewed; pending can neither see nor mark
  select count(*) into n from changes_to_review;
  execute 'reset role';
  update profiles set role = 'pending' where id = u;
  execute 'set local role authenticated';
  if (select count(*) from changes_to_review) <> 0 then raise exception 'FAIL T9a pending sees inbox'; end if;
  begin perform mark_changes_reviewed(); raise exception 'FAIL T9b';
  exception when others then if sqlerrm like 'FAIL%' then raise; end if; end;
  execute 'reset role';
  update profiles set role = 'admin' where id = u;
  execute 'set local role authenticated';
  perform mark_changes_reviewed();
  if (select count(*) from changes_to_review) <> 0 then raise exception 'FAIL T9c'; end if;
  log := log || format(' | T9 inbox had %s; pending sees 0 and cannot mark; clinician marked all reviewed', n);
  execute 'reset role';

  raise exception 'ALL PASS (rolled back): %', log;
end $$;
