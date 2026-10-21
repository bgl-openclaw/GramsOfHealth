-- 0037_plans_p1.sql — Plans P1 for full clients (owner go 2026-10-21).
-- Owner decisions: publishing is allowed with recipes still in Needs review, but the
-- warning names them and the published version records them; a start date is
-- required before a CLIENT plan can be published (templates come in P2, undated).
--
-- 1. Quarter serves: meal_plan_items.servings_override integer → numeric, steps of 0.25
--    (the app already offered 0.5 steps, which the integer column could not store).
-- 2. meal_plans.start_date + status ('draft' | 'published').
-- 3. meal_plan_days: per-day day-type overrides (only overrides are stored).
-- 4. plan_days(plan): day → date, weekday, day type (override › client's Mon–Sun
--    pattern › default) and that day's targets (falls back to the client's default
--    targets when the day type has none, and says so in targets_day_type).
-- 5. plan_slots(plan): the client's own meal slots in order (default four when the
--    plan has no client or the client has none), plus any slot name an item still uses.
-- 6. meal_plan_versions: append-only published versions. The app builds the snapshot
--    (everything the booklet + shopping list show, computed by its engine copy, which
--    is parity-checked against line_grams); the database checks the snapshot matches
--    the saved plan (items, servings, days, day types) before sealing it, and records
--    the Needs-review recipes itself. Published booklets/shopping lists render from
--    the snapshot, so later recipe or food edits never change what a client received.
-- 7. A published plan is locked (no item adds/edits, day-type, date, length or client
--    changes) until "Start new version". Item deletes stay allowed so deleting a recipe
--    still works; the published snapshot is unaffected. Status changes only through
--    publish_meal_plan / start_new_plan_version. Deleting a plan that has published
--    versions is dietitian/admin only (removes its history with it).
-- Idempotent. Engine untouched.

-- 1. Quarter serves -------------------------------------------------------------------
alter table meal_plan_items alter column servings_override type numeric(6,2) using servings_override::numeric;
alter table meal_plan_items drop constraint if exists meal_plan_items_servings_quarter;
alter table meal_plan_items add constraint meal_plan_items_servings_quarter check (
  servings_override is null
  or (servings_override > 0 and servings_override * 4 = round(servings_override * 4)));

-- 2. Start date + status ----------------------------------------------------------------
alter table meal_plans add column if not exists start_date date;
alter table meal_plans add column if not exists status text not null default 'draft';
alter table meal_plans drop constraint if exists meal_plans_status;
alter table meal_plans add constraint meal_plans_status check (status in ('draft', 'published'));
comment on column meal_plans.start_date is 'Date of Day 1. Required before a client plan can be published.';
comment on column meal_plans.status is 'draft | published. Changed only by publish_meal_plan / start_new_plan_version.';

-- 3. Day-type overrides -----------------------------------------------------------------
create table if not exists meal_plan_days (
  meal_plan_id uuid not null references meal_plans(id) on delete cascade,
  day          int  not null check (day between 1 and 28),
  day_type     text not null check (day_type in ('default', 'hard', 'moderate', 'rest')),
  primary key (meal_plan_id, day));
comment on table meal_plan_days is 'Per-day day-type overrides. Days without a row follow the client''s weekly pattern.';

alter table meal_plan_days enable row level security;
drop policy if exists meal_plan_days_access on meal_plan_days;
create policy meal_plan_days_access on meal_plan_days for all to authenticated
  using (can_access_plan(meal_plan_id)) with check (can_access_plan(meal_plan_id));
revoke all on meal_plan_days from anon;

-- 4. plan_days -------------------------------------------------------------------------------
create or replace function plan_days(p_plan_id uuid)
returns table (day int, date date, weekday text, day_type text, day_type_source text,
               targets_day_type text, kcal numeric, protein_g numeric, carb_g numeric,
               fat_g numeric, fibre_g numeric)
