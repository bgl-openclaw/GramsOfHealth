-- tests/sql/client_accounts_p1a.test.sql — live test of migrations 0039, 0039b, 0039c (+ 0040 sign-up rule) (always rolls back).
--   pass → "ALL PASS (rolled back)"   fail → "FAIL: ..."
-- Throwaway clients/plans/logins only. Sign-ups are simulated by inserting into
-- auth.users (fires the real handle_new_user trigger). Staff actions run as the
-- earliest admin; client actions impersonate the new client login.
do $$
declare
  adm uuid; adm_email text; c1 uuid; c2 uuid; cu2 uuid; p1 uuid; p2 uuid; ra uuid;
  u1 uuid := gen_random_uuid(); u2 uuid := gen_random_uuid(); u3 uuid := gen_random_uuid(); u4 uuid := gen_random_uuid();
  pid uuid; tok uuid; res jsonb; d jsonb; v jsonb; snap jsonb; n int; s text; log text := '';
  today date := (now() at time zone 'Australia/Sydney')::date;
begin
  select id, email into adm, adm_email from profiles where role = 'admin' order by created_at limit 1;
  select recipe_id into ra from recipe_verification where status = 'ai_verified' order by title limit 1;
  perform set_config('request.jwt.claims', json_build_object('sub', adm, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', adm::text, true);

  -- Fixtures: two clients, each with a published plan starting today
  insert into clients (full_name, email, assigned_dietitian) values ('ZZtest Alex Client', 'zz.alex@example.com', adm) returning id into c1;
  insert into clients (full_name, email) values ('ZZtest Blair Client', 'zz.blair@example.com') returning id into c2;
  insert into client_targets (client_id, day_type, kcal, protein_g, source) values (c1, 'default', 1800, 100, 'dietitian');
  insert into client_requirements (client_id, tag_id) select c1, id from tags where label in ('Vegan', 'Sesame', 'Heart-healthy');
  insert into client_food_rules (client_id, food_id, rule) values (c1, 'garlic', 'avoid');
  insert into client_supplements (client_id, name, dose) values (c1, 'Vitamin D', '1000 IU');
  insert into meal_plans (title, days, client_id, start_date) values ('ZZ Alex week', 7, c1, today) returning id into p1;
  insert into meal_plans (title, days, client_id, start_date) values ('ZZ Blair week', 7, c2, today) returning id into p2;
  insert into meal_plan_items (meal_plan_id, recipe_id, position, day, meal_slot) values (p1, ra, 0, 1, 'Lunch'), (p2, ra, 0, 1, 'Lunch');
  foreach pid in array array[p1, p2] loop
    snap := jsonb_build_object('schema', 1,
      'plan', jsonb_build_object('title', 'ZZ week', 'client_id', 'secret', 'start_date', today, 'days', 7),
      'items', (select jsonb_agg(jsonb_build_object('item_id', id, 'recipe_id', recipe_id, 'profile_id', profile_id,
                  'day', day, 'meal_slot', meal_slot, 'servings_override', servings_override, 'title', 'Bowl',
                  'version_status', 'Base', 'show_macros_export', true,
                  'per_serve', jsonb_build_object('kcal', 500), 'totals', jsonb_build_object('kcal', 500),
                  'lines', jsonb_build_array(jsonb_build_object('food_name', 'Egg', 'quantity', 1, 'unit', 'each', 'grams', 51, 'kcal', 70))))
                from meal_plan_items where meal_plan_id = pid),
      'days', (select jsonb_agg(jsonb_build_object('day', day, 'day_type', day_type, 'targets', jsonb_build_object('kcal', kcal),
                 'totals', jsonb_build_object('kcal', 500), 'targets_day_type', targets_day_type)) from plan_days(pid)),
      'week_average', jsonb_build_object('totals', jsonb_build_object('kcal', 500)),
      'shopping', jsonb_build_array(jsonb_build_object('food_name', 'Egg', 'grams', 51, 'buy', 'buy 1 (large)')));
    res := publish_meal_plan(pid, snap);
    if not (res->>'ok')::boolean then raise exception 'FAIL setup publish %', res; end if;
  end loop;

  -- T1 invite: dietitian gets a link; repeat returns the same link; intern refused
  res := invite_client_to_app(c1);
  if not (res->>'ok')::boolean then raise exception 'FAIL T1a %', res; end if;
  tok := (res->>'token')::uuid;
  if (invite_client_to_app(c1)->>'token')::uuid <> tok then raise exception 'FAIL T1b new token on repeat'; end if;
  update profiles set role = 'intern' where id = adm;
  if (invite_client_to_app(c1)->>'ok')::boolean then raise exception 'FAIL T1c intern invited'; end if;
  update profiles set role = 'admin' where id = adm;
  log := 'T1 invite link created (same link on repeat); intern refused';

  -- T2 sign-up WITH the invite token → client role, linked, invite accepted
  insert into auth.users (id, email, raw_user_meta_data) values
    (u1, 'zz.alex@example.com', jsonb_build_object('invitation_token', tok, 'full_name', 'Alex'));
  if (select role from profiles where id = u1) <> 'client' or (select user_id from clients where id = c1) is distinct from u1
     or (select accepted_at from invitations where token = tok) is null then raise exception 'FAIL T2'; end if;
  log := log || ' | T2 sign-up with invite link → client, linked, invite accepted';

  -- T3 client invite WITHOUT the token never links (email alone isn't proof). Since 0040 a self-registration
  --    gets its own fresh file instead of waiting unlinked; to exercise manual linking we then unlink it.
  res := invite_client_to_app(c2);
  insert into auth.users (id, email, raw_user_meta_data) values
    (u2, 'zz.blair@example.com', jsonb_build_object('account_type', 'client'));
  select id into cu2 from clients where user_id = u2;
  if (select role from profiles where id = u2) <> 'client' or (select user_id from clients where id = c2) is not null
     or cu2 is null or (select source from clients where id = cu2) <> 'self_signup'
     or (select accepted_at from invitations where token = (res->>'token')::uuid) is not null then raise exception 'FAIL T3a'; end if;
  if not (unlink_client_account(cu2)->>'ok')::boolean then raise exception 'FAIL T3b unlink own file'; end if;
  select count(*) into n from client_app_signups() where user_id = u2;
  if n <> 1 then raise exception 'FAIL T3c sign-up not listed'; end if;
  log := log || ' | T3 same email without the link → own new file (never the invited client''s); once unlinked it shows in "App sign-ups waiting"';

  -- T4 linking: intern refused; dietitian links; double-link refused
  update profiles set role = 'intern' where id = adm;
  if (link_client_account(c2, u2)->>'ok')::boolean then raise exception 'FAIL T4a intern linked'; end if;
  update profiles set role = 'admin' where id = adm;
  if not (link_client_account(c2, u2)->>'ok')::boolean then raise exception 'FAIL T4b'; end if;
  if (link_client_account(c1, u2)->>'ok')::boolean then raise exception 'FAIL T4c double link'; end if;
  begin update clients set user_id = null where id = c2; raise exception 'FAIL T4d direct unlink';
  exception when others then if sqlerrm like 'FAIL%' then raise; end if; end;
  log := log || ' | T4 dietitian links (intern refused, double link refused, direct edits refused)';

  -- T5 as the client: tables closed, own details, numbers hidden by default
  perform set_config('request.jwt.claims', json_build_object('sub', u1, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', u1::text, true);
  execute 'set local role authenticated';
  if (select count(*) from clients) + (select count(*) from meal_plans) + (select count(*) from meal_plan_versions)
     + (select count(*) from recipes) + (select count(*) from foods) <> 0 then raise exception 'FAIL T5a client reads tables'; end if;
  if (select count(*) from profiles) <> 1 then raise exception 'FAIL T5b profiles'; end if;
  d := my_details();
  if not (d->>'linked')::boolean or d->>'first_name' <> 'ZZtest' or d->>'contact_email' <> adm_email
     or d->'targets' <> 'null'::jsonb or (d->>'show_numbers')::boolean
     or jsonb_array_length(d->'requirements') <> 3 or d->'foods_to_avoid'->>0 <> 'Garlic, fresh'
     or jsonb_array_length(d->'supplements') <> 1 then raise exception 'FAIL T5c %', d; end if;
  select count(*) into n from my_plans() where plan_id = p1 and is_current;
  if n <> 1 or (select count(*) from my_plans()) <> 1 then raise exception 'FAIL T5d my_plans'; end if;
  v := my_plan_version(p1);
  if v->'items'->0 ? 'per_serve' or v->'items'->0 ? 'totals' or v->'items'->0 ? 'version_status'
     or v->'items'->0->'lines'->0 ? 'kcal' or (v->'items'->0->>'show_macros_export')::boolean
     or v->'days'->0 ? 'targets' or v->'week_average' <> 'null'::jsonb or v->'plan' ? 'client_id'
     or v->'items'->0->'lines'->0->>'grams' <> '51' or v->'shopping'->0->>'buy' <> 'buy 1 (large)' then
    raise exception 'FAIL T5e numbers leaked or content missing %', v; end if;
  if my_plan_version(p2) is not null then raise exception 'FAIL T5f other client''s plan visible'; end if;
  res := set_my_show_numbers(true);
  if (res->>'show_numbers')::boolean then raise exception 'FAIL T5g client turned numbers on without permission'; end if;
  log := log || ' | T5 client: every table closed, own profile only, details + current plan + recipes/shopping from the snapshot, NO calories/macros/targets, can''t open another client''s plan or switch numbers on alone';
  execute 'reset role';

  -- T6 numbers: intern can't allow; dietitian allows → client sees them; client hides → gone again
  perform set_config('request.jwt.claims', json_build_object('sub', adm, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', adm::text, true);
  update profiles set role = 'intern' where id = adm;
  begin update clients set numbers_allowed = true where id = c1; raise exception 'FAIL T6a intern allowed numbers';
  exception when others then if sqlerrm like 'FAIL%' then raise; end if; end;
  update profiles set role = 'admin' where id = adm;
  update clients set numbers_allowed = true where id = c1;
  begin update clients set client_shows_numbers = false where id = c1; raise exception 'FAIL T6b staff changed the client''s switch';
  exception when others then if sqlerrm like 'FAIL%' then raise; end if; end;
  perform set_config('request.jwt.claims', json_build_object('sub', u1, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', u1::text, true);
  execute 'set local role authenticated';
  v := my_plan_version(p1);
  d := my_details();
  if not (v->'items'->0 ? 'per_serve') or not (v->'items'->0->'lines'->0 ? 'kcal') or not (v->'days'->0 ? 'targets')
     or d->'targets'->0->>'kcal' <> '1800' then raise exception 'FAIL T6c numbers missing when allowed %', v; end if;
  res := set_my_show_numbers(false);
  v := my_plan_version(p1);
  if v->'items'->0 ? 'per_serve' or (my_details()->>'show_numbers')::boolean then raise exception 'FAIL T6d client hide ignored'; end if;
  execute 'reset role';
  log := log || ' | T6 numbers: intern can''t allow, staff can''t flip the client''s switch, allowed → shown, client hides → removed again';

  -- T7 unlink: client then sees nothing
  perform set_config('request.jwt.claims', json_build_object('sub', adm, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', adm::text, true);
  if not (unlink_client_account(c1)->>'ok')::boolean then raise exception 'FAIL T7a'; end if;
  perform set_config('request.jwt.claims', json_build_object('sub', u1, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', u1::text, true);
  execute 'set local role authenticated';
  -- still a client (the app shows "connecting your account"), not a refusal
  if (my_details()->>'linked') is distinct from 'false' or my_plan_version(p1) is not null or (select count(*) from my_plans()) <> 0 then
    raise exception 'FAIL T7b unlinked client still sees data (or was refused) %', my_details(); end if;
  execute 'reset role';
  log := log || ' | T7 unlinked → { linked: false }, sees nothing';

  -- T8 staff invites still work by email as before; a plain sign-up stays pending
  insert into invitations (email, role) values ('zz.staff@example.com', 'intern');
  insert into auth.users (id, email, raw_user_meta_data) values (u3, 'zz.staff@example.com', '{}'::jsonb);
  insert into auth.users (id, email, raw_user_meta_data) values (u4, 'zz.nobody@example.com', '{}'::jsonb);
  if (select role from profiles where id = u3) <> 'intern' or (select role from profiles where id = u4) <> 'pending' then
    raise exception 'FAIL T8'; end if;
  perform set_config('request.jwt.claims', json_build_object('sub', u4, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', u4::text, true);
  execute 'set local role authenticated';
  if (my_details()->>'message') is distinct from 'Client accounts only.' or (select count(*) from my_plans()) <> 0 then
    raise exception 'FAIL T8b pending not refused %', my_details(); end if;
  execute 'reset role';
  log := log || ' | T8 staff invite by email unchanged; plain sign-up → pending, refused by my_details, sees nothing';

  -- T9 (0039c) staff are refused by my_details — the app uses that refusal to keep staff out of the client area
  foreach s in array array['admin', 'dietitian', 'intern'] loop
    perform set_config('request.jwt.claims', json_build_object('sub', adm, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', adm::text, true);
    update profiles set role = s where id = adm;
    execute 'set local role authenticated';
    d := my_details();
    execute 'reset role';
    if (d->>'ok') is distinct from 'false' or (d->>'message') is distinct from 'Client accounts only.' then
      raise exception 'FAIL T9 % not refused %', s, d; end if;
  end loop;
  update profiles set role = 'admin' where id = adm;
  log := log || ' | T9 admin/dietitian/intern → "Client accounts only." (staff never routed to /me)';

  raise exception 'ALL PASS (rolled back): %', log;
end $$;
