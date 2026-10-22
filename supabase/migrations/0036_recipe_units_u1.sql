-- 0036_recipe_units_u1.sql — recipe units clean-up (U1). Owner go 2026-10-15:
--   "remove kg" · "yes need review" (estimated weights) · "yes add it" (Buy as).
--
-- 1. kg retired from recipes. The 5 existing "1 kg" lines become "1000 g" (exact —
--    no number changes; none of those recipes has saved versions or plan items).
--    The engine still understands kg; the app simply stops offering it.
-- 2. Estimated measures. 86 conversions were imported as `basis = 'default-estimate'`
--    (61 of them a placeholder "each = 100 g": ¼ watermelon counted as 25 g).
--    `unit_conversions.estimated` marks them; a recipe line weighed through one now
--    gives the recipe a Needs review reason ("uses an estimated weight"). Grams and
--    macros are unchanged — only the badge changes.
--      * a person typing a new weight replaces the estimate (estimated → false);
--      * "Confirm" in the app sets estimated = false without changing grams;
--      * the default-size "each" row copies its size row's estimated flag;
--      * confirm / re-estimate is logged in the change log.
--    Machines never set estimated = false except the default-size mirror.
-- 3. Unit names are stored trimmed, lower-case, single-spaced, and can't be the
--    engine's built-in weight units (g, gram, grams, kg). 10 untidy names renamed
--    (none used by any recipe line).
-- 4. foods.purchase_unit ("Buy as"): which of the food's measures the shopping
--    list counts in ("Iceberg lettuce · 285 g · buy 1 medium head"). Must be one of
--    the food's conversions; follows a rename; cleared if the measure is deleted.
--    Display only — never used for nutrition. Backfilled for 37 obvious foods
--    (whole produce with a default size, herb bunches, punnets, cans, pouches,
--    packets) — logged in the change log for review.
-- 5. line_grams / line_priceability gain `via_estimate` (appended; grams logic
--    unchanged, so engine parity holds); recipe_verification gains the new reason
--    plus estimated_line_count / estimated_ingredients (appended).
-- Idempotent. Engine untouched.

-- 1. kg → g --------------------------------------------------------------------
update ingredient_lines set quantity = quantity * 1000, unit = 'g' where unit = 'kg';

-- 2. Estimated measures ----------------------------------------------------------
alter table unit_conversions add column if not exists estimated boolean not null default false;
comment on column unit_conversions.estimated is
  'true = weight was never measured/confirmed (import placeholder). Lines weighed through it put the recipe in Needs review. Cleared by a person editing the grams or pressing Confirm.';

-- Backfill before the log trigger learns about this column (no inbox noise for the flag itself).
update unit_conversions set estimated = true where basis = 'default-estimate' and not estimated;
update unit_conversions e set estimated = true
  from foods f join unit_conversions s on s.food_id = f.food_id and s.unit = f.default_size
 where e.food_id = f.food_id and e.unit = 'each' and s.estimated and not e.estimated;

-- A person typing a new weight replaces the estimate. The default-size mirror
-- (below) sets goh.uc_sync so copying an estimated size keeps the flag.
create or replace function unit_conversions_confirm_on_edit() returns trigger
language plpgsql set search_path = public as $$
begin
  if old.estimated and new.estimated and new.grams is distinct from old.grams
     and coalesce(current_setting('goh.uc_sync', true), '') <> 'on' then
    new.estimated := false;
  end if;
  return new;
end $$;

drop trigger if exists unit_conversions_confirm_on_edit on unit_conversions;
create trigger unit_conversions_confirm_on_edit before update on unit_conversions
  for each row execute function unit_conversions_confirm_on_edit();

