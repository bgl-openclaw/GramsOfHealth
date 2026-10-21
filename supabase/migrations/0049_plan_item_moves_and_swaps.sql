-- 0049_plan_item_moves_and_swaps.sql — fixes found reviewing Lovable's P1b part A (22 Oct 2026).
-- APPLIED live 22 Oct 2026 (apply_migration "0049_plan_item_moves_and_swaps"); plans_0049, plans_p1b (T11d updated),
-- plans_p1 and client_accounts_p1a pass live.
--  1. Moving a meal (new day or slot) moves its alternatives and top-ups with it, whoever moves it (drag, planner, SQL).
--     Before: dragging a meal left its hidden alternatives behind, and publishing was refused with nothing on screen to fix.
--  2. use_plan_alternative(p_item_id): "Use this instead" as one transaction. The alternative takes the meal's place
--     (and position); the old meal and the other alternatives become its alternatives; top-ups follow.
--     Before: four separate updates from the app; a failure halfway left two meals counted, or orphaned alternatives.
--  3. my_plan_version returns slot_states (free choice / empty, with the reason), so the client app can show them.
-- Test: tests/sql/plans_0049.test.sql (plans_p1b and client_accounts_p1a must still pass).

-- 1. alternatives and top-ups follow their meal ----------------------------------------------------------------
create or replace function meal_plan_items_follow() returns trigger
language plpgsql set search_path = public as $$
begin
  update meal_plan_items
     set day = new.day, meal_slot = new.meal_slot
   where (option_of = new.id or boosts_item_id = new.id)
     and (day is distinct from new.day or meal_slot is distinct from new.meal_slot);
  return null;
end $$;
drop trigger if exists meal_plan_items_follow on meal_plan_items;
create trigger meal_plan_items_follow after update of day, meal_slot on meal_plan_items
  for each row when (old.day is distinct from new.day or old.meal_slot is distinct from new.meal_slot)
  execute function meal_plan_items_follow();

-- 2. swap an alternative in, all or nothing --------------------------------------------------------------------------
-- security invoker: the caller's own plan access (RLS) and the published-plan guard apply as for any edit.
create or replace function use_plan_alternative(p_item_id uuid) returns jsonb
language plpgsql security invoker set search_path = public as $$
declare
  a meal_plan_items%rowtype;
  m meal_plan_items%rowtype;
  n int;
begin
  select * into a from meal_plan_items where id = p_item_id for update;
  if not found then return jsonb_build_object('ok', false, 'message', 'Meal not found.'); end if;
  if a.option_of is null then return jsonb_build_object('ok', false, 'message', 'This meal is already the one in the plan.'); end if;
  select * into m from meal_plan_items where id = a.option_of for update;
  if m.batch_group is not null then
    return jsonb_build_object('ok', false, 'message', 'This meal is part of a leftovers cook-up. Remove the leftovers link before swapping it.');
  end if;
  update meal_plan_items set option_of = null, position = m.position where id = a.id;
  get diagnostics n = row_count;
  if n = 0 then return jsonb_build_object('ok', false, 'message', 'You can''t change this plan.'); end if;
  update meal_plan_items set option_of = a.id, position = a.position where id = m.id;
  update meal_plan_items set option_of = a.id where option_of = m.id and id <> a.id;
  update meal_plan_items set boosts_item_id = a.id where boosts_item_id = m.id;
  return jsonb_build_object('ok', true, 'message', 'Swapped.', 'item_id', a.id, 'previous_item_id', m.id);
end $$;

-- 3. the client app gets free-choice and empty slots -----------------------------------------------------------------
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
    'slot_states', coalesce(s -> 'slot_states', '[]'::jsonb),
    'week_average', case when v_num then s -> 'week_average' end,
    'shopping', coalesce(s -> 'shopping', '[]'::jsonb),
    'unresolved', coalesce(s -> 'unresolved', '[]'::jsonb));
end $$;

-- grants ---------------------------------------------------------------------------------------------------------------
revoke execute on function meal_plan_items_follow() from public, anon, authenticated;
revoke execute on function use_plan_alternative(uuid), my_plan_version(uuid, integer) from public, anon;
grant execute on function use_plan_alternative(uuid), my_plan_version(uuid, integer) to authenticated;
