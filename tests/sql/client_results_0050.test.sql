-- tests/sql/client_results_0050.test.sql — live test of migration 0050 (always rolls back).
--   pass → "ALL PASS (rolled back)"   fail → "FAIL: ..."
-- Throwaway logins (@example.com): two self-signed-up clients, a dietitian and an intern; plus the earliest admin.
do $$
declare
  adm uuid; d1 uuid := gen_random_uuid(); i1 uuid := gen_random_uuid(); u1 uuid := gen_random_uuid(); u2 uuid := gen_random_uuid();
  c1 uuid; c2 uuid; f1 text; f2 text; fs text; rid uuid; sid uuid;
  today date := (now() at time zone 'Australia/Sydney')::date;
  res jsonb; n int; raised boolean; log text := '';
begin
  select id into adm from profiles where role = 'admin' order by created_at limit 1;
  insert into auth.users (id, email, raw_user_meta_data) values
    (d1, 'zz.r.diet@example.com', '{"full_name":"ZZtest Dana Diet"}'), (i1, 'zz.r.intern@example.com', '{"full_name":"ZZtest Ira Intern"}'),
    (u1, 'zz.r.one@example.com', '{"account_type":"client","full_name":"ZZtest Riley One"}'),
    (u2, 'zz.r.two@example.com', '{"account_type":"client","full_name":"ZZtest Robin Two"}');
  update profiles set role = 'dietitian' where id = d1;
  update profiles set role = 'intern' where id = i1;
  select id into c1 from clients where user_id = u1;
  select id into c2 from clients where user_id = u2;
  f1 := c1::text || '/client-' || gen_random_uuid() || '-bloods.pdf';
  f2 := c1::text || '/client-' || gen_random_uuid() || '-dexa.pdf';
  fs := c1::text || '/' || gen_random_uuid() || '-staff-dexa.pdf';

  -- the dietitian files a staff record (with its own file) for client 1
  perform set_config('request.jwt.claims', json_build_object('sub', d1, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', d1::text, true);
  execute 'set local role authenticated';
  insert into storage.objects (bucket_id, name) values ('clinical-records', fs);
  insert into client_clinical_records (client_id, kind, recorded_on, summary, file_path, source, client_note, reviewed_at)
  values (c1, 'dexa', today - 30, 'Baseline scan', fs, 'client', 'faked', null) returning id into sid;
  if (select source from client_clinical_records where id = sid) <> 'staff' or (select client_note from client_clinical_records where id = sid) is not null
     or (select reviewed_by from client_clinical_records where id = sid) <> d1 then raise exception 'FAIL T1 staff insert not stamped'; end if;
  execute 'reset role';
  log := 'T1 staff records are always "staff", seen when added, stamped with who added them';

  -- T2 the client uploads into their own client- folder only
  perform set_config('request.jwt.claims', json_build_object('sub', u1, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', u1::text, true);
  execute 'set local role authenticated';
  insert into storage.objects (bucket_id, name) values ('clinical-records', f1), ('clinical-records', f2);
  raised := false; begin insert into storage.objects (bucket_id, name) values ('clinical-records', c2::text || '/client-x.pdf'); exception when others then raised := true; end;
  if not raised then raise exception 'FAIL T2a uploaded into another client''s folder'; end if;
  raised := false; begin insert into storage.objects (bucket_id, name) values ('clinical-records', c1::text || '/x.pdf'); exception when others then raised := true; end;
  if not raised then raise exception 'FAIL T2b uploaded outside the client- files'; end if;
  if exists (select 1 from storage.objects where bucket_id = 'clinical-records' and name = fs) then raise exception 'FAIL T2c client sees the staff file'; end if;
  if not exists (select 1 from storage.objects where bucket_id = 'clinical-records' and name = f1) then raise exception 'FAIL T2d client can''t open own file'; end if;
  log := log || ' | T2 client uploads and opens only their own client- files, never staff files or another client''s';

  -- T3 sending a result
  if (add_my_result('bloods', today + 1, f1, null)->>'ok')::boolean then raise exception 'FAIL T3a future date'; end if;
  if (add_my_result('xray', today, f1, null)->>'ok')::boolean then raise exception 'FAIL T3b bad kind'; end if;
  if (add_my_result('bloods', today, c1::text || '/client-missing.pdf', null)->>'ok')::boolean then raise exception 'FAIL T3c file not uploaded'; end if;
  if (add_my_result('bloods', today, fs, null)->>'ok')::boolean then raise exception 'FAIL T3d staff file'; end if;
  if (add_my_result('bloods', today, f1, repeat('x', 501))->>'ok')::boolean then raise exception 'FAIL T3e long note'; end if;
  res := add_my_result('bloods', today - 2, f1, '  Fasting bloods from my GP  ');
  if not (res->>'ok')::boolean then raise exception 'FAIL T3f %', res; end if;
  rid := (res->>'id')::uuid;
  if (add_my_result('bloods', today, f1, null)->>'ok')::boolean then raise exception 'FAIL T3g same file twice'; end if;
  if not (add_my_result('dexa', today - 1, f2, null)->>'ok')::boolean then raise exception 'FAIL T3h second result'; end if;
  res := my_results();
  if jsonb_array_length(res) <> 2 or res->1->>'note' <> 'Fasting bloods from my GP' or (res->1->>'seen')::boolean
     or res->1->>'kind' <> 'bloods' then raise exception 'FAIL T3i my_results %', res; end if;
  if (select count(*) from client_clinical_records) <> 0 then raise exception 'FAIL T3j client reads the table'; end if;
  if not public.clinical_file_in_use(f1) then raise exception 'FAIL T3k attached file can be deleted'; end if;
  log := log || ' | T3 send: past date, known kind, own uploaded file, once, note ≤ 500; my_results lists only theirs; table still closed; attached files protected';

  -- T4 removing before it's seen
  res := remove_my_result((select (x->>'id')::uuid from jsonb_array_elements(my_results()) x where x->>'kind' = 'dexa'));
  if not (res->>'ok')::boolean or res->>'file_path' <> f2 or jsonb_array_length(my_results()) <> 1 then raise exception 'FAIL T4a %', res; end if;
  if public.clinical_file_in_use(f2) then raise exception 'FAIL T4b removed file still in use'; end if;
  execute 'reset role';
  log := log || ' | T4 client removes an unseen result; its file is then free to delete';

  -- T5 the other client and staff can't use the client RPCs
  perform set_config('request.jwt.claims', json_build_object('sub', u2, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', u2::text, true);
  execute 'set local role authenticated';
  if jsonb_array_length(my_results()) <> 0 or (remove_my_result(rid)->>'ok')::boolean then raise exception 'FAIL T5a other client'; end if;
  if exists (select 1 from storage.objects where bucket_id = 'clinical-records' and name = f1) then raise exception 'FAIL T5b other client opens file'; end if;
  execute 'reset role';
  perform set_config('request.jwt.claims', json_build_object('sub', d1, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', d1::text, true);
  execute 'set local role authenticated';
  if (add_my_result('bloods', today, f1, null)->>'ok')::boolean then raise exception 'FAIL T5c staff used add_my_result'; end if;
  log := log || ' | T5 another client sees nothing; staff can''t send as a client';

  -- T6 the dietitian sees it as new, can't alter the client's details, marks it seen
  select count(*) into n from client_clinical_records where client_id = c1 and source = 'client' and reviewed_at is null;
  if n <> 1 then raise exception 'FAIL T6a % waiting', n; end if;
  if not exists (select 1 from storage.objects where bucket_id = 'clinical-records' and name = f1) then raise exception 'FAIL T6b dietitian can''t open the client''s file'; end if;
  raised := false; begin update client_clinical_records set client_note = 'edited' where id = rid; exception when raise_exception then raised := true; end;
  if not raised then raise exception 'FAIL T6c client note edited'; end if;
  raised := false; begin update client_clinical_records set file_path = fs where id = rid; exception when raise_exception then raised := true; end;
  if not raised then raise exception 'FAIL T6d client file replaced'; end if;
  update client_clinical_records set summary = 'Low ferritin', measurements = '[{"name":"Ferritin","value":"18","unit":"µg/L"}]', reviewed_at = now() where id = rid;
  if (select reviewed_by from client_clinical_records where id = rid) <> d1 or (select reviewed_by_name from client_clinical_records where id = rid) <> 'ZZtest Dana Diet'
    then raise exception 'FAIL T6e seen not stamped'; end if;
  execute 'reset role';
  log := log || ' | T6 dietitian sees it waiting, opens the file, adds a summary and values, marks it seen (stamped); the client''s note and file stay';

  -- T7 back as the client: shown as seen, no longer removable, staff summary never shown
  perform set_config('request.jwt.claims', json_build_object('sub', u1, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', u1::text, true);
  execute 'set local role authenticated';
  res := my_results();
  if not (res->0->>'seen')::boolean or res->0->>'seen_by_name' <> 'ZZtest Dana Diet' or res->0 ? 'summary' or res->0 ? 'measurements'
    then raise exception 'FAIL T7a %', res; end if;
  if (remove_my_result(rid)->>'ok')::boolean then raise exception 'FAIL T7b removed after it was seen'; end if;
  execute 'reset role';
  log := log || ' | T7 client sees "seen by", can''t remove it now, never sees staff summaries or values';

  -- T8 interns still have no access; the 20-waiting limit
  perform set_config('request.jwt.claims', json_build_object('sub', i1, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', i1::text, true);
  execute 'set local role authenticated';
  if (select count(*) from client_clinical_records) <> 0 or exists (select 1 from storage.objects where bucket_id = 'clinical-records')
    then raise exception 'FAIL T8a intern sees clinical records'; end if;
  execute 'reset role';
  insert into client_clinical_records (client_id, kind, recorded_on, source)
  select c1, 'other', today, 'client' from generate_series(1, 20);
  perform set_config('request.jwt.claims', json_build_object('sub', u1, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', u1::text, true);
  execute 'set local role authenticated';
  insert into storage.objects (bucket_id, name) values ('clinical-records', c1::text || '/client-limit.pdf');
  res := add_my_result('other', today, c1::text || '/client-limit.pdf', null);
  if (res->>'ok')::boolean or res->>'message' not like 'You have 20 results waiting%' then raise exception 'FAIL T8b limit %', res; end if;
  execute 'reset role';
  log := log || ' | T8 interns see nothing; at most 20 unseen results';

  raise exception 'ALL PASS (rolled back): %', log;
end $$;
