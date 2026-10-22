-- 0053_document_intake.sql — read a client's documents into their file (owner, 22 Oct 2026). Plan: docs/DOCUMENT-INTAKE-PLAN.md
-- APPLIED live 22 Oct 2026 (apply_migration "0053_document_intake"); document_intake_0053, client_results_0050 and p0_lockdown pass live.
-- The AI pass is the Edge Function supabase/functions/document-ai (deployed 22 Oct; needs the ANTHROPIC_API_KEY secret).
--  1. Documents: client_clinical_records takes letters and transcripts too (new kinds), with the document's text
--     (document_text, extracted in the browser) and the last AI pass (ai_summary).
--  2. New parts of the client file: address on clients; client_referrals, client_care_team, client_medications,
--     client_conditions, client_allergies (staff with access to the client), client_medicare (admins and dietitians;
--     number checked with the card's check digit).
--  3. client_document_facts: every item found in a document, by the rules reader ('rules'), the AI pass ('ai') or a
--     person highlighting text ('manual'). Every quoted item must quote text that is really in the document — the
--     database refuses any other. AI items are never 'sure'.
--  4. apply_document_facts(record): files the sure items — fills EMPTY fields and adds new list items, never overwrites;
--     a different value already in the file becomes a 'conflict'; uncertain items wait as 'please_check'.
--     decide_document_fact(fact, 'apply' | 'reject', value): a person's decision; 'apply' on a conflict replaces the
--     value in the file with the document's (or the corrected) value.
-- Test: tests/sql/document_intake_0053.test.sql

-- 1. documents -----------------------------------------------------------------------------------------------------
alter table client_clinical_records drop constraint if exists client_clinical_records_kind_check;
alter table client_clinical_records add constraint client_clinical_records_kind_check check (kind in
  ('dexa', 'bloods', 'other', 'gp_letter', 'specialist_letter', 'discharge_summary', 'transcript', 'letter'));
alter table client_clinical_records
  add column if not exists document_text text check (document_text is null or length(document_text) <= 500000),
  add column if not exists doc_meta      jsonb,
  add column if not exists ai_summary    jsonb;
comment on column client_clinical_records.document_text is 'The document''s text as extracted in the browser (PDF text layer, .docx, or a pasted transcript). Facts quote from it.';

-- 2. the client file ---------------------------------------------------------------------------------------------------
alter table clients
  add column if not exists address_line text check (address_line is null or length(address_line) <= 200),
  add column if not exists suburb       text check (suburb is null or length(suburb) <= 100),
  add column if not exists state        text check (state is null or state in ('NSW', 'VIC', 'QLD', 'WA', 'SA', 'TAS', 'ACT', 'NT')),
  add column if not exists postcode     text check (postcode is null or postcode ~ '^\d{4}$');

create table if not exists client_care_team (
  id              uuid primary key default gen_random_uuid(),
  client_id       uuid not null references clients (id) on delete cascade,
  record_id       uuid references client_clinical_records (id) on delete set null,
  role            text not null check (role in ('gp', 'specialist', 'other')),
  specialty       text check (length(specialty) <= 100),
  name            text not null check (length(btrim(name)) between 2 and 120),
  practice        text check (length(practice) <= 200),
  address         text check (length(address) <= 300),
  phone           text check (length(phone) <= 40),
  fax             text check (length(fax) <= 40),
  email           text check (length(email) <= 200),
  provider_number text check (provider_number is null or provider_number ~ '^[0-9]{6}[0-9A-Z][A-Z]$'),
  is_primary      boolean not null default false,
  notes           text check (length(notes) <= 1000),
  created_by      uuid references profiles (id) on delete set null default auth.uid(),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now());
create index if not exists client_care_team_client on client_care_team (client_id);

create table if not exists client_referrals (
  id                uuid primary key default gen_random_uuid(),
  client_id         uuid not null references clients (id) on delete cascade,
  record_id         uuid references client_clinical_records (id) on delete set null,
  pathway           text not null check (pathway in ('medicare_chronic', 'medicare_mental_health', 'ndis', 'dva',
                                                     'private_health', 'workers_comp', 'self', 'other')),
  plan_name         text check (length(plan_name) <= 120),      -- as printed, e.g. 'GPMP', 'TCA'
  referral_date     date,
  reason            text check (length(reason) <= 1000),
  sessions_approved int check (sessions_approved between 0 and 50),
  valid_until       date,
  referrer_id       uuid references client_care_team (id) on delete set null,
  status            text not null default 'active' check (status in ('active', 'closed')),
  notes             text check (length(notes) <= 1000),
  created_by        uuid references profiles (id) on delete set null default auth.uid(),
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now());
create index if not exists client_referrals_client on client_referrals (client_id);

create table if not exists client_medications (
  id          uuid primary key default gen_random_uuid(),
  client_id   uuid not null references clients (id) on delete cascade,
  record_id   uuid references client_clinical_records (id) on delete set null,
  name        text not null check (length(btrim(name)) between 2 and 120),
  strength    text check (length(strength) <= 80),
  form        text check (length(form) <= 60),
  dose        text check (length(dose) <= 80),
  frequency   text check (length(frequency) <= 160),
  as_printed  text check (length(as_printed) <= 400),
  active      boolean not null default true,
  started_on  date,
  stopped_on  date,
  notes       text check (length(notes) <= 500),
  created_by  uuid references profiles (id) on delete set null default auth.uid(),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now());
create index if not exists client_medications_client on client_medications (client_id);

create table if not exists client_conditions (
  id          uuid primary key default gen_random_uuid(),
  client_id   uuid not null references clients (id) on delete cascade,
  record_id   uuid references client_clinical_records (id) on delete set null,
  condition   text not null check (length(btrim(condition)) between 2 and 200),
  noted_on    date,
  status      text not null default 'current' check (status in ('current', 'past')),
  as_printed  text check (length(as_printed) <= 400),
  notes       text check (length(notes) <= 500),
  created_by  uuid references profiles (id) on delete set null default auth.uid(),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now());
create index if not exists client_conditions_client on client_conditions (client_id);

create table if not exists client_allergies (
  id          uuid primary key default gen_random_uuid(),
  client_id   uuid not null references clients (id) on delete cascade,
  record_id   uuid references client_clinical_records (id) on delete set null,
  kind        text not null check (kind in ('allergy', 'intolerance', 'nil_known')),
  substance   text check (length(substance) <= 120),
  reaction    text check (length(reaction) <= 200),
  as_printed  text check (length(as_printed) <= 400),
  noted_on    date,
  created_by  uuid references profiles (id) on delete set null default auth.uid(),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  constraint client_allergies_substance check ((kind = 'nil_known') = (substance is null)));
create index if not exists client_allergies_client on client_allergies (client_id);

create or replace function medicare_number_valid(p text) returns boolean
language sql immutable set search_path = public as $$
  select coalesce(p ~ '^[2-6][0-9]{9}$' and
    ((substr(p, 1, 1)::int * 1 + substr(p, 2, 1)::int * 3 + substr(p, 3, 1)::int * 7 + substr(p, 4, 1)::int * 9
    + substr(p, 5, 1)::int * 1 + substr(p, 6, 1)::int * 3 + substr(p, 7, 1)::int * 7 + substr(p, 8, 1)::int * 9) % 10)
    = substr(p, 9, 1)::int, false)
$$;

create table if not exists client_medicare (
  client_id  uuid primary key references clients (id) on delete cascade,
  number     text not null check (medicare_number_valid(number)),
  irn        int check (irn between 1 and 9),
  valid_to   text check (valid_to is null or valid_to ~ '^(0[1-9]|1[0-2])/20[0-9]{2}$'),
  record_id  uuid references client_clinical_records (id) on delete set null,
  updated_by uuid references profiles (id) on delete set null default auth.uid(),
  updated_at timestamptz not null default now());
comment on table client_medicare is 'Medicare card number (10 digits incl. issue number, check digit verified), IRN and valid-to (MM/YYYY). Admins and dietitians only.';

-- access: the client-file lists follow the client (allocated interns too); Medicare is admins and dietitians only
do $$
declare t text;
begin
  foreach t in array array['client_care_team', 'client_referrals', 'client_medications', 'client_conditions', 'client_allergies'] loop
    execute format('alter table %I enable row level security', t);
    execute format('drop policy if exists %I on %I', t || '_access', t);
    execute format('create policy %I on %I for all to authenticated using (can_access_client(client_id)) with check (can_access_client(client_id))', t || '_access', t);
    execute format('revoke all on %I from anon', t);
  end loop;
end $$;
alter table client_medicare enable row level security;
drop policy if exists client_medicare_clinician on client_medicare;
create policy client_medicare_clinician on client_medicare for all to authenticated using (is_clinician()) with check (is_clinician());
revoke all on client_medicare from anon;

-- 3. facts found in documents ------------------------------------------------------------------------------------------
create table if not exists client_document_facts (
  id              uuid primary key default gen_random_uuid(),
  record_id       uuid not null references client_clinical_records (id) on delete cascade,
  client_id       uuid not null references clients (id) on delete cascade,
  section         text not null check (section in ('client', 'medicare', 'care_team', 'referral', 'medication', 'condition',
                                                   'allergy', 'measurement', 'goal', 'food_rule', 'supplement', 'note')),
  field           text not null check (field ~ '^[a-z_]{1,40}$'),
  value           jsonb not null,
  quote           text not null default '' check (length(quote) <= 2000),
  page            int,
  method          text not null check (method in ('rules', 'ai', 'manual')),
  certainty       text not null check (certainty in ('sure', 'check')),
  check_reasons   text[] not null default '{}',
  status          text not null default 'pending' check (status in ('pending', 'applied', 'please_check', 'conflict',
                                                                      'confirmed', 'rejected')),
  target_table    text,
  target_id       uuid,
  existing_value  text,           -- what the file already had, for conflicts
  applied_at      timestamptz,
  decided_by      uuid references profiles (id) on delete set null,
  decided_by_name text,
  decided_at      timestamptz,
  ai_model        text,
  created_by      uuid references profiles (id) on delete set null,
  created_at      timestamptz not null default now(),
  constraint client_document_facts_ai_checked check (method <> 'ai' or certainty = 'check'),
  constraint client_document_facts_quoted check (method = 'manual' or quote <> ''));
create index if not exists client_document_facts_record on client_document_facts (record_id, status);
comment on table client_document_facts is 'Items found in a client document. Every quote is verified to be in the document''s text. Filed by apply_document_facts / decide_document_fact.';

create or replace function doc_text_norm(p text) returns text
language sql immutable set search_path = public as $$ select btrim(regexp_replace(lower(coalesce(p, '')), '\s+', ' ', 'g')) $$;

create or replace function client_document_facts_guard() returns trigger
language plpgsql set search_path = public as $$
declare v_text text;
begin
  if current_user not in ('authenticated', 'anon') then return new; end if;   -- migrations, the owner
  if tg_op = 'INSERT' then
    new.client_id := (select client_id from client_clinical_records where id = new.record_id);
    new.created_by := auth.uid();
    new.status := 'pending';
    new.target_table := null; new.target_id := null; new.existing_value := null; new.applied_at := null;
    new.decided_by := null; new.decided_by_name := null; new.decided_at := null;
    if new.method = 'ai' then new.certainty := 'check'; end if;
    if new.quote <> '' then
      select document_text into v_text from client_clinical_records where id = new.record_id;
      if v_text is null or position(doc_text_norm(new.quote) in doc_text_norm(v_text)) = 0 then
        raise exception 'That quote isn''t in the document, so the item can''t be added.';
      end if;
    end if;
    return new;
  end if;
  if coalesce(current_setting('goh.facts', true), '') <> 'on' then
    raise exception 'Found items are filed with apply_document_facts or decide_document_fact.';
  end if;
  return new;
end $$;
drop trigger if exists client_document_facts_guard on client_document_facts;
create trigger client_document_facts_guard before insert or update on client_document_facts
  for each row execute function client_document_facts_guard();

alter table client_document_facts enable row level security;
drop policy if exists client_document_facts_clinician on client_document_facts;
create policy client_document_facts_clinician on client_document_facts for all to authenticated
  using (is_clinician()) with check (is_clinician());
revoke all on client_document_facts from anon;

-- 4. filing -------------------------------------------------------------------------------------------------------------------
-- Files one fact. p_overwrite: a person chose the document's value over what's in the file.
-- Returns { status: 'applied' | 'conflict' | 'please_check', target_table, target_id, existing }.
create or replace function document_fact_file(f client_document_facts, p_value jsonb, p_overwrite boolean) returns jsonb
language plpgsql set search_path = public as $$
declare
  v_types constant jsonb := '{"full_name":"text","date_of_birth":"date","sex":"text","phone":"text","email":"text",
                               "address_line":"text","suburb":"text","state":"text","postcode":"text","height_cm":"numeric"}';
  v_cur text; v_new text; v_id uuid; v_row record; v_ref uuid; k text; v_diff boolean := false;
