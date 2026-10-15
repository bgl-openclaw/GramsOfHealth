-- 0026_staff_roles_access.sql  (Clients roadmap C0 — access control)
--
-- Roles: admin | dietitian | intern | pending.
--   clinician (admin, dietitian): every client, clinical records, targets.
--   intern: only clients a clinician has ticked for them in client_staff_access,
--           and that client's check-ins only if can_view_checkins is ticked.
--           Never clinical records. Cannot set targets.
--   pending (and any future client-app account): no access to client data.
-- Replaces the blanket "authenticated full access" policies on clients,
-- meal_plans and meal_plan_items. Recipes/foods keep their current policies
-- (Phase 5) — tighten those before any client-facing app ships.
-- Idempotent.

-- 1. Roles ---------------------------------------------------------------------
alter table profiles drop constraint if exists profiles_role_check;
alter table profiles add constraint profiles_role_check
  check (role in ('admin', 'dietitian', 'intern', 'pending'));

alter table invitations drop constraint if exists invitations_role_check;
alter table invitations add constraint invitations_role_check
  check (role in ('admin', 'dietitian', 'intern'));

-- 2. Role helpers (SECURITY DEFINER: read profiles regardless of caller RLS) ----
create or replace function current_staff_role() returns text
language sql stable security definer set search_path = public as $$
  select role from public.profiles where id = auth.uid();
$$;

create or replace function is_clinician() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(current_staff_role() in ('admin', 'dietitian'), false);
$$;

create or replace function is_staff() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(current_staff_role() in ('admin', 'dietitian', 'intern'), false);
$$;

-- 3. Per-client intern allocation ---------------------------------------------
create table if not exists client_staff_access (
  client_id         uuid not null references clients(id) on delete cascade,
  profile_id        uuid not null references profiles(id) on delete cascade,
  can_view_checkins boolean not null default false,
  granted_by        uuid references profiles(id) on delete set null default auth.uid(),
  granted_at        timestamptz not null default now(),
  primary key (client_id, profile_id)
);

alter table client_staff_access enable row level security;
drop policy if exists client_staff_access_read on client_staff_access;
create policy client_staff_access_read on client_staff_access
  for select to authenticated using (is_clinician() or profile_id = auth.uid());
drop policy if exists client_staff_access_write on client_staff_access;
create policy client_staff_access_write on client_staff_access
  for all to authenticated using (is_clinician()) with check (is_clinician());
revoke all on client_staff_access from anon;

create or replace function can_access_client(p_client_id uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select is_clinician()
      or (current_staff_role() = 'intern'
          and exists (select 1 from public.client_staff_access a
                      where a.client_id = p_client_id and a.profile_id = auth.uid()));
$$;

create or replace function can_view_checkins(p_client_id uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select is_clinician()
      or (current_staff_role() = 'intern'
          and exists (select 1 from public.client_staff_access a
                      where a.client_id = p_client_id and a.profile_id = auth.uid()
                        and a.can_view_checkins));
$$;

-- Plans: a plan linked to a client follows that client's access; an unlinked
-- plan (template) is visible to all staff.
create or replace function can_access_plan(p_plan_id uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.meal_plans p
    where p.id = p_plan_id
      and case when p.client_id is null then is_staff() else can_access_client(p.client_id) end);
$$;

revoke execute on function current_staff_role(), is_clinician(), is_staff(),
  can_access_client(uuid), can_view_checkins(uuid), can_access_plan(uuid) from public, anon;
grant execute on function current_staff_role(), is_clinician(), is_staff(),
  can_access_client(uuid), can_view_checkins(uuid), can_access_plan(uuid) to authenticated;

-- 4. Replace blanket policies -------------------------------------------------
drop policy if exists "authenticated full access" on clients;
drop policy if exists clients_read on clients;
drop policy if exists clients_update on clients;
drop policy if exists clients_insert on clients;
drop policy if exists clients_delete on clients;
create policy clients_read   on clients for select to authenticated using (can_access_client(id));
create policy clients_update on clients for update to authenticated
  using (can_access_client(id)) with check (can_access_client(id));
create policy clients_insert on clients for insert to authenticated with check (is_clinician());
create policy clients_delete on clients for delete to authenticated using (is_clinician());

drop policy if exists "authenticated full access" on meal_plans;
drop policy if exists meal_plans_access on meal_plans;
create policy meal_plans_access on meal_plans for all to authenticated
  using (case when client_id is null then is_staff() else can_access_client(client_id) end)
  with check (case when client_id is null then is_staff() else can_access_client(client_id) end);

drop policy if exists "authenticated full access" on meal_plan_items;
drop policy if exists meal_plan_items_access on meal_plan_items;
create policy meal_plan_items_access on meal_plan_items for all to authenticated
  using (can_access_plan(meal_plan_id)) with check (can_access_plan(meal_plan_id));
