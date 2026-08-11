-- Recipe profiles: named variations stored as DELTAS from the base recipe.
-- Macros are never stored — always derived by applying deltas then the engine.
-- Deltas deliberately do NOT FK ingredient_lines: saveRecipe rewrites all lines
-- (delete+reinsert) on every save, which would cascade-wipe deltas. line_ref is
-- a plain uuid; the base_* snapshot re-matches lines and flags orphaned deltas.
-- verified_fingerprint = hash of canonical base lines at sign-off; a mismatch at
-- read time means the base changed → profile shows as needing re-review.
create table if not exists recipe_profiles (
  id                   uuid primary key default gen_random_uuid(),
  recipe_id            uuid not null references recipes (id) on delete cascade,
  name                 text not null,
  position             integer not null default 0,
  verified             boolean not null default false,
  verified_fingerprint text,
  created_at           timestamptz not null default now()
);
create index if not exists recipe_profiles_recipe_idx on recipe_profiles (recipe_id);

create table if not exists recipe_profile_deltas (
  id            uuid primary key default gen_random_uuid(),
  profile_id    uuid not null references recipe_profiles (id) on delete cascade,
  line_ref      uuid,                    -- ingredient_lines.id at save time (no FK, see above)
  base_food_id  text,
  base_quantity numeric,
  base_unit     text,
  base_section  text,
  kind          text not null check (kind in ('quantity','swap','remove','add')),
  new_food_id   text,
  new_quantity  numeric,
  new_unit      text,
  position      integer not null default 0
);
create index if not exists recipe_profile_deltas_profile_idx on recipe_profile_deltas (profile_id);

alter table recipe_profiles enable row level security;
drop policy if exists "authenticated full access" on recipe_profiles;
create policy "authenticated full access" on recipe_profiles
  for all to authenticated using (true) with check (true);
alter table recipe_profile_deltas enable row level security;
drop policy if exists "authenticated full access" on recipe_profile_deltas;
create policy "authenticated full access" on recipe_profile_deltas
  for all to authenticated using (true) with check (true);

-- Meal plans will later reference recipe + profile.
alter table meal_plan_items add column if not exists profile_id uuid
  references recipe_profiles (id) on delete set null;