begin
  if f.section = 'client' then
    if not (v_types ? f.field) then return jsonb_build_object('status', 'please_check'); end if;
    v_new := p_value ->> 'value';
    execute format('select %I::text from clients where id = $1', f.field) into v_cur using f.client_id;
    if v_cur is not null and btrim(v_cur) <> '' and lower(btrim(v_cur)) <> lower(btrim(v_new)) and not p_overwrite then
      return jsonb_build_object('status', 'conflict', 'target_table', 'clients', 'target_id', f.client_id, 'existing', v_cur);
    end if;
    execute format('update clients set %I = $1::%s where id = $2', f.field, v_types ->> f.field) using v_new, f.client_id;
    return jsonb_build_object('status', 'applied', 'target_table', 'clients', 'target_id', f.client_id);

  elsif f.section = 'medicare' then
    select number || coalesce('/' || irn, '') into v_cur from client_medicare where client_id = f.client_id;
    if v_cur is not null and v_cur <> (p_value ->> 'number') || coalesce('/' || (p_value ->> 'irn'), '') and not p_overwrite then
      return jsonb_build_object('status', 'conflict', 'target_table', 'client_medicare', 'target_id', f.client_id, 'existing', v_cur);
    end if;
    insert into client_medicare (client_id, number, irn, valid_to, record_id)
    values (f.client_id, p_value ->> 'number', (p_value ->> 'irn')::int, p_value ->> 'valid_to', f.record_id)
    on conflict (client_id) do update set number = excluded.number, irn = excluded.irn,
      valid_to = coalesce(excluded.valid_to, client_medicare.valid_to), record_id = excluded.record_id, updated_at = now();
    return jsonb_build_object('status', 'applied', 'target_table', 'client_medicare', 'target_id', f.client_id);

  elsif f.section = 'care_team' then
    select * into v_row from client_care_team c
     where c.client_id = f.client_id
       and ((p_value ->> 'provider_number' is not null and c.provider_number = p_value ->> 'provider_number')
            or lower(btrim(c.name)) = lower(btrim(p_value ->> 'name')))
     order by c.created_at limit 1;
    if not found then
      insert into client_care_team (client_id, record_id, role, specialty, name, practice, address, phone, fax, email, provider_number, is_primary)
      values (f.client_id, f.record_id, coalesce(p_value ->> 'role', 'other'), p_value ->> 'specialty', p_value ->> 'name',
              p_value ->> 'practice', p_value ->> 'address', p_value ->> 'phone', p_value ->> 'fax', p_value ->> 'email',
              p_value ->> 'provider_number',
              coalesce(p_value ->> 'role', '') = 'gp' and not exists (select 1 from client_care_team where client_id = f.client_id and is_primary))
      returning id into v_id;
      return jsonb_build_object('status', 'applied', 'target_table', 'client_care_team', 'target_id', v_id);
    end if;
    foreach k in array array['specialty', 'practice', 'address', 'phone', 'fax', 'email', 'provider_number'] loop
      if p_value ->> k is not null and (to_jsonb(v_row) ->> k) is not null
         and lower(btrim(to_jsonb(v_row) ->> k)) <> lower(btrim(p_value ->> k)) then v_diff := true; end if;
    end loop;
    if v_diff and not p_overwrite then
      return jsonb_build_object('status', 'conflict', 'target_table', 'client_care_team', 'target_id', v_row.id,
                                'existing', concat_ws(' · ', v_row.practice, v_row.phone, v_row.provider_number));
    end if;
    update client_care_team set
      specialty = case when p_overwrite then coalesce(p_value ->> 'specialty', specialty) else coalesce(specialty, p_value ->> 'specialty') end,
      practice = case when p_overwrite then coalesce(p_value ->> 'practice', practice) else coalesce(practice, p_value ->> 'practice') end,
      address = case when p_overwrite then coalesce(p_value ->> 'address', address) else coalesce(address, p_value ->> 'address') end,
      phone = case when p_overwrite then coalesce(p_value ->> 'phone', phone) else coalesce(phone, p_value ->> 'phone') end,
      fax = case when p_overwrite then coalesce(p_value ->> 'fax', fax) else coalesce(fax, p_value ->> 'fax') end,
      email = case when p_overwrite then coalesce(p_value ->> 'email', email) else coalesce(email, p_value ->> 'email') end,
      provider_number = case when p_overwrite then coalesce(p_value ->> 'provider_number', provider_number) else coalesce(provider_number, p_value ->> 'provider_number') end,
      updated_at = now()
    where id = v_row.id;
    return jsonb_build_object('status', 'applied', 'target_table', 'client_care_team', 'target_id', v_row.id);

  elsif f.section = 'referral' then
    select id into v_id from client_referrals
     where client_id = f.client_id and pathway = coalesce(p_value ->> 'pathway', 'other')
       and referral_date is not distinct from (p_value ->> 'referral_date')::date;
    if found then return jsonb_build_object('status', 'applied', 'target_table', 'client_referrals', 'target_id', v_id); end if;
    select id into v_ref from client_care_team
     where client_id = f.client_id and lower(btrim(name)) = lower(btrim(p_value ->> 'referrer_name')) limit 1;
    insert into client_referrals (client_id, record_id, pathway, plan_name, referral_date, reason, sessions_approved, valid_until, referrer_id)
    values (f.client_id, f.record_id, coalesce(p_value ->> 'pathway', 'other'), p_value ->> 'plan_name', (p_value ->> 'referral_date')::date,
            p_value ->> 'reason', (p_value ->> 'sessions_approved')::int, (p_value ->> 'valid_until')::date, v_ref)
    returning id into v_id;
    return jsonb_build_object('status', 'applied', 'target_table', 'client_referrals', 'target_id', v_id);

  elsif f.section = 'medication' then
    select id into v_id from client_medications
     where client_id = f.client_id and active and lower(btrim(name)) = lower(btrim(p_value ->> 'name'))
       and coalesce(lower(strength), '') = coalesce(lower(p_value ->> 'strength'), '');
    if not found then
      insert into client_medications (client_id, record_id, name, strength, form, dose, frequency, as_printed)
      values (f.client_id, f.record_id, p_value ->> 'name', p_value ->> 'strength', p_value ->> 'form', p_value ->> 'dose',
              p_value ->> 'frequency', left(f.quote, 400))
      returning id into v_id;
    end if;
    return jsonb_build_object('status', 'applied', 'target_table', 'client_medications', 'target_id', v_id);

  elsif f.section = 'condition' then
    select id into v_id from client_conditions where client_id = f.client_id and lower(btrim(condition)) = lower(btrim(p_value ->> 'condition'));
    if not found then
      insert into client_conditions (client_id, record_id, condition, noted_on, status, as_printed)
      values (f.client_id, f.record_id, p_value ->> 'condition', (p_value ->> 'noted_on')::date,
              coalesce(p_value ->> 'status', 'current'), left(f.quote, 400))
      returning id into v_id;
    end if;
    return jsonb_build_object('status', 'applied', 'target_table', 'client_conditions', 'target_id', v_id);

  elsif f.section = 'allergy' then
    if p_value ->> 'kind' = 'nil_known' then
      if exists (select 1 from client_allergies where client_id = f.client_id and kind <> 'nil_known') and not p_overwrite then
        return jsonb_build_object('status', 'conflict', 'target_table', 'client_allergies', 'target_id', null,
          'existing', (select string_agg(substance, ', ') from client_allergies where client_id = f.client_id and kind <> 'nil_known'));
      end if;
      select id into v_id from client_allergies where client_id = f.client_id and kind = 'nil_known';
      if not found then
        insert into client_allergies (client_id, record_id, kind, as_printed) values (f.client_id, f.record_id, 'nil_known', left(f.quote, 400))
        returning id into v_id;
      end if;
    else
      select id into v_id from client_allergies where client_id = f.client_id and lower(btrim(substance)) = lower(btrim(p_value ->> 'substance'));
      if not found then
        insert into client_allergies (client_id, record_id, kind, substance, reaction, as_printed)
        values (f.client_id, f.record_id, coalesce(p_value ->> 'kind', 'allergy'), p_value ->> 'substance', p_value ->> 'reaction', left(f.quote, 400))
        returning id into v_id;
      end if;
    end if;
    return jsonb_build_object('status', 'applied', 'target_table', 'client_allergies', 'target_id', v_id);

  elsif f.section = 'measurement' and f.field = 'weight_kg' then
    select id into v_id from client_weights where client_id = f.client_id
       and recorded_on = coalesce((p_value ->> 'measured_on')::date, current_date) and weight_kg = (p_value ->> 'value')::numeric;
    if not found then
      insert into client_weights (client_id, weight_kg, recorded_on, note)
      values (f.client_id, (p_value ->> 'value')::numeric, coalesce((p_value ->> 'measured_on')::date, current_date), 'From a document')
      returning id into v_id;
    end if;
    return jsonb_build_object('status', 'applied', 'target_table', 'client_weights', 'target_id', v_id);
  end if;
  -- goals, food rules, supplements, notes and anything else: a person files them
  return jsonb_build_object('status', 'please_check');
