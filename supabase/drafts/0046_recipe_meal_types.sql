-- 0046_recipe_meal_types.sql — P0 of the plans roadmap (rev 2): meal type per recipe.  DRAFT, NOT APPLIED.
-- Apply only after the dietitian has reviewed seed/meal_types/meal_types_for_review.csv (gate B).
--   1. recipe_meal_types: one row per recipe and meal type (breakfast | lunch | dinner | snack), or a single
--      'not_a_meal' row for sauces, sides and drinks the planner must never place on their own.
--      source machine | dietitian, confidence high | medium | low, reason. Variants follow their base recipe
--      unless they have rows of their own (recipe_meal_types_effective).
--   2. meal_type_rule(title): the title rules. suggest_meal_types(recipe_id): rules + variant inheritance +
--      main-ingredient fallback. The first pass (review CSV) and the save-time suggestion both use these, so
--      they can't drift apart.
-- Owner decisions (21 Oct 2026): the generator uses every row whatever its confidence; the dietitian reviews
-- every recipe before the planner is used. Allergen and dietary screening is unaffected.

-- 1. table ------------------------------------------------------------------------------------------------
create table if not exists recipe_meal_types (
  recipe_id  uuid not null references recipes (id) on delete cascade,
  meal_type  text not null check (meal_type in ('breakfast', 'lunch', 'dinner', 'snack', 'not_a_meal')),
  source     text not null check (source in ('machine', 'dietitian')),
  confidence text not null default 'high' check (confidence in ('high', 'medium', 'low')),
  reason     text check (reason is null or length(reason) <= 300),
  set_by     uuid references profiles (id) on delete set null,
  set_at     timestamptz not null default now(),
  primary key (recipe_id, meal_type)
);
comment on table recipe_meal_types is 'Which plan slots a recipe can fill. not_a_meal = sauce, side or drink (never placed on its own). Variants without rows follow their base recipe.';

