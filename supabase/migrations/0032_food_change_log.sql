-- 0032_food_change_log.sql — "nothing changes silently" for the foods library.
--
-- Owner decisions (2026-10-15):
--   * every new food, food edit/delete, unit conversion change and food tag
--     change is logged with who / when / old → new, whatever made it (app,
--     importer, scripts) — database triggers, so nothing slips through;
--   * dietitians + admins see unreviewed changes in an inbox and mark them reviewed;
--   * a VERIFIED food whose nutrition values (kcal/protein/fat/carbs/fibre per
--     100 g), density or allergen/diet tags change becomes UNVERIFIED until a
--     dietitian re-checks it. Only ever true → false; nothing here sets verified = true.
--   * unit conversions / default sizes are logged for review but don't un-verify.
-- Cascade noise is suppressed: deleting a food logs one "Deleted food" entry,
-- not one per conversion/tag.
-- Idempotent.

create table if not exists change_log (
  id bigint generated always as identity primary key,
  entity text not null check (entity in ('food', 'unit_conversion', 'food_tag')),
  food_id text not null,
  food_name text,
  action text not null check (action in ('insert', 'update', 'delete')),
  changes jsonb not null default '{}'::jsonb,
  summary text not null,
  auto_unverified boolean not null default false,
  changed_by uuid references profiles(id) on delete set null,
  changed_at timestamptz not null default now(),
  reviewed_at timestamptz,
  reviewed_by uuid references profiles(id) on delete set null);
create index if not exists change_log_unreviewed on change_log (changed_at desc) where reviewed_at is null;
create index if not exists change_log_food on change_log (food_id, changed_at desc);

alter table change_log enable row level security;
drop policy if exists change_log_read on change_log;
create policy change_log_read on change_log for select to authenticated using (is_clinician());
revoke all on change_log from anon;
revoke insert, update, delete, truncate on change_log from authenticated;   -- written only by triggers / the RPC

