-- 0025_food_default_size.sql
-- A food's DEFAULT SIZE: which of its size conversions ("medium", "large",
-- "medium stalk", …) a recipe line written as "each" means. Chosen by a
-- dietitian; never set by a machine process except owner-approved backfills.
--
-- Mechanism: the engine (and the recipe_verification view) already resolve
-- "each" through unit_conversions, so the default is materialised as the food's
-- "each" row and kept in sync by triggers — engine untouched:
--   * setting foods.default_size upserts each = that size's grams
--   * editing the default size's grams updates each to match (no drift)
--   * deleting/renaming the default size row clears default_size (each stays)
--   * hand-editing each to a different value, or deleting it, clears
--     default_size (each becomes a manual value)
-- Idempotent.

alter table foods add column if not exists default_size text;
comment on column foods.default_size is
  'Size unit that "each" means for this food (e.g. medium). Kept in sync with unit_conversions(food_id, ''each'') by triggers.';

-- 1. Validate + materialise when a food's default changes ---------------------

create or replace function foods_default_size_validate() returns trigger
language plpgsql as $$
begin
  if new.default_size is not null then
    if new.default_size = 'each' then
      raise exception 'default size cannot be "each" itself';
    end if;
    if not exists (select 1 from unit_conversions
                   where food_id = new.food_id and unit = new.default_size) then
      raise exception 'default size "%" is not one of the conversions on food %',
        new.default_size, new.food_id;
    end if;
  end if;
  return new;
end $$;

create or replace function foods_default_size_sync() returns trigger
language plpgsql as $$
begin
  if new.default_size is not null
     and new.default_size is distinct from old.default_size then
    insert into unit_conversions (food_id, unit, grams, basis)
    select new.food_id, 'each', uc.grams, 'default size: ' || new.default_size
    from unit_conversions uc
    where uc.food_id = new.food_id and uc.unit = new.default_size
    on conflict (food_id, unit) do update
      set grams = excluded.grams, basis = excluded.basis;
  end if;
  return null;
end $$;

drop trigger if exists foods_default_size_validate on foods;
create trigger foods_default_size_validate
  before insert or update of default_size on foods
  for each row execute function foods_default_size_validate();

drop trigger if exists foods_default_size_sync on foods;
create trigger foods_default_size_sync
  after update of default_size on foods
  for each row execute function foods_default_size_sync();

-- 2. Keep "each" in step with conversion edits --------------------------------

create or replace function unit_conversions_default_size_sync() returns trigger
language plpgsql as $$
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
    -- size grams changed → each follows
    update unit_conversions set grams = new.grams
     where food_id = new.food_id and unit = 'each' and grams is distinct from new.grams;
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

drop trigger if exists unit_conversions_default_size_sync on unit_conversions;
create trigger unit_conversions_default_size_sync
  after insert or update or delete on unit_conversions
  for each row execute function unit_conversions_default_size_sync();

-- 3. Owner-approved backfill (2026-10-15): eggs default to large ---------------
update foods set default_size = 'large'
 where food_id in ('egg', 'egg_yolk') and default_size is null;