language sql stable security invoker set search_path = public as $$
  with p as (select * from meal_plans where id = p_plan_id),
  d as (
    select g.day::int as day,
           case when p.start_date is null then null else p.start_date + (g.day - 1)::int end as date,
           p.client_id
    from p, generate_series(1, greatest(coalesce(p.days, 1), 1)) as g(day)),
  typed as (
    select d.day, d.date, d.client_id, o.day_type as override,
           case when d.date is not null and cs.client_id is not null
                then cs.day_type_pattern[extract(isodow from d.date)::int] end as pattern
    from d
    left join meal_plan_days o on o.meal_plan_id = p_plan_id and o.day = d.day
    left join client_structure cs on cs.client_id = d.client_id),
  chosen as (
    select t.*, coalesce(t.override, t.pattern, 'default') as day_type,
           case when t.override is not null then 'override'
                when t.pattern is not null then 'weekly pattern'
                else 'default' end as day_type_source
    from typed t)
  select c.day, c.date, case when c.date is null then null else to_char(c.date, 'Dy') end,
         c.day_type, c.day_type_source,
         case when tt.client_id is not null then c.day_type
              when td.client_id is not null then 'default' end,
         coalesce(tt.kcal, td.kcal), coalesce(tt.protein_g, td.protein_g), coalesce(tt.carb_g, td.carb_g),
         coalesce(tt.fat_g, td.fat_g), coalesce(tt.fibre_g, td.fibre_g)
  from chosen c
  left join client_current_targets tt on tt.client_id = c.client_id and tt.day_type = c.day_type
  left join client_current_targets td on td.client_id = c.client_id and td.day_type = 'default'
                                     and tt.client_id is null
  order by c.day
$$;

-- 5. plan_slots ------------------------------------------------------------------------------
create or replace function plan_slots(p_plan_id uuid)
returns table ("position" int, name text, slot_kind text, free_choice boolean, source text)
language sql stable security invoker set search_path = public as $$
  with p as (select * from meal_plans where id = p_plan_id),
  client_slots as (
    select s.position, s.name, s.slot_kind, s.free_choice, 'client'::text as source
    from p join client_meal_slots s on s.client_id = p.client_id),
  base as (
    select * from client_slots
    union all
    select v.position, v.name, v.slot_kind, false, 'default'
    from (values (0, 'Breakfast', 'breakfast'), (1, 'Lunch', 'lunch'), (2, 'Dinner', 'dinner'), (3, 'Snacks', 'snack'))
           as v(position, name, slot_kind)
    where not exists (select 1 from client_slots)),
  extra as (
    select i.meal_slot as name, min(i.position) as first_pos
    from meal_plan_items i
    where i.meal_plan_id = p_plan_id and i.meal_slot is not null
      and i.meal_slot not in (select b.name from base b)
    group by i.meal_slot)
  select b.position, b.name, b.slot_kind, b.free_choice, b.source from base b
  union all
  select (select coalesce(max(b.position), -1) from base b) + row_number() over (order by e.first_pos, e.name)::int,
         e.name, null, false, 'item' from extra e
  order by 1
$$;

-- 6. Published versions -------------------------------------------------------------------------
create table if not exists meal_plan_versions (
  id                   uuid primary key default gen_random_uuid(),
  meal_plan_id         uuid not null references meal_plans(id) on delete cascade,
  version_no           int  not null,
  snapshot             jsonb not null,
  needs_review_recipes text[] not null default '{}',
  published_at         timestamptz not null default now(),
  published_by         uuid references profiles(id) on delete set null,
  published_by_name    text not null,
  unique (meal_plan_id, version_no));

alter table meal_plan_versions enable row level security;
drop policy if exists meal_plan_versions_read on meal_plan_versions;
create policy meal_plan_versions_read on meal_plan_versions for select to authenticated
  using (can_access_plan(meal_plan_id));
revoke all on meal_plan_versions from anon;
revoke insert, update, delete, truncate on meal_plan_versions from authenticated;

-- Append-only; rows go only when their plan is deleted.
create or replace function meal_plan_versions_guard() returns trigger
language plpgsql set search_path = public as $$
begin
  if tg_op = 'UPDATE' then
    raise exception 'A published plan version can''t be changed.';
  end if;
  if exists (select 1 from meal_plans where id = old.meal_plan_id) then
    raise exception 'A published plan version can''t be deleted on its own.';
  end if;
  return old;
end $$;