-- Plain-words helpers ----------------------------------------------------------
create or replace function change_log_fmt(v jsonb) returns text
language sql immutable set search_path = public as $$
  select case
    when v is null or v = 'null'::jsonb then '—'
    when jsonb_typeof(v) = 'boolean' then case when v = 'true'::jsonb then 'yes' else 'no' end
    when jsonb_typeof(v) = 'string' then left(v #>> '{}', 60)
    else v::text end
$$;

create or replace function food_field_label(k text) returns text
language sql immutable set search_path = public as $$
  select case k
    when 'energy_kcal_100g' then 'kcal/100 g'   when 'protein_100g' then 'protein/100 g'
    when 'fat_100g' then 'fat/100 g'            when 'carb_avail_100g' then 'carbs/100 g'
    when 'fibre_100g' then 'fibre/100 g'        when 'density_g_ml' then 'density (g/mL)'
    when 'display_name' then 'name'             when 'default_size' then 'default size'
    when 'protein_family' then 'protein family' when 'afcd_key' then 'AFCD key'
    when 'match_note' then 'match note'
    else replace(replace(k, '_100g', '/100 g'), '_', ' ') end
$$;

-- 1. Auto-unverify (BEFORE UPDATE on foods) --------------------------------------
create or replace function foods_auto_unverify() returns trigger
language plpgsql set search_path = public as $$
begin
  if old.verified and new.verified and (
       new.energy_kcal_100g is distinct from old.energy_kcal_100g
    or new.protein_100g     is distinct from old.protein_100g
    or new.fat_100g         is distinct from old.fat_100g
    or new.carb_avail_100g  is distinct from old.carb_avail_100g
    or new.fibre_100g       is distinct from old.fibre_100g
    or new.density_g_ml     is distinct from old.density_g_ml) then
    new.verified := false;
  end if;
  return new;
end $$;

drop trigger if exists foods_auto_unverify on foods;
create trigger foods_auto_unverify before update on foods
  for each row execute function foods_auto_unverify();

-- 2. Food log (AFTER INSERT/UPDATE/DELETE on foods) ----------------------------------
create or replace function foods_change_log() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  o jsonb; n jsonb; k text;
  diffs jsonb := '{}'::jsonb; parts text[] := '{}';
  engine_changed boolean; auto boolean;
begin
  if tg_op = 'INSERT' then
    insert into change_log (entity, food_id, food_name, action, changes, summary, changed_by)
    values ('food', new.food_id, new.display_name, 'insert', to_jsonb(new),
            format('New food: %s (%s, %s)', new.display_name, new.source,
                   case when new.verified then 'verified' else 'unverified' end), auth.uid());
    return null;
  elsif tg_op = 'DELETE' then
    insert into change_log (entity, food_id, food_name, action, changes, summary, changed_by)
    values ('food', old.food_id, old.display_name, 'delete', to_jsonb(old),
            format('Deleted food: %s', old.display_name), auth.uid());
    return null;
  end if;

  -- An un-verify caused by a tag change is logged on the tag entry instead.
  if current_setting('goh.tag_unverify', true) = new.food_id then
    perform set_config('goh.tag_unverify', '', true);
    if (to_jsonb(new) - 'verified') = (to_jsonb(old) - 'verified') then return null; end if;
  end if;

  o := to_jsonb(old); n := to_jsonb(new);
  for k in select jsonb_object_keys(n) loop
    if o->k is distinct from n->k then
      diffs := diffs || jsonb_build_object(k, jsonb_build_object('old', o->k, 'new', n->k));
      parts := parts || format('%s %s → %s', food_field_label(k), change_log_fmt(o->k), change_log_fmt(n->k));
    end if;
  end loop;
  if diffs = '{}'::jsonb then return null; end if;

  engine_changed := diffs ?| array['energy_kcal_100g', 'protein_100g', 'fat_100g', 'carb_avail_100g', 'fibre_100g', 'density_g_ml'];
  auto := old.verified and not new.verified and engine_changed;
  insert into change_log (entity, food_id, food_name, action, changes, summary, auto_unverified, changed_by)
  values ('food', new.food_id, new.display_name, 'update', diffs,
          new.display_name || ': ' || array_to_string(parts, '; ')
            || case when auto then ' — verification removed (values changed)' else '' end,
          auto, auth.uid());
  return null;
end $$;

drop trigger if exists foods_change_log on foods;
create trigger foods_change_log after insert or update or delete on foods
  for each row execute function foods_change_log();

-- 3. Unit conversion log (no un-verify) ----------------------------------------------
create or replace function unit_conversions_change_log() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_food text; v_name text; s text;
begin
  v_food := coalesce(new.food_id, old.food_id);
  select display_name into v_name from foods where food_id = v_food;
  if v_name is null then return null; end if;            -- food itself being deleted: logged once there
  if tg_op = 'INSERT' then
    s := format('%s: added "%s" = %s g', v_name, new.unit, new.grams);
  elsif tg_op = 'DELETE' then
    s := format('%s: removed "%s" (%s g)', v_name, old.unit, old.grams);
  else
    if new.unit = old.unit and new.grams = old.grams then return null; end if;
    s := format('%s: "%s" %s g → "%s" %s g', v_name, old.unit, old.grams, new.unit, new.grams);
  end if;
  insert into change_log (entity, food_id, food_name, action, changes, summary, changed_by)
  values ('unit_conversion', v_food, v_name, lower(tg_op),
          jsonb_build_object('old', case when tg_op <> 'INSERT' then to_jsonb(old) end,
                             'new', case when tg_op <> 'DELETE' then to_jsonb(new) end),
          s, auth.uid());
  return null;
end $$;

drop trigger if exists unit_conversions_change_log on unit_conversions;
create trigger unit_conversions_change_log after insert or update or delete on unit_conversions
  for each row execute function unit_conversions_change_log();

-- 4. Food tag log + un-verify ------------------------------------------------------
create or replace function food_tags_change_log() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_food text; v_name text; v_verified boolean; v_label text; v_tag uuid;
begin
  v_food := coalesce(new.food_id, old.food_id);
  v_tag  := coalesce(new.tag_id, old.tag_id);
  select display_name, verified into v_name, v_verified from foods where food_id = v_food;
  if v_name is null then return null; end if;            -- food being deleted
  select label into v_label from tags where id = v_tag;
  if v_verified then
    perform set_config('goh.tag_unverify', v_food, true);
    update foods set verified = false where food_id = v_food;
  end if;
  insert into change_log (entity, food_id, food_name, action, changes, summary, auto_unverified, changed_by)
  values ('food_tag', v_food, v_name, lower(tg_op), jsonb_build_object('tag', v_label),
          format('%s: %s %s', v_name, case when tg_op = 'INSERT' then 'tagged' else 'untagged' end, coalesce(v_label, '(tag)'))
            || case when v_verified then ' — verification removed (tags changed)' else '' end,
          coalesce(v_verified, false), auth.uid());
  return null;
end $$;

drop trigger if exists food_tags_change_log on food_tags;
create trigger food_tags_change_log after insert or delete on food_tags
  for each row execute function food_tags_change_log();

-- 5. Inbox + mark reviewed ----------------------------------------------------------
create or replace view changes_to_review with (security_invoker = on) as
select cl.id, cl.entity, cl.food_id, coalesce(f.display_name, cl.food_name) as food_name,
       cl.action, cl.summary, cl.auto_unverified, cl.changed_at, cl.changed_by,
       coalesce(nullif(btrim(p.full_name), ''), p.email, 'System / import') as changed_by_name,
       f.verified as food_verified_now, cl.changes
from change_log cl
left join foods f on f.food_id = cl.food_id
left join profiles p on p.id = cl.changed_by
where cl.reviewed_at is null;

revoke all on changes_to_review from anon;
grant select on changes_to_review to authenticated;

create or replace function mark_changes_reviewed(p_ids bigint[] default null) returns int
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if not is_clinician() then raise exception 'Only dietitians can mark changes reviewed'; end if;
  update change_log set reviewed_at = now(), reviewed_by = auth.uid()
   where reviewed_at is null and (p_ids is null or id = any(p_ids));
  get diagnostics n = row_count;
  return n;
end $$;

revoke execute on function mark_changes_reviewed(bigint[]) from public, anon;
grant execute on function mark_changes_reviewed(bigint[]) to authenticated;
revoke execute on function foods_change_log(), unit_conversions_change_log(), food_tags_change_log() from public, anon, authenticated;
