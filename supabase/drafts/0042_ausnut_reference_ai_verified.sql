-- 0042_ausnut_reference_ai_verified.sql — AUSNUT G1b. DRAFT: apply only on "go G1", after 0041.
-- Nothing here touches food values. It adds:
--   1. read-only AUSNUT 2023 reference tables (staff read; loaded by scripts/ausnut/load_reference.py)
--   2. machine-owned "AI verified" state on foods (+ ausnut_key), separate from dietitian `verified`
--   3. the rule that clears AI verification when a person changes the numbers, the tags, or removes
--      dietitian verification (the import's own write keeps it: it sets ai_verified_at in the same
--      statement)
--   4. change-log summaries that carry a note passed in the session (goh.change_note), so every
--      import write names its AUSNUT key
--   5. recipe readiness counting a food as verified when verified OR ai_verified. recipe_verification
--      keeps `reasons` empty for those (status is keyed off it) and reports them in new columns.
--      client_recipe_screen is NOT changed: client screening stays on dietitian verification.
-- Tests: tests/sql/ausnut_g1.test.sql.

-- 1. reference tables -----------------------------------------------------------------------------
create table if not exists ausnut_classifications (
  code       text primary key check (code ~ '^[0-9]{2}([0-9]|[0-9]{3})?$'),
  group_name text not null,
  level      smallint not null check (level in (2, 3, 5))
);

create table if not exists ausnut_master (
  public_food_key          text primary key check (public_food_key ~ '^F[0-9]{6}$'),
  survey_id                text not null unique,
  food_name                text not null,
  derivation               text,
  classification_code      text,
  classification_name      text,
  specific_gravity         numeric,
  edible_portion           text,           -- mostly a fraction, sometimes text ("0.87 (skin removed)")
  discretionary            boolean,
  energy_kj                numeric,
  energy_kcal              numeric,        -- kJ (with fibre) / 4.184
  protein_g                numeric,
  fat_g                    numeric,
  carb_avail_with_sa_g     numeric,
  carb_avail_without_sa_g  numeric,        -- the one foods.carb_avail_100g uses (matches AFCD)
  sugars_g                 numeric,
  fibre_g                  numeric,
  satfat_g                 numeric,
  sodium_mg                numeric,
  potassium_mg             numeric,
  calcium_mg               numeric,
  iron_mg                  numeric,
  zinc_mg                  numeric,
  magnesium_mg             numeric,
  folate_dfe_ug            numeric,
  folate_total_ug          numeric,        -- the one foods.folate_100g uses (matches AFCD)
  vitamin_b12_ug           numeric,
  description              text
);

create table if not exists ausnut_measures (
  measure_id         integer primary key,
  public_food_key    text not null references ausnut_master (public_food_key),
  quantity           numeric not null,
  descriptor_1       text,
  descriptor_2       text,
  descriptor_3       text,
  descriptor_4_brand text,
  gram_amount        numeric not null check (gram_amount > 0),
  volume_ml          numeric,
  is_density         boolean not null,
  is_brand_pack      boolean not null,
  size_word          text,
  suggested_unit     text
);
create index if not exists ausnut_measures_key on ausnut_measures (public_food_key);

do $rls$
declare t text;
begin
  foreach t in array array['ausnut_classifications', 'ausnut_master', 'ausnut_measures'] loop
    execute format('alter table %I enable row level security', t);
    execute format('drop policy if exists %I on %I', t || '_staff_read', t);
    execute format('create policy %I on %I for select using (is_staff())', t || '_staff_read', t);
    -- read-only to the app: no write policy; the loader runs with the service role
    execute format('revoke all on %I from anon', t);
    execute format('revoke insert, update, delete, truncate on %I from authenticated', t);
  end loop;
end $rls$;

-- 2. foods: AUSNUT key + machine-owned AI verification ----------------------------------------------
alter table foods
  add column if not exists ausnut_key text references ausnut_master (public_food_key),
  add column if not exists ai_verified boolean not null default false,
  add column if not exists ai_verified_at timestamptz,
  add column if not exists ai_match_confidence text,
  add column if not exists ai_evidence text;