drop trigger if exists meal_plan_versions_guard on meal_plan_versions;
create trigger meal_plan_versions_guard before update or delete on meal_plan_versions
  for each row execute function meal_plan_versions_guard();

-- 7. Locks -----------------------------------------------------------------------------------------
create or replace function meal_plans_guard() returns trigger
language plpgsql set search_path = public as $$
begin
  if tg_op = 'DELETE' then
    if exists (select 1 from meal_plan_versions where meal_plan_id = old.id)
       and auth.uid() is not null and not is_clinician() then
      raise exception 'Only a dietitian can delete a plan that has been published.';
    end if;
    return old;
  end if;
  if tg_op = 'INSERT' then
    if new.status <> 'draft' then raise exception 'New plans start as drafts.'; end if;
    return new;
  end if;
  if new.status is distinct from old.status
     and coalesce(current_setting('goh.plan_status', true), '') <> 'on' then
    raise exception 'Use Publish or Start new version to change a plan''s status.';
  end if;
  if old.status = 'published' and new.status = 'published'
     and ((new.days, new.start_date) is distinct from (old.days, old.start_date)
          -- client_id may only change by the client being deleted (FK sets it null)
          or (new.client_id is distinct from old.client_id
              and exists (select 1 from clients where id = old.client_id))) then
    raise exception 'This plan is published — start a new version to change it.';
  end if;
  return new;
end $$;

drop trigger if exists meal_plans_guard on meal_plans;
create trigger meal_plans_guard before insert or update or delete on meal_plans
  for each row execute function meal_plans_guard();

create or replace function meal_plan_children_guard() returns trigger
language plpgsql set search_path = public as $$
declare v_status text;
begin
  select status into v_status from meal_plans
   where id = case when tg_op = 'DELETE' then old.meal_plan_id else new.meal_plan_id end;
  if v_status = 'published' then
    raise exception 'This plan is published — start a new version to change it.';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end $$;

drop trigger if exists meal_plan_items_guard on meal_plan_items;
create trigger meal_plan_items_guard before insert or update on meal_plan_items
  for each row execute function meal_plan_children_guard();
drop trigger if exists meal_plan_days_guard on meal_plan_days;
create trigger meal_plan_days_guard before insert or update or delete on meal_plan_days
  for each row execute function meal_plan_children_guard();

-- 8. Publish check / publish / start new version -------------------------------------------------
create or replace function plan_publish_check(p_plan_id uuid) returns jsonb
language sql stable security invoker set search_path = public as $$
  with p as (select * from meal_plans where id = p_plan_id),
  blockers as (
    select array_remove(array[
      case when not exists (select 1 from p) then 'Plan not found.' end,
      case when (select status from p) = 'published' then 'This plan is published — start a new version to change it.' end,
      case when (select client_id from p) is not null and (select start_date from p) is null
           then 'Set a start date before publishing.' end,
      case when not exists (select 1 from meal_plan_items where meal_plan_id = p_plan_id)
           then 'Add at least one recipe before publishing.' end], null) as list),
  review as (
    select coalesce(array_agg(t.title order by t.title), '{}') as list
    from (select distinct coalesce(nullif(btrim(r.title), ''), 'Untitled recipe') as title
          from meal_plan_items i
          join recipes r on r.id = i.recipe_id
          join recipe_verification rv on rv.recipe_id = i.recipe_id
          where i.meal_plan_id = p_plan_id and rv.status = 'needs_review') t)
  select jsonb_build_object(
    'can_publish', cardinality(b.list) = 0,
    'blockers', to_jsonb(b.list),
    'needs_review', to_jsonb(r.list),
    'next_version', coalesce((select max(version_no) from meal_plan_versions where meal_plan_id = p_plan_id), 0) + 1)
  from blockers b, review r
$$;

