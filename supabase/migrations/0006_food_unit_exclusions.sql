-- Per-food unit exclusions: lets a dietitian hide a unit for a specific food
-- (custom rows AND built-ins tsp/tbsp/cup/mL). g and kg are the base units and
-- are never excludable (enforced in the engine, not here). Empty table = today's
-- behavior.
--
-- RLS mirrors the other data tables (authenticated full access). NOTE: unlike the
-- original spec, anon is NOT granted SELECT — all data tables in this project are
-- authenticated-only (foods are not publicly readable), so this stays consistent.

create table if not exists food_unit_exclusions (
  food_id text not null references foods (food_id) on delete cascade,
  unit    text not null,
  primary key (food_id, unit)
);

alter table food_unit_exclusions enable row level security;

drop policy if exists "authenticated full access" on food_unit_exclusions;
create policy "authenticated full access" on food_unit_exclusions
  for all to authenticated using (true) with check (true);
