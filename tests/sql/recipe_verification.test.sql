-- tests/sql/recipe_verification.test.sql — live test of migration 0023.
--
-- Everything runs inside ONE DO block that always finishes by raising, so
-- Postgres rolls the whole block back: nothing persists, pass or fail.
--   pass → error text starts "ALL PASS (rolled back)"
--   fail → error text starts "FAIL:"
-- Fixtures are picked live (first AI Verified recipe by title), never hardcoded.
-- The sign-off section impersonates an existing admin via request.jwt.claims
-- inside the doomed transaction, to exercise the human-only write path.
-- Run: paste into Supabase execute_sql, or psql -f this file.
do $$
declare
  a uuid; a_title text; f text; f_name text; b uuid; adm uuid;
  img1 text; img2 text; tmp_line uuid;
  saved ingredient_lines[];
  v recipe_verification%rowtype;
  res jsonb;
  log text := '';
begin
  -- fixtures
  select recipe_id, title into a, a_title
    from recipe_verification where status = 'ai_verified' order by title limit 1;
  if a is null then raise exception 'FAIL: no ai_verified recipe to test with'; end if;
  select il.food_id, fo.display_name into f, f_name
    from ingredient_lines il join foods fo on fo.food_id = il.food_id
   where il.recipe_id = a order by il.position limit 1;
  select recipe_id into b from recipe_verification where status = 'needs_review' order by title limit 1;
  select id into adm from profiles where role in ('admin', 'dietitian') order by created_at limit 1;
  log := format('fixture recipe=%s, food=%s (%s)', a_title, f_name, f);

  -- T1 food verified flag flips the badge live, both directions
  update foods set verified = false where food_id = f;
  select * into v from recipe_verification where recipe_id = a;
  if v.ai_verified or v.status <> 'needs_review'
     or v.reasons <> array[format('1 unverified food: %s', f_name)] then
    raise exception 'FAIL T1a: after un-verify got status=% reasons=%', v.status, v.reasons;
  end if;
  log := log || format(' | T1a un-verify → %s %s', v.status, v.reasons);
  update foods set verified = true where food_id = f;   -- restore original value
  select * into v from recipe_verification where recipe_id = a;
  if not v.ai_verified then raise exception 'FAIL T1b: re-verify did not restore, reasons=%', v.reasons; end if;
  log := log || format(' | T1b re-verify → %s', v.status);

  -- T2 adding a line that cannot resolve to grams
  insert into ingredient_lines (recipe_id, section, position, food_id, quantity, unit, prep_note)
  values (a, null, 999, f, 1, 'test_unit_no_conversion', '') returning id into tmp_line;
  select * into v from recipe_verification where recipe_id = a;
  if v.ai_verified or v.reasons <> array[format('1 ingredient can''t be calculated: %s (test_unit_no_conversion)', f_name)] then
    raise exception 'FAIL T2a: line add got reasons=%', v.reasons;
  end if;
  log := log || format(' | T2a line added → %s %s', v.status, v.reasons);
  delete from ingredient_lines where id = tmp_line;
  select * into v from recipe_verification where recipe_id = a;
  if not v.ai_verified then raise exception 'FAIL T2b: line removal did not restore'; end if;

  -- T3 image removed / re-attached
  select image_url_1, image_url_2 into img1, img2 from recipes where id = a;
  update recipes set image_url_1 = null, image_url_2 = null where id = a;
  select * into v from recipe_verification where recipe_id = a;
  if v.ai_verified or v.reasons <> array['no image'] then raise exception 'FAIL T3a: reasons=%', v.reasons; end if;
  log := log || format(' | T3a image cleared → %s %s', v.status, v.reasons);
  update recipes set image_url_1 = img1, image_url_2 = img2 where id = a;
  select * into v from recipe_verification where recipe_id = a;
  if not v.ai_verified then raise exception 'FAIL T3b: image re-attach did not restore'; end if;
  log := log || ' | T3b image re-attached → ai_verified';

  -- T4 machine can never sign off
  res := sign_off_recipe(a);
  if (res->>'ok')::boolean then raise exception 'FAIL T4a: sign-off with no user succeeded'; end if;
  log := log || format(' | T4a no-user sign_off → %s', res->>'message');
  begin
    insert into recipe_signoffs (recipe_id, signed_by, signed_by_name) values (a, adm, 'machine');
    raise exception 'FAIL T4b: direct machine insert was allowed';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
    log := log || ' | T4b direct machine insert → blocked';
  end;

  -- T5 dietitian sign-off path (impersonated inside this doomed transaction)
  if adm is null then raise exception 'FAIL T5: no admin/dietitian profile to impersonate'; end if;
  perform set_config('request.jwt.claims', json_build_object('sub', adm, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', adm::text, true);

  res := sign_off_recipe(b);
  if (res->>'ok')::boolean or jsonb_array_length(res->'reasons') = 0 then
    raise exception 'FAIL T5a: sign-off of needs_review recipe returned %', res;
  end if;
  log := log || format(' | T5a sign_off needs_review recipe → refused with %s reason(s)', jsonb_array_length(res->'reasons'));

  res := sign_off_recipe(a);
  select * into v from recipe_verification where recipe_id = a;
  if not (res->>'ok')::boolean or v.status <> 'dietitian_verified' or v.signed_by_name is null then
    raise exception 'FAIL T5b: sign-off res=% status=%', res, v.status;
  end if;
  log := log || format(' | T5b sign_off → %s by %s', v.status, v.signed_by_name);

  -- T6 auto-correct: a signed recipe that breaks shows needs_review (sign-off on hold)
  update foods set verified = false where food_id = f;
  select * into v from recipe_verification where recipe_id = a;
  if v.status <> 'needs_review' or not v.signoff_on_hold then
    raise exception 'FAIL T6a: broken signed recipe status=% hold=%', v.status, v.signoff_on_hold;
  end if;
  log := log || format(' | T6a signed + food un-verified → %s, on_hold=%s', v.status, v.signoff_on_hold);
  update foods set verified = true where food_id = f;
  select * into v from recipe_verification where recipe_id = a;
  if v.status <> 'dietitian_verified' then raise exception 'FAIL T6b: status=%', v.status; end if;
  log := log || ' | T6b fixed → dietitian_verified';

  -- T7 editor saveRecipe pattern (delete all lines, re-insert) must not lose the sign-off
  select array_agg(il) into saved from ingredient_lines il where recipe_id = a;
  delete from ingredient_lines where recipe_id = a;
  select * into v from recipe_verification where recipe_id = a;
  if v.status <> 'needs_review' or v.reasons <> array['no ingredients'] then
    raise exception 'FAIL T7a: mid-save status=% reasons=%', v.status, v.reasons;
  end if;
  insert into ingredient_lines select * from unnest(saved);
  select * into v from recipe_verification where recipe_id = a;
  if v.status <> 'dietitian_verified' then raise exception 'FAIL T7b: after re-insert status=%', v.status; end if;
  log := log || ' | T7 save round-trip → dietitian_verified kept';

  -- T8 revoke, and history is append-only
  res := revoke_recipe_signoff(a, 'test');
  select * into v from recipe_verification where recipe_id = a;
  if not (res->>'ok')::boolean or v.status <> 'ai_verified' then raise exception 'FAIL T8a: revoke res=% status=%', res, v.status; end if;
  log := log || ' | T8a revoke → ai_verified';
  begin
    update recipe_signoffs set revoked_at = null where recipe_id = a;
    raise exception 'FAIL T8b: un-revoke was allowed';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
    log := log || ' | T8b un-revoke → blocked';
  end;

  raise exception 'ALL PASS (rolled back): %', log;
end $$;
