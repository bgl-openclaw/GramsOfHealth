-- 0023_recipe_verification.sql
-- Three-state recipe badge: needs_review | ai_verified | dietitian_verified.
--
-- AI Verified is DERIVED at read time, never stored: "complete and computable".
-- It never means a dietitian approved the recipe.
--
-- Dietitian sign-off is a human-only event row in recipe_signoffs, written only
-- through sign_off_recipe() inside a signed-in admin/dietitian request. No
-- machine process can create one (guard trigger requires auth.uid()).
-- The badge status is derived: a sign-off only counts while the recipe still
-- passes every AI check; otherwise the recipe shows needs_review with
-- signoff_on_hold = true. Status is computed at read time (not by write
-- triggers) because the editor's saveRecipe rewrites lines/steps in separate
-- requests, so every save passes through a transient zero-line state.
--
-- Idempotent. Engine untouched. recipe_readiness untouched.

-- 1. Sign-off history ------------------------------------------------------

create table if not exists recipe_signoffs (
  id             uuid primary key default gen_random_uuid(),
  recipe_id      uuid not null references recipes(id) on delete cascade,
  signed_by      uuid references profiles(id) on delete set null,
  signed_by_name text not null,
  signed_at      timestamptz not null default now(),
  revoked_at     timestamptz,
  revoked_by     uuid references profiles(id) on delete set null,
  revoke_note    text
);

-- At most one active sign-off per recipe; revoked rows remain as history.
create unique index if not exists recipe_signoffs_one_active
  on recipe_signoffs (recipe_id) where revoked_at is null;

alter table recipe_signoffs enable row level security;
drop policy if exists recipe_signoffs_read on recipe_signoffs;
create policy recipe_signoffs_read on recipe_signoffs
  for select to authenticated using (true);
-- Writes only through the SECURITY DEFINER functions below.
revoke all on recipe_signoffs from anon;
revoke insert, update, delete, truncate on recipe_signoffs from authenticated;

create or replace function recipe_signoffs_guard() returns trigger
language plpgsql as $$
begin
  if tg_op = 'INSERT' then
    if auth.uid() is null or new.signed_by is distinct from auth.uid() then
      raise exception 'recipe sign-off must be made by the signed-in dietitian (machine sign-off is not allowed)';
    end if;
  elsif tg_op = 'UPDATE' then
    if new.recipe_id <> old.recipe_id
       or new.signed_at <> old.signed_at
       or new.signed_by_name <> old.signed_by_name
       or (new.signed_by is not null and new.signed_by is distinct from old.signed_by)
       or (old.revoked_at is not null and new.revoked_at is null) then
      raise exception 'recipe sign-off history is append-only (only revocation is allowed)';
    end if;
  end if;
  return new;
end $$;

drop trigger if exists recipe_signoffs_guard on recipe_signoffs;
create trigger recipe_signoffs_guard
  before insert or update on recipe_signoffs
  for each row execute function recipe_signoffs_guard();

-- 2. Plain-words list helper ("a; b; c; d; e +3 more") -------------------------
-- Semicolons, because AFCD display names contain commas ("Sugar, white").

create or replace function reason_list(items text[], max_items int default 5) returns text
language sql immutable as $$
  select array_to_string(items[1:max_items], '; ')
         || case when cardinality(items) > max_items
                 then format(' +%s more', cardinality(items) - max_items) else '' end
$$;

-- 3. The badge view -------------------------------------------------------

