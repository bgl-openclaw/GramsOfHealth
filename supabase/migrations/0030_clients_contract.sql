-- 0030_clients_contract.sql  (Clients roadmap C3 — database contract for Lovable)
--
--   line_grams               read-model replica of packages/engine toGrams (null = unresolvable)
--   recipe_protein_families  recipe → protein family grams (from dietitian-set foods.protein_family)
--   client_recipe_screen()   per-client recipe status: blocked | unconfirmed | disliked | ok, with reasons
--   save_client_structure()  one-transaction save of a client's structure section
--   client_overview          one row per client for the clients list
--   client_targets           calculator-accepted rows must carry the core working keys
-- All SECURITY INVOKER (callers see only what RLS allows). Engine untouched.
-- Idempotent.

-- 1. Grams per ingredient line (mirrors packages/engine toGrams exactly) --------
create or replace view line_grams with (security_invoker = on) as
select il.id, il.recipe_id, il.food_id, il.quantity, il.unit,
  case
    when il.unit in ('g', 'gram', 'grams') then il.quantity
    when il.unit = 'kg' then il.quantity * 1000
    when il.unit = 'x95g' then il.quantity * 95
    when il.unit in ('tsp', 'tbsp', 'cup', 'ml') then
      case
        when f.density_g_ml is not null and f.density_g_ml <> 0 then
          il.quantity * (case il.unit when 'tsp' then 5 when 'tbsp' then 20 when 'cup' then 250 else 1 end) * f.density_g_ml
        else il.quantity * uc.grams
      end
    else il.quantity * uc.grams
  end as grams
from ingredient_lines il
left join foods f on f.food_id = il.food_id
left join unit_conversions uc on uc.food_id = il.food_id and uc.unit = il.unit;

-- 2. Recipe protein families -----------------------------------------------------
create or replace view recipe_protein_families with (security_invoker = on) as
select lg.recipe_id, f.protein_family, pf.label as protein_family_label,
       sum(lg.grams) as grams,
       rank() over (partition by lg.recipe_id order by sum(lg.grams) desc nulls last) = 1 as is_main
from line_grams lg
join foods f on f.food_id = lg.food_id
join protein_families pf on pf.key = f.protein_family
group by lg.recipe_id, f.protein_family, pf.label;

