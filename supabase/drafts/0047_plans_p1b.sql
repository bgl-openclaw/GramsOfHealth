-- 0047_plans_p1b.sql — Plans P1b: the plan model the generator needs (plans roadmap rev 2). DRAFT, NOT APPLIED.
-- Builds on 0037 (quarter serves, start date, draft/published, day types, client slots, sealed versions).
-- Owner decisions (21 Oct 2026): any staff member with access to a plan may confirm and publish it (interns
-- included). Confirmation is required before publishing once the plan has a planner report.
--  1. Food items: an item is a recipe (as before) or a food + quantity + unit (snacks, top-ups).
--     boosts_item_id links a top-up to the meal it adds to ("extra 100 g chicken in Tuesday's salad").
--  2. meal_plan_item_deltas: ingredient changes on one plan item (adjust slider, applied suggestions). Same
--     shape as recipe_profile_deltas, applied after the item's profile. The recipe itself never changes.
--  3. Leftovers: batch_group + batch_role ('cook' | 'eat'), one cook per group. The publish check refuses
--     groups that mix recipes, have no cooked meal, or are eaten before they're cooked.
--  4. meal_plan_slot_states: per day and slot, 'free_choice' or 'empty' with a reason, and/or locked.
--  5. Planner output: plan_pool_snapshots (stored once per content hash), plan_generations (seed, settings,
--     pool, planner version, report), meal_plans.generation_id / report / report_at.
--  6. confirm_plan(plan, notes, confirm): stores review notes, who and when. Any change to items, ingredient
--     changes, day types, slot states, days, start date or client clears it. Publishing copies it into the version.
--  7. plan_edits: append-only edit log (operation, actor, diff).
--  8. client_meal_slots.energy_share (% of the day; null = the planner's default for the slot kind).
--  9. plan_publish_check / publish_meal_plan check and compare the new fields. Snapshots from the current app
--     (without the new fields) still publish plans that don't use them.
-- 10. Alternatives (owner, 22 Oct 2026: "the plan looks set up; swap only if needed"): option_of links an alternative
--     to the item it can replace (same day and slot). Hidden behind Swap; never counted in totals or shopping.
-- 11. Release date: publish_meal_plan(plan, snapshot, release_on). The client sees a version from that date (Sydney);
--     null = straight away. my_plans / my_plan_version only show released versions.
-- Test: tests/sql/plans_p1b.test.sql (and tests/sql/plans_p1.test.sql must still pass).

-- 1. food items, top-ups, leftovers ---------------------------------------------------------------------
alter table meal_plan_items alter column recipe_id drop not null;
alter table meal_plan_items
  add column if not exists food_id        text references foods (food_id) on delete restrict,
  add column if not exists quantity       numeric,
  add column if not exists unit           text,
  add column if not exists boosts_item_id uuid references meal_plan_items (id) on delete cascade,
  add column if not exists batch_group    uuid,
  add column if not exists batch_role     text,
  add column if not exists option_of      uuid references meal_plan_items (id) on delete cascade;
alter table meal_plan_items drop constraint if exists meal_plan_items_kind;
alter table meal_plan_items add constraint meal_plan_items_kind check (
  (recipe_id is not null and food_id is null and quantity is null and unit is null)
  or (recipe_id is null and food_id is not null and quantity > 0 and coalesce(btrim(unit), '') <> ''
      and profile_id is null and servings_override is null));
alter table meal_plan_items drop constraint if exists meal_plan_items_boost;
alter table meal_plan_items add constraint meal_plan_items_boost check (
  boosts_item_id is null or (food_id is not null and boosts_item_id <> id));
alter table meal_plan_items drop constraint if exists meal_plan_items_batch;
alter table meal_plan_items add constraint meal_plan_items_batch check (
  (batch_group is null) = (batch_role is null)
  and (batch_role is null or (batch_role in ('cook', 'eat') and recipe_id is not null)));
alter table meal_plan_items drop constraint if exists meal_plan_items_option;
alter table meal_plan_items add constraint meal_plan_items_option check (
  option_of is null or (option_of <> id and batch_group is null and boosts_item_id is null));
create unique index if not exists meal_plan_items_one_cook on meal_plan_items (meal_plan_id, batch_group) where batch_role = 'cook';
comment on column meal_plan_items.option_of is 'An alternative for another item in the same day and slot. The plan shows the main item; alternatives sit behind Swap and are not counted in totals or shopping.';
comment on column meal_plan_items.food_id is 'A food item (snack or top-up) instead of a recipe: food_id + quantity + unit.';
comment on column meal_plan_items.boosts_item_id is 'A top-up: the meal this food is added to (same plan, same day).';
comment on column meal_plan_items.batch_group is 'Leftovers: items sharing a batch_group are one cook-up. batch_role cook = cooked here (shopping counts the whole group once), eat = leftovers.';

create or replace function meal_plan_items_check() returns trigger
language plpgsql set search_path = public as $$
begin
  if new.boosts_item_id is not null
     and not exists (select 1 from meal_plan_items i where i.id = new.boosts_item_id and i.meal_plan_id = new.meal_plan_id) then
    raise exception 'A top-up must add to a meal in the same plan.';
  end if;
  if new.option_of is not null
     and not exists (select 1 from meal_plan_items i where i.id = new.option_of and i.meal_plan_id = new.meal_plan_id
                     and coalesce(i.day, 1) = coalesce(new.day, 1) and i.meal_slot is not distinct from new.meal_slot
                     and i.option_of is null) then
    raise exception 'An alternative must sit with a meal in the same plan, day and slot.';
  end if;
  return new;
end $$;
drop trigger if exists meal_plan_items_check on meal_plan_items;
create trigger meal_plan_items_check before insert or update on meal_plan_items
  for each row execute function meal_plan_items_check();

-- 2. ingredient changes on one plan item ------------------------------------------------------------------
create table if not exists meal_plan_item_deltas (
  id            uuid primary key default gen_random_uuid(),
  item_id       uuid not null references meal_plan_items (id) on delete cascade,
  line_ref      uuid,
  kind          text not null check (kind in ('quantity', 'swap', 'remove', 'add')),
  base_food_id  text,
  base_quantity numeric,
  base_unit     text,
  base_section  text,
  new_food_id   text references foods (food_id) on delete restrict,
  new_quantity  numeric check (new_quantity is null or new_quantity > 0),
  new_unit      text,
  position      int not null default 0,
  source        text not null default 'manual' check (source in ('manual', 'adjust', 'suggestion')),
  created_at    timestamptz not null default now(),
  constraint meal_plan_item_deltas_shape check (
    case kind
      when 'quantity' then line_ref is not null and new_quantity is not null and new_food_id is null
      when 'swap'     then line_ref is not null and new_food_id is not null and new_quantity is not null and new_unit is not null
      when 'remove'   then line_ref is not null and new_food_id is null and new_quantity is null
      when 'add'      then line_ref is null and new_food_id is not null and new_quantity is not null and new_unit is not null
    end));
create index if not exists meal_plan_item_deltas_item on meal_plan_item_deltas (item_id);
create unique index if not exists meal_plan_item_deltas_one_per_line on meal_plan_item_deltas (item_id, line_ref) where line_ref is not null;
comment on table meal_plan_item_deltas is 'Ingredient changes for one plan item (same shape as recipe_profile_deltas; line_ref = ingredient_lines.id). Applied after the item''s profile.';

alter table meal_plan_item_deltas enable row level security;
drop policy if exists meal_plan_item_deltas_access on meal_plan_item_deltas;
create policy meal_plan_item_deltas_access on meal_plan_item_deltas for all to authenticated
  using (exists (select 1 from meal_plan_items i where i.id = item_id and can_access_plan(i.meal_plan_id)))
  with check (exists (select 1 from meal_plan_items i where i.id = item_id and can_access_plan(i.meal_plan_id)));
revoke all on meal_plan_item_deltas from anon;

create or replace function meal_plan_item_deltas_guard() returns trigger
language plpgsql set search_path = public as $$
declare v_item uuid; v_status text; v_recipe uuid;
begin
  v_item := case when tg_op = 'DELETE' then old.item_id else new.item_id end;
  select p.status, i.recipe_id into v_status, v_recipe
    from meal_plan_items i join meal_plans p on p.id = i.meal_plan_id where i.id = v_item;
  if v_status = 'published' then
    raise exception 'This plan is published — start a new version to change it.';
  end if;
  if tg_op <> 'DELETE' and v_status is not null and v_recipe is null then
    raise exception 'Ingredient changes only apply to recipes.';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end $$;
drop trigger if exists meal_plan_item_deltas_guard on meal_plan_item_deltas;
create trigger meal_plan_item_deltas_guard before insert or update or delete on meal_plan_item_deltas
  for each row execute function meal_plan_item_deltas_guard();

-- 3. slot states --------------------------------------------------------------------------------------------
create table if not exists meal_plan_slot_states (
  meal_plan_id uuid not null references meal_plans (id) on delete cascade,
  day          int  not null check (day between 1 and 28),
  meal_slot    text not null check (btrim(meal_slot) <> ''),
  state        text check (state in ('free_choice', 'empty')),
  reason       text check (reason is null or length(reason) <= 300),
  locked       boolean not null default false,
  primary key (meal_plan_id, day, meal_slot),
  check (state is not null or locked));
comment on table meal_plan_slot_states is 'Per day and slot: free_choice / empty (with the reason shown to the dietitian) and locked (kept when regenerating). Slots without a row are normal.';

alter table meal_plan_slot_states enable row level security;
drop policy if exists meal_plan_slot_states_access on meal_plan_slot_states;
create policy meal_plan_slot_states_access on meal_plan_slot_states for all to authenticated
  using (can_access_plan(meal_plan_id)) with check (can_access_plan(meal_plan_id));
revoke all on meal_plan_slot_states from anon;
drop trigger if exists meal_plan_slot_states_guard on meal_plan_slot_states;
create trigger meal_plan_slot_states_guard before insert or update or delete on meal_plan_slot_states
  for each row execute function meal_plan_children_guard();

-- 4. planner output ---------------------------------------------------------------------------------------------
create table if not exists plan_pool_snapshots (
  hash         text primary key check (hash ~ '^[0-9a-f]{64}$'),
  recipe_count int not null check (recipe_count >= 0),
  content      jsonb not null,
  created_at   timestamptz not null default now());
comment on table plan_pool_snapshots is 'The recipe pool a generation drew from (per-serve values, meal types, tags), stored once per sha256 of its content so any run can be reproduced.';
alter table plan_pool_snapshots enable row level security;
drop policy if exists plan_pool_snapshots_read on plan_pool_snapshots;
create policy plan_pool_snapshots_read on plan_pool_snapshots for select using (is_staff());
drop policy if exists plan_pool_snapshots_insert on plan_pool_snapshots;
create policy plan_pool_snapshots_insert on plan_pool_snapshots for insert with check (is_staff());
revoke all on plan_pool_snapshots from anon;
revoke update, delete, truncate on plan_pool_snapshots from authenticated;

create table if not exists plan_generations (
  id              uuid primary key default gen_random_uuid(),
  meal_plan_id    uuid not null references meal_plans (id) on delete cascade,
  seed            bigint not null,
  settings        jsonb not null,
  pool_hash       text not null references plan_pool_snapshots (hash),
  planner_version text not null,
  report          jsonb not null,
  created_by      uuid references profiles (id) on delete set null,
  created_at      timestamptz not null default now());
create index if not exists plan_generations_plan on plan_generations (meal_plan_id, created_at desc);
alter table plan_generations enable row level security;
drop policy if exists plan_generations_read on plan_generations;
create policy plan_generations_read on plan_generations for select using (can_access_plan(meal_plan_id));
drop policy if exists plan_generations_insert on plan_generations;
create policy plan_generations_insert on plan_generations for insert with check (can_access_plan(meal_plan_id));
revoke all on plan_generations from anon;
revoke update, delete, truncate on plan_generations from authenticated;

alter table meal_plans
  add column if not exists generation_id     uuid references plan_generations (id) on delete set null,
  add column if not exists report            jsonb,
  add column if not exists report_at         timestamptz,
  add column if not exists review_notes      text check (review_notes is null or length(review_notes) <= 2000),
  add column if not exists confirmed_at      timestamptz,
  add column if not exists confirmed_by      uuid references profiles (id) on delete set null,
  add column if not exists confirmed_by_name text;
comment on column meal_plans.report is 'The planner''s latest report for this plan (refreshed after every planner edit). When set, the plan must be confirmed before publishing.';
comment on column meal_plans.confirmed_at is 'Set by confirm_plan; cleared automatically by any change to the plan''s food, days or dates.';

alter table meal_plan_versions
  add column if not exists generation_id     uuid,
  add column if not exists review_notes      text,
  add column if not exists confirmed_at      timestamptz,
  add column if not exists confirmed_by_name text;

-- 5. edit log ------------------------------------------------------------------------------------------------------
create table if not exists plan_edits (
  id           bigint generated always as identity primary key,
  meal_plan_id uuid not null references meal_plans (id) on delete cascade,
  operation    text not null check (operation ~ '^[a-z][a-z_]{1,40}$'),
  actor        uuid references profiles (id) on delete set null,
  actor_name   text,
  diff         jsonb not null default '{}'::jsonb,
  created_at   timestamptz not null default now());
create index if not exists plan_edits_plan on plan_edits (meal_plan_id, created_at desc);
alter table plan_edits enable row level security;
drop policy if exists plan_edits_read on plan_edits;
create policy plan_edits_read on plan_edits for select using (can_access_plan(meal_plan_id));
drop policy if exists plan_edits_insert on plan_edits;
create policy plan_edits_insert on plan_edits for insert with check (can_access_plan(meal_plan_id));
revoke all on plan_edits from anon;
revoke update, delete, truncate on plan_edits from authenticated;

-- who did it is always the signed-in person (plan_edits, plan_generations)
create or replace function plan_stamp_actor() returns trigger
language plpgsql set search_path = public as $$
begin
  if current_user in ('authenticated', 'anon') then
    if tg_table_name = 'plan_edits' then
      new.actor := auth.uid();
      new.actor_name := (select coalesce(nullif(btrim(full_name), ''), email) from profiles where id = auth.uid());
    else
      new.created_by := auth.uid();
    end if;
    new.created_at := now();
  end if;
  return new;
end $$;
drop trigger if exists plan_edits_stamp on plan_edits;
create trigger plan_edits_stamp before insert on plan_edits for each row execute function plan_stamp_actor();
drop trigger if exists plan_generations_stamp on plan_generations;
create trigger plan_generations_stamp before insert on plan_generations for each row execute function plan_stamp_actor();

-- 6. confirmation ----------------------------------------------------------------------------------------------------
-- any change to what the client would receive clears it
create or replace function plan_clear_confirmation() returns trigger
language plpgsql set search_path = public as $$
declare v_plan uuid;
begin
  if tg_table_name = 'meal_plan_item_deltas' then
    select meal_plan_id into v_plan from meal_plan_items
     where id = case when tg_op = 'DELETE' then old.item_id else new.item_id end;
  else
    v_plan := case when tg_op = 'DELETE' then old.meal_plan_id else new.meal_plan_id end;
  end if;
  if v_plan is not null and exists (select 1 from meal_plans where id = v_plan and confirmed_at is not null) then
    perform set_config('goh.plan_confirm', 'on', true);
    update meal_plans set confirmed_at = null, confirmed_by = null, confirmed_by_name = null where id = v_plan;
    perform set_config('goh.plan_confirm', '', true);
  end if;
  return null;
end $$;
drop trigger if exists meal_plan_items_unconfirm on meal_plan_items;
create trigger meal_plan_items_unconfirm after insert or update or delete on meal_plan_items
  for each row execute function plan_clear_confirmation();
drop trigger if exists meal_plan_days_unconfirm on meal_plan_days;
create trigger meal_plan_days_unconfirm after insert or update or delete on meal_plan_days
  for each row execute function plan_clear_confirmation();
drop trigger if exists meal_plan_slot_states_unconfirm on meal_plan_slot_states;
create trigger meal_plan_slot_states_unconfirm after insert or update or delete on meal_plan_slot_states
  for each row execute function plan_clear_confirmation();
drop trigger if exists meal_plan_item_deltas_unconfirm on meal_plan_item_deltas;
create trigger meal_plan_item_deltas_unconfirm after insert or update or delete on meal_plan_item_deltas
  for each row execute function plan_clear_confirmation();

-- 0037's guard + confirmation fields (only confirm_plan or the clearing above may change them) + generation check
create or replace function meal_plans_guard() returns trigger
language plpgsql set search_path = public as $$
declare v_confirm boolean := coalesce(current_setting('goh.plan_confirm', true), '') = 'on';
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
    if new.confirmed_at is not null or new.confirmed_by is not null or new.review_notes is not null then
      raise exception 'Use Confirm to confirm a plan.'; end if;
    if new.generation_id is not null then raise exception 'A new plan has no planner run yet.'; end if;
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
  if not v_confirm and (new.confirmed_at, new.confirmed_by, new.confirmed_by_name, new.review_notes)
                       is distinct from (old.confirmed_at, old.confirmed_by, old.confirmed_by_name, old.review_notes) then
    raise exception 'Use Confirm to confirm a plan.';
  end if;
  if new.generation_id is distinct from old.generation_id and new.generation_id is not null
     and not exists (select 1 from plan_generations g where g.id = new.generation_id and g.meal_plan_id = new.id) then
    raise exception 'That planner run belongs to another plan.';
  end if;
  if (new.days, new.start_date, new.client_id) is distinct from (old.days, old.start_date, old.client_id) then
    new.confirmed_at := null; new.confirmed_by := null; new.confirmed_by_name := null;
  end if;
  return new;
end $$;

create or replace function confirm_plan(p_plan_id uuid, p_notes text default null, p_confirm boolean default true) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v_name text; v_status text;
begin
  if v_uid is null or not is_staff() or not can_access_plan(p_plan_id) then
    return jsonb_build_object('ok', false, 'message', 'Plan not found.');
  end if;
  select status into v_status from meal_plans where id = p_plan_id for update;
  if v_status = 'published' then
    return jsonb_build_object('ok', false, 'message', 'This plan is published — start a new version to change it.');
  end if;
  if length(coalesce(p_notes, '')) > 2000 then
    return jsonb_build_object('ok', false, 'message', 'Keep the notes under 2,000 characters.');
  end if;
  select coalesce(nullif(btrim(full_name), ''), email) into v_name from profiles where id = v_uid;
  perform set_config('goh.plan_confirm', 'on', true);
  if coalesce(p_confirm, true) then
    update meal_plans set confirmed_at = now(), confirmed_by = v_uid, confirmed_by_name = coalesce(v_name, 'Unknown'),
                          review_notes = nullif(btrim(p_notes), '')
     where id = p_plan_id;
  else
    update meal_plans set confirmed_at = null, confirmed_by = null, confirmed_by_name = null where id = p_plan_id;
  end if;
  perform set_config('goh.plan_confirm', '', true);
  return jsonb_build_object('ok', true, 'message', case when coalesce(p_confirm, true) then 'Plan confirmed.' else 'Confirmation removed.' end);
end $$;

-- 7. energy share per client slot -------------------------------------------------------------------------------------
alter table client_meal_slots add column if not exists energy_share numeric(5,2)
  check (energy_share is null or (energy_share > 0 and energy_share <= 100));
comment on column client_meal_slots.energy_share is 'Share of the day''s energy for this slot, in % (a soft target for the planner). Null = the planner''s default for the slot kind.';

create or replace function save_client_structure(p_client_id uuid, p_settings jsonb, p_slots jsonb, p_protein_spread jsonb)
returns void language plpgsql set search_path = public as $$
begin
  if not can_access_client(p_client_id) then
    raise exception 'no access to this client';
  end if;

  if p_settings is not null then
    insert into client_structure (client_id, cycle_length_days, repeat_min_gap_days, repeat_max_per_cycle,
                                  batch_cooking, day_type_pattern, updated_at)
    values (p_client_id,
            (p_settings->>'cycle_length_days')::int,
            (p_settings->>'repeat_min_gap_days')::int,
            (p_settings->>'repeat_max_per_cycle')::int,
            coalesce((p_settings->>'batch_cooking')::boolean, false),
            coalesce((select array_agg(x order by i) from jsonb_array_elements_text(p_settings->'day_type_pattern') with ordinality t(x, i)),
                     array['default','default','default','default','default','default','default']),
            now())
    on conflict (client_id) do update set
      cycle_length_days = excluded.cycle_length_days,
      repeat_min_gap_days = excluded.repeat_min_gap_days,
      repeat_max_per_cycle = excluded.repeat_max_per_cycle,
      batch_cooking = excluded.batch_cooking,
      day_type_pattern = excluded.day_type_pattern,
      updated_at = now();
  end if;

  if p_slots is not null then
    delete from client_meal_slots where client_id = p_client_id;
    insert into client_meal_slots (client_id, position, name, slot_kind, time_of_day, free_choice, energy_share)
    select p_client_id, (i - 1)::int, btrim(s->>'name'), s->>'slot_kind',
           nullif(s->>'time_of_day', '')::time, coalesce((s->>'free_choice')::boolean, false),
           nullif(s->>'energy_share', '')::numeric
    from jsonb_array_elements(p_slots) with ordinality t(s, i);
  end if;

  if p_protein_spread is not null then
    delete from client_protein_spread where client_id = p_client_id;
    insert into client_protein_spread (client_id, protein_family, count_per_cycle)
    select p_client_id, s->>'protein_family', (s->>'count_per_cycle')::int
    from jsonb_array_elements(p_protein_spread) t(s);
  end if;
end $$;

-- 8. publish check / publish / new version ------------------------------------------------------------------------------
create or replace function plan_publish_check(p_plan_id uuid) returns jsonb
language sql stable security invoker set search_path = public as $$
  with p as (select * from meal_plans where id = p_plan_id),
  items as (select * from meal_plan_items where meal_plan_id = p_plan_id),
  groups as (
    select batch_group,
           count(distinct recipe_id) as recipes, count(distinct coalesce(profile_id::text, '-')) as profiles,
           count(*) filter (where batch_role = 'cook') as cooks,
           min(coalesce(day, 1)) filter (where batch_role = 'cook') as cook_day,
           min(coalesce(day, 1)) filter (where batch_role = 'eat') as first_eat_day
    from items where batch_group is not null group by batch_group),
  blockers as (
    select array_remove(array[
      case when not exists (select 1 from p) then 'Plan not found.' end,
      case when (select status from p) = 'published' then 'This plan is published — start a new version to change it.' end,
      case when (select client_id from p) is not null and (select start_date from p) is null
           then 'Set a start date before publishing.' end,
      case when not exists (select 1 from items)
           then 'Add at least one recipe or food before publishing.' end,
      case when exists (select 1 from groups where recipes > 1 or profiles > 1)
           then 'Leftovers must be the same recipe as the meal they come from.' end,
      case when exists (select 1 from groups where cooks = 0)
           then 'A leftover needs the meal it comes from (the day it''s cooked).' end,
      case when exists (select 1 from groups where first_eat_day < cook_day)
           then 'Leftovers can''t be eaten before the day they''re cooked.' end,
      case when exists (select 1 from items o join items m on m.id = o.option_of
                        where coalesce(o.day, 1) <> coalesce(m.day, 1) or o.meal_slot is distinct from m.meal_slot)
           then 'An alternative must be in the same day and slot as the meal it replaces.' end,
      case when exists (select 1 from items t join items b on b.id = t.boosts_item_id
                        where coalesce(t.day, 1) <> coalesce(b.day, 1))
           then 'A top-up must be on the same day as the meal it adds to.' end,
      case when exists (select 1 from meal_plan_slot_states s join items i
                          on coalesce(i.day, 1) = s.day and i.meal_slot = s.meal_slot
                        where s.meal_plan_id = p_plan_id and s.state is not null)
           then 'A slot marked free choice or empty still has food in it.' end,
      case when (select report from p) is not null and (select confirmed_at from p) is null
           then 'Review the planner report and confirm the plan before publishing.' end], null) as list),
  review as (
    select coalesce(array_agg(t.title order by t.title), '{}') as list
    from (select distinct coalesce(nullif(btrim(r.title), ''), 'Untitled recipe') as title
          from items i
          join recipes r on r.id = i.recipe_id
          join recipe_verification rv on rv.recipe_id = i.recipe_id
          where rv.status = 'needs_review'
          union
          select distinct coalesce(nullif(btrim(f.display_name), ''), f.food_id)
          from items i join foods f on f.food_id = i.food_id
          where not f.verified) t)
  select jsonb_build_object(
    'can_publish', cardinality(b.list) = 0,
    'blockers', to_jsonb(b.list),
    'needs_review', to_jsonb(r.list),
    'next_version', coalesce((select max(version_no) from meal_plan_versions where meal_plan_id = p_plan_id), 0) + 1)
  from blockers b, review r
$$;

alter table meal_plan_versions add column if not exists release_on date;
comment on column meal_plan_versions.release_on is 'The client sees this version from this date (practice time zone). Null = as soon as it is published.';
drop function if exists publish_meal_plan(uuid, jsonb);
create or replace function publish_meal_plan(p_plan_id uuid, p_snapshot jsonb, p_release_on date default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_today date := (now() at time zone coalesce(app_setting('timezone'), 'Australia/Sydney'))::date;
  v_uid uuid := auth.uid();
  v_name text;
  v_check jsonb;
  v_plan meal_plans%rowtype;
  v_items_diff int;
  v_deltas_diff int;
  v_slots_diff int;
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
    select item_id, recipe_id, profile_id, coalesce(day, 1) as day, meal_slot, servings_override,
           food_id, quantity, unit, boosts_item_id, batch_group, batch_role, option_of
    from jsonb_to_recordset(p_snapshot->'items')
      as x(item_id uuid, recipe_id uuid, profile_id uuid, day int, meal_slot text, servings_override numeric,
           food_id text, quantity numeric, unit text, boosts_item_id uuid, batch_group uuid, batch_role text, option_of uuid)),
  i as (
    select id, recipe_id, profile_id, coalesce(day, 1), meal_slot, servings_override,
           food_id, quantity, unit, boosts_item_id, batch_group, batch_role, option_of
    from meal_plan_items where meal_plan_id = p_plan_id)
  select (select count(*) from (select * from s except all select * from i) a)
       + (select count(*) from (select * from i except all select * from s) b)
    into v_items_diff;

  with s as (
    select (it->>'item_id')::uuid as item_id, x.kind, x.line_ref, x.new_food_id, x.new_quantity, x.new_unit
    from jsonb_array_elements(p_snapshot->'items') it
    cross join lateral jsonb_to_recordset(coalesce(it->'deltas', '[]'::jsonb))
      as x(kind text, line_ref uuid, new_food_id text, new_quantity numeric, new_unit text)),
  d as (
    select dl.item_id, dl.kind, dl.line_ref, dl.new_food_id, dl.new_quantity, dl.new_unit
    from meal_plan_item_deltas dl join meal_plan_items i on i.id = dl.item_id
    where i.meal_plan_id = p_plan_id)
  select (select count(*) from (select * from s except all select * from d) a)
       + (select count(*) from (select * from d except all select * from s) b)
    into v_deltas_diff;

  with s as (
    select day, meal_slot, state, reason
    from jsonb_to_recordset(coalesce(p_snapshot->'slot_states', '[]'::jsonb))
      as x(day int, meal_slot text, state text, reason text)),
  d as (
    select day, meal_slot, state, reason from meal_plan_slot_states
    where meal_plan_id = p_plan_id and state is not null)
  select (select count(*) from (select * from s except all select * from d) a)
       + (select count(*) from (select * from d except all select * from s) b)
    into v_slots_diff;

  with s as (
    select day, day_type from jsonb_to_recordset(p_snapshot->'days') as x(day int, day_type text)),
  d as (select day, day_type from plan_days(p_plan_id))
  select (select count(*) from (select * from s except all select * from d) a)
       + (select count(*) from (select * from d except all select * from s) b)
    into v_days_diff;

  if v_items_diff > 0 or v_deltas_diff > 0 or v_slots_diff > 0 or v_days_diff > 0 then
    return jsonb_build_object('ok', false,
      'message', 'The plan changed while publishing — reload the plan and try again.');
  end if;

  select coalesce(nullif(btrim(full_name), ''), email) into v_name from profiles where id = v_uid;
  v_no := (v_check->>'next_version')::int;
  insert into meal_plan_versions (meal_plan_id, version_no, snapshot, needs_review_recipes, published_by, published_by_name,
                                  generation_id, review_notes, confirmed_at, confirmed_by_name, release_on)
  values (p_plan_id, v_no, p_snapshot,
          array(select jsonb_array_elements_text(v_check->'needs_review')), v_uid, coalesce(v_name, 'Unknown'),
          v_plan.generation_id, v_plan.review_notes, v_plan.confirmed_at, v_plan.confirmed_by_name,
          case when p_release_on > v_today then p_release_on end);

  perform set_config('goh.plan_status', 'on', true);
  update meal_plans set status = 'published' where id = p_plan_id;
  perform set_config('goh.plan_status', '', true);

  return jsonb_build_object('ok', true, 'version_no', v_no, 'needs_review', v_check->'needs_review',
    'release_on', case when p_release_on > v_today then p_release_on end,
    'message', case when p_release_on > v_today
                    then format('Version %s published. The client sees it from %s.', v_no, to_char(p_release_on, 'FMDD Mon YYYY'))
                    else format('Version %s published.', v_no) end);
end $$;

-- the client only sees versions whose release date has arrived
create or replace function my_plans()
returns table (plan_id uuid, title text, start_date date, days integer, end_date date, version_no integer, published_at timestamptz, is_current boolean)
language sql stable security definer set search_path = public as $$
  with today as (select (now() at time zone coalesce(app_setting('timezone'), 'Australia/Sydney'))::date as d),
  latest as (
    select distinct on (v.meal_plan_id) v.meal_plan_id, v.version_no, v.published_at, v.snapshot
    from meal_plan_versions v join meal_plans p on p.id = v.meal_plan_id, today
    where p.client_id = my_client_id() and (v.release_on is null or v.release_on <= today.d)
    order by v.meal_plan_id, v.version_no desc),
  rows as (
    select l.meal_plan_id, coalesce(l.snapshot -> 'plan' ->> 'title', 'Your meal plan') as title,
           nullif(l.snapshot -> 'plan' ->> 'start_date', '')::date as start_date,
           greatest(coalesce((l.snapshot -> 'plan' ->> 'days')::int, jsonb_array_length(l.snapshot -> 'days')), 1) as days,
           l.version_no, l.published_at,
           (now() at time zone app_setting('timezone'))::date as today
    from latest l),
  ranked as (
    select r.*, r.start_date + r.days - 1 as end_date,
           row_number() over (order by
             case when r.start_date <= r.today and r.today <= r.start_date + r.days - 1 then 0
                  when r.start_date > r.today then 1 else 2 end,
             case when r.start_date > r.today then r.start_date end asc,
             r.start_date desc nulls last, r.published_at desc) as rk
    from rows r)
  select meal_plan_id, title, start_date, days, end_date, version_no, published_at, rk = 1
  from ranked order by rk
$$;

create or replace function my_plan_version(p_plan_id uuid, p_version_no integer default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_id uuid := my_client_id();
  c clients%rowtype;
  v meal_plan_versions%rowtype;
  s jsonb;
  v_num boolean;
  v_items jsonb;
  v_days jsonb;
  v_today date := (now() at time zone coalesce(app_setting('timezone'), 'Australia/Sydney'))::date;
begin
  if v_id is null or not exists (select 1 from meal_plans where id = p_plan_id and client_id = v_id) then
    return null;
  end if;
  select * into c from clients where id = v_id;
  v_num := c.numbers_allowed and c.client_shows_numbers;
  select * into v from meal_plan_versions
   where meal_plan_id = p_plan_id and (p_version_no is null or version_no = p_version_no)
     and (release_on is null or release_on <= v_today)
   order by version_no desc limit 1;
  if not found then return null; end if;
  s := v.snapshot;

  select coalesce(jsonb_agg(
           case when v_num then e.i - 'version_status'
                else (e.i - 'version_status' - 'per_serve' - 'totals')
                     || jsonb_build_object('show_macros_export', false,
                          'lines', coalesce((select jsonb_agg(l.x - 'kcal' - 'protein' - 'carb' - 'fat' - 'fibre' order by l.n)
                                             from jsonb_array_elements(e.i -> 'lines') with ordinality as l(x, n)), '[]'::jsonb))
           end order by e.n), '[]'::jsonb)
    into v_items
    from jsonb_array_elements(coalesce(s -> 'items', '[]'::jsonb)) with ordinality as e(i, n);

  select coalesce(jsonb_agg(case when v_num then d.x else d.x - 'targets' - 'totals' - 'targets_day_type' end order by d.n), '[]'::jsonb)
    into v_days
    from jsonb_array_elements(coalesce(s -> 'days', '[]'::jsonb)) with ordinality as d(x, n);

  return jsonb_build_object(
    'plan_id', p_plan_id,
    'version_no', v.version_no,
    'published_at', v.published_at,
    'show_numbers', v_num,
    'plan', (s -> 'plan') - 'client_id',
    'slots', coalesce(s -> 'slots', '[]'::jsonb),
    'days', v_days,
    'items', v_items,
    'week_average', case when v_num then s -> 'week_average' end,
    'shopping', coalesce(s -> 'shopping', '[]'::jsonb),
    'unresolved', coalesce(s -> 'unresolved', '[]'::jsonb));
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
  perform set_config('goh.plan_confirm', 'on', true);
  update meal_plans set status = 'draft', confirmed_at = null, confirmed_by = null, confirmed_by_name = null
   where id = p_plan_id;
  perform set_config('goh.plan_confirm', '', true);
  perform set_config('goh.plan_status', '', true);
  return jsonb_build_object('ok', true,
    'message', format('Editing a new draft. Version %s stays the published version until you publish again.', v_no));
end $$;

-- 9. grants --------------------------------------------------------------------------------------------------------------
revoke execute on function meal_plan_items_check(), meal_plan_item_deltas_guard(), plan_stamp_actor(),
  plan_clear_confirmation(), meal_plans_guard() from public, anon, authenticated;
revoke execute on function confirm_plan(uuid, text, boolean), publish_meal_plan(uuid, jsonb, date), my_plans(), my_plan_version(uuid, integer) from public, anon;
grant execute on function confirm_plan(uuid, text, boolean), publish_meal_plan(uuid, jsonb, date), my_plans(), my_plan_version(uuid, integer) to authenticated;