create or replace view recipe_verification with (security_invoker = on) as
with line_facts as (
  select lp.recipe_id, lp.food_id, coalesce(lp.unit, 'no unit') as unit, lp.priced, il.position,
         coalesce(f.display_name, lp.food_id, 'unlinked ingredient') as food_name,
         coalesce(f.verified, false) as food_verified
  from line_priceability lp
  join ingredient_lines il on il.id = lp.id
  left join foods f on f.food_id = lp.food_id
),
line_counts as (
  select recipe_id, count(*) as line_count,
         count(*) filter (where not priced) as uncalculable_line_count
  from line_facts group by recipe_id
),
unverified as (
  select recipe_id, array_agg(food_name order by first_pos, food_name) as names
  from (select recipe_id, food_id, food_name, min(position) as first_pos
        from line_facts where not food_verified
        group by recipe_id, food_id, food_name) x
  group by recipe_id
),
uncalculable as (
  select recipe_id, array_agg(label order by first_pos, label) as labels
  from (select recipe_id, food_name || ' (' || unit || ')' as label, min(position) as first_pos
        from line_facts where not priced
        group by recipe_id, food_name || ' (' || unit || ')') x
  group by recipe_id
),
steps as (
  select recipe_id, count(*) filter (where btrim(text) <> '') as step_count
  from method_steps group by recipe_id
),
base as (
  select r.id as recipe_id, r.title,
         not (coalesce(btrim(r.title), '') = '' or btrim(r.title) ilike 'untitled recipe') as has_title,
         (coalesce(btrim(r.image_url_1), '') <> '' or coalesce(btrim(r.image_url_2), '') <> '') as has_image,
         coalesce(lc.line_count, 0)::int as line_count,
         coalesce(st.step_count, 0)::int as step_count,
         coalesce(uv.names, '{}') as unverified_food_names,
         coalesce(lc.uncalculable_line_count, 0)::int as uncalculable_line_count,
         coalesce(uc.labels, '{}') as uncalculable_ingredients,
         nullif(btrim(r.data_issue), '') as data_issue,
         so.signed_by_name, so.signed_at
  from recipes r
  left join line_counts lc on lc.recipe_id = r.id
  left join unverified uv on uv.recipe_id = r.id
  left join uncalculable uc on uc.recipe_id = r.id
  left join steps st on st.recipe_id = r.id
  left join recipe_signoffs so on so.recipe_id = r.id and so.revoked_at is null
),
judged as (
  select b.*,
    array_remove(array[
      case when not b.has_title then 'no title' end,
      case when not b.has_image then 'no image' end,
      case when b.line_count = 0 then 'no ingredients' end,
      case when b.step_count = 0 then 'no method steps' end,
      case when cardinality(b.unverified_food_names) > 0 then
        format('%s unverified food%s: %s', cardinality(b.unverified_food_names),
               case when cardinality(b.unverified_food_names) = 1 then '' else 's' end,
               reason_list(b.unverified_food_names)) end,
      case when cardinality(b.uncalculable_ingredients) > 0 then
        format('%s ingredient%s can''t be calculated: %s', cardinality(b.uncalculable_ingredients),
               case when cardinality(b.uncalculable_ingredients) = 1 then '' else 's' end,
               reason_list(b.uncalculable_ingredients)) end,
      case when b.data_issue is not null then
        'data issue flagged: ' || case when length(b.data_issue) > 80
                                       then left(b.data_issue, 80) || '…' else b.data_issue end end
    ], null) as reasons
  from base b
)
select recipe_id, title,
       case when cardinality(reasons) = 0 and signed_at is not null then 'dietitian_verified'
            when cardinality(reasons) = 0 then 'ai_verified'
            else 'needs_review' end as status,
       cardinality(reasons) = 0 as ai_verified,
       reasons,
       signed_at is not null and cardinality(reasons) > 0 as signoff_on_hold,
       signed_by_name, signed_at,
       has_title, has_image, line_count, step_count,
       cardinality(unverified_food_names)::int as unverified_food_count, unverified_food_names,
       uncalculable_line_count, uncalculable_ingredients,
       data_issue
from judged;

revoke all on recipe_verification from anon;
grant select on recipe_verification to authenticated;

-- 4. Sign-off / revoke (the only write paths) ----------------------------------

create or replace function sign_off_recipe(p_recipe_id uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid  uuid := auth.uid();
  v_role text;
  v_name text;
  v_ai   boolean;
  v_reasons text[];
begin
  select role, coalesce(nullif(btrim(full_name), ''), email) into v_role, v_name
  from profiles where id = v_uid;
  if v_uid is null or v_role is null or v_role not in ('admin', 'dietitian') then
    return jsonb_build_object('ok', false, 'message', 'Only dietitians can sign off recipes.',
                              'reasons', '[]'::jsonb);
  end if;

  select ai_verified, reasons into v_ai, v_reasons
  from recipe_verification where recipe_id = p_recipe_id;
  if not found then
    return jsonb_build_object('ok', false, 'message', 'Recipe not found.', 'reasons', '[]'::jsonb);
  end if;
  if not v_ai then
    return jsonb_build_object('ok', false,
      'message', 'This recipe needs fixing before it can be signed off.',
      'reasons', to_jsonb(v_reasons));
  end if;

  insert into recipe_signoffs (recipe_id, signed_by, signed_by_name)
  values (p_recipe_id, v_uid, v_name)
  on conflict (recipe_id) where revoked_at is null do nothing;

  return jsonb_build_object('ok', true, 'status', 'dietitian_verified',
                            'message', 'Recipe signed off.', 'reasons', '[]'::jsonb);
end $$;

create or replace function revoke_recipe_signoff(p_recipe_id uuid, p_note text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid  uuid := auth.uid();
  v_role text;
begin
  select role into v_role from profiles where id = v_uid;
  if v_uid is null or v_role is null or v_role not in ('admin', 'dietitian') then
    return jsonb_build_object('ok', false, 'message', 'Only dietitians can remove a sign-off.');
  end if;
  update recipe_signoffs
     set revoked_at = now(), revoked_by = v_uid, revoke_note = nullif(btrim(p_note), '')
   where recipe_id = p_recipe_id and revoked_at is null;
  if not found then
    return jsonb_build_object('ok', false, 'message', 'This recipe has no active sign-off.');
  end if;
  return jsonb_build_object('ok', true, 'message', 'Sign-off removed.');
end $$;

revoke execute on function sign_off_recipe(uuid) from public, anon;
revoke execute on function revoke_recipe_signoff(uuid, text) from public, anon;
grant execute on function sign_off_recipe(uuid) to authenticated;
grant execute on function revoke_recipe_signoff(uuid, text) to authenticated;
