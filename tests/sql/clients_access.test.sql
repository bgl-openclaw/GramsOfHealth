-- tests/sql/clients_access.test.sql — live RLS test of migrations 0026 + 0027.
-- One DO block that always ends by raising → everything rolls back (role flips,
-- grants, inserted rows). pass → "ALL PASS (rolled back)"; fail → "FAIL: ...".
-- Impersonates the earliest staff profile via request.jwt.claims + SET ROLE
-- authenticated, temporarily switching its role to intern / pending / dietitian.
do $$
declare
  u uuid; c uuid; n int; ok boolean; log text := '';
begin
  select id into u from profiles order by created_at limit 1;
  select id into c from clients order by created_at limit 1;
  if u is null or c is null then raise exception 'FAIL: need one profile and one client'; end if;
  perform set_config('request.jwt.claims', json_build_object('sub', u, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', u::text, true);

  -- ── INTERN, not allocated ──
  update profiles set role = 'intern' where id = u;
  execute 'set local role authenticated';
  select count(*) into n from clients;              if n <> 0 then raise exception 'FAIL I1 intern sees % clients', n; end if;
  select count(*) into n from meal_plans where client_id is null;
  log := format('I1 intern unallocated: 0 clients, %s template plans visible', n);
  begin insert into clients (full_name) values ('x'); raise exception 'FAIL I2';
  exception when others then if sqlerrm like 'FAIL%' then raise; end if; log := log || ' | I2 create client refused'; end;
  execute 'reset role';

  -- ── INTERN, allocated without check-ins ──
  insert into client_staff_access (client_id, profile_id, can_view_checkins) values (c, u, false);
  execute 'set local role authenticated';
  select count(*) into n from clients;              if n <> 1 then raise exception 'FAIL I3 allocated intern sees % clients', n; end if;
  select count(*) into n from client_current_targets where client_id = c;
  log := log || format(' | I3 allocated: client visible, %s current target row(s) readable', n);
  begin insert into client_targets (client_id, day_type, kcal, source) values (c, 'default', 1, 'dietitian'); raise exception 'FAIL I4';
  exception when others then if sqlerrm like 'FAIL%' then raise; end if; log := log || ' | I4 set targets refused'; end;
  insert into client_weights (client_id, weight_kg, recorded_on) values (c, 70, current_date);
  log := log || ' | I5 log weight ok';
  begin insert into client_checkins (client_id, checkin_on) values (c, current_date); raise exception 'FAIL I6';
  exception when others then if sqlerrm like 'FAIL%' then raise; end if; log := log || ' | I6 check-in refused (not ticked)'; end;
  begin insert into client_clinical_records (client_id, kind, recorded_on) values (c, 'bloods', current_date); raise exception 'FAIL I7';
  exception when others then if sqlerrm like 'FAIL%' then raise; end if; log := log || ' | I7 clinical write refused'; end;
  execute 'reset role';

  -- ── INTERN, check-ins ticked ──
  update client_staff_access set can_view_checkins = true where client_id = c and profile_id = u;
  insert into client_clinical_records (client_id, kind, recorded_on, summary) values (c, 'bloods', current_date, 'test');
  execute 'set local role authenticated';
  insert into client_checkins (client_id, checkin_on, feeling) values (c, current_date, 4);
  select count(*) into n from client_checkins where client_id = c;   if n < 1 then raise exception 'FAIL I8'; end if;
  select count(*) into n from client_clinical_records;               if n <> 0 then raise exception 'FAIL I9 intern sees % clinical', n; end if;
  log := log || ' | I8 ticked: check-in saved & readable | I9 clinical rows hidden (0)';
  execute 'reset role';

  -- ── PENDING ──
  update profiles set role = 'pending' where id = u;
  execute 'set local role authenticated';
  select count(*) into n from clients;          if n <> 0 then raise exception 'FAIL P1 pending sees % clients', n; end if;
  select count(*) into n from meal_plans;       if n <> 0 then raise exception 'FAIL P2 pending sees % plans', n; end if;
  select count(*) into n from activity_levels;  if n <> 0 then raise exception 'FAIL P3 pending sees lookups'; end if;
  log := log || ' | P1-3 pending: 0 clients, 0 plans, 0 lookups';
  execute 'reset role';

  -- ── DIETITIAN ──
  update profiles set role = 'dietitian' where id = u;
  execute 'set local role authenticated';
  select count(*) into n from client_clinical_records;  if n < 1 then raise exception 'FAIL D1 dietitian sees no clinical'; end if;
  insert into client_targets (client_id, day_type, kcal, source) values (c, 'hard', 2600, 'dietitian');
  begin insert into client_targets (client_id, day_type, kcal, source) values (c, 'rest', 1900, 'calculator_accepted'); raise exception 'FAIL D2';
  exception when others then if sqlerrm like 'FAIL%' then raise; end if; end;
  log := log || ' | D1 dietitian reads clinical, sets targets | D2 calculator target without working refused';
  -- requirements → blocked / preferred
  insert into client_requirements (client_id, tag_id) select c, id from tags where label = 'Vegan' and kind = 'dietary';
  insert into client_requirements (client_id, tag_id) select c, id from tags where label = 'Sesame' and kind = 'allergen';
  insert into client_requirements (client_id, tag_id) select c, id from tags where label = 'Heart-healthy';
  select count(distinct blocked_tag_id) into n from client_blocked_tags where client_id = c;
  if n <> 7 then raise exception 'FAIL D3 blocked tags = % (want 7)', n; end if;
  select count(*) into n from client_preferred_tags where client_id = c;
  if n <> 1 then raise exception 'FAIL D4 preferred = %', n; end if;
  log := log || ' | D3 Vegan+Sesame → 7 blocked tags | D4 Heart-healthy → preferred';
  execute 'reset role';

  raise exception 'ALL PASS (rolled back): %', log;
end $$;