-- 2. title rules (first match wins) ---------------------------------------------------------------------
create or replace function meal_type_rule(p_title text)
returns table (meal_types text[], confidence text, reason text, discretionary boolean)
language sql immutable set search_path = public as $$
  with t as (select lower(btrim(coalesce(p_title, ''))) as s),
  rules (pos, pattern, types, conf, why) as (values
    (10,  '^(untitled recipe)?$',                                                   '{}'::text[],                 'low',    'no title'),
    (20,  '(curry paste|chilli oil|chutney|pickled veg|^(?!.*\m(with|w)\M).*\msauce$|\mpesto$)',
                                                                                    '{not_a_meal}',               'high',   'a sauce or condiment'),
    (30,  '(spritz|mocktail)',                                                      '{not_a_meal}',               'high',   'a drink'),
    (40,  '(brussel sprouts|^potato salad$|^leaf salad|smashed cucumber salad|watermelon, mint and feta salad|rocket & prosc|pita bread$)',
                                                                                    '{not_a_meal}',               'medium', 'a side dish'),
    (50,  '(\mdip\M|guacamole|cowboy caviar)',                                      '{snack}',                    'medium', 'a dip'),
    (60,  'breakfast',                                                              '{breakfast}',                'high',   '"breakfast" in the title'),
    (70,  '(iceblock|nice cream|ice-?cream|frozen yoghurt|yo-chi)',                 '{snack}',                    'high',   'a frozen treat'),
    (80,  'smoothie',                                                               '{breakfast,snack}',          'high',   'a smoothie'),
    (90,  '(baked oats|porridge|overnight|weetbix|granola$|bircher|muesli$)',       '{breakfast}',                'high',   'oats, porridge or granola'),
    (100, '(pancakes?\M|waffles|french toast)',                                     '{breakfast}',                'high',   'pancakes, waffles or French toast'),
    (110, 'pikelets',                                                               '{breakfast,snack}',          'medium', 'pikelets'),
    (120, '(scrambled eggs|scramble$|omelette|eggs on toast|turkish eggs|mcmuffin)', '{breakfast}',               'high',   'an egg breakfast'),
    (130, '(chia (seed )?pudding|parfait)',                                         '{breakfast,snack}',          'high',   'chia pudding or parfait'),
    (140, 'meatball',                                                               '{dinner}',                   'high',   'meatballs'),
    (150, 'shakshuka',                                                              '{breakfast,lunch}',          'medium', 'shakshuka (brunch)'),
    (160, '(frittata muffins|egg muffins)',                                         '{breakfast,snack}',          'high',   'egg muffins'),
    (170, 'frittata',                                                               '{breakfast,lunch}',          'medium', 'a frittata'),
    (180, 'bagels?$',                                                               '{breakfast,lunch}',          'medium', 'bagels'),
    (190, '(\mtoasts?$|\mtoast with\M)',                                            '{breakfast,snack}',          'medium', 'something on toast'),
    (200, '(bliss balls?|protein balls|pudding balls|cookies?\M|\mbars$|slice$|mug cake|\mcake$|cheesecake|mousse|pavlovas?|crumble|pudding$|rocky road|\mdates$|rice cakes|dehydrated|mochi|\mcups$|mille f|sandos|dessert)',
                                                                                    '{snack}',                    'high',   'a sweet snack or dessert'),
    (210, 'muffins?$',                                                              '{snack,breakfast}',          'high',   'muffins'),
    (220, 'sausage rolls',                                                          '{snack,lunch}',              'medium', 'sausage rolls'),
    (230, '(skewers|scrolls|pintxos|sushi (bites|balls|rice balls)|bites$)',        '{snack}',                    'high',   'a savoury snack'),
    (240, '(wraps?$|\mwrap\M|sandwich|toastie|sushi rolls|sushi$)',                 '{lunch}',                    'high',   'a wrap, sandwich or sushi'),
    (250, '(tostadas|tartare)',                                                     '{lunch,snack}',              'medium', 'tostadas or tartare'),
    (260, '(chicken|beef|tuna|prawn|tofu|salmon|lamb|steak|haloumi|lentil|egg|turkey|pork|chickpea|bean).*salad|salad.*(chicken|beef|tuna|prawn|tofu|salmon|lamb|steak|haloumi|lentil|egg|turkey|pork|chickpea|bean)',
                                                                                    '{lunch,dinner}',             'high',   'a salad with a main protein'),
    (270, '\mbowls?\M',                                                             '{lunch,dinner}',             'high',   'a bowl'),
    (280, 'salad',                                                                  '{lunch}',                    'medium', 'a salad without a main protein (could be a side)'),
    (290, '(soup|ramen)',                                                           '{lunch,dinner}',             'high',   'a soup or ramen'),
    (300, '(tacos|burgers?\M|burrito|quesadillas?|enchiladas|fajitas|gyros|kofta|pita|pockets|banh mi|bánh mì|sliders|pizzas?\M|nachos)',
                                                                                    '{lunch,dinner}',             'high',   'tacos, burgers, wraps-style or pizza'),
    (310, '(noodles?|pad thai|pad see ew|mi goreng|udon|soba|fried rice|\mrice$|larb)', '{lunch,dinner}',         'high',   'noodles or a rice dish'),
    (315, '\mmini\M',                                                               '{snack}',                    'medium', 'snack-sized ("mini")'),
    (320, '(dumplings|fritters?|fish cakes|okonomiyaki|patties|spanakopita|spannakoptia|orzo$)',
                                                                                    '{lunch,dinner}',             'medium', 'dumplings, fritters or patties'),
    (330, '(curry|tikka|masala|korma|massaman|stir fry|risotto|lasagne|bolognese|ragu|stroganoff|cacciatore|tagine|parmi|schnitzel|fish & chips|\mroast|tray bake|traybake|\mbake$|\mpies?$|rissoles|\mmash\M|cannel+oni|ravioli|manti|mac n|pasta|stuffed capsicums|eggplant boats|parcels|picadillo|qeema|mongolian|sweet and sour|paella|pilaf|one pan|one pot|dump bag|\msteak\M|slaw|(chicken|salmon|lamb|pork|beef|tofu|prawns|fish|barramundi)$)',
                                                                                    '{dinner}',                   'high',   'a cooked main'),
    (340, '(hash cakes)',                                                           '{breakfast,snack}',          'medium', 'hash cakes')
  ),
  disc (pattern) as (values
    ('(cookies?\M|cookie bars|\mcake$|mug cake|cheesecake|mousse|ice-?cream|pavlova|tiramisu cups|rocky road|sticky date|crumble|bliss ball|pudding balls|peanut butter cups|choc (covered|dipped)|chocolate dipped|mochi|dessert|mille f|lcm bars|lemon bars|florentine|spritz|sandos|marscarpone cups|brownie)')
  )
  select r.types, r.conf, r.why,
         exists (select 1 from disc, t where t.s ~* disc.pattern)
  from t
  left join lateral (select * from rules where t.s ~* rules.pattern order by pos limit 1) r on true
