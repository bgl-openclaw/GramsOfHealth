-- 0044_intake_sections_and_selection.sql — editable intake sections, ordering, per-client forms.
-- Backend for the Lovable "Client questions" change (owner-approved 21 Oct 2026):
--   1. intake_sections: key, title, position, active, builtins (the fixed client details a section holds)
--   2. dietitians and admins edit sections and questions (never delete: switch off; answers are kept)
--   3. no more health-only answers: everyone with access to a client sees every answer
--   4. per-client form: client_intake.question_keys (NULL = every active question)
--   5. set_client_intake_questions(), reorder_intake(); my_intake / intake_missing / submit follow the
--      client's own form; client_intake_for_staff returns sections, the selection and every answer
-- Safeguards: sections that hold fixed details (about, goals, food, health) and the privacy-consent
-- question are locked on: they can't be switched off or left off a client's form.
-- Test: tests/sql/intake_sections_0044.test.sql

-- 1. sections ---------------------------------------------------------------------------------------
create table if not exists intake_sections (
  key      text primary key check (key ~ '^[a-z][a-z0-9_]*$'),
  title    text not null check (length(btrim(title)) between 1 and 60),
  position integer not null default 0,
  active   boolean not null default true,
  builtins text[] not null default '{}' check (builtins <@ array['details', 'goal', 'requirements', 'supplements'])
);
comment on column intake_sections.builtins is 'Fixed client details shown in this section: details (name, phone, date of birth, sex, height, weight, activity), goal, requirements (food needs), supplements. Set by migration only.';
insert into intake_sections (key, title, position, builtins) values
  ('about', 'About you', 10, '{details}'), ('goals', 'Your goals', 20, '{goal}'), ('food', 'Food', 30, '{requirements}'),
  ('health', 'Health', 40, '{supplements}'), ('lifestyle', 'Lifestyle', 50, '{}'), ('consent', 'Almost done', 60, '{}')
on conflict (key) do nothing;

alter table intake_sections enable row level security;
drop policy if exists intake_sections_read on intake_sections;
create policy intake_sections_read on intake_sections for select using (is_staff());
drop policy if exists intake_sections_insert on intake_sections;
create policy intake_sections_insert on intake_sections for insert with check (is_clinician());
drop policy if exists intake_sections_update on intake_sections;
create policy intake_sections_update on intake_sections for update using (is_clinician()) with check (is_clinician());
revoke all on intake_sections from anon;
revoke delete, truncate on intake_sections from authenticated;
grant select, insert, update on intake_sections to authenticated;   -- the guard trigger protects key and builtins

-- 2. questions: section → intake_sections, the locked consent question, dietitians may edit -------------
alter table intake_questions drop constraint if exists intake_questions_section_check;
alter table intake_questions drop constraint if exists intake_questions_section_fkey;
alter table intake_questions add constraint intake_questions_section_fkey foreign key (section) references intake_sections (key);
alter table intake_questions add column if not exists locked boolean not null default false;
comment on column intake_questions.locked is 'Always on every client''s form and can''t be switched off (privacy consent). Set by migration only.';
comment on column intake_questions.clinical is 'No longer used (0044: every staff member with access sees every answer).';
update intake_questions set locked = true where key = 'consent_privacy';

drop policy if exists intake_questions_admin_write on intake_questions;
drop policy if exists intake_questions_insert on intake_questions;
create policy intake_questions_insert on intake_questions for insert with check (is_clinician());
drop policy if exists intake_questions_update on intake_questions;
create policy intake_questions_update on intake_questions for update using (is_clinician()) with check (is_clinician());
revoke delete, truncate on intake_questions from authenticated;
grant select, insert, update on intake_questions to authenticated;  -- the guard trigger protects key and locked

