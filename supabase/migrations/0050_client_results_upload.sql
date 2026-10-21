-- 0050_client_results_upload.sql — clients send their own bloodwork and DEXA scans (owner, 22 Oct 2026).
-- Owner: "dietitians, admin and clients can upload their PDF for bloodwork or dexa scans".
-- APPLIED live 22 Oct 2026 (apply_migration "0050_client_results_upload"); client_results_0050 and p0_lockdown pass live.
-- Admins and dietitians already add these in the client's Clinical section (client_clinical_records + the private
-- clinical-records bucket, 0027). This adds the client's side:
--  1. client_clinical_records: source ('staff' | 'client'), client_note, reviewed_at / reviewed_by / reviewed_by_name.
--     A client's upload is "new" until a dietitian or admin marks it seen. Staff records are seen when added.
--     A guard keeps who uploaded it, the client's note and the client's file as they were.
--  2. Storage: a client reads and uploads only {their client id}/client-… files, never the staff files beside them,
--     and can delete only a file of theirs that isn't attached to a record (a cancelled or removed upload).
--  3. RPCs for the client app: my_results(), add_my_result(kind, date, file, note), remove_my_result(id)
--     (only before it's been seen). At most 20 unseen results at a time.
-- Interns still have no access to clinical records (unchanged). Clients never see staff records, summaries or values.
-- Test: tests/sql/client_results_0050.test.sql

-- 1. columns ---------------------------------------------------------------------------------------------------------
alter table client_clinical_records
  add column if not exists source           text not null default 'staff',
  add column if not exists client_note      text,
  add column if not exists reviewed_at      timestamptz,
  add column if not exists reviewed_by      uuid references profiles (id) on delete set null,
  add column if not exists reviewed_by_name text;
alter table client_clinical_records drop constraint if exists client_clinical_records_source;
alter table client_clinical_records add constraint client_clinical_records_source check (source in ('staff', 'client'));
alter table client_clinical_records drop constraint if exists client_clinical_records_client_note;
alter table client_clinical_records add constraint client_clinical_records_client_note
  check (client_note is null or length(client_note) <= 500);
create unique index if not exists client_clinical_records_one_file on client_clinical_records (file_path) where file_path is not null;
create index if not exists client_clinical_records_waiting on client_clinical_records (client_id)
  where source = 'client' and reviewed_at is null;
comment on column client_clinical_records.source is 'staff = added by a dietitian or admin; client = sent by the client from the app.';
comment on column client_clinical_records.client_note is 'The client''s own note when they sent it (max 500). Staff notes go in summary.';
comment on column client_clinical_records.reviewed_at is 'When a dietitian or admin marked the client''s upload as seen (staff records: when added).';

create or replace function client_clinical_records_guard() returns trigger
language plpgsql set search_path = public as $$
declare v_name text;
begin
  if current_user not in ('authenticated', 'anon') then return new; end if;   -- the client RPCs run as the owner
  v_name := (select coalesce(nullif(btrim(full_name), ''), email) from profiles where id = auth.uid());
  if tg_op = 'INSERT' then
    new.source := 'staff';
    new.client_note := null;
    new.uploaded_by := auth.uid();
    new.reviewed_at := now();
    new.reviewed_by := auth.uid();
    new.reviewed_by_name := v_name;
    return new;
  end if;
  if new.client_id is distinct from old.client_id then
    raise exception 'A record can''t be moved to another client.';
  end if;
  if new.source is distinct from old.source or new.client_note is distinct from old.client_note
     or new.uploaded_by is distinct from old.uploaded_by then
    raise exception 'Who sent a record, and the client''s note, can''t be changed.';
  end if;
  if old.source = 'client' and new.file_path is distinct from old.file_path then
    raise exception 'Keep the client''s file. Add a separate record for another file.';
  end if;
  if old.reviewed_at is not null then
    new.reviewed_at := old.reviewed_at; new.reviewed_by := old.reviewed_by; new.reviewed_by_name := old.reviewed_by_name;
  elsif new.reviewed_at is not null then
    new.reviewed_at := now(); new.reviewed_by := auth.uid(); new.reviewed_by_name := v_name;
  else
    new.reviewed_by := null; new.reviewed_by_name := null;
  end if;
  return new;
end $$;
drop trigger if exists client_clinical_records_guard on client_clinical_records;
create trigger client_clinical_records_guard before insert or update on client_clinical_records
  for each row execute function client_clinical_records_guard();

-- 2. storage: the client's own uploads only ---------------------------------------------------------------------------
create or replace function clinical_file_in_use(p_path text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from client_clinical_records where file_path = p_path)
$$;

update storage.buckets
   set allowed_mime_types = array['application/pdf', 'image/jpeg', 'image/png', 'image/heic', 'image/heif']
 where id = 'clinical-records';

drop policy if exists "clinical-records client read own" on storage.objects;
create policy "clinical-records client read own" on storage.objects for select to authenticated
  using (bucket_id = 'clinical-records' and name like public.my_client_id()::text || '/client-%');
drop policy if exists "clinical-records client upload own" on storage.objects;
create policy "clinical-records client upload own" on storage.objects for insert to authenticated
  with check (bucket_id = 'clinical-records' and name like public.my_client_id()::text || '/client-%');
drop policy if exists "clinical-records client remove unattached" on storage.objects;
create policy "clinical-records client remove unattached" on storage.objects for delete to authenticated
  using (bucket_id = 'clinical-records' and name like public.my_client_id()::text || '/client-%'
         and not public.clinical_file_in_use(name));

-- 3. client app RPCs -----------------------------------------------------------------------------------------------------
create or replace function my_results() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', r.id, 'kind', r.kind, 'recorded_on', r.recorded_on, 'note', r.client_note,
           'file_path', r.file_path, 'sent_at', r.created_at,
           'seen', r.reviewed_at is not null, 'seen_at', r.reviewed_at, 'seen_by_name', r.reviewed_by_name)
         order by r.recorded_on desc, r.created_at desc), '[]'::jsonb)
  from client_clinical_records r
  where r.client_id = my_client_id() and r.source = 'client'
