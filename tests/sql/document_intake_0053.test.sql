-- tests/sql/document_intake_0053.test.sql — live test of migration 0053 (always rolls back).
--   pass → "ALL PASS (rolled back)"   fail → "FAIL: ..."
-- Throwaway client with a fake GP letter, plus logins (@example.com): a dietitian, an intern and a self-signed-up client.
do $$
declare
  d1 uuid := gen_random_uuid(); i1 uuid := gen_random_uuid(); cu uuid := gen_random_uuid();
  c uuid; rec uuid; f_phone uuid; f_ai uuid; f_goal uuid; f_med uuid; res jsonb; n int; raised boolean; log text := '';
  letter text := E'Example Family Doctors\n1 Example Street\nExampletown NSW 2000\nPhone: 02 9000 0000\n21/10/2026\nRE: ZZ Test\nDOB: 17/07/1967\n'
    || E'Thank you for seeing ZZ Test for an opinion and management of her dyslipidaemia under a GPMP.\n'
    || E'Her current medications are:\nSomac 40mg Tablet 1 Tablet Daily.\nAllergies:\nNil known.\nPast Medical History:\nOsteoporosis\nPeanut allergy noted\n'
    || E'Yours faithfully,\nDr Alex Example\n1234567A\nPhone: 0488 888 888\nMedicare Number: 2123 45670 1\nShe would like to lose 5 kg.';
