-- tests/sql/client_energy_inputs.test.sql — live test of migration 0029.
-- One DO block that always raises → everything rolls back.
-- pass → "ALL PASS (rolled back): … | ROW <json>"  (feed ROW to energyInputsFromRow
-- → estimateEnergy: expect BMR 1780, TDEE 2759 — roadmap fixture 1).
do $$
declare
  c uuid; u uuid; r record; n int; log text := '';
begin
  select id into c from clients order by created_at limit 1;
  select id into u from profiles order by created_at limit 1;

  -- Fixture 1 client: male, 180 cm, born 1996-10-15 (30 on 2026-10-15), moderately active
  update clients set sex = 'male', height_cm = 180, date_of_birth = '1996-10-15',
                     activity_level = 'moderately_active', protein_g_per_kg = 1.8
   where id = c;
  insert into client_weights (client_id, weight_kg, recorded_on) values
    (c, 85, '2026-09-01'), (c, 80, '2026-10-01'), (c, 75, '2026-11-01');   -- last is after as_of

  select * into r from client_energy_inputs(c, '2026-10-15');
  if r.weight_kg <> 80 or r.weighed_on <> '2026-10-01' then
    raise exception 'FAIL W1 picked % on %', r.weight_kg, r.weighed_on; end if;
  if r.activity_factor <> 1.55 or r.height_cm <> 180 or r.sex <> 'male' then
    raise exception 'FAIL W2 row %', row_to_json(r); end if;
  log := 'W1 latest weight on/before as_of = 80 kg (2026-10-01; 2026-11-01 ignored) | W2 height/sex/activity 1.55 carried';

  -- Postgres age() parity with packages/energy ageInYears()
  if date_part('year', age('2026-10-15'::date, '1996-10-16'::date)) <> 29
     or date_part('year', age('2026-10-15'::date, '1996-10-15'::date)) <> 30
     or date_part('year', age('2023-02-28'::date, '2000-02-29'::date)) <> 22
     or date_part('year', age('2023-03-01'::date, '2000-02-29'::date)) <> 23
     or date_part('year', age('2024-02-29'::date, '2000-02-29'::date)) <> 24 then
    raise exception 'FAIL A1 age() parity'; end if;
  log := log || ' | A1 age() matches TS on birthday eve/day and 29 Feb';

  -- RLS (SECURITY INVOKER): pending sees nothing; clinician sees the row
  perform set_config('request.jwt.claims', json_build_object('sub', u, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', u::text, true);
  update profiles set role = 'pending' where id = u;
  execute 'set local role authenticated';
  select count(*) into n from client_energy_inputs(c, '2026-10-15');
  execute 'reset role';
  if n <> 0 then raise exception 'FAIL R1 pending got % rows', n; end if;
  update profiles set role = 'dietitian' where id = u;
  execute 'set local role authenticated';
  select count(*) into n from client_energy_inputs(c, '2026-10-15');
  execute 'reset role';
  if n <> 1 then raise exception 'FAIL R2 dietitian got % rows', n; end if;
  log := log || ' | R1 pending → 0 rows | R2 dietitian → 1 row';

  raise exception 'ALL PASS (rolled back): % | ROW %', log, row_to_json(r);
end $$;
