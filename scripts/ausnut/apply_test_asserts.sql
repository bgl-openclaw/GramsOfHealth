
do $t$
declare r jsonb; n int; v text; skipped text;
begin
  -- T1 dry run: report comes back, nothing persists
  r := ausnut_apply_batch('g3a', true);
  if (r ->> 'dry_run')::boolean is not true or (r ->> 'applied')::int = 0 then raise exception 'T1 FAIL: dry-run report %', r; end if;
  if (select ai_verified from foods where food_id = 'almond') then raise exception 'T1 FAIL: dry run persisted'; end if;
  if exists (select 1 from ausnut_review_queue) then raise exception 'T1 FAIL: dry run queued rows'; end if;
  if exists (select 1 from ausnut_changeset where status <> 'pending') then raise exception 'T1 FAIL: dry run changed statuses'; end if;

  -- T2 g3a verified foods
  r := ausnut_apply_batch('g3a', false);
  if not (select ai_verified and verified and ai_match_confidence = 'checked_verified' and ausnut_key = 'F006081' and match_note like '%reviewed relink%'
            from foods where food_id = 'almond') then raise exception 'T2 FAIL: almond'; end if;
  if not (select ai_verified and verified and ausnut_key = 'F005174' from foods where food_id = 'lemon') then raise exception 'T2 FAIL: lemon key fix'; end if;
  if not exists (select 1 from ausnut_review_queue where food_id = 'milk_chocolate' and kind = 'urgent')
     or not (select not verified and not ai_verified and energy_kcal_100g = 81 from foods where food_id = 'milk_chocolate')
    then raise exception 'T2 FAIL: urgent food: badge removed, numbers untouched'; end if;
  if not (select ausnut_key = 'F004380' and not ai_verified and verified from foods where food_id = 'honey')
     or not exists (select 1 from ausnut_review_queue where food_id = 'honey' and kind = 'verified_check') then raise exception 'T2 FAIL: honey flag'; end if;
  if not exists (select 1 from ausnut_review_queue where food_id = 'vanilla_extract' and kind = 'verified_check') then raise exception 'T2 FAIL: no-key flag'; end if;
  if not exists (select 1 from change_log where food_id = 'almond' and summary like '%AUSNUT 2023 F006081%') then raise exception 'T2 FAIL: change note'; end if;

  -- T3 g3b: a person edits pepita after the build → its op must SKIP, not overwrite
  update foods set energy_kcal_100g = 999 where food_id = 'pepita';
  r := ausnut_apply_batch('g3b', false);
  if (select ai_verified from foods where food_id = 'pepita') then raise exception 'T3 FAIL: stale op overwrote pepita'; end if;
  if not exists (select 1 from ausnut_changeset where batch = 'g3b' and food_id = 'pepita' and status = 'skipped' and result like 'skipped: energy_kcal_100g is now 999%')
    then raise exception 'T3 FAIL: pepita skip not recorded'; end if;
  if (select count(*) from food_tags ft join tags t on t.id = ft.tag_id where ft.food_id = 'pancake' and t.label in ('Gluten', 'Egg', 'Dairy')) <> 3
    then raise exception 'T3 FAIL: pancake allergens'; end if;
  if not (select ai_verified and ai_match_confidence = 'exact_key' and energy_kcal_100g = 214.1 from foods where food_id = 'pancake')
    then raise exception 'T3 FAIL: pancake AI write (tags must come first)'; end if;
  if exists (select 1 from food_tags ft join tags t on t.id = ft.tag_id where ft.food_id = 'danish_feta' and t.label = 'Vegan')
     or (select verified from foods where food_id = 'danish_feta') then raise exception 'T3 FAIL: feta vegan claim'; end if;
  if not exists (select 1 from food_tags ft join tags t on t.id = ft.tag_id where ft.food_id = 'haloumi' and t.label = 'Dairy') then raise exception 'T3 FAIL: haloumi dairy'; end if;
  if not (select ai_verified and not verified and energy_kcal_100g = 313.3 and ausnut_key = 'F006316' and ai_match_confidence = 'agreed_list'
            from foods where food_id = 'paprika') then raise exception 'T3 FAIL: paprika'; end if;
  if not (select energy_kcal_100g = 50 and density_g_ml = 1.15 and ai_verified from foods where food_id = 'soy_sauce') then raise exception 'T3 FAIL: soy sauce (density kept)'; end if;
  if not exists (select 1 from ausnut_review_queue where food_id = 'protein_powder' and kind = 'label')
     or not exists (select 1 from ausnut_review_queue where food_id = 'soba_noodles' and kind = 'proposal')
     or (select ai_verified from foods where food_id = 'soba_noodles') then raise exception 'T3 FAIL: label/proposal queue'; end if;

  -- T4 g3c measures and lines
  r := ausnut_apply_batch('g3c', false);
  if not exists (select 1 from unit_conversions where food_id = 'sundried_tomato' and unit = 'each' and grams = 4.8 and not estimated) then raise exception 'T4 FAIL: sun-dried each'; end if;
  if not exists (select 1 from unit_conversions where food_id = 'garlic' and unit = 'large' and grams = 5 and estimated) then raise exception 'T4 FAIL: garlic large stays an estimate'; end if;
  if not exists (select 1 from unit_conversions where food_id = 'pear' and unit = 'medium' and not estimated) then raise exception 'T4 FAIL: pear confirmed'; end if;
  if not (select default_size = 'medium stalk' from foods where food_id = 'celery')
     or not exists (select 1 from unit_conversions where food_id = 'celery' and unit = 'each' and grams = 40) then raise exception 'T4 FAIL: celery each'; end if;
  if not exists (select 1 from unit_conversions where food_id = 'dijon_mustard' and unit = 'tsp' and grams = 5.3) then raise exception 'T4 FAIL: dijon tsp'; end if;
  if not exists (select 1 from ingredient_lines where id = (select (args ->> 'line_id')::uuid from ausnut_changeset where batch = 'g3c' and op = 'update_line' and food_id = 'green_bean')
                   and quantity = 200 and unit = 'g') then raise exception 'T4 FAIL: green bean line'; end if;
  if not exists (select 1 from ingredient_lines il join recipes rc on rc.id = il.recipe_id where rc.title = 'PIKELETS' and il.food_id = 'self_raising_flour' and il.unit = 'cup')
    then raise exception 'T4 FAIL: pikelet flour cup'; end if;
  if not exists (select 1 from ingredient_lines il join recipes rc on rc.id = il.recipe_id where rc.title = 'CHOPPED CHICKEN WRAP' and il.food_id = 'iceberg_lettuce' and il.unit = 'large leaf')
    then raise exception 'T4 FAIL: wrap lettuce'; end if;

  -- T5 g3d fills: no effect on verification
  r := ausnut_apply_batch('g3d', false);
  if not (select aisle = 'Pantry' from foods where food_id = 'fish_sauce') then raise exception 'T5 FAIL: aisle'; end if;
  if not (select protein_family = 'chicken' and verified from foods where food_id = 'chicken_breast') then raise exception 'T5 FAIL: protein family / kept verified'; end if;

  -- T6 g4a created foods
  r := ausnut_apply_batch('g4a', false);
  if not (select ai_verified and not verified and source = 'custom' and protein_family is null and default_size = 'regular' and ausnut_key = 'F008811'
            from foods where food_id = 'squash_button') then raise exception 'T6 FAIL: squash'; end if;
  if exists (select 1 from food_tags ft join tags t on t.id = ft.tag_id where ft.food_id = 'squash_button' and t.label = 'Shellfish') then raise exception 'T6 FAIL: squash shellfish'; end if;
  if not exists (select 1 from unit_conversions where food_id = 'squash_button' and unit = 'each' and grams = 57) then raise exception 'T6 FAIL: default size each'; end if;
  if not (select purchase_unit = 'punnet' and ai_verified from foods where food_id = 'blackberries') then raise exception 'T6 FAIL: buy-as'; end if;
  if not exists (select 1 from foods where food_id = 'gelatine_powder' and ai_verified) then raise exception 'T6 FAIL: gelatine'; end if;

  -- T7 g4b merges and deletes
  r := ausnut_apply_batch('g4b', false);
  if exists (select 1 from foods where food_id in ('tin_tuna_in_spring_water', 'soy', 'aaa')) then raise exception 'T7 FAIL: not deleted'; end if;
  if not exists (select 1 from unit_conversions where food_id = 'tuna_springwater' and unit = 'x85g') then raise exception 'T7 FAIL: x85g copied'; end if;
  if not exists (select 1 from ingredient_lines il join recipes rc on rc.id = il.recipe_id where rc.title = 'SPAGHETTI BOLOGNESE' and il.food_id = 'soy_sauce' and il.unit = 'tsp')
    then raise exception 'T7 FAIL: soy line moved'; end if;

  -- T7b combined ingredients split into separate lines, in place
  if exists (select 1 from ingredient_lines where food_id = 'salt_and_pepper') or exists (select 1 from foods where food_id = 'salt_and_pepper')
    then raise exception 'T7b FAIL: salt & pepper still there'; end if;
  if not exists (select 1 from ingredient_lines s join ingredient_lines p on p.recipe_id = s.recipe_id and p.position = s.position + 1
                  join recipes rc on rc.id = s.recipe_id
                 where rc.title = 'EGGS ON TOAST' and s.food_id = 'salt' and s.quantity = 0.5 and s.unit = 'tsp'
                   and p.food_id = 'pepper' and p.quantity = 0.5 and p.unit = 'tsp') then raise exception 'T7b FAIL: eggs on toast split'; end if;
  if (select count(*) from ingredient_lines il join recipes rc on rc.id = il.recipe_id where rc.title = 'BAKED VEGETABLE FRITTATA' and il.food_id in ('salt', 'pepper')) <> 2
    then raise exception 'T7b FAIL: frittata duplicate not removed'; end if;
  if not exists (select 1 from ingredient_lines il join recipes rc on rc.id = il.recipe_id where rc.title = 'BEEF AND VEGETABLE ENCHILADAS' and il.food_id = 'cumin_powder' and il.quantity = 1 and il.unit = 'tbsp')
     or not exists (select 1 from ingredient_lines il join recipes rc on rc.id = il.recipe_id where rc.title = 'BEEF AND VEGETABLE ENCHILADAS' and il.food_id = 'paprika' and il.quantity = 1)
     or exists (select 1 from ingredient_lines where food_id = 'each_paprika_and_cumin')
     or not exists (select 1 from foods where food_id = 'each_paprika_and_cumin') then raise exception 'T7b FAIL: paprika & cumin split'; end if;
  if exists (select 1 from ingredient_lines il join recipes rc on rc.id = il.recipe_id where rc.title = 'MEXICAN PICADILLO CON PAPAS'
             group by il.position having count(*) > 1) then raise exception 'T7b FAIL: positions collide after two splits'; end if;
  if not exists (select 1 from ingredient_lines il join recipes rc on rc.id = il.recipe_id where rc.title = 'MEXICAN PICADILLO CON PAPAS' and il.food_id = 'garlic_powder' and il.quantity = 0.5)
    then raise exception 'T7b FAIL: picadillo garlic powder'; end if;

  -- T8 g4c recipes
  r := ausnut_apply_batch('g4c', false);
  if exists (select 1 from ingredient_lines il join recipes rc on rc.id = il.recipe_id where rc.title = 'WAFFLES' and il.food_id = 'waffle') then raise exception 'T8 FAIL: yield line'; end if;
  if (select count(*) from ingredient_lines where food_id = 'pancake') <> 0 then raise exception 'T8 FAIL: pancake yield lines'; end if;
  if not (select data_issue like '%FLOUR%' from recipes where title = 'WAFFLES') then raise exception 'T8 FAIL: waffle note'; end if;
  if not exists (select 1 from ingredient_lines il join recipes rc on rc.id = il.recipe_id where rc.title = 'HIGH PROTEIN NO BAKE CHEESECAKE' and il.food_id = 'gelatine_powder')
    then raise exception 'T8 FAIL: gelatine restored'; end if;
  if not exists (select 1 from ingredient_lines il join recipes rc on rc.id = il.recipe_id where rc.title = 'SAVOURY EGG MUFFINS' and il.food_id = 'olive_oil_spray')
     or exists (select 1 from ingredient_lines il join recipes rc on rc.id = il.recipe_id where rc.title = 'SAVOURY EGG MUFFINS' and il.prep_note ilike '%greasing muffin tin%' and il.food_id = 'tasty_cheese')
    then raise exception 'T8 FAIL: egg muffins'; end if;

  -- T9 everything ran, nothing left pending; the readiness views still work
  if exists (select 1 from ausnut_changeset where status = 'pending') then raise exception 'T9 FAIL: pending rows left'; end if;
  perform count(*) from recipe_verification; perform count(*) from recipe_readiness; perform count(*) from line_grams;
  select string_agg(format('%s#%s %s %s: %s', batch, seq, op, food_id, result), E'\n' order by batch, seq) into skipped
    from ausnut_changeset where status = 'skipped';
  select count(*) into n from ausnut_changeset;
  raise exception 'ALL PASS (rolled back): % ops; skipped:%', n, E'\n' || coalesce(skipped, 'none');
end $t$;