create or replace function publish_meal_plan(p_plan_id uuid, p_snapshot jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_name text;
  v_check jsonb;
  v_plan meal_plans%rowtype;
  v_items_diff int;
  v_days_diff int;
  v_no int;
begin
  if v_uid is null or not is_staff() then
    return jsonb_build_object('ok', false, 'message', 'Sign in as staff to publish.');
  end if;
  select * into v_plan from meal_plans where id = p_plan_id for update;
  if not found or not can_access_plan(p_plan_id) then
    return jsonb_build_object('ok', false, 'message', 'Plan not found.');
  end if;

  v_check := plan_publish_check(p_plan_id);
  if not (v_check->>'can_publish')::boolean then
    return jsonb_build_object('ok', false, 'message', v_check->'blockers'->>0, 'blockers', v_check->'blockers');
  end if;

  if jsonb_typeof(p_snapshot) is distinct from 'object'
     or jsonb_typeof(p_snapshot->'items') is distinct from 'array'
     or jsonb_typeof(p_snapshot->'days') is distinct from 'array' then
    return jsonb_build_object('ok', false, 'message', 'The plan snapshot is incomplete — reload the plan and try again.');
  end if;

  -- The snapshot must describe the plan exactly as saved.
  with s as (
    select item_id, recipe_id, profile_id, coalesce(day, 1) as day, meal_slot, servings_override
    from jsonb_to_recordset(p_snapshot->'items')
      as x(item_id uuid, recipe_id uuid, profile_id uuid, day int, meal_slot text, servings_override numeric)),
  i as (
    select id, recipe_id, profile_id, coalesce(day, 1), meal_slot, servings_override
    from meal_plan_items where meal_plan_id = p_plan_id)
  select (select count(*) from (select * from s except all select * from i) a)
       + (select count(*) from (select * from i except all select * from s) b)
    into v_items_diff;

  with s as (
    select day, day_type from jsonb_to_recordset(p_snapshot->'days') as x(day int, day_type text)),
  d as (select day, day_type from plan_days(p_plan_id))
  select (select count(*) from (select * from s except all select * from d) a)
       + (select count(*) from (select * from d except all select * from s) b)
    into v_days_diff;

  if v_items_diff > 0 or v_days_diff > 0 then
    return jsonb_build_object('ok', false,
      'message', 'The plan changed while publishing — reload the plan and try again.');
  end if;

  select coalesce(nullif(btrim(full_name), ''), email) into v_name from profiles where id = v_uid;
  v_no := (v_check->>'next_version')::int;
  insert into meal_plan_versions (meal_plan_id, version_no, snapshot, needs_review_recipes, published_by, published_by_name)
  values (p_plan_id, v_no, p_snapshot,
          array(select jsonb_array_elements_text(v_check->'needs_review')), v_uid, coalesce(v_name, 'Unknown'));

  perform set_config('goh.plan_status', 'on', true);
  update meal_plans set status = 'published' where id = p_plan_id;
  perform set_config('goh.plan_status', '', true);

  return jsonb_build_object('ok', true, 'version_no', v_no, 'needs_review', v_check->'needs_review',
    'message', format('Version %s published.', v_no));
end $$;

create or replace function start_new_plan_version(p_plan_id uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_status text; v_no int;
begin
  if auth.uid() is null or not is_staff() or not can_access_plan(p_plan_id) then
    return jsonb_build_object('ok', false, 'message', 'Plan not found.');
  end if;
  select status into v_status from meal_plans where id = p_plan_id for update;
  if v_status is distinct from 'published' then
    return jsonb_build_object('ok', false, 'message', 'This plan is already a draft.');
  end if;
  select max(version_no) into v_no from meal_plan_versions where meal_plan_id = p_plan_id;
  perform set_config('goh.plan_status', 'on', true);
  update meal_plans set status = 'draft' where id = p_plan_id;
  perform set_config('goh.plan_status', '', true);
  return jsonb_build_object('ok', true,
    'message', format('Editing a new draft. Version %s stays the published version until you publish again.', v_no));
end $$;

revoke execute on function plan_days(uuid), plan_slots(uuid), plan_publish_check(uuid),
  publish_meal_plan(uuid, jsonb), start_new_plan_version(uuid) from public, anon;
grant execute on function plan_days(uuid), plan_slots(uuid), plan_publish_check(uuid),
  publish_meal_plan(uuid, jsonb), start_new_plan_version(uuid) to authenticated;
revoke execute on function meal_plans_guard(), meal_plan_children_guard(), meal_plan_versions_guard()
  from public, anon, authenticated;