alter table foods drop constraint if exists foods_ai_match_confidence_check;
alter table foods add constraint foods_ai_match_confidence_check
  check (ai_match_confidence is null or ai_match_confidence in ('exact_key', 'agreed_list', 'high_match', 'checked_verified'));
-- AI verified always carries its evidence (and stays short: every screen loads foods with select *)
alter table foods drop constraint if exists foods_ai_verified_complete;
alter table foods add constraint foods_ai_verified_complete
  check (not ai_verified or (ai_verified_at is not null and ai_match_confidence is not null
                             and ausnut_key is not null and length(btrim(coalesce(ai_evidence, ''))) between 1 and 400));
create index if not exists foods_ausnut_key on foods (ausnut_key);

create or replace function food_field_label(k text) returns text
language sql immutable set search_path = public as $$
  select case k
    when 'energy_kcal_100g' then 'kcal/100 g'   when 'protein_100g' then 'protein/100 g'
    when 'fat_100g' then 'fat/100 g'            when 'carb_avail_100g' then 'carbs/100 g'
    when 'fibre_100g' then 'fibre/100 g'        when 'density_g_ml' then 'density (g/mL)'
    when 'display_name' then 'name'             when 'default_size' then 'default size'
    when 'protein_family' then 'protein family' when 'afcd_key' then 'AFCD key'
    when 'match_note' then 'match note'         when 'purchase_unit' then 'buy as'
    when 'ausnut_key' then 'AUSNUT key'         when 'ai_verified' then 'AI verified'
    when 'ai_verified_at' then 'AI verified at' when 'ai_match_confidence' then 'AI match'
    when 'ai_evidence' then 'AI evidence'
    else replace(replace(k, '_100g', '/100 g'), '_', ' ') end
$$;

-- 3. clearing rules ----------------------------------------------------------------------------------
-- Dietitian verification: unchanged (cleared when kcal / macros / fibre / density change).
-- AI verification: cleared when those numbers change, or when dietitian verification is removed,
-- unless the same statement (re)sets ai_verified_at — that is the import writing its own evidence.
create or replace function foods_auto_unverify() returns trigger
language plpgsql set search_path = public as $$
declare v_numbers boolean;
begin
  v_numbers := new.energy_kcal_100g is distinct from old.energy_kcal_100g
            or new.protein_100g     is distinct from old.protein_100g
            or new.fat_100g         is distinct from old.fat_100g
            or new.carb_avail_100g  is distinct from old.carb_avail_100g
            or new.fibre_100g       is distinct from old.fibre_100g
            or new.density_g_ml     is distinct from old.density_g_ml;
  if old.verified and new.verified and v_numbers then
    new.verified := false;
  end if;
  if new.ai_verified and new.ai_verified_at is not distinct from old.ai_verified_at
     and (v_numbers or (old.verified and not new.verified)) then
    new.ai_verified := false;
    new.ai_verified_at := null;
    new.ai_match_confidence := null;
    new.ai_evidence := null;
  end if;
  return new;
end $$;

-- tag changes clear both kinds of verification (as before for `verified`)
create or replace function food_tags_change_log() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_food text; v_name text; v_verified boolean; v_ai boolean; v_label text; v_tag uuid;
  v_note text := nullif(btrim(coalesce(current_setting('goh.change_note', true), '')), '');
begin
  v_food := coalesce(new.food_id, old.food_id);
  v_tag  := coalesce(new.tag_id, old.tag_id);
  select display_name, verified, ai_verified into v_name, v_verified, v_ai from foods where food_id = v_food;
  if v_name is null then return null; end if;
  select label into v_label from tags where id = v_tag;
  if v_verified or v_ai then
    perform set_config('goh.tag_unverify', v_food, true);
    update foods set verified = false, ai_verified = false, ai_verified_at = null,
                     ai_match_confidence = null, ai_evidence = null
     where food_id = v_food;
  end if;
  insert into change_log (entity, food_id, food_name, action, changes, summary, auto_unverified, changed_by)
  values ('food_tag', v_food, v_name, lower(tg_op), jsonb_build_object('tag', v_label),
          format('%s: %s %s', v_name, case when tg_op = 'INSERT' then 'tagged' else 'untagged' end, coalesce(v_label, '(tag)'))
            || case when v_verified then ' — verification removed (tags changed)'
                    when v_ai then ' — AI verification removed (tags changed)' else '' end
            || coalesce(' [' || v_note || ']', ''),
          coalesce(v_verified, false) or coalesce(v_ai, false), auth.uid());
  return null;
