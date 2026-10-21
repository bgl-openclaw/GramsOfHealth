-- 0043_ausnut_apply.sql — AUSNUT G3/G4 machinery. DRAFT: apply only on "go", after 0041 + 0042.
-- The changeset is built offline (scripts/ausnut/build_changeset.py), uploaded into ausnut_changeset
-- and applied here one batch at a time, in ONE transaction per batch:
--   select ausnut_apply_batch('g3a', true);   -- dry run: everything rolls back, the report comes back
--   select ausnut_apply_batch('g3a', false);  -- real run
-- Each op re-checks its preconditions against the live row (e.g. "still unverified", "kcal unchanged
-- since the changeset was built"); a failed precondition SKIPS that op and says why. Any unexpected
-- error aborts the whole batch. Every write carries its note into change_log via goh.change_note.
-- Service role only: no app role can read or run any of this.

create table if not exists ausnut_changeset (
  id         bigint generated always as identity primary key,
  batch      text not null,
  seq        integer not null,
  op         text not null,
  food_id    text,
  args       jsonb not null default '{}'::jsonb,
  note       text,
  status     text not null default 'pending' check (status in ('pending', 'applied', 'skipped')),
  result     text,
  applied_at timestamptz,
  unique (batch, seq)
);
alter table ausnut_changeset enable row level security;          -- no policies: service role only
revoke all on ausnut_changeset from anon, authenticated;

-- The dietitians' queue ("Needs a dietitian"): one open row per food and kind.
create table if not exists ausnut_review_queue (
  id          bigint generated always as identity primary key,
  food_id     text not null references foods (food_id) on update cascade on delete cascade,
  kind        text not null check (kind in ('match', 'label', 'verified_check', 'urgent', 'proposal', 'hold')),
  reason      text not null,
  suggestion  jsonb,
  created_at  timestamptz not null default now(),
  resolved_at timestamptz,
  resolved_by uuid references profiles (id) on delete set null
);
create unique index if not exists ausnut_review_queue_open on ausnut_review_queue (food_id, kind) where resolved_at is null;
alter table ausnut_review_queue enable row level security;
drop policy if exists ausnut_review_queue_staff_read on ausnut_review_queue;
create policy ausnut_review_queue_staff_read on ausnut_review_queue for select using (is_staff());
drop policy if exists ausnut_review_queue_clinician_resolve on ausnut_review_queue;
create policy ausnut_review_queue_clinician_resolve on ausnut_review_queue for update using (is_clinician()) with check (is_clinician());
revoke all on ausnut_review_queue from anon;
revoke insert, delete, truncate on ausnut_review_queue from authenticated;

-- one op ---------------------------------------------------------------------------------------------
create or replace function ausnut_apply_op(p_op text, p_food text, a jsonb) returns text
language plpgsql security definer set search_path = public as $$
declare
  f foods%rowtype; k text; v jsonb; n int; v_to text; v_line uuid; v_rec uuid; v_pos int; v_sql text; v_sets text[] := '{}';
begin
  if p_op in ('set_food', 'add_conversion', 'confirm_conversion', 'fix_conversion', 'add_tag', 'remove_tag', 'set_default_size', 'set_purchase_unit', 'ai_verify', 'repoint', 'delete_food', 'queue') then
    select * into f from foods where food_id = p_food for update;
    if not found then return 'skipped: food not found'; end if;
  end if;

  -- preconditions shared by food ops: {"expect": {"verified": false, "energy_kcal_100g": 247, ...}}
  if a ? 'expect' then
    for k, v in select key, value from jsonb_each(a -> 'expect') loop
      if (to_jsonb(f) -> k) is distinct from v
         and not (jsonb_typeof(v) = 'number' and jsonb_typeof(to_jsonb(f) -> k) = 'number' and (to_jsonb(f) ->> k)::numeric = (v #>> '{}')::numeric) then
        return format('skipped: %s is now %s (expected %s)', k, coalesce(to_jsonb(f) ->> k, 'null'), coalesce(v #>> '{}', 'null'));
      end if;
    end loop;
  end if;

  case p_op
  when 'set_food' then
    -- {"set": {...}}; ai_verified_at may be given as "now"
    for k, v in select key, value from jsonb_each(a -> 'set') loop
      v_sets := v_sets || format('%I = %s', k,
        case when k = 'ai_verified_at' and v #>> '{}' = 'now' then 'clock_timestamp()'
             when jsonb_typeof(v) = 'null' then 'null'
             else format('(jsonb_populate_record(null::foods, %L::jsonb)).%I', jsonb_build_object(k, v)::text, k) end);
    end loop;
    execute format('update foods set %s where food_id = %L', array_to_string(v_sets, ', '), p_food);
    return 'applied';

  when 'ai_verify' then
    update foods set ausnut_key = a ->> 'ausnut_key', ai_verified = true, ai_verified_at = clock_timestamp(),
                     ai_match_confidence = a ->> 'confidence', ai_evidence = a ->> 'evidence'
     where food_id = p_food;
    return 'applied';

  when 'add_conversion' then
    if exists (select 1 from unit_conversions where food_id = p_food and unit = a ->> 'unit') then
      return 'skipped: measure already exists';
    end if;
    insert into unit_conversions (food_id, unit, grams, basis, estimated)
    values (p_food, a ->> 'unit', (a ->> 'grams')::numeric, a ->> 'basis', coalesce((a ->> 'estimated')::boolean, false));
    return 'applied';

  when 'confirm_conversion' then
    perform set_config('goh.uc_sync', 'on', true);       -- a machine confirmation, not a person editing grams
    update unit_conversions set estimated = false, basis = a ->> 'basis'
     where food_id = p_food and unit = a ->> 'unit' and estimated
       and abs(grams - (a ->> 'ausnut_grams')::numeric) <= 0.10 * (a ->> 'ausnut_grams')::numeric;
    get diagnostics n = row_count;
    perform set_config('goh.uc_sync', '', true);
    return case when n = 1 then 'applied' else 'skipped: not estimated or no longer within 10 %' end;

  when 'fix_conversion' then
    -- replace a placeholder measure: only while it still has the placeholder grams and is still an estimate
    if f.default_size is not null and a ->> 'unit' in ('each', f.default_size) then
      return 'skipped: measure is tied to the default size';
    end if;
    perform set_config('goh.uc_sync', 'on', true);       -- keep the estimated flag we set (no auto-confirm)
    update unit_conversions set grams = (a ->> 'grams')::numeric, estimated = (a ->> 'estimated')::boolean, basis = a ->> 'basis'
     where food_id = p_food and unit = a ->> 'unit' and estimated and grams = (a ->> 'expect_grams')::numeric;
    get diagnostics n = row_count;
    perform set_config('goh.uc_sync', '', true);
    return case when n = 1 then 'applied' else 'skipped: measure changed since the changeset was built' end;

  when 'add_tag' then
    insert into food_tags (food_id, tag_id) select p_food, id from tags where label = a ->> 'label'
    on conflict do nothing;
    get diagnostics n = row_count;
    return case when n = 1 then 'applied' else 'skipped: already tagged or unknown tag' end;

  when 'remove_tag' then
    delete from food_tags where food_id = p_food and tag_id = (select id from tags where label = a ->> 'label');
    get diagnostics n = row_count;
    return case when n = 1 then 'applied' else 'skipped: tag not present' end;

  when 'set_default_size' then
    if f.default_size is not null then return 'skipped: default size already set'; end if;
    if coalesce((a ->> 'allow_existing_each')::boolean, false) = false
       and exists (select 1 from unit_conversions where food_id = p_food and unit = 'each') then
      return 'skipped: food already has an each measure';
    end if;
    update foods set default_size = a ->> 'unit' where food_id = p_food;
    return 'applied';

  when 'set_purchase_unit' then
    if f.purchase_unit is not null then return 'skipped: buy-as already set'; end if;
    update foods set purchase_unit = a ->> 'unit' where food_id = p_food;
    return 'applied';

  when 'insert_food' then
    if exists (select 1 from foods where food_id = p_food) then return 'skipped: food_id already exists'; end if;
    -- only the columns given; everything else takes its column default
    v := (a -> 'row') || jsonb_build_object('food_id', p_food);
    select string_agg(quote_ident(key), ', ') into v_sql from jsonb_object_keys(v) key;
    execute format('insert into foods (%s) select %s from jsonb_populate_record(null::foods, %L::jsonb)', v_sql, v_sql, v::text);
    return 'applied';

  when 'repoint' then
    -- move every reference from p_food to the canonical food
    v_to := a ->> 'to';
    if not exists (select 1 from foods where food_id = v_to) then return 'skipped: canonical food missing'; end if;
    update ingredient_lines set food_id = v_to where food_id = p_food;
    insert into client_food_rules (client_id, food_id, rule, primary_only, note, added_by, created_at)
      select client_id, v_to, rule, primary_only, note, added_by, created_at from client_food_rules where food_id = p_food
      on conflict do nothing;
    delete from client_food_rules where food_id = p_food;
    update swap_suggestions set trigger_food_id = v_to where trigger_food_id = p_food;
    update swap_suggestions set suggestion_food_id = v_to where suggestion_food_id = p_food;
    insert into food_unit_exclusions select (jsonb_populate_record(null::food_unit_exclusions, to_jsonb(x) || jsonb_build_object('food_id', v_to))).*
      from food_unit_exclusions x where x.food_id = p_food on conflict do nothing;
    delete from food_unit_exclusions where food_id = p_food;
    return 'applied';

  when 'copy_conversion' then
    insert into unit_conversions (food_id, unit, grams, basis, estimated)
      select a ->> 'to', unit, grams, coalesce(basis, '') || ' (copied from ' || p_food || ')', estimated
        from unit_conversions where food_id = p_food and unit = a ->> 'unit'
      on conflict (food_id, unit) do nothing;
    get diagnostics n = row_count;
    return case when n = 1 then 'applied' else 'skipped: canonical already has it' end;

  when 'delete_food' then
    -- the FKs cascade, so check that nothing still points here before deleting
    if exists (select 1 from ingredient_lines where food_id = p_food)
       or exists (select 1 from client_food_rules where food_id = p_food)
       or exists (select 1 from swap_suggestions where p_food in (trigger_food_id, suggestion_food_id))
       or exists (select 1 from food_unit_exclusions where food_id = p_food) then
      raise exception 'delete_food %: still referenced', p_food;          -- never silently cascade
    end if;
    if f.verified then raise exception 'delete_food %: verified food', p_food; end if;
    delete from foods where food_id = p_food;
    return 'applied';

  when 'update_line' then
    v_line := (a ->> 'line_id')::uuid;
    if not exists (select 1 from ingredient_lines where id = v_line and food_id = a ->> 'expect_food'
                   and abs(quantity - (a ->> 'expect_quantity')::numeric) < 0.000001 and unit = a ->> 'expect_unit') then
      return 'skipped: line changed since the changeset was built';
    end if;
    update ingredient_lines set
      quantity  = coalesce((a -> 'set' ->> 'quantity')::numeric, quantity),
      unit      = coalesce(a -> 'set' ->> 'unit', unit),
      prep_note = case when a -> 'set' ? 'prep_note' then a -> 'set' ->> 'prep_note' else prep_note end
     where id = v_line;
    return 'applied';

  when 'delete_line' then
    v_line := (a ->> 'line_id')::uuid;
    delete from ingredient_lines where id = v_line and food_id = a ->> 'expect_food'
       and abs(quantity - (a ->> 'expect_quantity')::numeric) < 0.000001 and unit = a ->> 'expect_unit';
    get diagnostics n = row_count;
    return case when n = 1 then 'applied' else 'skipped: line changed since the changeset was built' end;

  when 'split_line' then
    -- one combined line ("salt & pepper") becomes one line per part, in the same place:
    -- {"line_id", "expect_food", "expect_quantity", "expect_unit", "parts": [{"food_id", "quantity"}, ...]}
    v_line := (a ->> 'line_id')::uuid;
    select recipe_id, position into v_rec, v_pos from ingredient_lines
     where id = v_line and food_id = a ->> 'expect_food'
       and abs(quantity - (a ->> 'expect_quantity')::numeric) < 0.000001 and unit = a ->> 'expect_unit';
    if not found then return 'skipped: line changed since the changeset was built'; end if;
    if exists (select 1 from jsonb_array_elements(a -> 'parts') as x(val) where not exists (select 1 from foods where food_id = x.val ->> 'food_id')) then
      return 'skipped: a part food is missing';
    end if;
    n := jsonb_array_length(a -> 'parts') - 1;
    update ingredient_lines set position = position + n where recipe_id = v_rec and position > v_pos;
    update ingredient_lines set food_id = a -> 'parts' -> 0 ->> 'food_id', quantity = (a -> 'parts' -> 0 ->> 'quantity')::numeric where id = v_line;
    insert into ingredient_lines (recipe_id, food_id, section, position, quantity, unit, prep_note)
      select v_rec, x.val ->> 'food_id', il.section, v_pos + x.i - 1, (x.val ->> 'quantity')::numeric, il.unit, il.prep_note
        from jsonb_array_elements(a -> 'parts') with ordinality as x(val, i), ingredient_lines il
       where il.id = v_line and x.i > 1;
    return 'applied';

  when 'insert_line' then
    v_rec := (a ->> 'recipe_id')::uuid;
    if not exists (select 1 from foods where food_id = p_food) then return 'skipped: food not found'; end if;
    if exists (select 1 from ingredient_lines where recipe_id = v_rec and food_id = p_food) then
      return 'skipped: recipe already has this food';
    end if;
    select coalesce(max(position), -1) + 1 into v_pos from ingredient_lines where recipe_id = v_rec;
    insert into ingredient_lines (recipe_id, food_id, position, quantity, unit, prep_note)
    values (v_rec, p_food, v_pos, (a ->> 'quantity')::numeric, a ->> 'unit', a ->> 'prep_note');
    return 'applied';

  when 'set_recipe_issue' then
    update recipes set data_issue = a ->> 'data_issue'
     where id = (a ->> 'recipe_id')::uuid and coalesce(data_issue, '') = coalesce(a ->> 'expect_issue', '');
    get diagnostics n = row_count;
    return case when n = 1 then 'applied' else 'skipped: data issue changed since the changeset was built' end;

  when 'queue' then
    insert into ausnut_review_queue (food_id, kind, reason, suggestion)
    values (p_food, a ->> 'kind', a ->> 'reason', a -> 'suggestion')
    on conflict (food_id, kind) where resolved_at is null do update set reason = excluded.reason, suggestion = excluded.suggestion;
    return 'applied';

  else
    raise exception 'unknown op %', p_op;
  end case;
end $$;

-- one batch, one transaction ---------------------------------------------------------------------------
create or replace function ausnut_apply_batch(p_batch text, p_dry_run boolean default true) returns jsonb
language plpgsql security definer set search_path = public set statement_timeout = '300s' as $$
declare r record; v_msg text; rows jsonb := '[]'::jsonb; applied int := 0; skipped int := 0;
begin
  begin
    for r in select * from ausnut_changeset where batch = p_batch and status = 'pending' order by seq loop
      perform set_config('goh.change_note', coalesce(r.note, ''), true);
      v_msg := ausnut_apply_op(r.op, r.food_id, r.args);
      if v_msg like 'skipped%' then skipped := skipped + 1; else applied := applied + 1; end if;
      if v_msg like 'skipped%' or p_dry_run then
        rows := rows || jsonb_build_object('seq', r.seq, 'op', r.op, 'food_id', r.food_id, 'result', v_msg);
      end if;
      if not p_dry_run then
        update ausnut_changeset set status = case when v_msg like 'skipped%' then 'skipped' else 'applied' end,
               result = v_msg, applied_at = now() where id = r.id;
      end if;
    end loop;
    perform set_config('goh.change_note', '', true);
    if p_dry_run then raise exception 'AUSNUT_DRY_RUN'; end if;
  exception when others then
    if sqlerrm = 'AUSNUT_DRY_RUN' then
      return jsonb_build_object('batch', p_batch, 'dry_run', true, 'applied', applied, 'skipped', skipped, 'rows', rows);
    end if;
    raise;                                                  -- a real error: the whole batch rolls back
  end;
  return jsonb_build_object('batch', p_batch, 'dry_run', false, 'applied', applied, 'skipped', skipped, 'skipped_rows', rows);
end $$;

revoke execute on function ausnut_apply_op(text, text, jsonb), ausnut_apply_batch(text, boolean) from public, anon, authenticated;
