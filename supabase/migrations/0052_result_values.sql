-- 0052_result_values.sql — values read from bloods (and later DEXA) reports (owner, 22 Oct 2026).
-- APPLIED live 22 Oct 2026 (apply_migration "0052_result_values"); result_values_0052 passes live.
-- Plan: docs/RESULTS-READER-PLAN.md. The reader runs in the staff member's browser (no outside service) when a result
-- with a PDF is opened, and writes one row per value it finds:
--   • 'sure' values (digital PDF text, known marker, recognised unit, clean number, plausible, range and flag agree,
--     test date found) go straight in as 'accepted';
--   • everything else is 'please_check' until a dietitian confirms, corrects or rejects it.
--   The database decides the status from the reader's certainty; text read from photos or scans (ocr) is never 'sure'.
-- People can also add values by hand ('manual', confirmed at once). Corrections keep what the reader read in `original`.
-- Admins and dietitians only, like the clinical records themselves; interns and clients see nothing.
-- Test: tests/sql/result_values_0052.test.sql

-- 1. when a record was read ------------------------------------------------------------------------------------------
alter table client_clinical_records
  add column if not exists read_at      timestamptz,
  add column if not exists read_by      uuid references profiles (id) on delete set null,
  add column if not exists read_summary jsonb;
comment on column client_clinical_records.read_summary is 'Last reader run: { reader_version, method, sure, please_check, unmatched, pages }.';

create or replace function client_clinical_records_read_stamp() returns trigger
language plpgsql set search_path = public as $$
begin
  if current_user in ('authenticated', 'anon') and new.read_summary is distinct from old.read_summary then
    new.read_at := now();
    new.read_by := auth.uid();
  end if;
  return new;
end $$;
drop trigger if exists client_clinical_records_read_stamp on client_clinical_records;
create trigger client_clinical_records_read_stamp before update on client_clinical_records
  for each row execute function client_clinical_records_read_stamp();

-- 2. the values -------------------------------------------------------------------------------------------------------
create table if not exists client_result_values (
  id               uuid primary key default gen_random_uuid(),
  record_id        uuid not null references client_clinical_records (id) on delete cascade,
  client_id        uuid not null references clients (id) on delete cascade,
  marker_code      text references clinical_markers (code) on update cascade,   -- null: looked like a result, no marker matched
  name_as_printed  text not null check (length(name_as_printed) <= 200),
  value            numeric,                -- in the unit as printed
  value_text       text not null check (length(value_text) <= 60),   -- as printed, e.g. '45', '<5'
  unit_as_printed  text check (length(unit_as_printed) <= 40),
  value_std        numeric,                -- in the marker's own unit, when an exact conversion is known
  lab_low          numeric,
  lab_high         numeric,
  lab_range_text   text check (length(lab_range_text) <= 80),
  lab_flag         text check (lab_flag in ('H', 'L', 'HH', 'LL', '*')),
  measured_on      date,
  page             int,
  line_text        text check (length(line_text) <= 500),
  method           text not null check (method in ('text', 'ocr', 'manual')),
  certainty        text not null check (certainty in ('sure', 'check')),
  check_reasons    text[] not null default '{}',
  status           text not null check (status in ('accepted', 'please_check', 'confirmed', 'corrected', 'rejected')),
  original         jsonb,
  decided_by       uuid references profiles (id) on delete set null,
  decided_by_name  text,
  decided_at       timestamptz,
  reader_version   text,
  created_by       uuid references profiles (id) on delete set null,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  constraint client_result_values_ocr_never_sure check (method <> 'ocr' or certainty = 'check'),
  constraint client_result_values_accepted_is_sure check (status <> 'accepted' or certainty = 'sure'));
create index if not exists client_result_values_record on client_result_values (record_id);
create index if not exists client_result_values_client_marker on client_result_values (client_id, marker_code, measured_on desc);
comment on table client_result_values is 'Values read from a clinical record''s report. accepted (reader sure), please_check, confirmed, corrected (original keeps the reader''s reading), rejected. Use client_result_values_usable.';

