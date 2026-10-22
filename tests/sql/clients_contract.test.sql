-- tests/sql/clients_contract.test.sql — live test of migration 0030.
-- One DO block that always raises → everything rolls back.
-- Impersonates the earliest staff profile (admin → clinician) via request.jwt.claims.
-- Uses a throwaway client so real client data (requirements, rules) can't skew the counts.
do $$
declare
  c uuid; u uuid; n int; n2 int; s text; log text := ''; dist text;
begin
  insert into clients (full_name) values ('ZZ contract test') returning id into c;   -- throwaway client: real clients carry real requirements
  select id into u from profiles order by created_at limit 1;
  perform set_config('request.jwt.claims', json_build_object('sub', u, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', u::text, true);
  insert into client_targets (client_id, day_type, kcal, source) values (c, 'default', 1800, 'dietitian');

  -- S1 no requirements → every recipe ok
  select count(*), count(*) filter (where status = 'ok') into n, n2 from client_recipe_screen(c);
  if n <> (select count(*) from recipes) or n2 <> n then raise exception 'FAIL S1 % rows, % ok', n, n2; end if;
  log := format('S1 no requirements → %s/%s ok', n2, n);

  -- S2 Vegan → blocked / unconfirmed / ok
  insert into client_requirements (client_id, tag_id) select c, id from tags where label = 'Vegan' and kind = 'dietary';
  select string_agg(status || ' ' || k, ', ' order by status) into dist
    from (select status, count(*) k from client_recipe_screen(c) group by status) x;
  select count(*) into n from client_recipe_screen(c) where status = 'blocked' and 'contains Egg (Vegan)' = any(reasons);
  if n = 0 then raise exception 'FAIL S2 no "contains Egg (Vegan)" reason'; end if;
  select count(*) into n from client_recipe_screen(c) s
    where s.status = 'ok' and exists (select 1 from ingredient_lines il join foods f on f.food_id = il.food_id
                                      where il.recipe_id = s.recipe_id and not f.verified);
  if n <> 0 then raise exception 'FAIL S3 % ok recipes have unverified foods', n; end if;
  log := log || format(' | S2 Vegan → %s | S3 no "ok" recipe has an unverified ingredient', dist);

  -- S4 avoid food
  insert into client_food_rules (client_id, food_id, rule) values (c, 'garlic', 'avoid');
  select count(*) into n from client_recipe_screen(c) where 'contains avoided food: Garlic, fresh' = any(reasons);
  select count(distinct recipe_id) into n2 from ingredient_lines where food_id = 'garlic';
  if n <> n2 then raise exception 'FAIL S4 avoid garlic flagged % of % recipes', n, n2; end if;
  log := log || format(' | S4 avoid garlic → all %s garlic recipes blocked', n);
  delete from client_food_rules where client_id = c;
  delete from client_requirements where client_id = c;

  -- S5 dislike carrot, primary only (≥10% of weight)
  insert into client_food_rules (client_id, food_id, rule, primary_only) values (c, 'carrot', 'dislike', true);
  select count(*) into n from client_recipe_screen(c) where status = 'disliked';
  select count(distinct recipe_id) into n2 from line_grams where food_id = 'carrot';
  select reasons[1] into s from client_recipe_screen(c) where status = 'disliked' limit 1;
  log := log || format(' | S5 dislike carrot (primary only) → %s of %s carrot recipes, e.g. "%s"', n, n2, s);
  delete from client_food_rules where client_id = c;

  -- S6 protein family preference
  update foods set protein_family = 'chicken' where food_id = 'chicken_breast';
  insert into client_protein_preferences (client_id, protein_family, preference) values (c, 'chicken', 'dislike');
  select count(*) into n from client_recipe_screen(c) where 'disliked protein: Chicken' = any(reasons);
  update client_protein_preferences set preference = 'like' where client_id = c;
  select count(*) into n2 from client_recipe_screen(c) where liked_protein;
  if n = 0 or n <> n2 then raise exception 'FAIL S6 disliked % vs liked %', n, n2; end if;
  log := log || format(' | S6 chicken main protein: %s recipes disliked↔liked', n);

  -- S7 access: pending → 0 rows
  update profiles set role = 'pending' where id = u;
  select count(*) into n from client_recipe_screen(c);
  update profiles set role = 'admin' where id = u;
  if n <> 0 then raise exception 'FAIL S7 pending got % rows', n; end if;
  log := log || ' | S7 pending → 0 rows';

  -- T1 save_client_structure, then a failing save leaves the previous save intact
  perform save_client_structure(c,
    '{"cycle_length_days":7,"repeat_min_gap_days":3,"repeat_max_per_cycle":2,"batch_cooking":true,
      "day_type_pattern":["hard","moderate","rest","default","hard","rest","default"]}'::jsonb,
    '[{"name":"Breakfast","slot_kind":"breakfast","time_of_day":"07:00"},{"name":"Lunch","slot_kind":"lunch"},
      {"name":"Dinner","slot_kind":"dinner","time_of_day":"18:30"},{"name":"Snack","slot_kind":"snack","free_choice":true}]'::jsonb,
    '[{"protein_family":"chicken","count_per_cycle":3},{"protein_family":"fish","count_per_cycle":2}]'::jsonb);
  perform save_client_structure(c, null,
    '[{"name":"Breakfast","slot_kind":"breakfast"},{"name":"Dinner","slot_kind":"dinner"}]'::jsonb, null);
  select count(*) into n from client_meal_slots where client_id = c;
  select count(*) into n2 from client_protein_spread where client_id = c;
  if n <> 2 or n2 <> 2 or (select day_type_pattern[1] from client_structure where client_id = c) <> 'hard' then
    raise exception 'FAIL T1 slots % spread %', n, n2; end if;
  begin
    perform save_client_structure(c, null, '[{"name":"Brunch","slot_kind":"brunch"}]'::jsonb, null);
    raise exception 'FAIL T2 invalid slot accepted';
  exception when others then if sqlerrm like 'FAIL%' then raise; end if; end;
  select count(*) into n from client_meal_slots where client_id = c;
  if n <> 2 then raise exception 'FAIL T2 slots after failed save = %', n; end if;
  log := log || ' | T1 structure saved (pattern, 4→2 slots, spread untouched by null) | T2 invalid save rejected, previous slots intact';

  -- T3 calculator-accepted target needs its working
  begin
    insert into client_targets (client_id, day_type, kcal, source, calc_inputs) values (c, 'rest', 1900, 'calculator_accepted', '{"bmr":1500}');
    raise exception 'FAIL T3';
  exception when others then if sqlerrm like 'FAIL%' then raise; end if; end;
  insert into client_targets (client_id, day_type, kcal, source, calc_inputs) values (c, 'rest', 1900, 'calculator_accepted',
    '{"as_of":"2026-10-15","weight_kg":80,"weighed_on":"2026-10-01","height_cm":180,"age_years":30,"sex_constant":"male","bmr":1780,"tdee":2759}');
  log := log || ' | T3 working without core keys refused; full working accepted';

  -- O1 overview
  select count(*) into n from client_overview where client_id = c and default_kcal is not null;
  if n <> 1 then raise exception 'FAIL O1'; end if;
  log := log || ' | O1 overview row with default kcal';

  raise exception 'ALL PASS (rolled back): %', log;
end $$;
