-- Meal plans (group recipes, export a combined A4 booklet, aggregate a
-- grams-based shopping list) + a recipe-level data_issue field for the
-- quality dashboard / Cowork ingest. Additive; same authenticated RLS pattern.

-- Recipe-level data issue (e.g. "salmon named in method, missing from list").
-- Mirrors the data_issue field already present in recipes_validation.json.
alter table recipes add column if not exists data_issue text;

create table if not exists meal_plans (
  id         uuid primary key default gen_random_uuid(),
  title      text not null,
  notes      text,
  days       integer,
  created_at timestamptz not null default now()
);

create table if not exists meal_plan_items (
  id               uuid primary key default gen_random_uuid(),
  meal_plan_id     uuid not null references meal_plans (id) on delete cascade,
  recipe_id        uuid not null references recipes (id) on delete cascade,
  position         integer not null,
  servings_override integer,
  day              integer,
  meal_slot        text
);

create index if not exists meal_plan_items_plan_id_idx on meal_plan_items (meal_plan_id);

alter table meal_plans      enable row level security;
alter table meal_plan_items enable row level security;

drop policy if exists "authenticated full access" on meal_plans;
create policy "authenticated full access" on meal_plans
  for all to authenticated using (true) with check (true);

drop policy if exists "authenticated full access" on meal_plan_items;
create policy "authenticated full access" on meal_plan_items
  for all to authenticated using (true) with check (true);
