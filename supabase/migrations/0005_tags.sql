-- Recipe tags: meal type / course / dietary / cuisine, plus free-form custom.
-- Calorie-band and macro grouping are DERIVED from the engine (no storage) and
-- live in the UI; only assigned tags need persistence. Same authenticated RLS.

create table if not exists tags (
  id       uuid primary key default gen_random_uuid(),
  label    text not null,
  category text not null,           -- 'meal' | 'course' | 'diet' | 'cuisine' | 'custom'
  unique (category, label)
);

create table if not exists recipe_tags (
  recipe_id uuid not null references recipes (id) on delete cascade,
  tag_id    uuid not null references tags (id)    on delete cascade,
  primary key (recipe_id, tag_id)
);

create index if not exists recipe_tags_tag_id_idx on recipe_tags (tag_id);

alter table tags        enable row level security;
alter table recipe_tags enable row level security;

drop policy if exists "authenticated full access" on tags;
create policy "authenticated full access" on tags
  for all to authenticated using (true) with check (true);

drop policy if exists "authenticated full access" on recipe_tags;
create policy "authenticated full access" on recipe_tags
  for all to authenticated using (true) with check (true);
