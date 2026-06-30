-- Clients: the people a dietitian builds plans for. Targets live here (per
-- client, reused across plans) and drive the per-day / weekly balance bars.
-- Restrictions are diet-tag labels the planner can warn against.

create table if not exists clients (
  id               uuid primary key default gen_random_uuid(),
  full_name        text not null,
  email            text,
  phone            text,
  kcal_target      numeric,
  protein_target_g numeric,
  carb_target_g    numeric,
  fat_target_g     numeric,
  fibre_target_g   numeric,
  restrictions     text[] not null default '{}',  -- e.g. {'Vegetarian','Gluten-free'}
  notes            text,
  created_at       timestamptz not null default now()
);

-- A plan is built for a client (keep the plan if the client is removed).
alter table meal_plans
  add column if not exists client_id uuid references clients (id) on delete set null;

alter table clients enable row level security;
drop policy if exists "authenticated full access" on clients;
create policy "authenticated full access" on clients
  for all to authenticated using (true) with check (true);