create or replace function client_result_values_guard() returns trigger
language plpgsql set search_path = public as $$
declare v_name text; v_changed boolean;
begin
  if current_user not in ('authenticated', 'anon') then return coalesce(new, old); end if;
  if tg_op = 'DELETE' then return old; end if;
  v_name := (select coalesce(nullif(btrim(full_name), ''), email) from profiles where id = auth.uid());
  if tg_op = 'INSERT' then
    new.client_id := (select client_id from client_clinical_records where id = new.record_id);
    new.created_by := auth.uid();
    new.original := null;
    if new.method = 'manual' then
      new.certainty := 'sure'; new.status := 'confirmed'; new.check_reasons := '{}';
      new.decided_by := auth.uid(); new.decided_by_name := v_name; new.decided_at := now();
    else
      -- the database, not the app, turns the reader's certainty into a status
      new.status := case when new.certainty = 'sure' then 'accepted' else 'please_check' end;
      new.decided_by := null; new.decided_by_name := null; new.decided_at := null;
    end if;
    return new;
  end if;
  -- UPDATE: what the reader saw stays as it was
  if new.record_id is distinct from old.record_id or new.client_id is distinct from old.client_id
     or new.name_as_printed is distinct from old.name_as_printed or new.line_text is distinct from old.line_text
     or new.page is distinct from old.page or new.method is distinct from old.method
     or new.certainty is distinct from old.certainty or new.check_reasons is distinct from old.check_reasons
     or new.reader_version is distinct from old.reader_version or new.created_by is distinct from old.created_by
     or new.original is distinct from old.original then
    raise exception 'What the reader read can''t be changed. Correct the value instead.';
  end if;
  v_changed := new.marker_code is distinct from old.marker_code or new.value is distinct from old.value
     or new.value_text is distinct from old.value_text or new.unit_as_printed is distinct from old.unit_as_printed
     or new.value_std is distinct from old.value_std or new.measured_on is distinct from old.measured_on
     or new.lab_low is distinct from old.lab_low or new.lab_high is distinct from old.lab_high
     or new.lab_range_text is distinct from old.lab_range_text or new.lab_flag is distinct from old.lab_flag;
  if v_changed then
    if old.method <> 'manual' then
      new.status := 'corrected';
      if old.original is null then
        new.original := jsonb_build_object('marker_code', old.marker_code, 'value', old.value, 'value_text', old.value_text,
          'unit_as_printed', old.unit_as_printed, 'value_std', old.value_std, 'measured_on', old.measured_on,
          'lab_low', old.lab_low, 'lab_high', old.lab_high, 'lab_range_text', old.lab_range_text, 'lab_flag', old.lab_flag);
      else
        new.original := old.original;
      end if;
    else
      new.status := 'confirmed';
    end if;
  elsif new.status is distinct from old.status then
    if new.status not in ('confirmed', 'rejected') then
      raise exception 'A value can be confirmed, corrected or rejected.';
    end if;
  else
    new.decided_by := old.decided_by; new.decided_by_name := old.decided_by_name; new.decided_at := old.decided_at;
    new.updated_at := now();
    return new;
  end if;
  new.decided_by := auth.uid(); new.decided_by_name := v_name; new.decided_at := now();
  new.updated_at := now();
  return new;
end $$;
drop trigger if exists client_result_values_guard on client_result_values;
create trigger client_result_values_guard before insert or update or delete on client_result_values
  for each row execute function client_result_values_guard();

alter table client_result_values enable row level security;
drop policy if exists client_result_values_clinician on client_result_values;
create policy client_result_values_clinician on client_result_values for all to authenticated
  using (is_clinician()) with check (is_clinician());
revoke all on client_result_values from anon;

-- 3. what can be used (trends, flags, the planner later) ----------------------------------------------------------------
create or replace view client_result_values_usable with (security_invoker = true) as
  select v.*, coalesce(v.value_std, v.value) as value_for_marker
  from client_result_values v
  where v.status in ('accepted', 'confirmed', 'corrected') and v.marker_code is not null;
revoke all on client_result_values_usable from anon;
grant select on client_result_values_usable to authenticated;

revoke execute on function client_result_values_guard(), client_clinical_records_read_stamp() from public, anon, authenticated;
