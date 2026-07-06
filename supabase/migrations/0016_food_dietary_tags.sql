-- Dietary/allergen tags on FOODS, derived onto RECIPES, with per-recipe
-- overrides. Extends the existing tags table (id/label/category) with a `kind`
-- rather than creating a rival registry; the five dietary starters reuse the
-- existing diet-category rows so their ids (and any UI chips) are unchanged.
--
-- Combine rules (recipe_effective_tags view):
--   allergen (contains-type) : recipe has it if ANY ingredient food has it.
--   dietary  (suitable-type) : recipe has it only if EVERY ingredient food
--                              explicitly has it — an untagged food is NEVER
--                              treated as suitable, and a recipe with no
--                              ingredients derives no dietary tags.
-- Effective = (derived EXCEPT 'remove' overrides) UNION 'add' overrides.
-- A live view recomputes on every read, so ingredient/food-tag changes are
-- reflected immediately with no cache to refresh. Idempotent throughout.

do $$ begin
  create type tag_kind as enum ('allergen','dietary');
exception when duplicate_object then null; end $$;

do $$ begin
  create type override_action as enum ('add','remove');
exception when duplicate_object then null; end $$;

alter table tags add column if not exists kind tag_kind;
comment on column tags.kind is 'allergen = contains-type (union onto recipes); dietary = suitable-type (all ingredients must carry it); null = plain classification tag';

-- Starter dietary tags: reuse the existing diet-category rows.
update tags set kind = 'dietary'
 where category = 'diet'
   and label in ('Vegan','Vegetarian','Gluten-free','Dairy-free','Nut-free');

-- Starter allergen tags (the substance the food contains).
insert into tags (label, category, kind) values
  ('Gluten','allergen','allergen'),
  ('Dairy','allergen','allergen'),
  ('Egg','allergen','allergen'),
  ('Tree nuts','allergen','allergen'),
  ('Peanuts','allergen','allergen'),
  ('Soy','allergen','allergen'),
  ('Sesame','allergen','allergen'),
  ('Fish','allergen','allergen'),
  ('Shellfish','allergen','allergen')
on conflict (category, label) do update set kind = excluded.kind;

-- Food-level tag assignments (dietitian-entered in Lovable).
create table if not exists food_tags (
  food_id text not null references foods (food_id) on delete cascade,
  tag_id  uuid not null references tags (id) on delete cascade,
  primary key (food_id, tag_id)
);
create index if not exists food_tags_tag_id_idx on food_tags (tag_id);

-- Per-recipe overrides of the derived set. Never touches foods or other recipes.
create table if not exists recipe_tag_overrides (
  recipe_id uuid not null references recipes (id) on delete cascade,
  tag_id    uuid not null references tags (id) on delete cascade,
  action    override_action not null,
  primary key (recipe_id, tag_id)
);

alter table food_tags enable row level security;
drop policy if exists "authenticated full access" on food_tags;
create policy "authenticated full access" on food_tags
  for all to authenticated using (true) with check (true);

alter table recipe_tag_overrides enable row level security;
drop policy if exists "authenticated full access" on recipe_tag_overrides;
create policy "authenticated full access" on recipe_tag_overrides
  for all to authenticated using (true) with check (true);

-- Effective tags per recipe. security_invoker so the callers' RLS applies.
create or replace view recipe_effective_tags
  with (security_invoker = on) as
with ing as (
  select distinct recipe_id, food_id from ingredient_lines
),
derived as (
  -- allergen: union — any ingredient carries it
  select distinct i.recipe_id, ft.tag_id
    from ing i
    join food_tags ft on ft.food_id = i.food_id
    join tags t on t.id = ft.tag_id and t.kind = 'allergen'
  union
  -- dietary: every ingredient must explicitly carry it; never vacuous
  select c.recipe_id, t.id
    from (select recipe_id, count(*) as n from ing group by recipe_id) c
    cross join tags t
   where t.kind = 'dietary'
     and c.n > 0
     and not exists (
       select 1 from ing x
        where x.recipe_id = c.recipe_id
          and not exists (
            select 1 from food_tags ft
             where ft.food_id = x.food_id and ft.tag_id = t.id
          )
     )
)
select e.recipe_id,
       e.tag_id,
       t.label as name,
       t.kind,
       (o.tag_id is not null) as from_override
  from (
    (select recipe_id, tag_id from derived
     except
     select recipe_id, tag_id from recipe_tag_overrides where action = 'remove')
    union
    select recipe_id, tag_id from recipe_tag_overrides where action = 'add'
  ) e
  join tags t on t.id = e.tag_id
  left join recipe_tag_overrides o
    on o.recipe_id = e.recipe_id and o.tag_id = e.tag_id and o.action = 'add';

comment on view recipe_effective_tags is 'Derived recipe tags (allergen=union, dietary=all-must-qualify) with per-recipe add/remove overrides applied. Live — always current.';