begin
  insert into auth.users (id, email, raw_user_meta_data) values
    (d1, 'zz.di.diet@example.com', '{"full_name":"ZZtest Dina Intake"}'), (i1, 'zz.di.intern@example.com', '{"full_name":"ZZtest Ivan Intake"}'),
    (cu, 'zz.di.client@example.com', '{"account_type":"client","full_name":"ZZtest Cleo Intake"}');
  update profiles set role = 'dietitian' where id = d1;
  update profiles set role = 'intern' where id = i1;
  insert into clients (full_name, phone) values ('ZZ Test', '0400 000 000') returning id into c;
  insert into client_clinical_records (client_id, kind, recorded_on, document_text) values (c, 'gp_letter', date '2026-10-21', letter) returning id into rec;
  if not medicare_number_valid('2123456701') or medicare_number_valid('2123456711') or medicare_number_valid('11111111') then
    raise exception 'FAIL T0 Medicare check digit'; end if;

  perform set_config('request.jwt.claims', json_build_object('sub', d1, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', d1::text, true);
  execute 'set local role authenticated';

  -- T1 facts must quote the document; AI items are never sure
  insert into client_document_facts (record_id, client_id, section, field, value, quote, method, certainty) values
    (rec, c, 'client', 'full_name', '{"value":"ZZ Test"}', 'RE: ZZ Test', 'rules', 'sure'),
    (rec, c, 'client', 'date_of_birth', '{"value":"1967-07-17"}', 'DOB: 17/07/1967', 'rules', 'sure'),
    (rec, c, 'medicare', 'number', '{"number":"2123456701","irn":null}', 'Medicare Number: 2123 45670 1', 'rules', 'sure'),
    (rec, c, 'care_team', 'gp', '{"role":"gp","name":"Dr Alex Example","practice":"Example Family Doctors","phone":"02 9000 0000","provider_number":"1234567A"}', 'Dr Alex Example', 'rules', 'sure'),
    (rec, c, 'referral', 'referral', '{"pathway":"medicare_chronic","plan_name":"GPMP","referral_date":"2026-10-21","reason":"dyslipidaemia","referrer_name":"Dr Alex Example"}', 'under a GPMP', 'rules', 'sure'),
    (rec, c, 'condition', 'item', '{"condition":"Osteoporosis"}', 'Osteoporosis', 'rules', 'sure'),
    (rec, c, 'allergy', 'item', '{"kind":"nil_known"}', 'Nil known.', 'rules', 'sure');
  insert into client_document_facts (record_id, client_id, section, field, value, quote, method, certainty)
  values (rec, c, 'client', 'phone', '{"value":"0488 888 888"}', 'Phone: 0488 888 888', 'rules', 'sure') returning id into f_phone;
  insert into client_document_facts (record_id, client_id, section, field, value, quote, method, certainty)
  values (rec, c, 'medication', 'item', '{"name":"Somac","strength":"40mg","form":"Tablet","dose":"1 Tablet","frequency":"Daily"}', 'Somac 40mg Tablet 1 Tablet Daily.', 'rules', 'sure') returning id into f_med;
  insert into client_document_facts (record_id, client_id, section, field, value, quote, method, certainty)
  values (rec, c, 'condition', 'item', '{"condition":"Dyslipidaemia"}', 'her dyslipidaemia', 'ai', 'sure') returning id into f_ai;
  insert into client_document_facts (record_id, client_id, section, field, value, quote, method, certainty)
  values (rec, c, 'goal', 'item', '{"detail":"Lose 5 kg"}', 'She would like to lose 5 kg.', 'rules', 'sure') returning id into f_goal;
  if (select certainty from client_document_facts where id = f_ai) <> 'check' then raise exception 'FAIL T1a AI item stored as sure'; end if;
  raised := false; begin insert into client_document_facts (record_id, client_id, section, field, value, quote, method, certainty)
    values (rec, c, 'medication', 'item', '{"name":"Metformin"}', 'Metformin 500mg', 'ai', 'check'); exception when raise_exception then raised := true; end;
  if not raised then raise exception 'FAIL T1b invented quote accepted'; end if;
  log := 'T1 every item quotes the document (invented quotes refused); AI items are never sure';

  -- T2 filing: sure items fill empty fields and add list items; a different value already in the file is a conflict
  res := apply_document_facts(rec);
  if not (res->>'ok')::boolean or (res->>'applied')::int <> 8 or (res->>'conflict')::int <> 1 or (res->>'please_check')::int <> 2
    then raise exception 'FAIL T2a %', res; end if;
  if (select date_of_birth from clients where id = c) <> date '1967-07-17' or (select phone from clients where id = c) <> '0400 000 000'
     or (select existing_value from client_document_facts where id = f_phone) <> '0400 000 000'
     or (select status from client_document_facts where id = f_phone) <> 'conflict' then raise exception 'FAIL T2b fill-empty / conflict'; end if;
  if (select number from client_medicare where client_id = c) <> '2123456701'
     or not (select is_primary from client_care_team where client_id = c and name = 'Dr Alex Example')
     or (select referrer_id from client_referrals where client_id = c) <> (select id from client_care_team where client_id = c)
     or (select count(*) from client_medications where client_id = c) <> 1
     or (select count(*) from client_conditions where client_id = c) <> 1
     or (select kind from client_allergies where client_id = c) <> 'nil_known'
     or (select status from client_document_facts where id = f_goal) <> 'please_check'
     or (select status from client_document_facts where id = f_ai) <> 'please_check' then raise exception 'FAIL T2c filed rows'; end if;
  log := log || ' | T2 sure items filed (empty fields, new list items, GP linked to the referral); phone differs → conflict, not overwritten; AI and goals wait';

  -- T3 decisions: a person can take the document's value, or leave an item out
  res := decide_document_fact(f_phone, 'apply');
  if not (res->>'ok')::boolean or (select phone from clients where id = c) <> '0488 888 888'
     or (select decided_by from client_document_facts where id = f_phone) <> d1 then raise exception 'FAIL T3a apply conflict %', res; end if;
  res := decide_document_fact(f_ai, 'apply');
  if (select count(*) from client_conditions where client_id = c) <> 2 or (select status from client_document_facts where id = f_ai) <> 'confirmed'
    then raise exception 'FAIL T3b confirm AI item'; end if;
  res := decide_document_fact(f_goal, 'reject');
  if (select status from client_document_facts where id = f_goal) <> 'rejected' then raise exception 'FAIL T3c reject'; end if;
  res := decide_document_fact(f_med, 'apply', '{"number":"bad"}');
  log := log || ' | T3 apply takes the document''s value over the file; AI items filed only when a person confirms; reject leaves it out';

  -- T4 filing the same thing twice adds nothing; found items can't be edited directly
  insert into client_document_facts (record_id, client_id, section, field, value, quote, method, certainty)
  values (rec, c, 'medication', 'item', '{"name":"Somac","strength":"40mg"}', 'Somac 40mg', 'rules', 'sure');
  res := apply_document_facts(rec);
  if (select count(*) from client_medications where client_id = c) <> 1 then raise exception 'FAIL T4a duplicate medication'; end if;
  raised := false; begin update client_document_facts set status = 'confirmed' where id = f_goal; exception when raise_exception then raised := true; end;
  if not raised then raise exception 'FAIL T4b found item edited directly'; end if;
  log := log || ' | T4 refiling adds no duplicates; items change only through filing';

  -- T5 an invalid Medicare number is refused with a message; a real allergy then makes "nil known" a conflict
  insert into client_document_facts (record_id, client_id, section, field, value, quote, method, certainty)
  values (rec, c, 'medicare', 'number', '{"number":"11111111"}', 'Medicare Number', 'rules', 'check') returning id into f_med;
  res := decide_document_fact(f_med, 'apply');
  if (res->>'ok')::boolean or res->>'message' not like 'Couldn''t file it%' then raise exception 'FAIL T5a invalid Medicare %', res; end if;
  insert into client_document_facts (record_id, client_id, section, field, value, quote, method, certainty)
  values (rec, c, 'allergy', 'item', '{"kind":"allergy","substance":"Peanut"}', 'Peanut allergy noted', 'rules', 'sure');
  res := apply_document_facts(rec);
  insert into client_document_facts (record_id, client_id, section, field, value, quote, method, certainty)
  values (rec, c, 'allergy', 'item', '{"kind":"nil_known"}', 'Nil known', 'rules', 'sure');
  res := apply_document_facts(rec);
  if (res->>'conflict')::int <> 1 then raise exception 'FAIL T5b nil known vs a real allergy %', res; end if;
  execute 'reset role';
  log := log || ' | T5 invalid Medicare refused with a message; "nil known" against a recorded allergy is a conflict';

  -- T6 interns can't see or file document items; clients see nothing
  perform set_config('request.jwt.claims', json_build_object('sub', i1, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', i1::text, true);
  execute 'set local role authenticated';
  if (select count(*) from client_document_facts) + (select count(*) from client_medicare) <> 0 then raise exception 'FAIL T6a intern reads facts'; end if;
  if (apply_document_facts(rec)->>'ok')::boolean then raise exception 'FAIL T6b intern filed'; end if;
  execute 'reset role';
  perform set_config('request.jwt.claims', json_build_object('sub', cu, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', cu::text, true);
  execute 'set local role authenticated';
  if (select count(*) from client_medications) + (select count(*) from client_conditions) + (select count(*) from client_allergies)
     + (select count(*) from client_care_team) + (select count(*) from client_referrals) + (select count(*) from client_document_facts) <> 0
    then raise exception 'FAIL T6c client reads the new tables'; end if;
  execute 'reset role';
  log := log || ' | T6 interns don''t see documents'' items or Medicare; clients see nothing';

  raise exception 'ALL PASS (rolled back): %', log;
end $$;