end $$;

-- 4. change-log summaries carry the session note ------------------------------------------------------
create or replace function foods_change_log() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  o jsonb; n jsonb; k text;
  diffs jsonb := '{}'::jsonb; parts text[] := '{}';
  engine_changed boolean; auto boolean; auto_ai boolean;
  v_note text := nullif(btrim(coalesce(current_setting('goh.change_note', true), '')), '');
  v_verif_keys text[] := array['verified', 'ai_verified', 'ai_verified_at', 'ai_match_confidence', 'ai_evidence'];
begin
  if tg_op = 'INSERT' then
    insert into change_log (entity, food_id, food_name, action, changes, summary, changed_by)
    values ('food', new.food_id, new.display_name, 'insert', to_jsonb(new),
            format('New food: %s (%s, %s)', new.display_name, new.source,
                   case when new.verified then 'verified' else 'unverified' end)
              || coalesce(' [' || v_note || ']', ''), auth.uid());
    return null;
  elsif tg_op = 'DELETE' then
    insert into change_log (entity, food_id, food_name, action, changes, summary, changed_by)
    values ('food', old.food_id, old.display_name, 'delete', to_jsonb(old),
            format('Deleted food: %s', old.display_name) || coalesce(' [' || v_note || ']', ''), auth.uid());
    return null;
  end if;

  -- the tag trigger already logged this un-verification
  if current_setting('goh.tag_unverify', true) = new.food_id then
    perform set_config('goh.tag_unverify', '', true);
    if (to_jsonb(new) - v_verif_keys) = (to_jsonb(old) - v_verif_keys) then return null; end if;
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
  auto_ai := old.ai_verified and not new.ai_verified and (engine_changed or (old.verified and not new.verified));
  insert into change_log (entity, food_id, food_name, action, changes, summary, auto_unverified, changed_by)
  values ('food', new.food_id, new.display_name, 'update', diffs,
          new.display_name || ': ' || array_to_string(parts, '; ')
            || case when auto then ' — verification removed (values changed)' else '' end
            || case when auto_ai then ' — AI verification removed' else '' end
            || coalesce(' [' || v_note || ']', ''),
          auto or auto_ai, auth.uid());
  return null;
end $$;

create or replace function unit_conversions_change_log() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_food text; v_name text; s text;
  v_note text := nullif(btrim(coalesce(current_setting('goh.change_note', true), '')), '');
begin
  v_food := coalesce(new.food_id, old.food_id);
  select display_name into v_name from foods where food_id = v_food;
  if v_name is null then return null; end if;            -- food itself being deleted: logged once there
  if tg_op = 'INSERT' then
    s := format('%s: added "%s" = %s g', v_name, new.unit, new.grams);
  elsif tg_op = 'DELETE' then
    s := format('%s: removed "%s" (%s g)', v_name, old.unit, old.grams);
  else
    if new.unit = old.unit and new.grams = old.grams then
      if new.estimated = old.estimated then return null; end if;
      s := format('%s: "%s" = %s g %s', v_name, new.unit, new.grams,
                  case when new.estimated then 'marked as an estimate' else 'confirmed (no longer an estimate)' end);
    else
      s := format('%s: "%s" %s g → "%s" %s g', v_name, old.unit, old.grams, new.unit, new.grams)
           || case when old.estimated and not new.estimated then ' (estimate replaced)' else '' end;
    end if;
  end if;
  insert into change_log (entity, food_id, food_name, action, changes, summary, changed_by)
  values ('unit_conversion', v_food, v_name, lower(tg_op),
          jsonb_build_object('old', case when tg_op <> 'INSERT' then to_jsonb(old) end,
                             'new', case when tg_op <> 'DELETE' then to_jsonb(new) end),
          s || coalesce(' [' || v_note || ']', ''), auth.uid());
  return null;
