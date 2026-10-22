-- tests/sql/plans_0049.test.sql — live test of migration 0049 (always rolls back).
--   pass → "ALL PASS (rolled back)"   fail → "FAIL: ..."
-- Throwaway client login (@example.com, self sign-up) with a draft plan; runs as the earliest admin, then as the client.
do $$
declare
  adm uuid; cu uuid := gen_random_uuid(); c uuid; p uuid; ra uuid; rb uuid; f1 text;
  m uuid; a1 uuid; a2 uuid; t uuid; lc uuid; la uuid; g uuid := gen_random_uuid();
  res jsonb; v jsonb; n int; raised boolean; log text := '';
begin
  select id into adm from profiles where role = 'admin' order by created_at limit 1;
  select v.recipe_id into ra from recipe_verification v where v.line_count > 0 order by v.title limit 1;
  select v.recipe_id into rb from recipe_verification v where v.line_count > 0 and v.recipe_id <> ra order by v.title limit 1;
  select food_id into f1 from foods where verified order by food_id limit 1;
  insert into auth.users (id, email, raw_user_meta_data) values
    (cu, 'zz.p0049@example.com', '{"account_type":"client","full_name":"ZZtest Pat Plan"}'::jsonb);
  select id into c from clients where user_id = cu;
  insert into meal_plans (title, days, client_id) values ('ZZ 0049 plan', 7, c) returning id into p;

  perform set_config('request.jwt.claims', json_build_object('sub', adm, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', adm::text, true);
  execute 'set local role authenticated';

  -- T1 moving a meal moves its alternatives and top-ups
  insert into meal_plan_items (meal_plan_id, recipe_id, position, day, meal_slot) values (p, ra, 0, 1, 'Dinner') returning id into m;
  insert into meal_plan_items (meal_plan_id, recipe_id, position, day, meal_slot, option_of) values (p, rb, 5, 1, 'Dinner', m) returning id into a1;
  insert into meal_plan_items (meal_plan_id, recipe_id, position, day, meal_slot, option_of) values (p, ra, 6, 1, 'Dinner', m) returning id into a2;
  insert into meal_plan_items (meal_plan_id, food_id, quantity, unit, boosts_item_id, position, day, meal_slot)
  values (p, f1, 50, 'g', m, 1, 1, 'Dinner') returning id into t;
  update meal_plan_items set day = 3, meal_slot = 'Lunch' where id = m;
  select count(*) into n from meal_plan_items where id in (a1, a2, t) and day = 3 and meal_slot = 'Lunch';
  if n <> 3 then raise exception 'FAIL T1a % of 3 followed the meal', n; end if;
  if exists (select 1 from jsonb_array_elements_text(plan_publish_check(p)->'blockers') b where b ilike '%alternative%' or b ilike '%top-up%')
    then raise exception 'FAIL T1b publish still blocked %', plan_publish_check(p)->'blockers'; end if;
  raised := false; begin update meal_plan_items set day = 4 where id = a1; exception when raise_exception then raised := true; end;
  if not raised then raise exception 'FAIL T1c an alternative moved away from its meal'; end if;
  log := 'T1 a moved meal takes its alternatives and top-ups; an alternative alone still can''t leave its meal';

  -- T2 swap an alternative in, in one step
  res := use_plan_alternative(a1);
  if not (res->>'ok')::boolean then raise exception 'FAIL T2a %', res; end if;
  if (select option_of from meal_plan_items where id = a1) is not null
     or (select option_of from meal_plan_items where id = m) <> a1
     or (select option_of from meal_plan_items where id = a2) <> a1
     or (select boosts_item_id from meal_plan_items where id = t) <> a1
     or (select position from meal_plan_items where id = a1) <> 0
     or (select position from meal_plan_items where id = m) <> 5 then raise exception 'FAIL T2b links after the swap'; end if;
  select count(*) into n from meal_plan_items where meal_plan_id = p and day = 3 and meal_slot = 'Lunch' and option_of is null and boosts_item_id is null;
  if n <> 1 then raise exception 'FAIL T2c % meals in the slot', n; end if;
  if (use_plan_alternative(a1)->>'ok')::boolean then raise exception 'FAIL T2d swapped the meal already shown'; end if;
  if (use_plan_alternative(gen_random_uuid())->>'ok')::boolean then raise exception 'FAIL T2e unknown item'; end if;
  res := use_plan_alternative(m);
  if not (res->>'ok')::boolean or (select option_of from meal_plan_items where id = m) is not null
     or (select option_of from meal_plan_items where id = a1) <> m then raise exception 'FAIL T2f swap back %', res; end if;
  -- a leftovers cook-up can't be swapped out (refused with a message, nothing changes)
  insert into meal_plan_items (meal_plan_id, recipe_id, position, day, meal_slot, batch_group, batch_role)
  values (p, ra, 0, 5, 'Dinner', g, 'cook') returning id into lc;
  insert into meal_plan_items (meal_plan_id, recipe_id, position, day, meal_slot, option_of) values (p, rb, 1, 5, 'Dinner', lc) returning id into la;
  res := use_plan_alternative(la);
  if (res->>'ok')::boolean or (select option_of from meal_plan_items where id = la) <> lc then raise exception 'FAIL T2g leftovers swap %', res; end if;
  execute 'reset role';
  log := log || ' | T2 swap in one step (positions swap, others and top-ups follow, swap back works); leftovers and repeats refused';

  -- T3 the client sees free-choice / empty slots in the published version
  insert into meal_plan_versions (meal_plan_id, version_no, snapshot, published_by_name) values (p, 1,
    '{"schema":2,"plan":{"title":"ZZ 0049 plan","days":7},"days":[],"items":[],"slot_states":[{"day":2,"meal_slot":"Dinner","state":"free_choice","reason":"Dinner out"}]}'::jsonb,
    'ZZ test');
  perform set_config('request.jwt.claims', json_build_object('sub', cu, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', cu::text, true);
  execute 'set local role authenticated';
  v := my_plan_version(p);
  if v is null or v->'slot_states'->0->>'state' <> 'free_choice' or v->'slot_states'->0->>'reason' <> 'Dinner out'
    then raise exception 'FAIL T3 %', v; end if;
  execute 'reset role';
  log := log || ' | T3 client receives slot_states';

  raise exception 'ALL PASS (rolled back): %', log;
end $$;
