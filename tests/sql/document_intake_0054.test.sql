-- tests/sql/document_intake_0054.test.sql — live test of migration 0054 (always rolls back).
--   pass → "ALL PASS (rolled back)"   fail → "FAIL: ..."
do $$
declare
  d1 uuid := gen_random_uuid(); c uuid; rec uuid; n int; res jsonb; f uuid; log text := '';
begin
  insert into auth.users (id, email, raw_user_meta_data) values (d1, 'zz.di54.diet@example.com', '{"full_name":"ZZtest Dot Fifty"}');
  update profiles set role = 'dietitian' where id = d1;
  insert into clients (full_name, phone) values ('ZZ Fifty', '0400 000 000') returning id into c;
  insert into client_clinical_records (client_id, kind, recorded_on, document_text)
  values (c, 'transcript', current_date, E'Client: I avoid dairy.\nClient: My phone is 0488 888 888.') returning id into rec;

  -- T1 the bucket takes Word documents and text transcripts
  if not (select allowed_mime_types @> array['application/vnd.openxmlformats-officedocument.wordprocessingml.document', 'text/plain', 'text/vtt', 'application/x-subrip', 'application/pdf']
          from storage.buckets where id = 'clinical-records') then raise exception 'FAIL T1 bucket types'; end if;
  log := 'T1 the bucket accepts .docx, .txt, .vtt and .srt as well as PDFs and photos';

  perform set_config('request.jwt.claims', json_build_object('sub', d1, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', d1::text, true);
  execute 'set local role authenticated';
  -- T2 the same item twice (keys in another order) is kept once; a different item is added
  insert into client_document_facts (record_id, client_id, section, field, value, quote, method, certainty)
  values (rec, c, 'food_rule', 'item', '{"food":"dairy","rule":"avoid"}', 'I avoid dairy.', 'ai', 'check');
  insert into client_document_facts (record_id, client_id, section, field, value, quote, method, certainty)
  values (rec, c, 'food_rule', 'item', '{"rule":"avoid","food":"dairy"}', 'I avoid dairy', 'ai', 'check');
  insert into client_document_facts (record_id, client_id, section, field, value, quote, method, certainty)
  values (rec, c, 'client', 'phone', '{"value":"0488 888 888"}', 'My phone is 0488 888 888.', 'rules', 'sure');
  select count(*) into n from client_document_facts where record_id = rec;
  if n <> 2 then raise exception 'FAIL T2a % items (want 2)', n; end if;
  log := log || ' | T2 a repeated item (any key order) is skipped';

  -- T3 a settled conflict doesn't come back on a re-read
  res := apply_document_facts(rec);
  select id into f from client_document_facts where record_id = rec and section = 'client';
  if (select status from client_document_facts where id = f) <> 'conflict' then raise exception 'FAIL T3a conflict %', res; end if;
  res := decide_document_fact(f, 'reject');
  insert into client_document_facts (record_id, client_id, section, field, value, quote, method, certainty)
  values (rec, c, 'client', 'phone', '{"value":"0488 888 888"}', 'My phone is 0488 888 888.', 'rules', 'sure');
  select count(*) into n from client_document_facts where record_id = rec and section = 'client';
  res := apply_document_facts(rec);
  if n <> 1 or (select status from client_document_facts where id = f) <> 'rejected' or (select phone from clients where id = c) <> '0400 000 000'
    then raise exception 'FAIL T3b settled conflict came back'; end if;
  execute 'reset role';
  log := log || ' | T3 "Keep the file''s" stays settled after a re-read';

  raise exception 'ALL PASS (rolled back): %', log;
end $$;