-- 0025's default-size mirror, now also copying `estimated`.
create or replace function foods_default_size_sync() returns trigger
language plpgsql set search_path = public as $$
begin
  if new.default_size is not null
     and new.default_size is distinct from old.default_size then
    perform set_config('goh.uc_sync', 'on', true);
    insert into unit_conversions (food_id, unit, grams, basis, estimated)
    select new.food_id, 'each', uc.grams, 'default size: ' || new.default_size, uc.estimated
    from unit_conversions uc
    where uc.food_id = new.food_id and uc.unit = new.default_size
    on conflict (food_id, unit) do update
      set grams = excluded.grams, basis = excluded.basis, estimated = excluded.estimated;
    perform set_config('goh.uc_sync', '', true);
  end if;
  return null;
end $$;

create or replace function unit_conversions_default_size_sync() returns trigger
language plpgsql set search_path = public as $$
declare
  v_default text;
  v_default_grams numeric;
begin
  if tg_op = 'DELETE' then
    select default_size into v_default from foods where food_id = old.food_id;
    if v_default is not null and old.unit in (v_default, 'each') then
      update foods set default_size = null where food_id = old.food_id;
    end if;
    return null;
  end if;

  select default_size into v_default from foods where food_id = new.food_id;
  if v_default is null then return null; end if;

  -- default size row renamed away → default no longer valid
  if tg_op = 'UPDATE' and old.unit = v_default and new.unit <> v_default then
    update foods set default_size = null where food_id = new.food_id;
    return null;
  end if;

  if new.unit = v_default then
    -- size grams (or its estimated flag) changed → each follows
    perform set_config('goh.uc_sync', 'on', true);
    update unit_conversions set grams = new.grams, estimated = new.estimated
     where food_id = new.food_id and unit = 'each'
       and (grams, estimated) is distinct from (new.grams, new.estimated);
    perform set_config('goh.uc_sync', '', true);
  elsif new.unit = 'each' then
    -- each hand-edited away from the default size → it becomes a manual value
    select grams into v_default_grams from unit_conversions
     where food_id = new.food_id and unit = v_default;
    if new.grams is distinct from v_default_grams then
      update foods set default_size = null where food_id = new.food_id;
    end if;
  end if;
  return null;
end $$;

-- 0032's conversion log, now also recording confirm / estimate changes.
create or replace function unit_conversions_change_log() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_food text; v_name text; s text;
begin
  v_food := coalesce(new.food_id, old.food_id);
  select display_name into v_name from foods where food_id = v_food;
  if v_name is null then return null; end if;            -- food itself being deleted: logged once there
  if tg_op = 'INSERT' then
    s := format('%s: added "%s" = %s g', v_name, new.unit, new.grams);
  elsif tg_op = 'DELETE' then
    s := format('%s: removed "%s" (%s g)', v_name, old.unit, old.grams);
  else
    if new.unit = old.unit and new.grams = old.grams then
      if new.estimated = old.estimated then return null; end if;
      s := format('%s: "%s" = %s g %s', v_name, new.unit, new.grams,
                  case when new.estimated then 'marked as an estimate' else 'confirmed (no longer an estimate)' end);
    else
      s := format('%s: "%s" %s g → "%s" %s g', v_name, old.unit, old.grams, new.unit, new.grams)
           || case when old.estimated and not new.estimated then ' (estimate replaced)' else '' end;
    end if;
  end if;
  insert into change_log (entity, food_id, food_name, action, changes, summary, changed_by)
  values ('unit_conversion', v_food, v_name, lower(tg_op),
          jsonb_build_object('old', case when tg_op <> 'INSERT' then to_jsonb(old) end,
                             'new', case when tg_op <> 'DELETE' then to_jsonb(new) end),
          s, auth.uid());
  return null;
end $$;

-- 3. Unit names ----------------------------------------------------------------------
update unit_conversions set unit = 'large'           where unit = 'Large';
update unit_conversions set unit = 'quarter cabbage' where unit = 'Quarter Cabbage';
update unit_conversions set unit = 'half cabbage'    where unit = 'Half cabbage';
update unit_conversions set unit = 'cup (diced)'     where unit = 'cup, diced';
update unit_conversions set unit = 'tbsp (chopped)'  where unit = 'tbsp, chopped';
update unit_conversions set unit = 'tsp (chopped)'   where unit = 'tsp, chopped';
update unit_conversions set unit = 'tbsp (grated)'   where unit = 'tbsp, grated/shredded';
update unit_conversions set unit = 'tsp (grated)'    where unit = 'tsp, grated/shredded';
update unit_conversions set unit = 'cup'             where unit = '1 cup';
update unit_conversions set unit = 'small piece'     where unit = 'piece (small)';

