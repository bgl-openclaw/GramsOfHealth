-- tests/sql/p0_lockdown.test.sql — live test of migration 0038 (+ 0040's new tables) (always rolls back).
--   pass → "ALL PASS (rolled back)"   fail → "FAIL: ..."
-- Impersonates the earliest profile as each role in turn (request.jwt.claims +
-- SET ROLE authenticated) and checks what that role can see and change.
do $$
declare
  u uuid; r text; t text; n int; base int; log text := '';
  lib text[] := array['food_tags', 'food_unit_exclusions', 'foods', 'ingredient_lines', 'method_steps',
    'recipe_profile_deltas', 'recipe_profiles', 'recipe_tag_overrides', 'recipe_tags', 'recipes',
    'swap_suggestions', 'tags', 'unit_conversions', 'afcd_master', 'recipe_signoffs',
    'clients', 'meal_plans', 'meal_plan_items', 'meal_plan_versions', 'change_log',
    'intake_questions', 'client_areas', 'client_intake', 'client_intake_log'];
  staff_sees text := ''; other_sees text := '';
  nprofiles int;
begin
  select id into u from profiles order by created_at limit 1;
  select count(*) into nprofiles from profiles;
  perform set_config('request.jwt.claims', json_build_object('sub', u, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', u::text, true);

  foreach r in array array['admin', 'dietitian', 'intern', 'pending', 'client'] loop
    execute 'reset role';
    update profiles set role = r where id = u;
    execute 'set local role authenticated';

    -- READ: library tables visible to staff in full, to pending/client not at all
    foreach t in array lib loop
      execute 'reset role';
      execute format('select count(*) from public.%I', t) into base;
      execute 'set local role authenticated';
      execute format('select count(*) from public.%I', t) into n;
      if r in ('admin', 'dietitian', 'intern') then
        -- staff: full library; client-scoped tables follow their own rules (intern unallocated → none)
        if t in ('clients', 'meal_plans', 'meal_plan_items', 'meal_plan_versions', 'change_log', 'client_intake', 'client_intake_log') then
          null;
        elsif n <> base then raise exception 'FAIL % sees %/% rows of %', r, n, base, t;
        end if;
      elsif n <> 0 then
        raise exception 'FAIL % sees % rows of %', r, n, t;
      end if;
    end loop;

    -- profiles: staff see everyone, others only themselves
    select count(*) into n from profiles;
    if r in ('admin', 'dietitian', 'intern') and n <> nprofiles then raise exception 'FAIL % sees % profiles', r, n; end if;
    if r in ('pending', 'client') and (n <> 1 or not exists (select 1 from profiles where id = u)) then
      raise exception 'FAIL % sees % profiles (want own only)', r, n; end if;

    -- WRITE: staff can edit the library; pending/client can't (insert errors, update/delete touch 0 rows)
    begin
      insert into tags (label, category) values ('zz p0 test tag ' || r, 'other');
      if r not in ('admin', 'dietitian', 'intern') then raise exception 'FAIL % inserted a tag', r; end if;
    exception when others then
      if sqlerrm like 'FAIL%' then raise; end if;
      if r in ('admin', 'dietitian', 'intern') then raise exception 'FAIL staff % could not insert a tag: %', r, sqlerrm; end if;
    end;
    update foods set display_name = display_name where food_id = 'egg';
    get diagnostics n = row_count;
    if (r in ('admin', 'dietitian', 'intern')) <> (n = 1) then raise exception 'FAIL % food update touched % rows', r, n; end if;
    begin
      insert into afcd_master (public_food_key, food_name) values ('ZZP0', 'zz');
      raise exception 'FAIL % inserted into AFCD', r;
    exception when others then if sqlerrm like 'FAIL%' then raise; end if; end;

    -- STORAGE: recipe photo upload staff-only
    begin
      insert into storage.objects (bucket_id, name) values ('recipe-images', 'zz-p0-test/' || r || '.jpg');
      if r not in ('admin', 'dietitian', 'intern') then raise exception 'FAIL % uploaded a recipe photo', r; end if;
    exception when others then
      if sqlerrm like 'FAIL%' then raise; end if;
      if r in ('admin', 'dietitian', 'intern') then raise exception 'FAIL staff % could not upload: %', r, sqlerrm; end if;
    end;

    -- VIEWS follow the tables
    select count(*) into n from recipe_verification;
    if (r in ('admin', 'dietitian', 'intern')) <> (n > 0) then raise exception 'FAIL % sees % recipe_verification rows', r, n; end if;

    if r in ('admin', 'dietitian', 'intern') then staff_sees := staff_sees || r || ' ';
    else other_sees := other_sees || r || ' '; end if;
  end loop;
  execute 'reset role';

  log := format('staff (%s) read+write the full library, see all %s profiles, can upload photos | %s see 0 rows of every library/client/plan table and views, only their own profile, can''t write tags/foods/AFCD or upload photos | AFCD read-only for everyone',
                btrim(staff_sees), nprofiles, btrim(other_sees));
  raise exception 'ALL PASS (rolled back): %', log;
end $$;
