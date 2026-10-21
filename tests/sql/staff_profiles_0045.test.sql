-- tests/sql/staff_profiles_0045.test.sql — live test of migration 0045 (always rolls back).
--   pass → "ALL PASS (rolled back)"   fail → "FAIL: ..."
-- Throwaway staff logins (@example.com) are created through the real sign-up trigger, then given roles.
do $$
declare
  adm uuid; adm2 uuid; d1 uuid := gen_random_uuid(); i1 uuid := gen_random_uuid(); i2 uuid := gen_random_uuid(); cl uuid := gen_random_uuid();
  today date := (now() at time zone 'Australia/Sydney')::date;
  apd uuid; res jsonb; d jsonb; n int; raised boolean; log text := '';
begin
  select id into adm from profiles where role = 'admin' order by created_at limit 1;
  select id into adm2 from profiles where role = 'admin' and id <> adm order by created_at limit 1;
  insert into auth.users (id, email, raw_user_meta_data) values
    (d1, 'zz.diet@example.com', '{"full_name":"ZZtest Dee Diet"}'), (i1, 'zz.intern1@example.com', '{"full_name":"ZZtest Ian Intern"}'),
    (i2, 'zz.intern2@example.com', '{"full_name":"ZZtest Ivy Intern"}'), (cl, 'zz.client@example.com', '{"account_type":"client","full_name":"ZZtest Cal Client"}');
  update profiles set role = 'dietitian' where id = d1;
  update profiles set role = 'intern' where id in (i1, i2);

  -- T1 profiles: own details yes; own role/email no; others' rows no; supervisor must be a dietitian/admin
  perform set_config('request.jwt.claims', json_build_object('sub', d1, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', d1::text, true);
  execute 'set local role authenticated';
  update profiles set preferred_name = 'Dee', pronouns = 'she/her', bio = 'Gut health dietitian.', phone = '0400 111 222' where id = d1;
  get diagnostics n = row_count; if n <> 1 then raise exception 'FAIL T1a own edit'; end if;
  raised := false; begin update profiles set role = 'admin' where id = d1; exception when raise_exception then raised := true; end;
  if not raised then raise exception 'FAIL T1b own role'; end if;
  raised := false; begin update profiles set email = 'x@example.com' where id = d1; exception when raise_exception then raised := true; end;
  if not raised then raise exception 'FAIL T1c own email'; end if;
  update profiles set full_name = 'hacked' where id = i1;
  get diagnostics n = row_count; if n <> 0 then raise exception 'FAIL T1d edited someone else'; end if;
  delete from profiles where id = d1;
  get diagnostics n = row_count; if n <> 0 then raise exception 'FAIL T1e deleted own profile'; end if;
  execute 'reset role';
  perform set_config('request.jwt.claims', json_build_object('sub', i1, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', i1::text, true);
  execute 'set local role authenticated';
  raised := false; begin update profiles set supervisor_id = i2 where id = i1; exception when raise_exception then raised := true; end;
  if not raised then raise exception 'FAIL T1f intern as supervisor'; end if;
  update profiles set supervisor_id = d1, university = 'ZZ University', placement_start = today - 60, placement_end = today - 1 where id = i1;
  get diagnostics n = row_count; if n <> 1 then raise exception 'FAIL T1g intern own placement'; end if;
  execute 'reset role';
  perform set_config('request.jwt.claims', json_build_object('sub', cl, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', cl::text, true);
  execute 'set local role authenticated';
  update profiles set full_name = 'Changed' where id = cl;
  get diagnostics n = row_count; if n <> 0 then raise exception 'FAIL T1h client edited profile'; end if;
  execute 'reset role';
  execute 'set local role anon';
  raised := false; begin update profiles set full_name = 'x' where id = adm; exception when insufficient_privilege then raised := true; end;
  if not raised then raise exception 'FAIL T1i anon write grant'; end if;
  execute 'reset role';
  -- admins: change other people's roles, not their own; can't delete admins or themselves
  perform set_config('request.jwt.claims', json_build_object('sub', adm, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', adm::text, true);
  execute 'set local role authenticated';
  update profiles set role = 'intern' where id = d1;
  update profiles set role = 'dietitian' where id = d1;
  if (select role from profiles where id = d1) <> 'dietitian' then raise exception 'FAIL T1j admin role change'; end if;
  raised := false; begin update profiles set role = 'dietitian' where id = adm; exception when raise_exception then raised := true; end;
  if not raised then raise exception 'FAIL T1k admin own role'; end if;
  raised := false; begin delete from profiles where id = adm2; exception when raise_exception then raised := true; end;
  if not raised then raise exception 'FAIL T1l deleted an admin'; end if;
  raised := false; begin delete from profiles where id = adm; exception when raise_exception then raised := true; end;
  if not raised then raise exception 'FAIL T1m admin deleted self'; end if;
  execute 'reset role';
  log := 'T1 own details only; no own role/email; admins change others'' roles; admins and self undeletable; anon/clients can''t write';

  -- T2 credentials: own only; only admins mark checked; changing details clears the check
  perform set_config('request.jwt.claims', json_build_object('sub', d1, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', d1::text, true);
  execute 'set local role authenticated';
  insert into staff_credentials (profile_id, type, number, expires_on) values (d1, 'apd', 'APD123', today + 20) returning id into apd;
  raised := false; begin insert into staff_credentials (profile_id, type, number) values (i1, 'wwcc', 'X'); exception when others then raised := true; end;
  if not raised then raise exception 'FAIL T2a wrote someone else''s credential'; end if;
  raised := false; begin update staff_credentials set checked_at = now() where id = apd; exception when raise_exception then raised := true; end;
  if not raised then raise exception 'FAIL T2b self-checked'; end if;
  res := mark_credential_checked(apd, true);
  if (res->>'ok')::boolean then raise exception 'FAIL T2c dietitian marked checked'; end if;
  execute 'reset role';
  perform set_config('request.jwt.claims', json_build_object('sub', adm, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', adm::text, true);
  execute 'set local role authenticated';
  res := mark_credential_checked(apd, true);
  if not (res->>'ok')::boolean or (select checked_by from staff_credentials where id = apd) <> adm then raise exception 'FAIL T2d admin check %', res; end if;
  execute 'reset role';
  perform set_config('request.jwt.claims', json_build_object('sub', d1, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', d1::text, true);
  execute 'set local role authenticated';
  update staff_credentials set expires_on = today + 50 where id = apd;
  if (select checked_at from staff_credentials where id = apd) is not null then raise exception 'FAIL T2e check not cleared'; end if;
  execute 'reset role';
  perform set_config('request.jwt.claims', json_build_object('sub', i1, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', i1::text, true);
  execute 'set local role authenticated';
  insert into staff_credentials (profile_id, type, number, state, expires_on) values (i1, 'wwcc', 'WWC0001', 'NSW', today + 100);
  if (select count(*) from staff_credentials) <> 1 then raise exception 'FAIL T2f intern sees other credentials'; end if;
  execute 'reset role';
  log := log || ' | T2 own credentials only; only admins mark checked; edits clear the check';

  -- T3 status thresholds
  if credential_status(today - 1) <> 'expired' or credential_status(today) <> 'due_30' or credential_status(today + 30) <> 'due_30'
     or credential_status(today + 31) <> 'due_60' or credential_status(today + 60) <> 'due_60' or credential_status(today + 61) <> 'current'
     or credential_status(null) <> 'no_date' then raise exception 'FAIL T3 thresholds'; end if;
  log := log || ' | T3 expired / due in 30 / due in 60 / current';

  -- T4 team view
  perform set_config('request.jwt.claims', json_build_object('sub', d1, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', d1::text, true);
  execute 'set local role authenticated';
  d := team_compliance();
  if not (d->>'ok')::boolean or jsonb_array_length(d->'people') <> 2
     or not exists (select 1 from jsonb_array_elements(d->'people') p where (p->>'profile_id')::uuid = i1 and p->>'placement' = 'ended'
                    and exists (select 1 from jsonb_array_elements(p->'items') x where x->>'type' = 'wwcc' and x->>'status' = 'current' and x->'number' = 'null'::jsonb))
     or not exists (select 1 from jsonb_array_elements(d->'people') p where (p->>'is_me')::boolean
                    and exists (select 1 from jsonb_array_elements(p->'items') x where x->>'type' = 'apd' and x->>'status' = 'due_60' and x->>'number' = 'APD123'))
     or (d->>'needs_attention')::int <> 1 then raise exception 'FAIL T4a dietitian view %', d; end if;
  update credential_types set required_for = '{intern}' where key = 'police_check';
  get diagnostics n = row_count; if n <> 0 then raise exception 'FAIL T4b dietitian edited credential types'; end if;
  execute 'reset role';
  perform set_config('request.jwt.claims', json_build_object('sub', i1, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', i1::text, true);
  execute 'set local role authenticated';
  d := team_compliance();
  if jsonb_array_length(d->'people') <> 1 or not exists (select 1 from jsonb_array_elements(d->'people'->0->'items') x where x->>'number' = 'WWC0001')
    then raise exception 'FAIL T4c intern view %', d; end if;
  execute 'reset role';
  perform set_config('request.jwt.claims', json_build_object('sub', adm, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', adm::text, true);
  execute 'set local role authenticated';
  update credential_types set required_for = '{intern}' where key = 'police_check';
  d := team_compliance();
  if jsonb_array_length(d->'people') <> (select count(*) from profiles where role in ('admin', 'dietitian', 'intern'))
     or not exists (select 1 from jsonb_array_elements(d->'people') p where (p->>'profile_id')::uuid = i2 and (p->>'needs_attention')::boolean
                    and exists (select 1 from jsonb_array_elements(p->'items') x where x->>'type' = 'police_check' and x->>'status' = 'missing'))
     or not exists (select 1 from jsonb_array_elements(d->'people') p where (p->>'profile_id')::uuid = i1
                    and exists (select 1 from jsonb_array_elements(p->'items') x where x->>'type' = 'wwcc' and x->>'number' = 'WWC0001'))
    then raise exception 'FAIL T4d admin view'; end if;
  execute 'reset role';
  log := log || ' | T4 admin sees everyone with details; dietitian sees self + own interns (status only); intern sees self; required → Missing; placement ended flagged';

  -- T5 private documents: own folder (or admin) only
  perform set_config('request.jwt.claims', json_build_object('sub', d1, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', d1::text, true);
  execute 'set local role authenticated';
  insert into storage.objects (bucket_id, name) values ('staff-documents', d1::text || '/apd-zz.pdf');
  raised := false; begin insert into storage.objects (bucket_id, name) values ('staff-documents', i1::text || '/zz.pdf'); exception when others then raised := true; end;
  if not raised then raise exception 'FAIL T5a wrote into someone else''s folder'; end if;
  execute 'reset role';
  perform set_config('request.jwt.claims', json_build_object('sub', i1, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', i1::text, true);
  execute 'set local role authenticated';
  if exists (select 1 from storage.objects where bucket_id = 'staff-documents' and name like d1::text || '/%') then raise exception 'FAIL T5b intern read a dietitian''s file'; end if;
  execute 'reset role';
  perform set_config('request.jwt.claims', json_build_object('sub', adm, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', adm::text, true);
  execute 'set local role authenticated';
  if not exists (select 1 from storage.objects where bucket_id = 'staff-documents' and name = d1::text || '/apd-zz.pdf') then raise exception 'FAIL T5c admin can''t read'; end if;
  execute 'reset role';
  log := log || ' | T5 documents: own folder or admin only';

  raise exception 'ALL PASS (rolled back): %', log;
end $$;