create or replace function unit_conversions_normalise_unit() returns trigger
language plpgsql set search_path = public as $$
begin
  new.unit := lower(regexp_replace(btrim(new.unit), '\s+', ' ', 'g'));
  return new;
end $$;

drop trigger if exists unit_conversions_normalise_unit on unit_conversions;
create trigger unit_conversions_normalise_unit before insert or update of unit on unit_conversions
  for each row execute function unit_conversions_normalise_unit();

alter table unit_conversions drop constraint if exists unit_conversions_unit_name;
alter table unit_conversions add constraint unit_conversions_unit_name check (
  unit <> ''
  and unit = lower(regexp_replace(btrim(unit), '\s+', ' ', 'g'))
  and unit not in ('g', 'gram', 'grams', 'kg'));

-- 4. Buy as -----------------------------------------------------------------------------
alter table foods add column if not exists purchase_unit text;
comment on column foods.purchase_unit is
  '"Buy as": the conversion unit the shopping list counts this food in (e.g. medium head, can, bunch). Display only; null = grams only.';

create or replace function foods_purchase_unit_validate() returns trigger
language plpgsql set search_path = public as $$
begin
  if new.purchase_unit is not null and not exists (
       select 1 from unit_conversions where food_id = new.food_id and unit = new.purchase_unit) then
    raise exception 'Buy as "%" is not one of the measures on food %', new.purchase_unit, new.food_id;
  end if;
  return new;
end $$;

drop trigger if exists foods_purchase_unit_validate on foods;
create trigger foods_purchase_unit_validate before insert or update of purchase_unit on foods
  for each row execute function foods_purchase_unit_validate();

create or replace function unit_conversions_purchase_unit_sync() returns trigger
language plpgsql set search_path = public as $$
begin
  if tg_op = 'DELETE' then
    update foods set purchase_unit = null where food_id = old.food_id and purchase_unit = old.unit;
  elsif new.unit <> old.unit then
    update foods set purchase_unit = new.unit where food_id = new.food_id and purchase_unit = old.unit;
  end if;
  return null;
end $$;

drop trigger if exists unit_conversions_purchase_unit_sync on unit_conversions;
create trigger unit_conversions_purchase_unit_sync after update of unit or delete on unit_conversions
  for each row execute function unit_conversions_purchase_unit_sync();

create or replace function food_field_label(k text) returns text
language sql immutable set search_path = public as $$
  select case k
    when 'energy_kcal_100g' then 'kcal/100 g'   when 'protein_100g' then 'protein/100 g'
    when 'fat_100g' then 'fat/100 g'            when 'carb_avail_100g' then 'carbs/100 g'
    when 'fibre_100g' then 'fibre/100 g'        when 'density_g_ml' then 'density (g/mL)'
    when 'display_name' then 'name'             when 'default_size' then 'default size'
    when 'protein_family' then 'protein family' when 'afcd_key' then 'AFCD key'
    when 'match_note' then 'match note'         when 'purchase_unit' then 'buy as'
    else replace(replace(k, '_100g', '/100 g'), '_', ' ') end
$$;