end $$;

create or replace function apply_document_facts(p_record_id uuid) returns jsonb
language plpgsql security invoker set search_path = public as $$
declare f client_document_facts%rowtype; r jsonb; v_applied int := 0; v_check int := 0; v_conflict int := 0;
begin
  if not is_clinician() then
    return jsonb_build_object('ok', false, 'message', 'Only dietitians and admins can file documents.');
  end if;
  perform set_config('goh.facts', 'on', true);
  for f in select * from client_document_facts where record_id = p_record_id and status = 'pending'
           order by case section when 'client' then 0 when 'medicare' then 1 when 'care_team' then 2 when 'referral' then 3 else 4 end,
                    created_at, id
           for update loop
    if f.certainty <> 'sure' then
      r := jsonb_build_object('status', 'please_check');
    else
      begin
        r := document_fact_file(f, f.value, false);
      exception when others then
        r := jsonb_build_object('status', 'please_check', 'error', sqlerrm);
      end;
    end if;
    update client_document_facts set status = r ->> 'status', target_table = r ->> 'target_table',
      target_id = (r ->> 'target_id')::uuid, existing_value = r ->> 'existing',
      check_reasons = case when r ? 'error' then check_reasons || ('couldn''t file it: ' || (r ->> 'error')) else check_reasons end,
      applied_at = case when r ->> 'status' = 'applied' then now() end
    where id = f.id;
    if r ->> 'status' = 'applied' then v_applied := v_applied + 1;
    elsif r ->> 'status' = 'conflict' then v_conflict := v_conflict + 1;
    else v_check := v_check + 1; end if;
  end loop;
  perform set_config('goh.facts', '', true);
  return jsonb_build_object('ok', true, 'applied', v_applied, 'please_check', v_check, 'conflict', v_conflict,
    'message', format('%s filed, %s to check, %s different from the file.', v_applied, v_check, v_conflict));