-- guards (for app users; migrations run as the owner and may change builtins/locked): keys never change,
-- nothing is deleted, locked things stay on. Saving a whole row back unchanged is fine.
create or replace function intake_sections_guard() returns trigger
language plpgsql set search_path = public as $$
declare v_app boolean := current_user in ('authenticated', 'anon');
begin
  if tg_op = 'DELETE' then
    if v_app then raise exception 'Sections can''t be deleted. Switch the section off instead (answers are kept).'; end if;
    return old;
  end if;
  if tg_op = 'INSERT' then
    if v_app and cardinality(new.builtins) > 0 then raise exception 'New sections can''t hold the fixed client details.'; end if;
    return new;
  end if;
  if new.key <> old.key then raise exception 'A section''s key can''t change.'; end if;
  if v_app and new.builtins is distinct from old.builtins then raise exception 'The fixed client details can''t be moved between sections.'; end if;
  if old.active and not new.active and (cardinality(old.builtins) > 0
       or exists (select 1 from intake_questions q where q.section = old.key and q.locked)) then
    raise exception 'The % section holds details the app needs, so it can''t be switched off.', old.title;
  end if;
  return new;
end $$;
drop trigger if exists intake_sections_guard on intake_sections;
create trigger intake_sections_guard before insert or update or delete on intake_sections for each row execute function intake_sections_guard();

create or replace function intake_questions_guard() returns trigger
language plpgsql set search_path = public as $$
declare v_app boolean := current_user in ('authenticated', 'anon');
begin
  if tg_op = 'DELETE' then
    if v_app then raise exception 'Questions can''t be deleted. Switch the question off instead (answers are kept).'; end if;
    return old;
  end if;
  if tg_op = 'INSERT' then
    if v_app and new.locked then raise exception 'Only the privacy consent question is locked.'; end if;
    return new;
  end if;
  if new.key <> old.key then raise exception 'A question''s key can''t change (answers are stored under it).'; end if;
  if v_app and new.locked is distinct from old.locked then raise exception 'Only the privacy consent question is locked.'; end if;
  if old.locked and (not new.active or not new.required or new.kind <> old.kind) then
    raise exception 'The privacy consent question is always on every client''s form.';
  end if;
  return new;
end $$;
drop trigger if exists intake_questions_guard on intake_questions;
create trigger intake_questions_guard before insert or update or delete on intake_questions for each row execute function intake_questions_guard();

-- 3. per-client form ---------------------------------------------------------------------------------
alter table client_intake add column if not exists question_keys text[];
comment on column client_intake.question_keys is 'The questions on this client''s form. NULL = every active question (including ones added later). Locked questions are always included.';

-- the active questions on one client's form, with their section position (internal helper)
create or replace function intake_client_questions(p_client_id uuid)
returns table (key text, section text, label text, help text, kind text, options jsonb, required boolean, locked boolean, q_pos integer, s_pos integer)
language sql stable security definer set search_path = public as $$
  select q.key, q.section, q.label, q.help, q.kind, q.options, q.required, q.locked, q.position, s.position
  from intake_questions q
  join intake_sections s on s.key = q.section
  left join client_intake ci on ci.client_id = p_client_id
  where q.active and s.active
    and (q.locked or ci.question_keys is null or q.key = any (ci.question_keys))
$$;