$$;

-- 3. suggestion for one recipe: variants follow their base; otherwise rules, then the main ingredient --------
create or replace function suggest_meal_types(p_recipe_id uuid)
returns table (meal_types text[], confidence text, reason text, discretionary boolean)
language plpgsql stable set search_path = public as $$
declare
  v_title text; v_base uuid; v_base_title text; v_main text; v_main_role text;
  r record;
begin
  select rc.title, rc.variant_of into v_title, v_base from recipes rc where rc.id = p_recipe_id;
  if not found then return; end if;
  if v_base is not null then
    select title into v_base_title from recipes where id = v_base;
    select * into r from suggest_meal_types(v_base);
    return query select r.meal_types, r.confidence, 'variant of ' || coalesce(v_base_title, 'another recipe') || ': ' || r.reason, r.discretionary;
    return;
  end if;
  select * into r from meal_type_rule(v_title);
  if r.meal_types is not null then
    return query select r.meal_types, r.confidence, r.reason, r.discretionary;
    return;
  end if;
  select coalesce(f.display_name, lg.food_id), f.role into v_main, v_main_role
    from line_grams lg left join foods f on f.food_id = lg.food_id
   where lg.recipe_id = p_recipe_id and lg.grams is not null
   order by lg.grams desc, lg.food_id limit 1;
  if v_main_role = 'adjustable_protein' then
    return query select '{lunch,dinner}'::text[], 'low'::text, 'main ingredient is a protein (' || v_main || ')', r.discretionary;
  else
    return query select '{}'::text[], 'low'::text, 'no clear meal type from the title or ingredients', r.discretionary;
  end if;
end $$;

-- 4. what the planner reads: own rows, else the base recipe's rows -------------------------------------------
create or replace view recipe_meal_types_effective with (security_invoker = true) as
  select rc.id as recipe_id, m.meal_type, m.source, m.confidence, m.reason, (m.recipe_id <> rc.id) as inherited
  from recipes rc
  join recipe_meal_types m
    on m.recipe_id = case when exists (select 1 from recipe_meal_types o where o.recipe_id = rc.id) then rc.id
                          else coalesce(rc.variant_of, rc.id) end;

-- 5. access: staff read; staff write (dietitians and interns tag recipes, like other library edits) --------
alter table recipe_meal_types enable row level security;
drop policy if exists recipe_meal_types_read on recipe_meal_types;
create policy recipe_meal_types_read on recipe_meal_types for select using (is_staff());
drop policy if exists recipe_meal_types_write on recipe_meal_types;
create policy recipe_meal_types_write on recipe_meal_types for all using (is_staff()) with check (is_staff());
revoke all on recipe_meal_types from anon;
revoke execute on function meal_type_rule(text), suggest_meal_types(uuid) from public, anon;
grant execute on function meal_type_rule(text), suggest_meal_types(uuid) to authenticated;
