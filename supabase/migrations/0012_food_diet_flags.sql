-- Food-level dietary flags = what a food CONTAINS / its FODMAP status. This is
-- the source of truth: a recipe's dietary suitability is COMPUTED from the union
-- of its ingredient foods (a recipe is gluten-free only if no ingredient has the
-- 'gluten' flag), and the meal planner excludes recipes that violate a client's
-- restrictions. Editing one food's flags reflects everywhere it's used.
--
-- Controlled flag vocabulary:
--   meat, fish, shellfish, dairy, egg, gluten,
--   tree_nut, peanut, soy, sesame, honey, high_fodmap
-- (meat = land animals incl. poultry + gelatine; fish ≠ meat so Pescatarian works.)
--
-- Diabetes-friendly / Heart-healthy are clinical nutrition profiles, NOT derivable
-- from ingredient presence — those stay dietitian-assigned (see app logic).

create table if not exists food_diet_flags (
  food_id text not null references foods (food_id) on delete cascade,
  flag    text not null,
  primary key (food_id, flag)
);

create index if not exists food_diet_flags_flag_idx on food_diet_flags (flag);

alter table food_diet_flags enable row level security;
drop policy if exists "authenticated full access" on food_diet_flags;
create policy "authenticated full access" on food_diet_flags
  for all to authenticated using (true) with check (true);