$$;

create or replace function add_my_result(p_kind text, p_recorded_on date, p_file_path text, p_note text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_client uuid := my_client_id();
  v_today date := (now() at time zone coalesce(app_setting('timezone'), 'Australia/Sydney'))::date;
  v_id uuid;
begin
  if v_client is null then
    return jsonb_build_object('ok', false, 'message', 'Only client accounts can send results.');
  end if;
  if p_kind is null or p_kind not in ('bloods', 'dexa', 'other') then
    return jsonb_build_object('ok', false, 'message', 'Choose bloodwork, DEXA scan or other.');
  end if;
  if p_recorded_on is null then
    return jsonb_build_object('ok', false, 'message', 'Enter the date of the test.');
  end if;
  if p_recorded_on > v_today then
    return jsonb_build_object('ok', false, 'message', 'The test date can''t be in the future.');
  end if;
  if length(coalesce(p_note, '')) > 500 then
    return jsonb_build_object('ok', false, 'message', 'Keep the note to 500 characters.');
  end if;
  if p_file_path is null or p_file_path not like v_client::text || '/client-%'
     or not exists (select 1 from storage.objects o where o.bucket_id = 'clinical-records' and o.name = p_file_path) then
    return jsonb_build_object('ok', false, 'message', 'Upload the file first.');
  end if;
  if exists (select 1 from client_clinical_records where file_path = p_file_path) then
    return jsonb_build_object('ok', false, 'message', 'This file has already been sent.');
  end if;
  if (select count(*) from client_clinical_records
       where client_id = v_client and source = 'client' and reviewed_at is null) >= 20 then
    return jsonb_build_object('ok', false,
      'message', 'You have 20 results waiting for your dietitian. Please wait until they''ve looked at them.');
  end if;
  insert into client_clinical_records (client_id, kind, recorded_on, client_note, file_path, source, uploaded_by)
  values (v_client, p_kind, p_recorded_on, nullif(btrim(p_note), ''), p_file_path, 'client', auth.uid())
  returning id into v_id;
  return jsonb_build_object('ok', true, 'message', 'Sent to your dietitian.', 'id', v_id);
end $$;

create or replace function remove_my_result(p_id uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r client_clinical_records%rowtype;
begin
  select * into r from client_clinical_records where id = p_id and client_id = my_client_id() and source = 'client';
  if not found then
    return jsonb_build_object('ok', false, 'message', 'Result not found.');
  end if;
  if r.reviewed_at is not null then
    return jsonb_build_object('ok', false, 'message', 'Your dietitian has already seen this. Ask them if it should be removed.');
  end if;
  delete from client_clinical_records where id = r.id;
  return jsonb_build_object('ok', true, 'message', 'Removed.', 'file_path', r.file_path);
end $$;

-- grants -------------------------------------------------------------------------------------------------------------------
revoke execute on function client_clinical_records_guard() from public, anon, authenticated;
revoke execute on function clinical_file_in_use(text), my_results(), add_my_result(text, date, text, text), remove_my_result(uuid)
  from public, anon;
grant execute on function clinical_file_in_use(text), my_results(), add_my_result(text, date, text, text), remove_my_result(uuid)
  to authenticated;
