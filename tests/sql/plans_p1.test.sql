-- tests/sql/plans_p1.test.sql — live test of migration 0037 (always rolls back).
--   pass → "ALL PASS (rolled back)"   fail → "FAIL: ..."
-- Uses a throwaway client "ZZ P1 Test" (Mon–Sun pattern hard,moderate,default,rest,…;
-- targets for default + moderate only) and the first AI Verified / Needs review recipes.
-- Publishing runs as the earliest admin/dietitian (request.jwt.claims).
do $$
declare
  adm uuid; c uuid; p uuid; p2 uuid; ra uuid; rn uuid; i1 uuid; i2 uuid;
  res jsonb; snap jsonb; n int; s text; rec record; log text := '';
begin
  select id into adm from profiles where role in ('admin', 'dietitian') order by created_at limit 1;
  perform set_config('request.jwt.claims', json_build_object('sub', adm, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', adm::text, true);
  select recipe_id into ra from recipe_verification where status = 'ai_verified' order by title limit 1;
  select recipe_id into rn from recipe_verification where status = 'needs_review' order by title limit 1;

  insert into clients (full_name) values ('ZZ P1 Test') returning id into c;
  insert into client_structure (client_id, cycle_length_days, day_type_pattern)
  values (c, 7, array['hard','moderate','default','rest','moderate','moderate','default']);
  insert into client_targets (client_id, day_type, kcal, protein_g, source) values
    (c, 'default', 1800, 100, 'dietitian'), (c, 'moderate', 2100, 120, 'dietitian');
  insert into client_meal_slots (client_id, position, name, slot_kind, free_choice) values
    (c, 0, 'Breakfast', 'breakfast', false), (c, 1, 'Lunch', 'lunch', false),
    (c, 2, 'Dinner', 'dinner', false), (c, 3, 'Evening snack', 'snack', true);
  insert into meal_plans (title, days, client_id) values ('ZZ P1 plan', 7, c) returning id into p;

  -- T1 quarter serves
  insert into meal_plan_items (meal_plan_id, recipe_id, position, servings_override, day, meal_slot)
  values (p, ra, 0, 1.25, 1, 'Lunch') returning id into i1;
  begin update meal_plan_items set servings_override = 1.3 where id = i1; raise exception 'FAIL T1';
  exception when others then if sqlerrm like 'FAIL%' then raise; end if; end;
  log := 'T1 1.25 serves saved, 1.3 refused';

  -- T2 publish needs a start date for a client plan
  res := plan_publish_check(p);
  if (res->>'can_publish')::boolean or res->'blockers'->>0 <> 'Set a start date before publishing.' then
    raise exception 'FAIL T2 %', res; end if;
  update meal_plans set start_date = date '2026-10-26' where id = p;   -- a Monday
  log := log || ' | T2 no start date → "Set a start date before publishing."';

  -- T3 day types + targets
  select * into rec from plan_days(p) where day = 1;
  if rec.weekday <> 'Mon' or rec.day_type <> 'hard' or rec.day_type_source <> 'weekly pattern'
     or rec.targets_day_type <> 'default' or rec.kcal <> 1800 then raise exception 'FAIL T3a %', rec; end if;
  select * into rec from plan_days(p) where day = 2;
  if rec.day_type <> 'moderate' or rec.targets_day_type <> 'moderate' or rec.kcal <> 2100 then raise exception 'FAIL T3b %', rec; end if;
  insert into meal_plan_days (meal_plan_id, day, day_type) values (p, 3, 'moderate');
  select * into rec from plan_days(p) where day = 3;
  if rec.date <> date '2026-10-28' or rec.day_type <> 'moderate' or rec.day_type_source <> 'override' or rec.kcal <> 2100 then
    raise exception 'FAIL T3c %', rec; end if;
  select count(*) into n from plan_days(p);
  if n <> 7 then raise exception 'FAIL T3d % days', n; end if;
  log := log || ' | T3 Mon=hard (no hard targets → default 1800), Tue=moderate 2100, Wed override → moderate';

  -- T4 slots: client's own, plus an orphan item slot; plan without client → default four
  insert into meal_plan_items (meal_plan_id, recipe_id, position, day, meal_slot)
  values (p, rn, 1, 2, 'Supper') returning id into i2;
  select string_agg(name || ':' || source || case when free_choice then '(free)' else '' end, ', ' order by position) into s
    from plan_slots(p);
  if s <> 'Breakfast:client, Lunch:client, Dinner:client, Evening snack:client(free), Supper:item' then
    raise exception 'FAIL T4a %', s; end if;
  insert into meal_plans (title, days) values ('ZZ P1 no client', 1) returning id into p2;
  select string_agg(name, ', ' order by position) into s from plan_slots(p2);
  if s <> 'Breakfast, Lunch, Dinner, Snacks' then raise exception 'FAIL T4b %', s; end if;
  log := log || ' | T4 slots: ' || (select string_agg(name, ', ' order by position) from plan_slots(p)) || '; no client → default four';

  -- Snapshot as the app would build it (raw item fields + days)
  snap := jsonb_build_object('schema', 1,
    'items', (select jsonb_agg(jsonb_build_object('item_id', id, 'recipe_id', recipe_id, 'profile_id', profile_id,
                'day', day, 'meal_slot', meal_slot, 'servings_override', servings_override, 'title', 'x'))
              from meal_plan_items where meal_plan_id = p),
    'days', (select jsonb_agg(jsonb_build_object('day', day, 'day_type', day_type, 'date', date)) from plan_days(p)));

  -- T5 a stale snapshot is refused
  res := publish_meal_plan(p, jsonb_set(snap, '{items}', (snap->'items') - 1));
  if (res->>'ok')::boolean or res->>'message' not like 'The plan changed while publishing%' then raise exception 'FAIL T5a %', res; end if;
  res := publish_meal_plan(p, jsonb_set(snap, '{items,0,servings_override}', '2'));
  if (res->>'ok')::boolean then raise exception 'FAIL T5b servings mismatch accepted'; end if;
  log := log || ' | T5 stale snapshot (missing item / different serves) refused';

  -- T6 publish; Needs-review recipe recorded by the database
  res := publish_meal_plan(p, snap);
  if not (res->>'ok')::boolean or (res->>'version_no')::int <> 1 or (select status from meal_plans where id = p) <> 'published'
     or not exists (select 1 from meal_plan_versions where meal_plan_id = p and version_no = 1
                    and cardinality(needs_review_recipes) = 1) then raise exception 'FAIL T6 %', res; end if;
  log := log || format(' | T6 published v1, needs review recorded: %s', res->'needs_review');

  -- T7 published plan is locked; title still editable
  begin insert into meal_plan_items (meal_plan_id, recipe_id, position, day, meal_slot) values (p, ra, 9, 1, 'Dinner'); raise exception 'FAIL T7a';
  exception when others then if sqlerrm like 'FAIL%' then raise; end if; end;
  begin update meal_plan_items set servings_override = 2 where id = i1; raise exception 'FAIL T7b';
  exception when others then if sqlerrm like 'FAIL%' then raise; end if; end;
  begin insert into meal_plan_days (meal_plan_id, day, day_type) values (p, 4, 'hard'); raise exception 'FAIL T7c';
  exception when others then if sqlerrm like 'FAIL%' then raise; end if; end;
  begin update meal_plans set start_date = date '2026-11-02' where id = p; raise exception 'FAIL T7d';
  exception when others then if sqlerrm like 'FAIL%' then raise; end if; end;
  begin update meal_plans set status = 'draft' where id = p; raise exception 'FAIL T7e';
  exception when others then if sqlerrm like 'FAIL%' then raise; end if; end;
  update meal_plans set title = 'ZZ P1 plan (renamed)' where id = p;
  res := publish_meal_plan(p, snap);
  if (res->>'ok')::boolean then raise exception 'FAIL T7f re-publish without new version'; end if;
  log := log || ' | T7 locked: add/edit item, day type, start date, direct status change, re-publish all refused; title editable';

  -- T8 versions are append-only
  begin update meal_plan_versions set needs_review_recipes = '{}' where meal_plan_id = p; raise exception 'FAIL T8a';
  exception when others then if sqlerrm like 'FAIL%' then raise; end if; end;
  begin delete from meal_plan_versions where meal_plan_id = p; raise exception 'FAIL T8b';
  exception when others then if sqlerrm like 'FAIL%' then raise; end if; end;
  log := log || ' | T8 version edit/delete refused';

  -- T9 start a new version, edit, publish v2
  res := start_new_plan_version(p);
  if not (res->>'ok')::boolean or (select status from meal_plans where id = p) <> 'draft' then raise exception 'FAIL T9a %', res; end if;
  update meal_plan_items set servings_override = 1.5 where id = i1;
  delete from meal_plan_items where id = i2;
  snap := jsonb_set(snap, '{items}', (select jsonb_agg(jsonb_build_object('item_id', id, 'recipe_id', recipe_id,
            'profile_id', profile_id, 'day', day, 'meal_slot', meal_slot, 'servings_override', servings_override))
            from meal_plan_items where meal_plan_id = p));
  res := publish_meal_plan(p, snap);
  if not (res->>'ok')::boolean or (res->>'version_no')::int <> 2
     or (select cardinality(needs_review_recipes) from meal_plan_versions where meal_plan_id = p and version_no = 2) <> 0 then
    raise exception 'FAIL T9b %', res; end if;
  log := log || ' | T9 new version → edit → v2 published (no needs-review recipes)';

  -- T10 deleting a recipe used in a published plan still works (item removed, snapshot kept)
  delete from meal_plan_items where id = i1;
  if (select count(*) from meal_plan_versions where meal_plan_id = p) <> 2 then raise exception 'FAIL T10'; end if;
  log := log || ' | T10 item delete on published plan allowed, versions kept';

  -- T11 deleting the client unlinks the published plan; deleting the plan removes its versions
  delete from clients where id = c;
  if (select client_id from meal_plans where id = p) is not null then raise exception 'FAIL T11a'; end if;
  delete from meal_plans where id = p;
  if exists (select 1 from meal_plan_versions where meal_plan_id = p) then raise exception 'FAIL T11b'; end if;
  log := log || ' | T11 client delete unlinks plan; dietitian deletes plan → versions go with it';

  raise exception 'ALL PASS (rolled back): %', log;
end $$;
