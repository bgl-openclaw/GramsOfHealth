-- tests/sql/plans_p1b.test.sql — live test of migration 0047, updated for 0049 (always rolls back).
--   pass → "ALL PASS (rolled back)"   fail → "FAIL: ..."
-- Throwaway client "ZZ P1b Test"; runs as the earliest admin (signed in as an app user), briefly as an intern.
do $$
declare
  adm uuid; c uuid; p uuid; p2 uuid; ra uuid; rn uuid; l1 uuid; l2 uuid; f1 text; f2 text;
  iR uuid; iFood uuid; iT uuid; iC uuid; iE uuid; i9 uuid; iO uuid; cu uuid := gen_random_uuid(); cid uuid; pr uuid; g uuid := gen_random_uuid(); gen uuid; h text;
  res jsonb; snap jsonb; n int; s text; raised boolean; log text := '';
begin
  select id into adm from profiles where role = 'admin' order by created_at limit 1;
  select v.recipe_id into ra from recipe_verification v where v.status = 'ai_verified' and v.line_count >= 2 order by v.title limit 1;
  select v.recipe_id into rn from recipe_verification v where v.recipe_id <> ra and v.line_count > 0 order by v.title limit 1;
  select id into l1 from ingredient_lines where recipe_id = ra order by position, id limit 1;
  select id into l2 from ingredient_lines where recipe_id = ra order by position, id offset 1 limit 1;
  select food_id into f1 from foods where verified and role = 'adjustable_protein' order by food_id limit 1;
  select food_id into f2 from foods where verified and role = 'adjustable_carb' order by food_id limit 1;

  insert into clients (full_name) values ('ZZ P1b Test') returning id into c;
  insert into client_structure (client_id, cycle_length_days) values (c, 7);
  insert into client_meal_slots (client_id, position, name, slot_kind) values
    (c, 0, 'Breakfast', 'breakfast'), (c, 1, 'Lunch', 'lunch'), (c, 2, 'Dinner', 'dinner'), (c, 3, 'Snack', 'snack');
  insert into meal_plans (title, days, client_id, start_date) values ('ZZ P1b plan', 7, c, date '2026-10-26') returning id into p;
  insert into meal_plans (title, days) values ('ZZ P1b other', 1) returning id into p2;
  insert into meal_plan_items (meal_plan_id, recipe_id, position, day, meal_slot) values (p2, ra, 0, 1, 'Lunch') returning id into i9;

  perform set_config('request.jwt.claims', json_build_object('sub', adm, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', adm::text, true);
  execute 'set local role authenticated';

  -- T1 food items
  insert into meal_plan_items (meal_plan_id, food_id, quantity, unit, position, day, meal_slot)
  values (p, f1, 100, 'g', 0, 1, 'Snack') returning id into iFood;
  raised := false; begin insert into meal_plan_items (meal_plan_id, food_id, quantity, unit, servings_override, position, day, meal_slot)
    values (p, f1, 100, 'g', 1, 1, 1, 'Snack'); exception when check_violation then raised := true; end;
  if not raised then raise exception 'FAIL T1a food item with serves'; end if;
  raised := false; begin insert into meal_plan_items (meal_plan_id, recipe_id, quantity, unit, position, day, meal_slot)
    values (p, ra, 100, 'g', 1, 1, 'Lunch'); exception when check_violation then raised := true; end;
  if not raised then raise exception 'FAIL T1b recipe item with a quantity'; end if;
  raised := false; begin insert into meal_plan_items (meal_plan_id, recipe_id, food_id, quantity, unit, position, day, meal_slot)
    values (p, ra, f1, 100, 'g', 1, 1, 'Lunch'); exception when check_violation then raised := true; end;
  if not raised then raise exception 'FAIL T1c both recipe and food'; end if;
  raised := false; begin insert into meal_plan_items (meal_plan_id, food_id, quantity, unit, position, day, meal_slot)
    values (p, f1, 0, 'g', 1, 1, 'Snack'); exception when check_violation then raised := true; end;
  if not raised then raise exception 'FAIL T1d zero quantity'; end if;
  log := 'T1 food items: food + quantity + unit; no serves, no mixing, no zero';

  -- T2 top-ups
  insert into meal_plan_items (meal_plan_id, recipe_id, position, day, meal_slot) values (p, ra, 1, 1, 'Lunch') returning id into iR;
  insert into meal_plan_items (meal_plan_id, food_id, quantity, unit, boosts_item_id, position, day, meal_slot)
  values (p, f1, 50, 'g', iR, 2, 1, 'Lunch') returning id into iT;
  raised := false; begin insert into meal_plan_items (meal_plan_id, recipe_id, boosts_item_id, position, day, meal_slot)
    values (p, ra, iR, 3, 1, 'Lunch'); exception when check_violation then raised := true; end;
  if not raised then raise exception 'FAIL T2a recipe as a top-up'; end if;
  raised := false; begin insert into meal_plan_items (meal_plan_id, food_id, quantity, unit, boosts_item_id, position, day, meal_slot)
    values (p, f1, 50, 'g', i9, 3, 1, 'Lunch'); exception when raise_exception then raised := true; end;
  if not raised then raise exception 'FAIL T2b top-up across plans'; end if;
  update meal_plan_items set day = 2 where id = iT;
  if not (plan_publish_check(p)->'blockers' ? 'A top-up must be on the same day as the meal it adds to.') then raise exception 'FAIL T2c'; end if;
  update meal_plan_items set day = 1 where id = iT;
  log := log || ' | T2 top-ups: food only, same plan, same day';

  -- T3 ingredient changes on one item
  insert into meal_plan_item_deltas (item_id, line_ref, kind, base_food_id, base_quantity, base_unit, new_quantity, new_unit, source)
  select iR, l1, 'quantity', il.food_id, il.quantity, il.unit, coalesce(il.quantity, 1) * 1.2, il.unit, 'adjust' from ingredient_lines il where il.id = l1;
  raised := false; begin insert into meal_plan_item_deltas (item_id, line_ref, kind, new_quantity) values (iR, l1, 'quantity', 5);
    exception when unique_violation then raised := true; end;
  if not raised then raise exception 'FAIL T3a two changes to one line'; end if;
  raised := false; begin insert into meal_plan_item_deltas (item_id, line_ref, kind, new_food_id, new_quantity) values (iR, l2, 'swap', f2, 50);
    exception when check_violation then raised := true; end;
  if not raised then raise exception 'FAIL T3b swap without a unit'; end if;
  raised := false; begin insert into meal_plan_item_deltas (item_id, line_ref, kind, new_food_id, new_quantity, new_unit) values (iR, l2, 'add', f2, 50, 'g');
    exception when check_violation then raised := true; end;
  if not raised then raise exception 'FAIL T3c add pointing at a line'; end if;
  raised := false; begin insert into meal_plan_item_deltas (item_id, line_ref, kind, new_quantity) values (iFood, l1, 'quantity', 5);
    exception when raise_exception then raised := true; end;
  if not raised then raise exception 'FAIL T3d change on a food item'; end if;
  insert into meal_plan_item_deltas (item_id, kind, new_food_id, new_quantity, new_unit, source) values (iR, 'add', f2, 40, 'g', 'suggestion');
  log := log || ' | T3 item ingredient changes: one per line, shape checked, recipes only';

  -- T4 leftovers
  insert into meal_plan_items (meal_plan_id, recipe_id, position, day, meal_slot, batch_group, batch_role)
  values (p, ra, 4, 1, 'Dinner', g, 'cook') returning id into iC;
  insert into meal_plan_items (meal_plan_id, recipe_id, position, day, meal_slot, batch_group, batch_role)
  values (p, ra, 5, 2, 'Lunch', g, 'eat') returning id into iE;
  res := plan_publish_check(p);
  if exists (select 1 from jsonb_array_elements_text(res->'blockers') b where b ilike '%leftover%') then raise exception 'FAIL T4a %', res; end if;
  raised := false; begin insert into meal_plan_items (meal_plan_id, recipe_id, position, day, meal_slot, batch_group, batch_role)
    values (p, ra, 6, 3, 'Dinner', g, 'cook'); exception when unique_violation then raised := true; end;
  if not raised then raise exception 'FAIL T4b two cooks'; end if;
  update meal_plan_items set recipe_id = rn where id = iE;
  if not (plan_publish_check(p)->'blockers' ? 'Leftovers must be the same recipe as the meal they come from.') then raise exception 'FAIL T4c'; end if;
  update meal_plan_items set recipe_id = ra where id = iE;
  update meal_plan_items set day = 3 where id = iC;
  if not (plan_publish_check(p)->'blockers' ? 'Leftovers can''t be eaten before the day they''re cooked.') then raise exception 'FAIL T4d'; end if;
  update meal_plan_items set day = 1 where id = iC;
  raised := false; begin update meal_plan_items set batch_group = g, batch_role = 'eat' where id = iFood; exception when check_violation then raised := true; end;
  if not raised then raise exception 'FAIL T4e food item as a leftover'; end if;
  log := log || ' | T4 leftovers: one cook, same recipe, not before cooking';

  -- T5 slot states
  insert into meal_plan_slot_states (meal_plan_id, day, meal_slot, state, reason) values (p, 3, 'Lunch', 'free_choice', 'Lunch out with work');
  insert into meal_plan_slot_states (meal_plan_id, day, meal_slot, state, reason) values (p, 1, 'Lunch', 'empty', 'No lunch fits');
  if not (plan_publish_check(p)->'blockers' ? 'A slot marked free choice or empty still has food in it.') then raise exception 'FAIL T5a'; end if;
  delete from meal_plan_slot_states where meal_plan_id = p and day = 1;
  raised := false; begin insert into meal_plan_slot_states (meal_plan_id, day, meal_slot) values (p, 4, 'Dinner'); exception when check_violation then raised := true; end;
  if not raised then raise exception 'FAIL T5b a row that says nothing'; end if;
  insert into meal_plan_slot_states (meal_plan_id, day, meal_slot, locked) values (p, 1, 'Dinner', true);
  log := log || ' | T5 slot states: free choice/empty with reason, locked; food in a free-choice slot blocks publishing';

  -- T6 confirmation (an intern may confirm — owner decision)
  update meal_plans set report = '{"days": [], "rules": []}'::jsonb, report_at = now() where id = p;
  if not (plan_publish_check(p)->'blockers' ? 'Review the planner report and confirm the plan before publishing.') then raise exception 'FAIL T6a'; end if;
  raised := false; begin update meal_plans set confirmed_at = now() where id = p; exception when raise_exception then raised := true; end;
  if not raised then raise exception 'FAIL T6b confirmed directly'; end if;
  execute 'reset role';
  update profiles set role = 'intern' where id = adm;
  insert into client_staff_access (client_id, profile_id) values (c, adm) on conflict do nothing;
  execute 'set local role authenticated';
  res := confirm_plan(p, 'Checked protein on days 1-3');
  if not (res->>'ok')::boolean or (select confirmed_by from meal_plans where id = p) <> adm then raise exception 'FAIL T6c intern confirm %', res; end if;
  execute 'reset role';
  update profiles set role = 'admin' where id = adm;
  execute 'set local role authenticated';
  update meal_plan_items set servings_override = 1.5 where id = iR;
  if (select confirmed_at from meal_plans where id = p) is not null then raise exception 'FAIL T6d edit kept confirmation'; end if;
  res := confirm_plan(p, 'Checked protein on days 1-3');
  update meal_plan_item_deltas set new_quantity = new_quantity + 1 where item_id = iR and kind = 'add';
  if (select confirmed_at from meal_plans where id = p) is not null then raise exception 'FAIL T6e ingredient change kept confirmation'; end if;
  res := confirm_plan(p, 'Checked protein on days 1-3');
  update meal_plans set start_date = date '2026-11-02' where id = p;
  if (select confirmed_at from meal_plans where id = p) is not null then raise exception 'FAIL T6f new start date kept confirmation'; end if;
  update meal_plans set title = 'ZZ P1b plan (renamed)' where id = p;
  res := confirm_plan(p, 'Checked protein on days 1-3');
  update meal_plans set title = 'ZZ P1b plan' where id = p;
  if (select confirmed_at from meal_plans where id = p) is null then raise exception 'FAIL T6g renaming cleared confirmation'; end if;
  log := log || ' | T6 confirm: required once there is a report; intern can confirm; any change to food/days/dates clears it, renaming doesn''t';

  -- T7 publish with the new fields
  snap := jsonb_build_object('schema', 2,
    'items', (select jsonb_agg(jsonb_build_object('item_id', i.id, 'recipe_id', i.recipe_id, 'profile_id', i.profile_id,
                'day', i.day, 'meal_slot', i.meal_slot, 'servings_override', i.servings_override, 'food_id', i.food_id,
                'quantity', i.quantity, 'unit', i.unit, 'boosts_item_id', i.boosts_item_id, 'batch_group', i.batch_group,
                'batch_role', i.batch_role,
                'deltas', (select coalesce(jsonb_agg(jsonb_build_object('kind', d.kind, 'line_ref', d.line_ref, 'new_food_id', d.new_food_id,
                             'new_quantity', d.new_quantity, 'new_unit', d.new_unit)), '[]'::jsonb)
                           from meal_plan_item_deltas d where d.item_id = i.id)))
              from meal_plan_items i where i.meal_plan_id = p),
    'slot_states', (select jsonb_agg(jsonb_build_object('day', day, 'meal_slot', meal_slot, 'state', state, 'reason', reason))
                    from meal_plan_slot_states where meal_plan_id = p and state is not null),
    'days', (select jsonb_agg(jsonb_build_object('day', day, 'day_type', day_type)) from plan_days(p)));
  res := publish_meal_plan(p, jsonb_set(snap, '{items}', (select jsonb_agg(x - 'deltas') from jsonb_array_elements(snap->'items') x)));
  if (res->>'ok')::boolean or res->>'message' not like 'The plan changed while publishing%' then raise exception 'FAIL T7a missing changes %', res; end if;
  res := publish_meal_plan(p, snap - 'slot_states');
  if (res->>'ok')::boolean then raise exception 'FAIL T7b missing free-choice slot'; end if;
  res := publish_meal_plan(p, snap);
  if not (res->>'ok')::boolean then raise exception 'FAIL T7c %', res; end if;
  if not exists (select 1 from meal_plan_versions where meal_plan_id = p and version_no = 1
                 and review_notes = 'Checked protein on days 1-3' and confirmed_at is not null and confirmed_by_name is not null)
    then raise exception 'FAIL T7d version without confirmation'; end if;
  raised := false; begin insert into meal_plan_item_deltas (item_id, line_ref, kind) values (iR, l2, 'remove'); exception when raise_exception then raised := true; end;
  if not raised then raise exception 'FAIL T7e change after publishing'; end if;
  raised := false; begin insert into meal_plan_slot_states (meal_plan_id, day, meal_slot, locked) values (p, 2, 'Dinner', true); exception when raise_exception then raised := true; end;
  if not raised then raise exception 'FAIL T7f slot state after publishing'; end if;
  res := start_new_plan_version(p);
  if not (res->>'ok')::boolean or (select confirmed_at from meal_plans where id = p) is not null then raise exception 'FAIL T7g %', res; end if;
  log := log || ' | T7 publish compares items, ingredient changes and free-choice slots; version keeps the confirmation; locked after; new version needs confirming again';

  -- T8 edit log: actor is always the signed-in person; append-only
  insert into plan_edits (meal_plan_id, operation, actor, actor_name, diff) values (p, 'swap_in_slot', gen_random_uuid(), 'Someone else', '{"day": 1}');
  if (select actor from plan_edits where meal_plan_id = p) <> adm then raise exception 'FAIL T8a actor spoofed'; end if;
  raised := false; begin update plan_edits set diff = '{}' where meal_plan_id = p; exception when insufficient_privilege then raised := true; end;
  if not raised then raise exception 'FAIL T8b log edited'; end if;
  raised := false; begin delete from plan_edits where meal_plan_id = p; exception when insufficient_privilege then raised := true; end;
  if not raised then raise exception 'FAIL T8c log deleted'; end if;
  log := log || ' | T8 edit log: actor stamped, no edits or deletes';

  -- T9 planner runs
  h := encode(sha256('zz pool'::bytea), 'hex');
  insert into plan_pool_snapshots (hash, recipe_count, content) values (h, 0, '[]');
  insert into plan_generations (meal_plan_id, seed, settings, pool_hash, planner_version, report, created_by)
  values (p, 42, '{}', h, 'test', '{}', gen_random_uuid()) returning id into gen;
  if (select created_by from plan_generations where id = gen) <> adm then raise exception 'FAIL T9a'; end if;
  update meal_plans set generation_id = gen where id = p;
  raised := false; begin update meal_plans set generation_id = gen where id = p2; exception when raise_exception then raised := true; end;
  if not raised then raise exception 'FAIL T9b another plan''s run'; end if;
  raised := false; begin update plan_pool_snapshots set recipe_count = 1 where hash = h; exception when insufficient_privilege then raised := true; end;
  if not raised then raise exception 'FAIL T9c snapshot edited'; end if;
  log := log || ' | T9 planner runs: pool snapshot + run stored, tied to their plan, append-only';

  -- T10 energy share per client slot
  perform save_client_structure(c, null,
    '[{"name": "Breakfast", "slot_kind": "breakfast", "energy_share": 25}, {"name": "Lunch", "slot_kind": "lunch", "energy_share": 30},
      {"name": "Dinner", "slot_kind": "dinner"}, {"name": "Snack", "slot_kind": "snack", "energy_share": 15}]'::jsonb, null);
  select string_agg(name || '=' || coalesce(energy_share::text, '-'), ',' order by position) into s from client_meal_slots where client_id = c;
  if s <> 'Breakfast=25.00,Lunch=30.00,Dinner=-,Snack=15.00' then raise exception 'FAIL T10a %', s; end if;
  raised := false; begin perform save_client_structure(c, null, '[{"name": "Lunch", "slot_kind": "lunch", "energy_share": 0}]'::jsonb, null);
    exception when check_violation then raised := true; end;
  if not raised then raise exception 'FAIL T10b 0%% share'; end if;
  log := log || ' | T10 slot energy share saved (blank = default), 0 refused';

  -- T11 alternatives: same day and slot, no chains, never on a leftover or top-up; they move with their meal (0049)
  insert into meal_plan_items (meal_plan_id, recipe_id, position, day, meal_slot, option_of) values (p, rn, 7, 1, 'Lunch', iR) returning id into iO;
  raised := false; begin insert into meal_plan_items (meal_plan_id, recipe_id, position, day, meal_slot, option_of) values (p, rn, 8, 1, 'Dinner', iR);
    exception when raise_exception then raised := true; end;
  if not raised then raise exception 'FAIL T11a alternative in another slot'; end if;
  raised := false; begin insert into meal_plan_items (meal_plan_id, recipe_id, position, day, meal_slot, option_of) values (p, rn, 8, 1, 'Lunch', iO);
    exception when raise_exception then raised := true; end;
  if not raised then raise exception 'FAIL T11b alternative of an alternative'; end if;
  raised := false; begin insert into meal_plan_items (meal_plan_id, recipe_id, position, day, meal_slot, option_of, batch_group, batch_role) values (p, ra, 9, 1, 'Dinner', iC, g, 'eat'); exception when check_violation then raised := true; end;
  if not raised then raise exception 'FAIL T11c leftover as an alternative'; end if;
  -- since 0049 moving the meal moves its alternative and top-up too, so nothing is left behind
  update meal_plan_items set meal_slot = 'Dinner' where id = iR;
  if (select meal_slot from meal_plan_items where id = iO) <> 'Dinner' or (select meal_slot from meal_plan_items where id = iT) <> 'Dinner'
     or plan_publish_check(p)->'blockers' ? 'An alternative must be in the same day and slot as the meal it replaces.' then raise exception 'FAIL T11d'; end if;
  update meal_plan_items set meal_slot = 'Lunch' where id = iR;
  if (select meal_slot from meal_plan_items where id = iO) <> 'Lunch' then raise exception 'FAIL T11d back'; end if;
  snap := jsonb_build_object('items', (select jsonb_agg(jsonb_build_object('item_id', i.id, 'recipe_id', i.recipe_id, 'profile_id', i.profile_id, 'day', i.day,
                'meal_slot', i.meal_slot, 'servings_override', i.servings_override, 'food_id', i.food_id, 'quantity', i.quantity, 'unit', i.unit,
                'boosts_item_id', i.boosts_item_id, 'batch_group', i.batch_group, 'batch_role', i.batch_role, 'option_of', i.option_of,
                'deltas', (select coalesce(jsonb_agg(jsonb_build_object('kind', d.kind, 'line_ref', d.line_ref, 'new_food_id', d.new_food_id,
                           'new_quantity', d.new_quantity, 'new_unit', d.new_unit)), '[]'::jsonb) from meal_plan_item_deltas d where d.item_id = i.id)))
              from meal_plan_items i where i.meal_plan_id = p),
    'slot_states', (select jsonb_agg(jsonb_build_object('day', day, 'meal_slot', meal_slot, 'state', state, 'reason', reason)) from meal_plan_slot_states where meal_plan_id = p and state is not null),
    'days', (select jsonb_agg(jsonb_build_object('day', day, 'day_type', day_type)) from plan_days(p)));
  res := confirm_plan(p, 'Checked protein on days 1-3');
  res := publish_meal_plan(p, jsonb_set(snap, '{items}', (select jsonb_agg(x - 'option_of') from jsonb_array_elements(snap->'items') x)));
  if (res->>'ok')::boolean then raise exception 'FAIL T11e snapshot without the alternative link accepted'; end if;
  res := publish_meal_plan(p, snap);
  if not (res->>'ok')::boolean then raise exception 'FAIL T11f %', res; end if;
  log := log || ' | T11 ok';

  -- T12 release date: the client sees a version only from its release date
  execute 'reset role';
  insert into auth.users (id, email, raw_user_meta_data) values (cu, 'zz.p1b.client@example.com', '{"account_type":"client","full_name":"ZZtest Rhea Release"}');
  select id into cid from clients where user_id = cu;
  insert into meal_plans (title, days, client_id, start_date) values ('ZZ P1b release', 1, cid, date '2026-10-26') returning id into pr;
  insert into meal_plan_items (meal_plan_id, recipe_id, position, day, meal_slot) values (pr, ra, 0, 1, 'Lunch');
  execute 'set local role authenticated';
  snap := jsonb_build_object('items', (select jsonb_agg(jsonb_build_object('item_id', id, 'recipe_id', recipe_id, 'day', day, 'meal_slot', meal_slot)) from meal_plan_items where meal_plan_id = pr),
                             'days', (select jsonb_agg(jsonb_build_object('day', day, 'day_type', day_type)) from plan_days(pr)), 'plan', jsonb_build_object('title', 'ZZ P1b release'));
  res := publish_meal_plan(pr, snap, (now() at time zone 'Australia/Sydney')::date + 3);
  if not (res->>'ok')::boolean or res->>'message' not like '%The client sees it from%'
     or (select release_on from meal_plan_versions where meal_plan_id = pr and version_no = 1) is null then raise exception 'FAIL T12a %', res; end if;
  execute 'reset role';
  perform set_config('request.jwt.claims', json_build_object('sub', cu, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', cu::text, true);
  execute 'set local role authenticated';
  if exists (select 1 from my_plans()) or my_plan_version(pr) is not null then raise exception 'FAIL T12b client saw an unreleased version'; end if;
  execute 'reset role';
  perform set_config('request.jwt.claims', json_build_object('sub', adm, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', adm::text, true);
  execute 'set local role authenticated';
  res := start_new_plan_version(pr);
  res := publish_meal_plan(pr, snap);
  if not (res->>'ok')::boolean or (res->>'version_no')::int <> 2 then raise exception 'FAIL T12c %', res; end if;
  execute 'reset role';
  perform set_config('request.jwt.claims', json_build_object('sub', cu, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', cu::text, true);
  execute 'set local role authenticated';
  if (select version_no from my_plans()) <> 2 or (my_plan_version(pr)->>'version_no')::int <> 2 or my_plan_version(pr, 1) is not null
    then raise exception 'FAIL T12d released version not shown'; end if;
  log := log || ' | T12 ok';

  execute 'reset role';
  raise exception 'ALL PASS (rolled back): %', log;
end $$;