-- Backfill (explicit list; only where the food has that measure and no Buy as yet).
update foods f set purchase_unit = v.unit
  from (values
    ('egg', 'each'), ('avocado', 'each'), ('banana', 'each'), ('onion_brown', 'each'),
    ('capsicum', 'each'), ('carrot', 'each'), ('cucumber', 'each'), ('eggplant', 'each'),
    ('green_capsicum', 'each'), ('leek', 'each'), ('pear', 'each'), ('zucchini', 'each'),
    ('basil', 'bunch'), ('coriander_fresh', 'bunch'), ('mint', 'bunch'), ('parsley', 'bunch'),
    ('thai_basil', 'bunch'), ('radish', 'bunch'),
    ('cherry_tomato', 'punnet'), ('raspberry', 'punnet'), ('strawberry', 'punnet'),
    ('sardine_in', 'can'), ('lentil_brown', 'can'), ('g_can_chickpea', 'can'),
    ('can_corn_kernel', 'can'), ('crushed_tomato_canned', 'can'), ('diced_tomato_canned', 'can'),
    ('four_bean_mix', 'can'), ('can_kidney_bean', 'can'), ('lentils_kidney_bean', 'can'),
    ('canned_pineapple_piece', 'can'), ('adzuki_bean', 'can'),
    ('brown_rice_and_quinoa_microwave_packet', 'pouch'),
    ('gluten_free_puff_pastry', 'packet'), ('taco_seasoning_mix', 'packet'),
    ('vetta_smart_fibre_pasta', 'packet'), ('wok_ready_noodle', 'packet')
  ) as v(food_id, unit)
 where f.food_id = v.food_id and f.purchase_unit is null
   and exists (select 1 from unit_conversions u where u.food_id = v.food_id and u.unit = v.unit);

-- 5. Read-models ---------------------------------------------------------------------------
create or replace view line_grams with (security_invoker = on) as
select il.id, il.recipe_id, il.food_id, il.quantity, il.unit,
  case
    when il.unit in ('g', 'gram', 'grams') then il.quantity
    when il.unit = 'kg' then il.quantity * 1000
    when il.unit = 'x95g' then il.quantity * 95
    when il.unit in ('tsp', 'tbsp', 'cup', 'ml') then
      case when f.density_g_ml is not null and f.density_g_ml <> 0
           then il.quantity * (case il.unit when 'tsp' then 5 when 'tbsp' then 20 when 'cup' then 250 else 1 end) * f.density_g_ml
           else il.quantity * uc.grams end
    else il.quantity * uc.grams
  end as grams,
  case
    when il.unit in ('g', 'gram', 'grams', 'kg', 'x95g') then false
    when il.unit in ('tsp', 'tbsp', 'cup', 'ml') and f.density_g_ml is not null and f.density_g_ml <> 0 then false
    else coalesce(uc.estimated, false)
  end as via_estimate
from ingredient_lines il
left join foods f on f.food_id = il.food_id
left join unit_conversions uc on uc.food_id = il.food_id and uc.unit = il.unit;

create or replace view line_priceability with (security_invoker = on) as
select id, recipe_id, food_id, unit, grams is not null as priced, via_estimate
from line_grams lg;

