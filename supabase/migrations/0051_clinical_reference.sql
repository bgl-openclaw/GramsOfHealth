-- 0051_clinical_reference.sql — home for the blood marker ranges and the meal plan logic (owner, 22 Oct 2026).
-- APPLIED live 22 Oct 2026 (apply_migration "0051_clinical_reference"); loaded with scripts/reference/import_reference.py;
-- clinical_reference_0051 and p0_lockdown pass live.
-- Source workbooks (prepared in another workstream, "these might change or be adjusted in time"):
--   marker_ranges_dietitian_decides.xlsx  → clinical_markers, marker_ranges, reference_sources
--   meal_plan_logic_dietitian_decides.xlsx → nutrient_reference_values, nutrition_targets, plan_rules,
--                                            reference_decisions, reference_sources
-- How it works
--   • Reference columns (the workbooks' green columns) arrive only through the importer
--     (scripts/reference/import_reference.py, service key). The app can't change them.
--   • Decision columns (the yellow ones) are set in the app: admins and dietitians decide; interns and other staff
--     may only write comments. Every change is stamped (who, when) and logged in reference_change_log.
--   • Nothing is active until decided: the active_* views return only rows a dietitian agreed to (or edited),
--     and only while the reference row is unchanged since that decision.
--   • Re-importing a newer workbook: unchanged rows keep their decision; changed rows keep it for reference but go
--     back to "changed" (inactive) until re-decided; rows no longer in the workbook are retired, never deleted.
-- Test: tests/sql/clinical_reference_0051.test.sql

-- 1. tables ------------------------------------------------------------------------------------------------------------
create table if not exists reference_imports (
  id          bigint generated always as identity primary key,
  workbook    text not null check (workbook in ('marker_ranges', 'meal_plan_logic')),
  file_name   text,
  summary     jsonb not null default '{}'::jsonb,
  imported_at timestamptz not null default now());

create table if not exists clinical_markers (
  id               uuid primary key default gen_random_uuid(),
  row_key          text not null unique,
  code             text not null unique check (code ~ '^[a-z0-9_]+$'),
  name             text not null,
  unit             text,
  category         text not null default 'bloods' check (category in ('bloods', 'dexa', 'other')),
  position         int,
  ref              jsonb not null default '{}'::jsonb,   -- the workbook's reference columns, as printed
  content_hash     text not null,
  -- decisions (Marker decisions tab)
  track            boolean,
  practice_range   text,
  refer_when       text,
  food_action      text,
  retest_window    text,
  variation_pct    text,
  practice_note    text,
  comments         text,
  review_state     text not null default 'proposed' check (review_state in ('proposed', 'decided', 'changed')),
  decided_by       uuid references profiles (id) on delete set null,
  decided_by_name  text,
  decided_at       timestamptz,
  change_reason    text,
  previous_ref     jsonb,
  retired_at       timestamptz,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now());

create table if not exists marker_ranges (
  id               uuid primary key default gen_random_uuid(),
  row_key          text not null unique,
  marker_code      text not null references clinical_markers (code) on update cascade,
  position         int,
  population       text not null,
  sex              text not null check (sex in ('any', 'male', 'female')),
  age_from_days    int,          -- inclusive; null = from birth
  age_to_days      int,          -- exclusive; null = no upper age
  pregnancy        boolean not null default false,
  unit             text,
  range_type       text not null,
  low              numeric,      -- parsed from the printed value when it is a plain number or a simple ≥/≤ limit
  high             numeric,
  low_text         text,         -- as printed
  high_text        text,
  is_gap           boolean not null default false,
  is_comparator    boolean not null default false,
  ref              jsonb not null default '{}'::jsonb,
  content_hash     text not null,
  -- decisions (Ranges by age tab)
  decision         text check (decision in ('agree', 'reject', 'edit')),
  practice_low     numeric,
  practice_high    numeric,
  dietitian_note   text,
  comments         text,
  review_state     text not null default 'proposed' check (review_state in ('proposed', 'decided', 'changed')),
  decided_by       uuid references profiles (id) on delete set null,
  decided_by_name  text,
  decided_at       timestamptz,
  change_reason    text,
  previous_ref     jsonb,
  retired_at       timestamptz,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  constraint marker_ranges_edit_values check (decision is distinct from 'edit' or practice_low is not null or practice_high is not null));
create index if not exists marker_ranges_marker on marker_ranges (marker_code);

create table if not exists nutrient_reference_values (
  id               uuid primary key default gen_random_uuid(),
  row_key          text not null unique,
  nutrient_code    text not null check (nutrient_code ~ '^[a-z0-9_]+$'),
  nutrient         text not null,
  position         int,
  unit             text,
  food_column      text,          -- foods column the plan check reads (null = not stored yet)
  life_stage       text not null,
  sex              text not null check (sex in ('any', 'male', 'female')),
  age_from_days    int,
  age_to_days      int,
  status           text not null check (status in ('general', 'pregnancy', 'lactation')),
  ear              numeric,
  rdi              numeric,
  ai               numeric,
  ul               numeric,
  sdt              numeric,
  ul_applies_to    text,
  ref              jsonb not null default '{}'::jsonb,
  content_hash     text not null,
  -- decisions (NRVs tab)
  decision         text check (decision in ('agree', 'reject', 'edit')),
  check_against    text check (check_against in ('ear', 'rdi', 'ai', 'sdt')),
  practice_target  numeric,
  practice_ceiling numeric,
  use_in_checks    boolean,
  comments         text,
  review_state     text not null default 'proposed' check (review_state in ('proposed', 'decided', 'changed')),
  decided_by       uuid references profiles (id) on delete set null,
  decided_by_name  text,
  decided_at       timestamptz,
  change_reason    text,
  previous_ref     jsonb,
  retired_at       timestamptz,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now());
create index if not exists nutrient_reference_values_code on nutrient_reference_values (nutrient_code);

create table if not exists nutrition_targets (
  id               uuid primary key default gen_random_uuid(),
  row_key          text not null unique,
  code             text not null,
  what             text not null,
  position         int,
  unit             text,
  life_stage       text,
  sex              text not null check (sex in ('any', 'male', 'female')),
  lower            numeric,
  upper            numeric,
  ref              jsonb not null default '{}'::jsonb,
  content_hash     text not null,
  -- decisions (Targets and ranges tab)
  decision         text check (decision in ('agree', 'reject', 'edit')),
  practice_lower   numeric,
  practice_upper   numeric,
  use_in_checks    boolean,
  comments         text,
  review_state     text not null default 'proposed' check (review_state in ('proposed', 'decided', 'changed')),
  decided_by       uuid references profiles (id) on delete set null,
  decided_by_name  text,
  decided_at       timestamptz,
  change_reason    text,
  previous_ref     jsonb,
  retired_at       timestamptz,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now());

create table if not exists plan_rules (
  id                uuid primary key default gen_random_uuid(),
  row_key           text not null unique,
  code              text not null unique check (code ~ '^[a-z0-9_]+$'),
  rule              text not null,
  position          int,
  ref               jsonb not null default '{}'::jsonb,
  content_hash      text not null,
  -- decisions (Plan rules tab)
  use_rule          boolean,
  practice_defaults text,
  when_to_offer     text,
  practice_note     text,
  comments          text,
  review_state      text not null default 'proposed' check (review_state in ('proposed', 'decided', 'changed')),
  decided_by        uuid references profiles (id) on delete set null,
  decided_by_name   text,
  decided_at        timestamptz,
  change_reason     text,
  previous_ref      jsonb,
  retired_at        timestamptz,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now());

create table if not exists reference_decisions (
  id               uuid primary key default gen_random_uuid(),
  row_key          text not null unique,   -- workbook|D1
  workbook         text not null check (workbook in ('marker_ranges', 'meal_plan_logic')),
  code             text not null,
  question         text not null,
  position         int,
  ref              jsonb not null default '{}'::jsonb,
  content_hash     text not null,
  -- decisions (Decisions tab)
  decision         text,
  settings         text,
  comments         text,
  review_state     text not null default 'proposed' check (review_state in ('proposed', 'decided', 'changed')),
  decided_by       uuid references profiles (id) on delete set null,
  decided_by_name  text,
  decided_at       timestamptz,
  change_reason    text,
  previous_ref     jsonb,
  retired_at       timestamptz,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now());

create table if not exists reference_sources (
  id             uuid primary key default gen_random_uuid(),
  row_key        text not null unique,   -- workbook|short name
  workbook       text not null check (workbook in ('marker_ranges', 'meal_plan_logic')),
  short_name     text not null,
  full_reference text,
  link           text,
  position       int,
  content_hash   text not null,
  retired_at     timestamptz,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now());

create table if not exists reference_change_log (
  id          bigint generated always as identity primary key,
  at          timestamptz not null default now(),
  by_id       uuid references profiles (id) on delete set null,
  by_name     text,
  table_name  text not null,
  row_key     text not null,
  field       text not null,
  old_value   text,
  new_value   text,
  reason      text,
  kind        text not null default 'decision' check (kind in ('decision', 'import', 'workbook')));
create index if not exists reference_change_log_row on reference_change_log (table_name, row_key, at desc);

comment on table marker_ranges is 'Blood marker ranges by population (from marker_ranges_dietitian_decides.xlsx). Inactive until a dietitian agrees or edits; see active_marker_ranges.';
comment on table nutrient_reference_values is 'NRVs by life stage (from meal_plan_logic_dietitian_decides.xlsx). Inactive until decided; see active_nutrient_reference_values.';

-- 2. guard: reference columns are import-only; decisions are stamped and logged ----------------------------------------
-- App users can't write the log directly; the guard writes it through this function, which refuses direct calls.
create or replace function reference_log_change(p_table text, p_row_key text, p_field text, p_old text, p_new text,
                                                p_reason text, p_by_name text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if pg_trigger_depth() < 1 then
    raise exception 'Only the reference guard writes the change log.';
  end if;
  insert into reference_change_log (by_id, by_name, table_name, row_key, field, old_value, new_value, reason, kind)
  values (auth.uid(), p_by_name, p_table, p_row_key, p_field, p_old, p_new, p_reason, 'decision');
end $$;

-- TG_ARGV: the decision columns app users may change on this table (comments is always allowed).
create or replace function reference_row_guard() returns trigger
language plpgsql set search_path = public as $$
declare
  v_allowed text[] := array(select unnest(tg_argv)) || array['comments', 'change_reason'];
  v_stamps  text[] := array['review_state', 'decided_by', 'decided_by_name', 'decided_at', 'updated_at'];
  v_old jsonb; v_new jsonb; k text; v_decided boolean := false; v_name text; v_role text;
begin
  if current_user not in ('authenticated', 'anon') then   -- the importer (service key) and migrations
    if tg_op = 'DELETE' then return old; end if;
    new.updated_at := now();
    return new;
  end if;
  if tg_op <> 'UPDATE' then
    raise exception 'Reference rows come from the workbook import.';
  end if;
  v_old := to_jsonb(old); v_new := to_jsonb(new);
  v_role := current_staff_role();
  v_name := (select coalesce(nullif(btrim(full_name), ''), email) from profiles where id = auth.uid());
  for k in select jsonb_object_keys(v_new) loop
    continue when k = any (v_stamps);
    if (v_new -> k) is distinct from (v_old -> k) then
      if not (k = any (v_allowed)) then
        raise exception 'Reference values come from the workbook. Record the practice''s own value in the practice columns instead.';
      end if;
      if k <> 'comments' and k <> 'change_reason' then
        if v_role not in ('admin', 'dietitian') then
          raise exception 'Only dietitians and admins can make these decisions. You can add a comment.';
        end if;
        v_decided := true;
      end if;
      if k <> 'change_reason' then
        perform reference_log_change(tg_table_name, old.row_key, k, v_old ->> k, v_new ->> k,
                                     nullif(btrim(new.change_reason), ''), v_name);
      end if;
    end if;
  end loop;
  -- stamps are the database's
  new.review_state := old.review_state; new.decided_by := old.decided_by;
  new.decided_by_name := old.decided_by_name; new.decided_at := old.decided_at;
  if v_decided then
    new.review_state := 'decided'; new.decided_by := auth.uid(); new.decided_by_name := v_name; new.decided_at := now();
  end if;
  new.updated_at := now();
  return new;
end $$;

drop trigger if exists clinical_markers_guard on clinical_markers;
create trigger clinical_markers_guard before insert or update or delete on clinical_markers for each row
  execute function reference_row_guard('track', 'practice_range', 'refer_when', 'food_action', 'retest_window', 'variation_pct', 'practice_note');
drop trigger if exists marker_ranges_guard on marker_ranges;
create trigger marker_ranges_guard before insert or update or delete on marker_ranges for each row
  execute function reference_row_guard('decision', 'practice_low', 'practice_high', 'dietitian_note');
drop trigger if exists nutrient_reference_values_guard on nutrient_reference_values;
create trigger nutrient_reference_values_guard before insert or update or delete on nutrient_reference_values for each row
  execute function reference_row_guard('decision', 'check_against', 'practice_target', 'practice_ceiling', 'use_in_checks');
drop trigger if exists nutrition_targets_guard on nutrition_targets;
create trigger nutrition_targets_guard before insert or update or delete on nutrition_targets for each row
  execute function reference_row_guard('decision', 'practice_lower', 'practice_upper', 'use_in_checks');
drop trigger if exists plan_rules_guard on plan_rules;
create trigger plan_rules_guard before insert or update or delete on plan_rules for each row
  execute function reference_row_guard('use_rule', 'practice_defaults', 'when_to_offer', 'practice_note');
drop trigger if exists reference_decisions_guard on reference_decisions;
create trigger reference_decisions_guard before insert or update or delete on reference_decisions for each row
  execute function reference_row_guard('decision', 'settings');

-- 3. access: staff read and update (the guard decides what); nobody in the app inserts or deletes ------------------------
do $$
declare t text;
begin
  foreach t in array array['clinical_markers', 'marker_ranges', 'nutrient_reference_values', 'nutrition_targets',
                           'plan_rules', 'reference_decisions'] loop
    execute format('alter table %I enable row level security', t);
    execute format('drop policy if exists %I on %I', t || '_staff_read', t);
    execute format('create policy %I on %I for select to authenticated using (is_staff())', t || '_staff_read', t);
    execute format('drop policy if exists %I on %I', t || '_staff_update', t);
    execute format('create policy %I on %I for update to authenticated using (is_staff()) with check (is_staff())', t || '_staff_update', t);
    execute format('revoke all on %I from anon', t);
  end loop;
  foreach t in array array['reference_sources', 'reference_change_log', 'reference_imports'] loop
    execute format('alter table %I enable row level security', t);
    execute format('drop policy if exists %I on %I', t || '_staff_read', t);
    execute format('create policy %I on %I for select to authenticated using (is_staff())', t || '_staff_read', t);
    execute format('revoke all on %I from anon', t);
  end loop;
end $$;
revoke insert, delete on clinical_markers, marker_ranges, nutrient_reference_values, nutrition_targets, plan_rules,
  reference_decisions, reference_sources, reference_change_log, reference_imports from authenticated;
revoke update on reference_sources, reference_change_log, reference_imports from authenticated;

-- 4. what the app may use: decided rows only -----------------------------------------------------------------------
create or replace view active_marker_ranges with (security_invoker = true) as
  select r.*,
         case when r.decision = 'edit' then r.practice_low else r.low end as effective_low,
         case when r.decision = 'edit' then r.practice_high else r.high end as effective_high
  from marker_ranges r join clinical_markers m on m.code = r.marker_code
  where r.retired_at is null and r.review_state = 'decided' and r.decision in ('agree', 'edit')
    and m.retired_at is null;

create or replace view active_nutrient_reference_values with (security_invoker = true) as
  select n.*,
         case when n.decision = 'edit' and n.practice_target is not null then n.practice_target
              else case n.check_against when 'ear' then n.ear when 'rdi' then n.rdi when 'ai' then n.ai when 'sdt' then n.sdt end
         end as effective_target,
         case when n.decision = 'edit' and n.practice_ceiling is not null then n.practice_ceiling
              when n.ul_applies_to = 'Total intake' then n.ul end as effective_ceiling
  from nutrient_reference_values n
  where n.retired_at is null and n.review_state = 'decided' and n.decision in ('agree', 'edit') and n.use_in_checks;

create or replace view active_nutrition_targets with (security_invoker = true) as
  select t.*,
         case when t.decision = 'edit' then t.practice_lower else t.lower end as effective_lower,
         case when t.decision = 'edit' then t.practice_upper else t.upper end as effective_upper
  from nutrition_targets t
  where t.retired_at is null and t.review_state = 'decided' and t.decision in ('agree', 'edit') and t.use_in_checks;

create or replace view active_plan_rules with (security_invoker = true) as
  select * from plan_rules where retired_at is null and review_state = 'decided' and use_rule;

-- progress per tab, for the review screen
create or replace view reference_review_progress with (security_invoker = true) as
  select 'markers' as tab, count(*) filter (where retired_at is null) as total,
         count(*) filter (where retired_at is null and review_state = 'decided') as decided,
         count(*) filter (where retired_at is null and review_state = 'changed') as changed from clinical_markers
  union all select 'ranges', count(*) filter (where retired_at is null), count(*) filter (where retired_at is null and review_state = 'decided'),
         count(*) filter (where retired_at is null and review_state = 'changed') from marker_ranges
  union all select 'nrvs', count(*) filter (where retired_at is null), count(*) filter (where retired_at is null and review_state = 'decided'),
         count(*) filter (where retired_at is null and review_state = 'changed') from nutrient_reference_values
  union all select 'targets', count(*) filter (where retired_at is null), count(*) filter (where retired_at is null and review_state = 'decided'),
         count(*) filter (where retired_at is null and review_state = 'changed') from nutrition_targets
  union all select 'plan_rules', count(*) filter (where retired_at is null), count(*) filter (where retired_at is null and review_state = 'decided'),
         count(*) filter (where retired_at is null and review_state = 'changed') from plan_rules
  union all select 'decisions', count(*) filter (where retired_at is null), count(*) filter (where retired_at is null and review_state = 'decided'),
         count(*) filter (where retired_at is null and review_state = 'changed') from reference_decisions;

revoke all on active_marker_ranges, active_nutrient_reference_values, active_nutrition_targets, active_plan_rules,
  reference_review_progress from anon;
grant select on active_marker_ranges, active_nutrient_reference_values, active_nutrition_targets, active_plan_rules,
  reference_review_progress to authenticated;
revoke execute on function reference_row_guard() from public, anon, authenticated;
revoke execute on function reference_log_change(text, text, text, text, text, text, text) from public, anon;
grant execute on function reference_log_change(text, text, text, text, text, text, text) to authenticated;
