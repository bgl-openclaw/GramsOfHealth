-- Grams of Health — initial schema (Phase 0).
--
-- Every column is snake_case. Every macro the app shows is computed from grams
-- by the engine; nothing here stores a final, manually-overridden macro number.
-- "Carbs" = available carbohydrate (excludes fibre); fibre is carried separately.

-- gen_random_uuid()
create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------------
-- afcd_master — the Australian Food Composition Database reference table.
-- Per-100g values (sodium per 100g in mg). Specific gravity is g/mL for
-- liquids, null for solids.
-- ---------------------------------------------------------------------------
create table afcd_master (
  public_food_key  text primary key,
  food_name        text not null,
  classification   text,
  specific_gravity numeric,
  energy_kcal      numeric,
  protein          numeric,
  fat              numeric,
  satfat           numeric,
  carb_avail       numeric,
  sugars           numeric,
  fibre            numeric,
  sodium_mg        numeric
);

comment on table afcd_master is 'AFCD Release 3 reference foods (per 100 g). carb_avail excludes fibre.';

-- ---------------------------------------------------------------------------
-- foods — the working ingredient library the engine runs on.
-- ---------------------------------------------------------------------------
create type food_source as enum ('afcd', 'custom');

create table foods (
  food_id          text primary key,
  display_name     text not null,
  -- Logical reference to afcd_master.public_food_key; not an enforced FK so
  -- custom foods (null key) and provisional keys can be imported freely.
  afcd_key         text,
  source           food_source not null,
  energy_kcal_100g numeric,
  protein_100g     numeric,
  fat_100g         numeric,
  carb_avail_100g  numeric,
  fibre_100g       numeric,
  density_g_ml     numeric,
  verified         boolean not null default false,
  match_note       text
);

comment on column foods.afcd_key is 'Logical reference to afcd_master.public_food_key (not an enforced FK).';
comment on column foods.carb_avail_100g is 'Available carbohydrate per 100 g, excluding fibre.';

-- ---------------------------------------------------------------------------
-- unit_conversions — size-to-grams weights per food (1 clove = 3 g, etc.).
-- Liquids resolve volume via density and need no rows here.
-- ---------------------------------------------------------------------------
create table unit_conversions (
  id      bigint generated always as identity primary key,
  food_id text not null references foods (food_id) on delete cascade,
  unit    text not null,
  grams   numeric not null,
  basis   text,
  unique (food_id, unit)
);

-- ---------------------------------------------------------------------------
-- recipes
-- ---------------------------------------------------------------------------
create table recipes (
  id                 uuid primary key default gen_random_uuid(),
  title              text not null,
  servings           integer not null,
  time_minutes       integer,
  show_macros_export boolean not null default true,
  variant_of         uuid references recipes (id) on delete set null,
  image_url_1        text,
  image_url_2        text
);

-- ---------------------------------------------------------------------------
-- ingredient_lines — the four-field lines (food, quantity, unit, prep),
-- ordered within optional sections (To serve, Marinade, …).
-- ---------------------------------------------------------------------------
create table ingredient_lines (
  id        uuid primary key default gen_random_uuid(),
  recipe_id uuid not null references recipes (id) on delete cascade,
  food_id   text not null references foods (food_id),
  section   text,
  position  integer not null,
  quantity  numeric not null,
  unit      text not null,
  prep_note text
);

create index ingredient_lines_recipe_id_idx on ingredient_lines (recipe_id);

-- ---------------------------------------------------------------------------
-- method_steps — ordered method text per recipe.
-- ---------------------------------------------------------------------------
create table method_steps (
  id        uuid primary key default gen_random_uuid(),
  recipe_id uuid not null references recipes (id) on delete cascade,
  position  integer not null,
  text      text not null
);

create index method_steps_recipe_id_idx on method_steps (recipe_id);
