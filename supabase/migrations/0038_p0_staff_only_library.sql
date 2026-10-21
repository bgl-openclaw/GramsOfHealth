-- 0038_p0_staff_only_library.sql — client app P0: security lockdown before any
-- client can sign in (owner go 2026-10-21). Nothing changes for staff.
--
-- Before: 14 library tables had "authenticated full access" — any signed-in
-- account (incl. 'pending', and future client logins) could read AND write the
-- recipe/food library through the API. Staff profiles (name/email/phone) and
-- recipe sign-offs were readable by any signed-in account. Any signed-in account
-- could upload/replace/delete recipe photos.
-- After:
--   * library tables: staff (admin | dietitian | intern) read + write, exactly as
--     the app uses them today; AFCD reference data: staff read-only (never written
--     by the app). Pending accounts and clients get nothing.
--   * profiles: you can read your own row; staff can read everyone's.
--   * recipe_signoffs: staff read (writes still only via the sign-off RPCs).
--   * recipe-images bucket: public read unchanged; upload/replace/delete staff-only.
--   * profiles.role gains 'client' (no client can sign up yet — invitations still
--     only issue staff roles; client invites arrive in P1). is_staff() already
--     excludes it, so a client account sees nothing until P1 adds client-only reads.
-- Owner actions (Supabase dashboard, not SQL): rotate DB password + service-role
-- key, turn on leaked-password protection.
-- Idempotent.

-- 1. Library tables → staff only ---------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['food_tags', 'food_unit_exclusions', 'foods', 'ingredient_lines',
    'method_steps', 'recipe_profile_deltas', 'recipe_profiles', 'recipe_tag_overrides',
    'recipe_tags', 'recipes', 'swap_suggestions', 'tags', 'unit_conversions'] loop
    execute format('drop policy if exists "authenticated full access" on public.%I', t);
    execute format('drop policy if exists %I on public.%I', t || '_staff', t);
    execute format('create policy %I on public.%I for all to authenticated using (is_staff()) with check (is_staff())',
                   t || '_staff', t);
    execute format('revoke all on public.%I from anon', t);
  end loop;
end $$;

drop policy if exists "authenticated full access" on afcd_master;
drop policy if exists afcd_master_staff_read on afcd_master;
create policy afcd_master_staff_read on afcd_master for select to authenticated using (is_staff());
revoke all on afcd_master from anon;

-- 2. Profiles: own row, or staff ---------------------------------------------------------
drop policy if exists "profiles read" on profiles;
drop policy if exists profiles_read_own_or_staff on profiles;
create policy profiles_read_own_or_staff on profiles for select to authenticated
  using (id = (select auth.uid()) or is_staff());

alter table profiles drop constraint if exists profiles_role_check;
alter table profiles add constraint profiles_role_check
  check (role in ('admin', 'dietitian', 'intern', 'pending', 'client'));

-- 3. Recipe sign-offs: staff read ---------------------------------------------------------
drop policy if exists recipe_signoffs_read on recipe_signoffs;
create policy recipe_signoffs_read on recipe_signoffs for select to authenticated using (is_staff());

-- 4. Recipe photos: public read stays; writes staff-only ----------------------------------
drop policy if exists "recipe-images insert" on storage.objects;
create policy "recipe-images insert" on storage.objects for insert to authenticated
  with check (bucket_id = 'recipe-images' and public.is_staff());
drop policy if exists "recipe-images update" on storage.objects;
create policy "recipe-images update" on storage.objects for update to authenticated
  using (bucket_id = 'recipe-images' and public.is_staff())
  with check (bucket_id = 'recipe-images' and public.is_staff());
drop policy if exists "recipe-images delete" on storage.objects;
create policy "recipe-images delete" on storage.objects for delete to authenticated
  using (bucket_id = 'recipe-images' and public.is_staff());