end $$;

-- 5. readiness views ---------------------------------------------------------------------------------
-- recipe_verification: a food counts when verified OR ai_verified. Columns appended at the end:
-- ai_verified_food_count, ai_verified_food_names (foods counted only through AI verification),
-- food_note ("3 foods AI verified, 1 unverified"). `reasons` and every existing column are unchanged.
create or replace view recipe_verification with (security_invoker = on) as
 WITH line_facts AS (
         SELECT lp.recipe_id,
            lp.food_id,
            COALESCE(lp.unit, 'no unit'::text) AS unit,
            lp.priced,
            lp.via_estimate,
            il."position",
            COALESCE(f.display_name, lp.food_id, 'unlinked ingredient'::text) AS food_name,
            COALESCE(f.verified, false) OR COALESCE(f.ai_verified, false) AS food_verified,
            NOT COALESCE(f.verified, false) AND COALESCE(f.ai_verified, false) AS food_ai_only
           FROM line_priceability lp
             JOIN ingredient_lines il ON il.id = lp.id
             LEFT JOIN foods f ON f.food_id = lp.food_id
        ), line_counts AS (
         SELECT line_facts.recipe_id,
            count(*) AS line_count,
            count(*) FILTER (WHERE NOT line_facts.priced) AS uncalculable_line_count,
            count(*) FILTER (WHERE line_facts.priced AND line_facts.via_estimate) AS estimated_line_count
           FROM line_facts
          GROUP BY line_facts.recipe_id
        ), unverified AS (
         SELECT x.recipe_id,
            array_agg(x.food_name ORDER BY x.first_pos, x.food_name) AS names
           FROM ( SELECT line_facts.recipe_id, line_facts.food_id, line_facts.food_name,
                    min(line_facts."position") AS first_pos
                   FROM line_facts
                  WHERE NOT line_facts.food_verified
                  GROUP BY line_facts.recipe_id, line_facts.food_id, line_facts.food_name) x
          GROUP BY x.recipe_id
        ), ai_only AS (
         SELECT x.recipe_id,
            array_agg(x.food_name ORDER BY x.first_pos, x.food_name) AS names
           FROM ( SELECT line_facts.recipe_id, line_facts.food_id, line_facts.food_name,
                    min(line_facts."position") AS first_pos
                   FROM line_facts
                  WHERE line_facts.food_ai_only
                  GROUP BY line_facts.recipe_id, line_facts.food_id, line_facts.food_name) x
          GROUP BY x.recipe_id
        ), uncalculable AS (
         SELECT x.recipe_id,
            array_agg(x.label ORDER BY x.first_pos, x.label) AS labels
           FROM ( SELECT line_facts.recipe_id,
                    ((line_facts.food_name || ' ('::text) || line_facts.unit) || ')'::text AS label,
                    min(line_facts."position") AS first_pos
                   FROM line_facts
                  WHERE NOT line_facts.priced
                  GROUP BY line_facts.recipe_id, (((line_facts.food_name || ' ('::text) || line_facts.unit) || ')'::text)) x
          GROUP BY x.recipe_id
        ), estimated AS (
         SELECT x.recipe_id,
            array_agg(x.label ORDER BY x.first_pos, x.label) AS labels
           FROM ( SELECT line_facts.recipe_id,
                    ((line_facts.food_name || ' ('::text) || line_facts.unit) || ')'::text AS label,
                    min(line_facts."position") AS first_pos
                   FROM line_facts
                  WHERE line_facts.priced AND line_facts.via_estimate
                  GROUP BY line_facts.recipe_id, (((line_facts.food_name || ' ('::text) || line_facts.unit) || ')'::text)) x
          GROUP BY x.recipe_id
        ), steps AS (
         SELECT method_steps.recipe_id,
            count(*) FILTER (WHERE btrim(method_steps.text) <> ''::text) AS step_count
           FROM method_steps
          GROUP BY method_steps.recipe_id
        ), base AS (
         SELECT r.id AS recipe_id,
            r.title,
            NOT (COALESCE(btrim(r.title), ''::text) = ''::text OR btrim(r.title) ~~* 'untitled recipe'::text) AS has_title,
            COALESCE(btrim(r.image_url_1), ''::text) <> ''::text OR COALESCE(btrim(r.image_url_2), ''::text) <> ''::text AS has_image,
            COALESCE(lc.line_count, 0::bigint)::integer AS line_count,
            COALESCE(st.step_count, 0::bigint)::integer AS step_count,
            COALESCE(uv.names, '{}'::text[]) AS unverified_food_names,
            COALESCE(lc.uncalculable_line_count, 0::bigint)::integer AS uncalculable_line_count,
            COALESCE(uc.labels, '{}'::text[]) AS uncalculable_ingredients,
            COALESCE(lc.estimated_line_count, 0::bigint)::integer AS estimated_line_count,
            COALESCE(es.labels, '{}'::text[]) AS estimated_ingredients,
            NULLIF(btrim(r.data_issue), ''::text) AS data_issue,
            so.signed_by_name,
            so.signed_at,
            COALESCE(ao.names, '{}'::text[]) AS ai_verified_food_names
           FROM recipes r
             LEFT JOIN line_counts lc ON lc.recipe_id = r.id
             LEFT JOIN unverified uv ON uv.recipe_id = r.id
             LEFT JOIN ai_only ao ON ao.recipe_id = r.id
             LEFT JOIN uncalculable uc ON uc.recipe_id = r.id
             LEFT JOIN estimated es ON es.recipe_id = r.id
             LEFT JOIN steps st ON st.recipe_id = r.id
             LEFT JOIN recipe_signoffs so ON so.recipe_id = r.id AND so.revoked_at IS NULL
        ), judged AS (
         SELECT b.recipe_id, b.title, b.has_title, b.has_image, b.line_count, b.step_count,
            b.unverified_food_names, b.uncalculable_line_count, b.uncalculable_ingredients,
            b.estimated_line_count, b.estimated_ingredients, b.data_issue, b.signed_by_name, b.signed_at,
            b.ai_verified_food_names,
            array_remove(ARRAY[
                CASE WHEN NOT b.has_title THEN 'no title'::text ELSE NULL::text END,
                CASE WHEN NOT b.has_image THEN 'no image'::text ELSE NULL::text END,
                CASE WHEN b.line_count = 0 THEN 'no ingredients'::text ELSE NULL::text END,
                CASE WHEN b.step_count = 0 THEN 'no method steps'::text ELSE NULL::text END,
                CASE WHEN cardinality(b.unverified_food_names) > 0 THEN format('%s unverified food%s: %s'::text, cardinality(b.unverified_food_names),
                    CASE WHEN cardinality(b.unverified_food_names) = 1 THEN ''::text ELSE 's'::text END, reason_list(b.unverified_food_names))
                    ELSE NULL::text END,
                CASE WHEN cardinality(b.uncalculable_ingredients) > 0 THEN format('%s ingredient%s can''t be calculated: %s'::text, cardinality(b.uncalculable_ingredients),
                    CASE WHEN cardinality(b.uncalculable_ingredients) = 1 THEN ''::text ELSE 's'::text END, reason_list(b.uncalculable_ingredients))
                    ELSE NULL::text END,
                CASE WHEN cardinality(b.estimated_ingredients) > 0 THEN format('%s ingredient%s an estimated weight: %s'::text, cardinality(b.estimated_ingredients),
                    CASE WHEN cardinality(b.estimated_ingredients) = 1 THEN ' uses'::text ELSE 's use'::text END, reason_list(b.estimated_ingredients))
                    ELSE NULL::text END,
                CASE WHEN b.data_issue IS NOT NULL THEN 'data issue flagged: '::text ||
                    CASE WHEN length(b.data_issue) > 80 THEN "left"(b.data_issue, 80) || '…'::text ELSE b.data_issue END
                    ELSE NULL::text END], NULL::text) AS reasons
           FROM base b
        )
 SELECT recipe_id,
    title,
        CASE
            WHEN cardinality(reasons) = 0 AND signed_at IS NOT NULL THEN 'dietitian_verified'::text
            WHEN cardinality(reasons) = 0 THEN 'ai_verified'::text
            ELSE 'needs_review'::text
        END AS status,
    cardinality(reasons) = 0 AS ai_verified,
    reasons,
    signed_at IS NOT NULL AND cardinality(reasons) > 0 AS signoff_on_hold,
    signed_by_name,
    signed_at,
    has_title,
    has_image,
    line_count,
    step_count,
    cardinality(unverified_food_names) AS unverified_food_count,
    unverified_food_names,
    uncalculable_line_count,
    uncalculable_ingredients,
    data_issue,
    estimated_line_count,
    estimated_ingredients,
    cardinality(ai_verified_food_names) AS ai_verified_food_count,
    ai_verified_food_names,
    NULLIF(concat_ws(', ',
        CASE WHEN cardinality(ai_verified_food_names) > 0 THEN format('%s food%s AI verified', cardinality(ai_verified_food_names),
             CASE WHEN cardinality(ai_verified_food_names) = 1 THEN '' ELSE 's' END) END,
        CASE WHEN cardinality(unverified_food_names) > 0 THEN format('%s unverified', cardinality(unverified_food_names)) END), '') AS food_note
   FROM judged;

