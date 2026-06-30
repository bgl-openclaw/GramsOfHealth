-- Basic security: enable Row Level Security on every table and restrict access
-- to authenticated users.
--
--   * anon / publishable key  -> denied (closes the public PostgREST exposure)
--   * service_role            -> bypasses RLS (import scripts keep working)
--   * authenticated users     -> full read/write
--
-- This is an interim internal-tool posture. Phase 5 (Auth) should replace the
-- blanket "authenticated full access" policies with team-scoped rules for
-- Nikki's team.

alter table afcd_master      enable row level security;
alter table foods            enable row level security;
alter table unit_conversions enable row level security;
alter table recipes          enable row level security;
alter table ingredient_lines enable row level security;
alter table method_steps     enable row level security;

create policy "authenticated full access" on afcd_master
  for all to authenticated using (true) with check (true);

create policy "authenticated full access" on foods
  for all to authenticated using (true) with check (true);

create policy "authenticated full access" on unit_conversions
  for all to authenticated using (true) with check (true);

create policy "authenticated full access" on recipes
  for all to authenticated using (true) with check (true);

create policy "authenticated full access" on ingredient_lines
  for all to authenticated using (true) with check (true);

create policy "authenticated full access" on method_steps
  for all to authenticated using (true) with check (true);