create or replace function intake_missing(p_client_id uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  with c as (select * from clients where id = p_client_id),
       a as (select coalesce((select answers from client_intake where client_id = p_client_id), '{}'::jsonb) answers),
       core as (
         select 1 o, 'Your full name' l where (select coalesce(btrim(full_name), '') = '' from c)
         union all select 2, 'Date of birth' where (select date_of_birth is null from c)
         union all select 3, 'Height' where (select height_cm is null from c)
         union all select 4, 'Current weight' where not exists (select 1 from client_weights w where w.client_id = p_client_id)),
       qs as (
         select 100 + row_number() over (order by q.s_pos, q.q_pos, q.key) o, q.label l
         from intake_client_questions(p_client_id) q, a
         where q.required
           and case when q.kind = 'yes_no' then (a.answers -> q.key) is distinct from 'true'::jsonb
                    else (a.answers -> q.key) is null end)
  select coalesce(jsonb_agg(l order by o), '[]'::jsonb) from (select * from core union all select * from qs) m
$$;

-- the client's own form: only their sections and questions, in the set order
create or replace function my_intake() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid(); v_id uuid; c clients%rowtype; ci client_intake%rowtype;
  w record; g record; v_today date := (now() at time zone coalesce(app_setting('timezone'), 'Australia/Sydney'))::date;
begin
  if coalesce(current_staff_role(), '') <> 'client' then
    return jsonb_build_object('ok', false, 'message', 'Client accounts only.');
  end if;
  v_id := my_client_id();
  if v_id is null then return jsonb_build_object('ok', false, 'message', 'Your account isn''t connected yet.'); end if;
  select * into c from clients where id = v_id;
  select * into ci from client_intake where client_id = v_id;
  select weight_kg, recorded_on into w from client_weights where client_id = v_id order by recorded_on desc, created_at desc limit 1;
  select g2.goal_type, g2.detail, g2.target_date, gt.label, (g2.set_by = v_uid) as mine into g
    from client_goals g2 join goal_types gt on gt.key = g2.goal_type
   where g2.client_id = v_id and g2.is_primary and g2.ended_on is null limit 1;
  return jsonb_build_object(
    'ok', true,
    'status', coalesce(ci.status, 'open'),
    'can_edit', coalesce(ci.status, 'open') <> 'reviewed',
    'submitted_at', ci.submitted_at,
    'about', jsonb_build_object('full_name', c.full_name, 'email', c.email, 'phone', c.phone,
               'date_of_birth', c.date_of_birth, 'sex', c.sex, 'height_cm', c.height_cm,
               'activity_level', c.activity_level, 'weight_kg', w.weight_kg, 'weight_recorded_on', w.recorded_on),
    'goal', case when g.goal_type is null then null else jsonb_build_object(
               'goal_type', g.goal_type, 'label', g.label, 'detail', g.detail, 'target_date', g.target_date,
               'mine', coalesce(g.mine, false)) end,
    'requirements', (select coalesce(jsonb_agg(jsonb_build_object('tag_id', t.id, 'label', t.label,
                        'kind', coalesce(client_tag_kind(t.id), 'other'), 'mine', r.added_by is not distinct from v_uid) order by t.label), '[]'::jsonb)
                     from client_requirements r join tags t on t.id = r.tag_id where r.client_id = v_id),
    'food_rules', (select coalesce(jsonb_agg(jsonb_build_object('name', f.display_name, 'rule', fr.rule) order by f.display_name), '[]'::jsonb)
                   from client_food_rules fr join foods f on f.food_id = fr.food_id where fr.client_id = v_id),
    'supplements', (select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'name', s.name, 'dose', s.dose, 'timing', s.timing,
                        'mine', s.added_by is not distinct from v_uid) order by s.position, s.name), '[]'::jsonb)
                    from client_supplements s where s.client_id = v_id and (s.ended_on is null or s.ended_on >= v_today)),
    'answers', coalesce(ci.answers, '{}'::jsonb),
    -- sections on this client's form: active, and either holding fixed details or at least one of their questions
    'sections', (select coalesce(jsonb_agg(jsonb_build_object('key', s.key, 'title', s.title, 'builtins', to_jsonb(s.builtins))
                     order by s.position, s.key), '[]'::jsonb)
                 from intake_sections s
                 where s.active and (cardinality(s.builtins) > 0
                       or exists (select 1 from intake_client_questions(v_id) q where q.section = s.key))),
    'questions', (select coalesce(jsonb_agg(jsonb_build_object('key', q.key, 'section', q.section, 'label', q.label, 'help', q.help,
                     'kind', q.kind, 'options', q.options, 'required', q.required)
                     order by q.s_pos, q.q_pos, q.key), '[]'::jsonb)
                  from intake_client_questions(v_id) q),
    'options', jsonb_build_object(
       'sexes', '[{"key":"female","label":"Female"},{"key":"male","label":"Male"},{"key":"other","label":"Another sex or intersex"},{"key":"unspecified","label":"Prefer not to say"}]'::jsonb,
       'activity_levels', (select coalesce(jsonb_agg(jsonb_build_object('key', key, 'label', label) order by position), '[]'::jsonb) from activity_levels where active),
       'goal_types', (select coalesce(jsonb_agg(jsonb_build_object('key', key, 'label', label) order by position), '[]'::jsonb) from goal_types where active),
       'avoid',  (select coalesce(jsonb_agg(jsonb_build_object('tag_id', id, 'label', label) order by label), '[]'::jsonb) from tags where client_tag_kind(id) = 'avoid'),
       'diet',   (select coalesce(jsonb_agg(jsonb_build_object('tag_id', id, 'label', label) order by label), '[]'::jsonb) from tags where client_tag_kind(id) = 'diet'),
       'prefer', (select coalesce(jsonb_agg(jsonb_build_object('tag_id', id, 'label', label) order by label), '[]'::jsonb) from tags where client_tag_kind(id) = 'prefer')),
    'missing', intake_missing(v_id));