create or replace view recipe_readiness with (security_invoker = on) as
 SELECT r.id AS recipe_id,
    r.title,
    count(lp.id) AS total_lines,
    count(*) FILTER (WHERE NOT lp.priced) AS unpriced_lines,
    count(DISTINCT il.food_id) FILTER (WHERE NOT (f.verified OR f.ai_verified)) AS unverified_foods,
    r.data_issue IS NOT NULL AND length(TRIM(BOTH FROM r.data_issue)) > 0 AS has_data_issue,
    count(*) FILTER (WHERE NOT lp.priced) = 0 AND count(DISTINCT il.food_id) FILTER (WHERE NOT (f.verified OR f.ai_verified)) = 0
      AND count(lp.id) > 0 AND (r.data_issue IS NULL OR length(TRIM(BOTH FROM r.data_issue)) = 0) AS ready
   FROM recipes r
     LEFT JOIN ingredient_lines il ON il.recipe_id = r.id
     LEFT JOIN line_priceability lp ON lp.id = il.id
     LEFT JOIN foods f ON f.food_id = il.food_id
  GROUP BY r.id, r.title, r.data_issue;

-- food_leverage: `verified` keeps meaning dietitian-verified (the app reads it); blocked_recipes now
-- counts a food as done when AI verified too; appended: ai_verified, awaiting_dietitian_recipes.
create or replace view food_leverage with (security_invoker = on) as
 SELECT f.food_id,
    f.display_name,
    f.verified,
    count(DISTINCT il.recipe_id) AS used_in_recipes,
        CASE WHEN f.verified OR f.ai_verified THEN 0::bigint ELSE count(DISTINCT il.recipe_id) END AS blocked_recipes,
    f.ai_verified,
        CASE WHEN f.verified THEN 0::bigint ELSE count(DISTINCT il.recipe_id) END AS awaiting_dietitian_recipes
   FROM foods f
     LEFT JOIN ingredient_lines il ON il.food_id = f.food_id
  GROUP BY f.food_id, f.display_name, f.verified, f.ai_verified;

create or replace view changes_to_review with (security_invoker = on) as
 SELECT cl.id,
    cl.entity,
    cl.food_id,
    COALESCE(f.display_name, cl.food_name) AS food_name,
    cl.action,
    cl.summary,
    cl.auto_unverified,
    cl.changed_at,
    cl.changed_by,
    COALESCE(NULLIF(btrim(p.full_name), ''::text), p.email, 'System / import'::text) AS changed_by_name,
    f.verified AS food_verified_now,
    cl.changes,
    f.ai_verified AS food_ai_verified_now
   FROM change_log cl
     LEFT JOIN foods f ON f.food_id = cl.food_id
     LEFT JOIN profiles p ON p.id = cl.changed_by
  WHERE cl.reviewed_at IS NULL;
