-- tests/sql/result_values_0052.test.sql — live test of migration 0052 (always rolls back).
--   pass → "ALL PASS (rolled back)"   fail → "FAIL: ..."
-- Throwaway client and record, plus logins (@example.com): a dietitian, an intern and a self-signed-up client.
do $$
declare
  d1 uuid := gen_random_uuid(); i1 uuid := gen_random_uuid(); cu uuid := gen_random_uuid();
  c uuid; c_other uuid; rec uuid; vs uuid; vc uuid; vm uuid; n int; raised boolean; log text := '';
begin
  insert into auth.users (id, email, raw_user_meta_data) values
    (d1, 'zz.rv.diet@example.com', '{"full_name":"ZZtest Dot Values"}'), (i1, 'zz.rv.intern@example.com', '{"full_name":"ZZtest Ike Values"}'),
    (cu, 'zz.rv.client@example.com', '{"account_type":"client","full_name":"ZZtest Cy Values"}');
  update profiles set role = 'dietitian' where id = d1;
  update profiles set role = 'intern' where id = i1;
  insert into clients (full_name) values ('ZZ Values Client') returning id into c;
  insert into clients (full_name) values ('ZZ Other Client') returning id into c_other;
  insert into client_clinical_records (client_id, kind, recorded_on) values (c, 'bloods', current_date - 3) returning id into rec;

  perform set_config('request.jwt.claims', json_build_object('sub', d1, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', d1::text, true);
  execute 'set local role authenticated';

  -- T1 the database turns certainty into status; client comes from the record; OCR is never sure; manual is confirmed
  insert into client_result_values (record_id, client_id, marker_code, name_as_printed, value, value_text, unit_as_printed, lab_low, lab_high,
                                    lab_range_text, measured_on, page, line_text, method, certainty, status)
  values (rec, c_other, 'ferritin', 'Ferritin', 45, '45', 'ug/L', 30, 500, '(30-500)', current_date - 3, 1, 'Ferritin 45 ug/L (30-500)', 'text', 'sure', 'please_check')
  returning id into vs;
  if (select status from client_result_values where id = vs) <> 'accepted' or (select client_id from client_result_values where id = vs) <> c
    then raise exception 'FAIL T1a sure value'; end if;
  insert into client_result_values (record_id, client_id, marker_code, name_as_printed, value, value_text, unit_as_printed, line_text, method, certainty, check_reasons, status)
  values (rec, c, 'haemoglobin', 'Hb', 128, '128', 'g/L', 'Hb 128 g/L', 'text', 'check', '{name not on the marker list}', 'accepted')
  returning id into vc;
  if (select status from client_result_values where id = vc) <> 'please_check' then raise exception 'FAIL T1b unsure value accepted'; end if;
  raised := false; begin insert into client_result_values (record_id, client_id, name_as_printed, value_text, method, certainty, status)
    values (rec, c, 'Ferritin', '45', 'ocr', 'sure', 'accepted'); exception when check_violation then raised := true; end;
  if not raised then raise exception 'FAIL T1c a photo reading was sure'; end if;
  insert into client_result_values (record_id, client_id, marker_code, name_as_printed, value, value_text, unit_as_printed, method, certainty, status)
  values (rec, c, 'vitamin_d', 'Vitamin D', 62, '62', 'nmol/L', 'manual', 'check', 'please_check') returning id into vm;
  if (select status from client_result_values where id = vm) <> 'confirmed' or (select decided_by from client_result_values where id = vm) <> d1
    then raise exception 'FAIL T1d manual value'; end if;
  log := 'T1 status comes from certainty (app can''t choose it); client from the record; photo readings never sure; hand-entered values confirmed';

  -- T2 corrections keep the reader's original (the first one)
  update client_result_values set value = 54, value_text = '54' where id = vs;
  if (select status from client_result_values where id = vs) <> 'corrected' or (select original ->> 'value' from client_result_values where id = vs) <> '45'
     or (select decided_by_name from client_result_values where id = vs) <> 'ZZtest Dot Values' then raise exception 'FAIL T2a correction'; end if;
  update client_result_values set value = 55, value_text = '55' where id = vs;
  if (select original ->> 'value' from client_result_values where id = vs) <> '45' then raise exception 'FAIL T2b original overwritten'; end if;
  log := log || ' | T2 a correction keeps the first reading as original, stamped';

  -- T3 confirm; can't go back to accepted; what the reader saw can't change
  update client_result_values set status = 'confirmed' where id = vc;
  if (select status from client_result_values where id = vc) <> 'confirmed' or (select decided_by from client_result_values where id = vc) <> d1
    then raise exception 'FAIL T3a confirm'; end if;
  raised := false; begin update client_result_values set status = 'accepted' where id = vc; exception when raise_exception then raised := true; end;
  if not raised then raise exception 'FAIL T3b set back to accepted'; end if;
  raised := false; begin update client_result_values set line_text = 'Hb 182 g/L' where id = vc; exception when raise_exception then raised := true; end;
  if not raised then raise exception 'FAIL T3c reader text changed'; end if;
  update client_result_values set status = 'rejected' where id = vm;
  log := log || ' | T3 confirm and reject are stamped; nothing goes back to accepted; the reader''s text is fixed';

  -- T4 only accepted, confirmed and corrected values are usable
  select count(*) into n from client_result_values_usable where record_id = rec;
  if n <> 2 or (select value_for_marker from client_result_values_usable where id = vs) <> 55 then raise exception 'FAIL T4 usable (%)', n; end if;
  log := log || ' | T4 usable = accepted, confirmed, corrected';

  -- T5 reading the record is stamped
  update client_clinical_records set read_summary = '{"reader_version":"t","sure":1,"please_check":1}' where id = rec;
  if (select read_by from client_clinical_records where id = rec) <> d1 or (select read_at from client_clinical_records where id = rec) is null
    then raise exception 'FAIL T5 read stamp'; end if;
  log := log || ' | T5 the record''s read run is stamped';
  execute 'reset role';

  -- T6 interns and clients see nothing and can't write
  perform set_config('request.jwt.claims', json_build_object('sub', i1, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', i1::text, true);
  execute 'set local role authenticated';
  if (select count(*) from client_result_values) <> 0 then raise exception 'FAIL T6a intern reads values'; end if;
  raised := false; begin insert into client_result_values (record_id, client_id, name_as_printed, value_text, method, certainty, status)
    values (rec, c, 'x', '1', 'manual', 'sure', 'confirmed'); exception when others then raised := true; end;
  if not raised then raise exception 'FAIL T6b intern wrote a value'; end if;
  execute 'reset role';
  perform set_config('request.jwt.claims', json_build_object('sub', cu, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', cu::text, true);
  execute 'set local role authenticated';
  if (select count(*) from client_result_values) + (select count(*) from client_result_values_usable) <> 0 then raise exception 'FAIL T6c client reads values'; end if;
  execute 'reset role';
  log := log || ' | T6 interns and clients see nothing';

  -- T7 a dietitian can clear a reading (to read again); deleting the record removes its values
  perform set_config('request.jwt.claims', json_build_object('sub', d1, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', d1::text, true);
  execute 'set local role authenticated';
  delete from client_result_values where id = vm;
  get diagnostics n = row_count; if n <> 1 then raise exception 'FAIL T7a delete'; end if;
  delete from client_clinical_records where id = rec;
  execute 'reset role';
  if exists (select 1 from client_result_values where record_id = rec) then raise exception 'FAIL T7b values outlived the record'; end if;
  log := log || ' | T7 values can be cleared and go with their record';

  raise exception 'ALL PASS (rolled back): %', log;
end $$;