end $$;

-- staff view: every answer for everyone with access to the client; sections and the client's selection
create or replace function client_intake_for_staff(p_client_id uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare c clients%rowtype; ci client_intake%rowtype;
begin
  if not can_access_client(p_client_id) then return jsonb_build_object('ok', false, 'message', 'No access to this client.'); end if;
  select * into c from clients where id = p_client_id;
  select * into ci from client_intake where client_id = p_client_id;
  return jsonb_build_object(
    'ok', true,
    'status', coalesce(ci.status, 'open'),
    'source', c.source,
    'client_status', c.status,
    'submitted_at', ci.submitted_at,
    'reviewed_at', ci.reviewed_at,
    'reviewed_by_name', (select coalesce(nullif(btrim(full_name), ''), email) from profiles where id = ci.reviewed_by),
    'updated_at', ci.updated_at,
    'missing', intake_missing(p_client_id),
    'question_keys', to_jsonb(ci.question_keys),          -- null = every active question
    'sections', (select coalesce(jsonb_agg(jsonb_build_object('key', s.key, 'title', s.title, 'position', s.position,
                     'active', s.active, 'builtins', to_jsonb(s.builtins)) order by s.position, s.key), '[]'::jsonb)
                 from intake_sections s),
    'questions', (select coalesce(jsonb_agg(jsonb_build_object('key', q.key, 'section', q.section, 'label', q.label,
                     'kind', q.kind, 'options', q.options, 'required', q.required, 'locked', q.locked, 'active', q.active,
                     'clinical', false,
                     'selected', coalesce(q.locked or ci.question_keys is null or q.key = any (ci.question_keys), false),
                     'answer', coalesce(ci.answers, '{}'::jsonb) -> q.key)
                     order by s.position, q.position, q.key), '[]'::jsonb)
                  from intake_questions q join intake_sections s on s.key = q.section
                  where q.active or coalesce(ci.answers, '{}'::jsonb) ? q.key),
    'hidden_clinical_count', 0,                            -- kept for the current app until its next publish
    'changes', (select coalesce(jsonb_agg(x order by x.changed_at desc), '[]'::jsonb) from (
           select l.field, l.action, l.old_value, l.new_value, l.changed_at,
                  l.changed_by = c.user_id as by_client,
                  (select coalesce(nullif(btrim(full_name), ''), email) from profiles where id = l.changed_by) as changed_by_name
           from client_intake_log l where l.client_id = p_client_id order by l.changed_at desc limit 100) x),
    'changes_since_review', case when ci.reviewed_at is not null then
        (select count(*) from client_intake_log l where l.client_id = p_client_id and l.changed_at > ci.reviewed_at
           and l.changed_by is distinct from ci.reviewed_by) else 0 end);
end $$;

-- choose a client's form. p_question_keys NULL = every active question (and any added later).
create or replace function set_client_intake_questions(p_client_id uuid, p_question_keys text[]) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_old text[]; v_keys text[]; v_unknown text[];
begin
  if not (is_clinician() and can_access_client(p_client_id)) then
    return jsonb_build_object('ok', false, 'message', 'Only a dietitian can choose a client''s form.'); end if;
  if not exists (select 1 from clients where id = p_client_id) then
    return jsonb_build_object('ok', false, 'message', 'Client not found.'); end if;
  if p_question_keys is not null then
    select array_agg(k order by k) into v_unknown from unnest(p_question_keys) k
     where not exists (select 1 from intake_questions q where q.key = k);
    if v_unknown is not null then
      return jsonb_build_object('ok', false, 'message', 'Unknown question: ' || array_to_string(v_unknown, ', ')); end if;
    select array_agg(distinct k order by k) into v_keys
      from unnest(p_question_keys || array(select key from intake_questions where locked)) k;
  end if;
  insert into client_intake (client_id) values (p_client_id) on conflict do nothing;
  select question_keys into v_old from client_intake where client_id = p_client_id for update;
  if v_old is not distinct from v_keys then
    return jsonb_build_object('ok', true, 'message', 'No change.', 'question_keys', to_jsonb(v_keys), 'missing', intake_missing(p_client_id)); end if;
  update client_intake set question_keys = v_keys, updated_at = now(), updated_by = auth.uid() where client_id = p_client_id;
  perform _log_client_change(p_client_id, 'intake_form', 'set',
            coalesce(array_to_string(v_old, ', '), 'all questions'), coalesce(array_to_string(v_keys, ', '), 'all questions'));
  return jsonb_build_object('ok', true, 'message', 'Form saved.', 'question_keys', to_jsonb(v_keys), 'missing', intake_missing(p_client_id));
end $$;

-- save the order of sections and questions in one go.
-- p_sections: ["about", "goals", ...] in order. p_questions: [{"key": "reasons", "section": "goals"}, ...] in order
-- ("section" optional: moves the question). Inactive questions always sort after active ones in their section.
create or replace function reorder_intake(p_sections jsonb, p_questions jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_bad text;
begin
  if not is_clinician() then
    return jsonb_build_object('ok', false, 'message', 'Only dietitians and admins can change the client form.'); end if;
  if p_sections is not null and jsonb_typeof(p_sections) <> 'array' or p_questions is not null and jsonb_typeof(p_questions) <> 'array' then
    return jsonb_build_object('ok', false, 'message', 'Send the order as lists.'); end if;
  select string_agg(k, ', ') into v_bad from jsonb_array_elements_text(coalesce(p_sections, '[]')) k
   where not exists (select 1 from intake_sections s where s.key = k);
  if v_bad is not null then return jsonb_build_object('ok', false, 'message', 'Unknown section: ' || v_bad); end if;
  select string_agg(coalesce(e ->> 'key', '?'), ', ') into v_bad from jsonb_array_elements(coalesce(p_questions, '[]')) e
   where not exists (select 1 from intake_questions q where q.key = e ->> 'key')
      or (e ? 'section' and not exists (select 1 from intake_sections s where s.key = e ->> 'section'));
  if v_bad is not null then return jsonb_build_object('ok', false, 'message', 'Unknown question or section: ' || v_bad); end if;

  update intake_sections s set position = o.ord * 10
    from jsonb_array_elements_text(coalesce(p_sections, '[]')) with ordinality as o(k, ord)
   where s.key = o.k and s.position is distinct from o.ord * 10;
  update intake_questions q set position = o.ord * 10, section = coalesce(o.e ->> 'section', q.section)
    from jsonb_array_elements(coalesce(p_questions, '[]')) with ordinality as o(e, ord)
   where q.key = o.e ->> 'key';
  -- tidy: 10, 20, 30… within each section, active first
  update intake_questions q set position = r.rn * 10
    from (select key, row_number() over (partition by section order by (not active), position, key) rn from intake_questions) r
   where q.key = r.key and q.position is distinct from r.rn * 10;
  return jsonb_build_object('ok', true, 'message', 'Order saved.',
    'sections', (select jsonb_agg(jsonb_build_object('key', key, 'position', position) order by position, key) from intake_sections),
    'questions', (select jsonb_agg(jsonb_build_object('key', key, 'section', section, 'position', position) order by section, position) from intake_questions));
end $$;

-- 4. grants ------------------------------------------------------------------------------------------
revoke execute on function intake_client_questions(uuid), intake_sections_guard(), intake_questions_guard() from public, anon, authenticated;
revoke execute on function set_client_intake_questions(uuid, text[]), reorder_intake(jsonb, jsonb) from public, anon;
grant execute on function set_client_intake_questions(uuid, text[]), reorder_intake(jsonb, jsonb) to authenticated;