create or replace view recipe_verification with (security_invoker = on) as
with line_facts as (
  select lp.recipe_id, lp.food_id, coalesce(lp.unit, 'no unit') as unit, lp.priced, lp.via_estimate, il.position,
         coalesce(f.display_name, lp.food_id, 'unlinked ingredient') as food_name,
         coalesce(f.verified, false) as food_verified
  from line_priceability lp
  join ingredient_lines il on il.id = lp.id
  left join foods f on f.food_id = lp.food_id
),
line_counts as (
  select recipe_id, count(*) as line_count,
         count(*) filter (where not priced) as uncalculable_line_count,
         count(*) filter (where priced and via_estimate) as estimated_line_count
  from line_facts group by recipe_id
),
unverified as (
  select recipe_id, array_agg(food_name order by first_pos, food_name) as names
  from (select recipe_id, food_id, food_name, min(position) as first_pos
        from line_facts where not food_verified
        group by recipe_id, food_id, food_name) x
  group by recipe_id
),
uncalculable as (
  select recipe_id, array_agg(label order by first_pos, label) as labels
  from (select recipe_id, food_name || ' (' || unit || ')' as label, min(position) as first_pos
        from line_facts where not priced
        group by recipe_id, food_name || ' (' || unit || ')') x
  group by recipe_id
),
estimated as (
  select recipe_id, array_agg(label order by first_pos, label) as labels
  from (select recipe_id, food_name || ' (' || unit || ')' as label, min(position) as first_pos
        from line_facts where priced and via_estimate
        group by recipe_id, food_name || ' (' || unit || ')') x
  group by recipe_id
),
steps as (
  select recipe_id, count(*) filter (where btrim(text) <> '') as step_count
  from method_steps group by recipe_id
),
base as (
  select r.id as recipe_id, r.title,
         not (coalesce(btrim(r.title), '') = '' or btrim(r.title) ilike 'untitled recipe') as has_title,
         (coalesce(btrim(r.image_url_1), '') <> '' or coalesce(btrim(r.image_url_2), '') <> '') as has_image,
         coalesce(lc.line_count, 0)::int as line_count,
         coalesce(st.step_count, 0)::int as step_count,
         coalesce(uv.names, '{}') as unverified_food_names,
         coalesce(lc.uncalculable_line_count, 0)::int as uncalculable_line_count,
         coalesce(uc.labels, '{}') as uncalculable_ingredients,
         coalesce(lc.estimated_line_count, 0)::int as estimated_line_count,
         coalesce(es.labels, '{}') as estimated_ingredients,
         nullif(btrim(r.data_issue), '') as data_issue,
         so.signed_by_name, so.signed_at
  from recipes r
  left join line_counts lc on lc.recipe_id = r.id
  left join unverified uv on uv.recipe_id = r.id
  left join uncalculable uc on uc.recipe_id = r.id
  left join estimated es on es.recipe_id = r.id
  left join steps st on st.recipe_id = r.id
  left join recipe_signoffs so on so.recipe_id = r.id and so.revoked_at is null
),
judged as (
  select b.*,
    array_remove(array[
      case when not b.has_title then 'no title' end,
      case when not b.has_image then 'no image' end,
      case when b.line_count = 0 then 'no ingredients' end,
      case when b.step_count = 0 then 'no method steps' end,
      case when cardinality(b.unverified_food_names) > 0 then
        format('%s unverified food%s: %s', cardinality(b.unverified_food_names),
               case when cardinality(b.unverified_food_names) = 1 then '' else 's' end,
               reason_list(b.unverified_food_names)) end,
      case when cardinality(b.uncalculable_ingredients) > 0 then
        format('%s ingredient%s can''t be calculated: %s', cardinality(b.uncalculable_ingredients),
               case when cardinality(b.uncalculable_ingredients) = 1 then '' else 's' end,
               reason_list(b.uncalculable_ingredients)) end,
      case when cardinality(b.estimated_ingredients) > 0 then
        format('%s ingredient%s an estimated weight: %s', cardinality(b.estimated_ingredients),
               case when cardinality(b.estimated_ingredients) = 1 then ' uses' else 's use' end,
               reason_list(b.estimated_ingredients)) end,
      case when b.data_issue is not null then
        'data issue flagged: ' || case when length(b.data_issue) > 80
                                       then left(b.data_issue, 80) || '…' else b.data_issue end end
    ], null) as reasons
  from base b
)
select recipe_id, title,
       case when cardinality(reasons) = 0 and signed_at is not null then 'dietitian_verified'
            when cardinality(reasons) = 0 then 'ai_verified'
            else 'needs_review' end as status,
       cardinality(reasons) = 0 as ai_verified,
       reasons,
       signed_at is not null and cardinality(reasons) > 0 as signoff_on_hold,
       signed_by_name, signed_at,
       has_title, has_image, line_count, step_count,
       cardinality(unverified_food_names)::int as unverified_food_count, unverified_food_names,
       uncalculable_line_count, uncalculable_ingredients,
       data_issue,
       estimated_line_count, estimated_ingredients
from judged;

revoke all on recipe_verification from anon;
grant select on recipe_verification to authenticated;