end $$;

create or replace function decide_document_fact(p_fact_id uuid, p_decision text, p_value jsonb default null) returns jsonb
language plpgsql security invoker set search_path = public as $$
declare f client_document_facts%rowtype; r jsonb; v_name text;
begin
  if not is_clinician() then
    return jsonb_build_object('ok', false, 'message', 'Only dietitians and admins can file documents.');
  end if;
  select * into f from client_document_facts where id = p_fact_id for update;
  if not found then return jsonb_build_object('ok', false, 'message', 'Item not found.'); end if;
  if f.status in ('applied', 'confirmed', 'rejected') and p_decision = 'apply' and p_value is null then
    return jsonb_build_object('ok', false, 'message', 'This item has already been filed.');
  end if;
  v_name := (select coalesce(nullif(btrim(full_name), ''), email) from profiles where id = auth.uid());
  perform set_config('goh.facts', 'on', true);
  if p_decision = 'reject' then
    update client_document_facts set status = 'rejected', decided_by = auth.uid(), decided_by_name = v_name, decided_at = now() where id = f.id;
    perform set_config('goh.facts', '', true);
    return jsonb_build_object('ok', true, 'status', 'rejected', 'message', 'Left out of the file.');
  elsif p_decision <> 'apply' then
    perform set_config('goh.facts', '', true);
    return jsonb_build_object('ok', false, 'message', 'Choose apply or reject.');
  end if;
  begin
    r := document_fact_file(f, coalesce(p_value, f.value), true);
  exception when others then
    perform set_config('goh.facts', '', true);
    return jsonb_build_object('ok', false, 'message', 'Couldn''t file it: ' || sqlerrm);
  end;
  if r ->> 'status' = 'please_check' then
    -- sections a person files in the app (goals, food rules, supplements, notes): record the decision
    r := jsonb_build_object('status', 'applied');
  end if;
  update client_document_facts set status = 'confirmed', value = coalesce(p_value, value),
    target_table = coalesce(r ->> 'target_table', target_table), target_id = coalesce((r ->> 'target_id')::uuid, target_id),
    applied_at = now(), decided_by = auth.uid(), decided_by_name = v_name, decided_at = now()
  where id = f.id;
  perform set_config('goh.facts', '', true);
  return jsonb_build_object('ok', true, 'status', 'confirmed', 'message', 'Filed.');
end $$;

revoke execute on function client_document_facts_guard() from public, anon, authenticated;
-- document_fact_file runs as the caller (RLS applies), so calling it directly allows nothing the caller couldn't already do
revoke execute on function document_fact_file(client_document_facts, jsonb, boolean) from public, anon;
grant execute on function document_fact_file(client_document_facts, jsonb, boolean) to authenticated;
revoke execute on function apply_document_facts(uuid), decide_document_fact(uuid, text, jsonb), medicare_number_valid(text), doc_text_norm(text) from public, anon;
grant execute on function apply_document_facts(uuid), decide_document_fact(uuid, text, jsonb), medicare_number_valid(text), doc_text_norm(text) to authenticated;