-- 3. Per-client recipe screen ------------------------------------------------------
-- Status precedence: blocked (contains a blocked tag, or an "avoid" food)
--   > unconfirmed (client has allergen/diet requirements and the recipe has
--     unverified ingredients, so its "contains" tags can't be trusted)
--   > disliked (disliked food — or, with primary_only, ≥10% of recipe weight —
--     or main protein family the client dislikes)
--   > ok.
create or replace function client_recipe_screen(p_client_id uuid)
returns table (
  recipe_id uuid, status text, reasons text[],
  preferred_tags text[], main_protein_families text[],
  liked_protein boolean)
language sql stable security invoker set search_path = public as $$
  with access as (select can_access_client(p_client_id) as ok),
  blocked as (
    select ret.recipe_id,
           array_agg(distinct case when cbt.because_tag_id = cbt.blocked_tag_id
                                   then 'contains ' || cbt.blocked_label
                                   else 'contains ' || cbt.blocked_label || ' (' || cbt.because_label || ')' end) as reasons
    from client_blocked_tags cbt
    join recipe_effective_tags ret on ret.tag_id = cbt.blocked_tag_id
    where cbt.client_id = p_client_id
    group by ret.recipe_id),
  has_screen as (select exists (select 1 from client_blocked_tags where client_id = p_client_id) as yes),
  totals as (select recipe_id, sum(grams) as total_g from line_grams group by recipe_id),
  food_hits as (
    select lg.recipe_id, fr.rule, fr.primary_only, f.display_name,
           case when t.total_g > 0 then sum(lg.grams) / t.total_g end as share
    from line_grams lg
    join client_food_rules fr on fr.client_id = p_client_id and fr.food_id = lg.food_id
    join foods f on f.food_id = lg.food_id
    join totals t on t.recipe_id = lg.recipe_id
    group by lg.recipe_id, fr.rule, fr.primary_only, f.display_name, t.total_g),
  avoided as (
    select recipe_id, array_agg('contains avoided food: ' || display_name order by display_name) as reasons
    from food_hits where rule = 'avoid' group by recipe_id),
  disliked as (
    select recipe_id,
           array_agg(case when primary_only
                          then 'disliked food is a main ingredient: ' || display_name || ' (' || round(share * 100) || '%)'
                          else 'contains disliked food: ' || display_name end order by display_name) as reasons
    from food_hits
    where rule = 'dislike' and (not primary_only or coalesce(share, 0) >= 0.10)
    group by recipe_id),
  unverified as (
    select il.recipe_id, array_agg(distinct f.display_name order by f.display_name) as names
    from ingredient_lines il join foods f on f.food_id = il.food_id
    where not f.verified
    group by il.recipe_id),
  mains as (
    select rpf.recipe_id, array_agg(rpf.protein_family order by rpf.protein_family) as families,
           bool_or(cpp.preference = 'like') as liked,
           array_agg('disliked protein: ' || rpf.protein_family_label order by rpf.protein_family_label)
             filter (where cpp.preference = 'dislike') as disliked_reasons
    from recipe_protein_families rpf
    left join client_protein_preferences cpp on cpp.client_id = p_client_id and cpp.protein_family = rpf.protein_family
    where rpf.is_main
    group by rpf.recipe_id),
  preferred as (
    select ret.recipe_id, array_agg(cpt.label order by cpt.label) as labels
    from client_preferred_tags cpt
    join recipe_effective_tags ret on ret.tag_id = cpt.tag_id
    where cpt.client_id = p_client_id
    group by ret.recipe_id)
  select r.id,
         case
           when b.reasons is not null or a.reasons is not null then 'blocked'
           when hs.yes and u.names is not null then 'unconfirmed'
           when d.reasons is not null or m.disliked_reasons is not null then 'disliked'
           else 'ok'
         end,
         coalesce(b.reasons, '{}') || coalesce(a.reasons, '{}')
           || case when hs.yes and u.names is not null
                   then array[format('screen unconfirmed — %s unverified ingredient%s: %s',
                                     cardinality(u.names), case when cardinality(u.names) = 1 then '' else 's' end,
                                     reason_list(u.names))]
                   else '{}'::text[] end
           || coalesce(d.reasons, '{}') || coalesce(m.disliked_reasons, '{}'),
         coalesce(p.labels, '{}'),
         coalesce(m.families, '{}'),
         coalesce(m.liked, false)
  from recipes r
  cross join access ac
  cross join has_screen hs
  left join blocked b on b.recipe_id = r.id
  left join avoided a on a.recipe_id = r.id
  left join disliked d on d.recipe_id = r.id
  left join unverified u on u.recipe_id = r.id
  left join mains m on m.recipe_id = r.id
  left join preferred p on p.recipe_id = r.id
  where ac.ok;
$$;

-- 4. One-transaction save of the Structure section -----------------------------------
-- p_settings: {cycle_length_days, repeat_min_gap_days, repeat_max_per_cycle, batch_cooking, day_type_pattern[7]}
-- p_slots:    [{name, slot_kind, time_of_day ("HH:MM" or null), free_choice}]  (order = position)
-- p_protein_spread: [{protein_family, count_per_cycle}]
-- A null argument leaves that part unchanged. Any invalid value aborts the whole save.
create or replace function save_client_structure(
  p_client_id uuid, p_settings jsonb, p_slots jsonb, p_protein_spread jsonb)
returns void
language plpgsql security invoker set search_path = public as $$
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
    insert into client_meal_slots (client_id, position, name, slot_kind, time_of_day, free_choice)
    select p_client_id, (i - 1)::int, btrim(s->>'name'), s->>'slot_kind',
           nullif(s->>'time_of_day', '')::time, coalesce((s->>'free_choice')::boolean, false)
    from jsonb_array_elements(p_slots) with ordinality t(s, i);
  end if;

  if p_protein_spread is not null then
    delete from client_protein_spread where client_id = p_client_id;
    insert into client_protein_spread (client_id, protein_family, count_per_cycle)
    select p_client_id, s->>'protein_family', (s->>'count_per_cycle')::int
    from jsonb_array_elements(p_protein_spread) t(s);
  end if;
end $$;

-- 5. Clients list ------------------------------------------------------------------
create or replace view client_overview with (security_invoker = on) as
select c.id as client_id, c.full_name, c.status,
       c.assigned_dietitian, coalesce(nullif(btrim(pr.full_name), ''), pr.email) as assigned_dietitian_name,
       g.goal_type as primary_goal, gt.label as primary_goal_label,
       w.weight_kg as latest_weight_kg, w.recorded_on as latest_weight_on,
       ck.checkin_on as latest_checkin_on,
       t.kcal as default_kcal,
       (select count(*) from meal_plans mp where mp.client_id = c.id)::int as plan_count
from clients c
left join profiles pr on pr.id = c.assigned_dietitian
left join client_goals g on g.client_id = c.id and g.is_primary and g.ended_on is null
left join goal_types gt on gt.key = g.goal_type
left join lateral (select cw.weight_kg, cw.recorded_on from client_weights cw
                   where cw.client_id = c.id order by cw.recorded_on desc, cw.created_at desc limit 1) w on true
left join lateral (select cc.checkin_on from client_checkins cc
                   where cc.client_id = c.id order by cc.checkin_on desc limit 1) ck on true
left join client_current_targets t on t.client_id = c.id and t.day_type = 'default';

-- 6. Calculator-accepted targets must carry the core working ---------------------------
alter table client_targets drop constraint if exists client_targets_calc_snapshot;
alter table client_targets add constraint client_targets_calc_snapshot check (
  source <> 'calculator_accepted'
  or (calc_inputs is not null
      and calc_inputs ?& array['as_of', 'weight_kg', 'height_cm', 'age_years', 'sex_constant', 'bmr']));

-- Grants ----------------------------------------------------------------------------
revoke all on line_grams, recipe_protein_families, client_overview from anon;
grant select on line_grams, recipe_protein_families, client_overview to authenticated;
revoke execute on function client_recipe_screen(uuid) from public, anon;
revoke execute on function save_client_structure(uuid, jsonb, jsonb, jsonb) from public, anon;
grant execute on function client_recipe_screen(uuid) to authenticated;
grant execute on function save_client_structure(uuid, jsonb, jsonb, jsonb) to authenticated;
