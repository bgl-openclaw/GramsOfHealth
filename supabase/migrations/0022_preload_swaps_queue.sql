-- P2: machine-draft profile marker, swap-suggestion table, review-queue views.

-- Feature 1: machine-draft marker + draft-time base fingerprint.
-- origin flips to 'dietitian' when a dietitian edits a machine draft (UI
-- contract); the preload runner only ever touches rows where
-- origin='machine' AND verified=false AND base_fingerprint differs.
alter table recipe_profiles add column if not exists origin text not null default 'dietitian'
  check (origin in ('dietitian','machine'));
alter table recipe_profiles add column if not exists base_fingerprint text;

-- Feature 2: curated swap suggestions (the ONLY source of assisted swaps).
create table if not exists swap_suggestions (
  id                 uuid primary key default gen_random_uuid(),
  trigger_food_id    text references foods (food_id) on delete cascade,
  trigger_tag_id     uuid references tags (id) on delete cascade,
  applies_for_tag_id uuid not null references tags (id) on delete cascade,
  suggestion_name    text not null,
  suggestion_food_id text references foods (food_id) on delete set null,
  notes              text,
  position           integer not null default 0,
  check (trigger_food_id is not null or trigger_tag_id is not null)
);
alter table swap_suggestions enable row level security;
drop policy if exists "authenticated full access" on swap_suggestions;
create policy "authenticated full access" on swap_suggestions
  for all to authenticated using (true) with check (true);

-- Feature 3: review-queue views (derived, never stored).
create or replace view line_priceability with (security_invoker = on) as
select il.id, il.recipe_id, il.food_id, il.unit,
  case
    when il.unit in ('g','gram','grams','kg','x95g') then true
    when il.unit in ('tsp','tbsp','cup','ml') then (f.density_g_ml is not null or uc.grams is not null)
    else uc.grams is not null
  end as priced
from ingredient_lines il
left join foods f on f.food_id = il.food_id
left join unit_conversions uc on uc.food_id = il.food_id and uc.unit = il.unit;

create or replace view recipe_readiness with (security_invoker = on) as
select r.id as recipe_id, r.title,
       count(lp.id) as total_lines,
       count(*) filter (where not lp.priced) as unpriced_lines,
       count(distinct il.food_id) filter (where not f.verified) as unverified_foods,
       (r.data_issue is not null and length(trim(r.data_issue)) > 0) as has_data_issue,
       (count(*) filter (where not lp.priced) = 0
        and count(distinct il.food_id) filter (where not f.verified) = 0
        and count(lp.id) > 0
        and (r.data_issue is null or length(trim(r.data_issue)) = 0)) as ready
from recipes r
left join ingredient_lines il on il.recipe_id = r.id
left join line_priceability lp on lp.id = il.id
left join foods f on f.food_id = il.food_id
group by r.id, r.title, r.data_issue;

create or replace view food_leverage with (security_invoker = on) as
select f.food_id, f.display_name, f.verified,
       count(distinct il.recipe_id) as used_in_recipes,
       case when f.verified then 0 else count(distinct il.recipe_id) end as blocked_recipes
from foods f
left join ingredient_lines il on il.food_id = f.food_id
group by f.food_id, f.display_name, f.verified;

create or replace view conversion_gaps with (security_invoker = on) as
select lp.food_id, lp.unit, count(distinct lp.recipe_id) as affected_recipes
from line_priceability lp
where not lp.priced
group by lp.food_id, lp.unit;
