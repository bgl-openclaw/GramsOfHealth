-- 0040_client_onboarding.sql — P1c: clients onboard themselves; dietitians invite with a link that
-- works whether or not the client already has an account; an intake form the client fills in and
-- the dietitian reviews; "coming soon" areas for the client app. Owner-approved 2026-10-21.
--
-- Two ways in:
--   • Dietitian first: create the client (name + email minimum) → invite_client_to_app → send the
--     link. New person → sign up through the link (linked by handle_new_user, as before). Already
--     has an account → sign in through the link → claim_client_invite. Either way they land on
--     their own file with whatever the dietitian entered, and can complete the rest.
--   • Client first (/join): the sign-up now ALWAYS creates a fresh client file (source
--     'self_signup', status 'new') linked to the account, so they can fill everything in at once.
--     It is never matched to an existing client by email — emails aren't verified yet, and a match
--     would reveal who is already a client. Dietitians see possible duplicates in
--     client_signup_queue() and fold them together with merge_client_into().
--
-- Intake: client_intake holds status (open → submitted → reviewed) and answers to the data-driven
-- intake_questions. Core facts the planner uses (name, DOB, sex, height, weight, activity, goal,
-- must-avoid / diet / health-focus tags, supplements) are written to their usual tables. Clients
-- can remove only what THEY added; anything the dietitian set stays (shown read-only). After review
-- the client can still ADD a must-avoid item (safety); everything else goes through "Request a
-- change". Every client edit is logged in client_intake_log for the dietitian.
-- Idempotent where practical; tests: tests/sql/client_onboarding_p1c.test.sql.

-- 1. clients: where the file came from + a 'new' status for unreviewed self sign-ups ---------------
alter table clients add column if not exists source text not null default 'staff';
alter table clients drop constraint if exists clients_source_check;
alter table clients add constraint clients_source_check check (source in ('staff', 'self_signup'));
alter table clients drop constraint if exists clients_status_check;
alter table clients add constraint clients_status_check check (status in ('new', 'active', 'paused', 'finished'));

-- who added a supplement (clients may remove only their own; existing rows = staff)
alter table client_supplements add column if not exists added_by uuid default auth.uid()
  references profiles(id) on delete set null;

-- 2. intake questions (data-driven; admins edit; staff read; clients read via my_intake) ----------
create table if not exists intake_questions (
  key       text primary key check (key ~ '^[a-z][a-z0-9_]*$'),
  section   text not null check (section in ('about', 'goals', 'food', 'health', 'lifestyle', 'consent')),
  label     text not null,
  help      text,
  kind      text not null check (kind in ('text', 'long_text', 'number', 'date', 'single', 'multi', 'yes_no', 'scale')),
  options   jsonb check (options is null or jsonb_typeof(options) = 'array'),
  required  boolean not null default false,   -- yes_no + required = must be ticked (consents)
  clinical  boolean not null default false,   -- answers hidden from interns
  position  integer not null default 0,
  active    boolean not null default true
);
alter table intake_questions enable row level security;
drop policy if exists intake_questions_read on intake_questions;
create policy intake_questions_read on intake_questions for select using (is_staff());
drop policy if exists intake_questions_admin_write on intake_questions;
create policy intake_questions_admin_write on intake_questions for all using (is_admin()) with check (is_admin());
revoke all on intake_questions from anon;

-- 3. client intake: one row per client (no row = open and empty) ------------------------------------
create table if not exists client_intake (
  client_id    uuid primary key references clients(id) on delete cascade,
  status       text not null default 'open' check (status in ('open', 'submitted', 'reviewed')),
  answers      jsonb not null default '{}'::jsonb check (jsonb_typeof(answers) = 'object'),
  submitted_at timestamptz,
  reviewed_at  timestamptz,
  reviewed_by  uuid references profiles(id) on delete set null,
  updated_at   timestamptz not null default now(),
  updated_by   uuid references profiles(id) on delete set null
);
alter table client_intake enable row level security;
-- clinicians only: answers include health questions. Interns use client_intake_for_staff().
drop policy if exists client_intake_clinician on client_intake;
create policy client_intake_clinician on client_intake for all
  using (is_clinician() and can_access_client(client_id)) with check (is_clinician() and can_access_client(client_id));
revoke all on client_intake from anon;

-- 4. what changed, by whom (client edits + staff intake edits) --------------------------------------
create table if not exists client_intake_log (
  id         bigint generated always as identity primary key,
  client_id  uuid not null references clients(id) on delete cascade,
  field      text not null,
  action     text not null check (action in ('set', 'add', 'remove')),
  old_value  text,
  new_value  text,
  changed_by uuid references profiles(id) on delete set null,
  changed_at timestamptz not null default clock_timestamp()   -- wall clock, so order within one transaction is real
);
create index if not exists client_intake_log_client on client_intake_log (client_id, changed_at desc);
alter table client_intake_log enable row level security;
drop policy if exists client_intake_log_read on client_intake_log;
create policy client_intake_log_read on client_intake_log for select using (is_clinician() and can_access_client(client_id));
revoke all on client_intake_log from anon;

-- 5. client app areas: registry of extra areas; 'coming_soon' shows a locked tile ------------------
create table if not exists client_areas (
  key      text primary key check (key ~ '^[a-z][a-z0-9_]*$'),
  title    text not null,
  blurb    text not null,
  icon     text,                      -- lucide icon name (hint for the app)
  status   text not null default 'coming_soon' check (status in ('live', 'coming_soon', 'hidden')),
  position integer not null default 0
);
alter table client_areas enable row level security;
drop policy if exists client_areas_read on client_areas;
create policy client_areas_read on client_areas for select using (is_staff());
drop policy if exists client_areas_admin_write on client_areas;
create policy client_areas_admin_write on client_areas for all using (is_admin()) with check (is_admin());
revoke all on client_areas from anon;

insert into client_areas (key, title, blurb, icon, position) values
  ('checkins',     'Weekly check-ins', 'A quick weekly check-in with your dietitian: how you''re feeling, hunger, energy and sleep.', 'clipboard-check', 10),
  ('progress',     'Progress',         'Track your weight, measurements and wins over time.',                                      'trending-up',     20),
  ('documents',    'Documents',        'Upload blood tests, referral letters and scan results before your consult.',               'file-up',         30),
  ('next_steps',   'Your next steps',  'A short summary after each consult with the three things to focus on.',                    'list-checks',     40),
  ('swaps',        'Meal swaps',       'Swap a meal for one your dietitian has already approved.',                                 'repeat',          50),
  ('messages',     'Messages',         'Message your dietitian between consults.',                                                 'message-circle',  60),
  ('appointments', 'Appointments',     'See your upcoming consults and book your next review.',                                    'calendar',        70),
  ('food_photos',  'Food photos',      'Snap your meals so your dietitian can see how the week really went.',                      'camera',          80),
  ('library',      'Learn',            'Handouts, guides and short videos picked for you.',                                        'book-open',       90),
  ('programs',     'Programs',         'Step-by-step nutrition programs that unlock week by week.',                                'layers',         100),
  ('classes',      'Cooking classes',  'Book a class and get the recipes afterwards.',                                             'chef-hat',       110),
  ('community',    'Community',        'Member catch-ups, live Q&A and challenges.',                                               'users',          120)
on conflict (key) do nothing;

-- 6. seed intake questions (from the GoH blueprint/website + Enriching Health intake forms) --------
-- Funding numbers (Medicare, NDIS, DVA, health fund) are deliberately NOT collected in the app yet.
insert into intake_questions (key, section, label, help, kind, options, required, clinical, position) values
  ('preferred_name', 'about', 'What would you like us to call you?', null, 'text', null, false, false, 10),
  ('pronouns', 'about', 'Your pronouns', null, 'single', '["She/her","He/him","They/them","Something else","Prefer not to say"]', false, false, 20),
  ('occupation', 'about', 'What do you do for work?', null, 'text', null, false, false, 30),
  ('how_heard', 'about', 'How did you hear about us?', null, 'single', '["Facebook or Instagram","Google","Friend or family","My GP or another health professional","A cooking class","Something else"]', false, false, 40),
  ('referrer', 'about', 'Who referred you?', 'If a person or clinic sent you our way.', 'text', null, false, false, 50),
  ('support_person', 'about', 'Does someone help with your food?', 'If a parent, partner, carer or support worker shops or cooks for you, add their name and best contact.', 'long_text', null, false, false, 60),

  ('reasons', 'goals', 'What brings you to Grams of Health?', 'Choose all that apply.', 'multi', '["Weight management","Sports nutrition","Gut health","A health condition (e.g. diabetes, heart health)","Women''s health","NDIS support","Something else"]', true, false, 10),
  ('top_priorities', 'goals', 'What are the top three things you''d like help with?', null, 'long_text', null, true, false, 20),
  ('success', 'goals', 'In three months, what would tell you this has worked?', null, 'long_text', null, false, false, 30),
  ('tried_before', 'goals', 'What have you tried before? What worked and what didn''t?', null, 'long_text', null, false, false, 40),

  ('foods_disliked', 'food', 'Any foods you dislike or won''t eat?', 'Your dietitian will add these to your plan settings.', 'long_text', null, false, false, 10),
  ('go_to_foods', 'food', 'Your go-to foods', 'Meals or foods you always enjoy or rely on.', 'long_text', null, false, false, 20),
  ('proteins_enjoyed', 'food', 'Which proteins do you enjoy?', null, 'multi', '["Chicken","Beef","Lamb","Pork","Fish","Seafood","Eggs","Tofu or tempeh","Beans and lentils"]', false, false, 30),
  ('eating_pattern', 'food', 'How do you usually eat across a day?', null, 'single', '["Two meals","Three meals","Three meals and snacks","Small meals through the day","It changes a lot"]', false, false, 40),
  ('variety', 'food', 'How much variety do you like?', null, 'single', '["Happy to repeat meals and batch cook","A little variety","Something different every day"]', false, false, 50),
  ('cooking_time', 'food', 'How much time do you have to cook on a weeknight?', null, 'single', '["Under 15 minutes","15 to 30 minutes","30 to 60 minutes","I love to cook"]', false, false, 60),
  ('who_cooks', 'food', 'Who usually does the cooking?', null, 'single', '["Me","My partner","Another family member","A support worker","We share it"]', false, false, 70),
  ('household_size', 'food', 'How many people do you usually cook for?', null, 'number', null, false, false, 80),
  ('budget', 'food', 'How would you describe your food budget?', null, 'single', '["Tight","Moderate","Flexible"]', false, false, 90),
  ('eating_out', 'food', 'How often do you eat out or order in?', null, 'single', '["Rarely","About once a week","A few times a week","Most days"]', false, false, 100),

  ('conditions', 'health', 'Any medical conditions or diagnoses?', null, 'long_text', null, false, true, 10),
  ('medications', 'health', 'Medications you take', 'Name, dose and how long you''ve been taking it.', 'long_text', null, false, true, 20),
  ('gut_symptoms', 'health', 'Do you get any of these regularly?', null, 'multi', '["Bloating","Reflux or heartburn","Constipation","Diarrhoea","Tummy pain or cramping","None of these"]', false, true, 30),
  ('womens_health', 'health', 'Women''s health', 'Skip this if it doesn''t apply to you.', 'single', '["Regular cycle","Irregular cycle","Pregnant","Breastfeeding","Perimenopause","Menopause or post-menopause","Prefer not to say"]', false, true, 40),
  ('eating_disorder_history', 'health', 'Have you ever been diagnosed with, or treated for, an eating disorder?', 'This helps your dietitian care for you safely. Your answer is only seen by your dietitian.', 'single', '["No","Yes","Prefer to talk about it in my consult"]', false, true, 50),
  ('recent_bloods', 'health', 'Have you had blood tests in the last six months?', 'Bring them to your consult if you can.', 'single', '["Yes","No","Not sure"]', false, true, 60),
  ('gp', 'health', 'Your GP''s name and clinic', null, 'text', null, false, false, 70),
  ('funding', 'health', 'How are you planning to pay for your consults?', null, 'single', '["Paying privately","Private health insurance","Medicare (GP care plan)","NDIS","DVA","Not sure yet"]', false, false, 80),

  ('training', 'lifestyle', 'What exercise or training do you do in a typical week?', null, 'long_text', null, false, false, 10),
  ('work_pattern', 'lifestyle', 'Your usual work pattern', null, 'single', '["Regular daytime hours","Shift work","Night shifts","Not working or retired","Studying"]', false, false, 20),
  ('sleep_hours', 'lifestyle', 'How many hours do you usually sleep?', null, 'single', '["Less than 5","5 to 6","7 to 8","More than 8"]', false, false, 30),
  ('stress', 'lifestyle', 'How has your stress been lately?', '1 = very low, 5 = very high', 'scale', null, false, false, 40),
  ('alcohol', 'lifestyle', 'How much alcohol do you usually drink?', null, 'single', '["None","1 to 2 drinks a week","3 to 7 drinks a week","More than 7 drinks a week"]', false, false, 50),
  ('anything_else', 'lifestyle', 'Anything else you''d like us to know?', null, 'long_text', null, false, false, 60),

  ('consent_privacy', 'consent', 'I agree to Grams of Health collecting and storing my health information to provide my care.', 'Your information is only seen by the Grams of Health team looking after you.', 'yes_no', null, true, false, 10),
  ('consent_marketing', 'consent', 'Send me recipes, tips and offers by email.', 'Optional. You can stop these at any time.', 'yes_no', null, false, false, 20)
on conflict (key) do nothing;

-- 7. helpers (internal) --------------------------------------------------------------------------
-- How a requirement tag reads for a client: allergen → avoid; diet tag that blocks things → diet;
-- other diet-category tag → prefer (health focus). Null = not offered to clients.
create or replace function client_tag_kind(p_tag_id uuid) returns text
language sql stable security definer set search_path = public as $$
  select case when t.kind = 'allergen' then 'avoid'
              when (t.kind = 'dietary' or lower(coalesce(t.category, '')) = 'diet')
                   and exists (select 1 from tag_blockers b where b.tag_id = t.id) then 'diet'
              when lower(coalesce(t.category, '')) = 'diet' then 'prefer' end
  from tags t where t.id = p_tag_id
$$;

create or replace function _log_client_change(p_client_id uuid, p_field text, p_action text, p_old text, p_new text)
returns void language sql security definer set search_path = public as $$
  insert into client_intake_log (client_id, field, action, old_value, new_value, changed_by)
  values (p_client_id, p_field, p_action, left(p_old, 500), left(p_new, 500), auth.uid())
$$;

-- Check one answer against its question; returns the cleaned value, null = "remove the answer".
create or replace function _intake_normalise(p_key text, p_value jsonb) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare q intake_questions%rowtype; v jsonb := p_value; t text; n numeric; e jsonb; lim int;
begin
  select * into q from intake_questions where key = p_key;
  if not found then raise exception 'unknown_question'; end if;
  if v is null or jsonb_typeof(v) = 'null'
     or (jsonb_typeof(v) = 'string' and btrim(v #>> '{}') = '')
     or (jsonb_typeof(v) = 'array' and jsonb_array_length(v) = 0) then
    return null;
  end if;
  case q.kind
    when 'text', 'long_text' then
      if jsonb_typeof(v) not in ('string', 'number') then raise exception 'Please check "%".', q.label; end if;
      t := btrim(v #>> '{}');
      lim := case when q.kind = 'text' then 300 else 3000 end;
      if length(t) > lim then
        raise exception 'Your answer to "%" is a bit long. Please shorten it.', q.label; end if;
      return to_jsonb(t);
    when 'number', 'scale' then
      begin n := (v #>> '{}')::numeric; exception when others then raise exception 'Please enter a number for "%".', q.label; end;
      if q.kind = 'scale' and (n < 1 or n > 5 or n <> round(n)) then raise exception 'Please choose 1 to 5 for "%".', q.label; end if;
      if q.kind = 'number' and (n < 0 or n > 100000) then raise exception 'Please check "%".', q.label; end if;
      return to_jsonb(n);
    when 'date' then
      begin return to_jsonb(((v #>> '{}')::date)::text); exception when others then raise exception 'Please check the date for "%".', q.label; end;
    when 'single' then
      t := v #>> '{}';
      if jsonb_typeof(v) <> 'string' or (q.options is not null and not q.options ? t) then
        raise exception 'Please choose an option for "%".', q.label; end if;
      return to_jsonb(t);
    when 'multi' then
      if jsonb_typeof(v) <> 'array' or jsonb_array_length(v) > 30 then raise exception 'Please check "%".', q.label; end if;
      for e in select * from jsonb_array_elements(v) loop
        if jsonb_typeof(e) <> 'string' or (q.options is not null and not q.options ? (e #>> '{}')) then
          raise exception 'Please choose from the options for "%".', q.label; end if;
      end loop;
      return (select jsonb_agg(distinct x.val) from jsonb_array_elements(v) as x(val));
    when 'yes_no' then
      if jsonb_typeof(v) <> 'boolean' then raise exception 'Please answer yes or no for "%".', q.label; end if;
      return v;
  end case;
  return v;
end $$;

-- What still needs an answer before the client can send their details (labels, in form order).
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
         select 100 + row_number() over (order by array_position(array['about','goals','food','health','lifestyle','consent'], q.section), q.position) o,
                q.label l
         from intake_questions q, a
         where q.active and q.required
           and case when q.kind = 'yes_no' then (a.answers -> q.key) is distinct from 'true'::jsonb
                    else (a.answers -> q.key) is null end)
  select coalesce(jsonb_agg(l order by o), '[]'::jsonb) from (select * from core union all select * from qs) m
$$;

-- Fold a fresh self sign-up into another client file (used by claim_client_invite and staff merge).
create or replace function _merge_client_records(p_from uuid, p_into uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare f clients%rowtype; t clients%rowtype; fi client_intake%rowtype; ti client_intake%rowtype;
begin
  select * into f from clients where id = p_from for update;
  select * into t from clients where id = p_into for update;
  if f.id is null or t.id is null or f.id = t.id then
    return jsonb_build_object('ok', false, 'message', 'Choose two different clients.'); end if;
  if f.source <> 'self_signup' then
    return jsonb_build_object('ok', false, 'message', 'Only a client''s own sign-up can be merged into another file.'); end if;
  if exists (select 1 from meal_plans where client_id = p_from)
     or exists (select 1 from client_targets where client_id = p_from)
     or exists (select 1 from client_clinical_records where client_id = p_from)
     or exists (select 1 from client_structure where client_id = p_from)
     or exists (select 1 from client_meal_slots where client_id = p_from)
     or exists (select 1 from client_protein_preferences where client_id = p_from)
     or exists (select 1 from client_protein_spread where client_id = p_from) then
    return jsonb_build_object('ok', false,
      'message', 'A dietitian has already started work on this sign-up (plans, targets or settings), so it can''t be merged automatically.');
  end if;
  if f.user_id is not null and t.user_id is not null and f.user_id <> t.user_id then
    return jsonb_build_object('ok', false, 'message', 'Both files already have their own app account.'); end if;

  -- fill blanks on the kept file; the dietitian's entries win
  update clients set
    email          = coalesce(nullif(btrim(t.email), ''), f.email),
    phone          = coalesce(nullif(btrim(t.phone), ''), f.phone),
    date_of_birth  = coalesce(t.date_of_birth, f.date_of_birth),
    sex            = case when t.sex = 'unspecified' then f.sex else t.sex end,
    height_cm      = coalesce(t.height_cm, f.height_cm),
    activity_level = coalesce(t.activity_level, f.activity_level)
  where id = p_into;

  insert into client_requirements (client_id, tag_id, note, added_by, created_at)
    select p_into, tag_id, note, added_by, created_at from client_requirements where client_id = p_from
    on conflict do nothing;
  insert into client_food_rules (client_id, food_id, rule, primary_only, note, added_by, created_at)
    select p_into, food_id, rule, primary_only, note, added_by, created_at from client_food_rules where client_id = p_from
    on conflict do nothing;
  insert into client_staff_access (client_id, profile_id, can_view_checkins, granted_by, granted_at)
    select p_into, profile_id, can_view_checkins, granted_by, granted_at from client_staff_access where client_id = p_from
    on conflict do nothing;
  update client_supplements set client_id = p_into where client_id = p_from;
  update client_weights     set client_id = p_into where client_id = p_from;
  update client_checkins    set client_id = p_into where client_id = p_from;
  -- a goal comes across as primary only if the kept file has no current primary goal
  update client_goals set client_id = p_into,
         is_primary = is_primary and not exists (select 1 from client_goals g
                                                 where g.client_id = p_into and g.is_primary and g.ended_on is null)
   where client_id = p_from;
  update client_intake_log  set client_id = p_into where client_id = p_from;

  select * into fi from client_intake where client_id = p_from;
  select * into ti from client_intake where client_id = p_into;
  if fi.client_id is not null then
    insert into client_intake (client_id, status, answers, submitted_at, updated_at, updated_by)
    values (p_into,
            case when ti.status = 'reviewed' then 'reviewed'
                 when fi.status in ('submitted', 'reviewed') or ti.status = 'submitted' then 'submitted'
                 else 'open' end,
            fi.answers || coalesce(ti.answers, '{}'::jsonb),            -- kept file's answers win
            coalesce(ti.submitted_at, fi.submitted_at), now(), auth.uid())
    on conflict (client_id) do update
      set status = excluded.status, answers = excluded.answers, submitted_at = excluded.submitted_at,
          updated_at = excluded.updated_at, updated_by = excluded.updated_by;
  end if;

  perform set_config('goh.client_link', 'on', true);
  update clients set user_id = null where id = p_from;
  if f.user_id is not null and t.user_id is null then
    update clients set user_id = f.user_id where id = p_into;
  end if;
  perform set_config('goh.client_link', '', true);
  delete from clients where id = p_from;
  perform _log_client_change(p_into, 'merged', 'add', null, 'Merged sign-up from ' || f.full_name);
  return jsonb_build_object('ok', true, 'message', 'Merged into ' || t.full_name || '.', 'client_id', p_into);
end $$;

-- 8. sign-up trigger: invites as before; a client sign-up without a usable invite gets a fresh file -
create or replace function handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  inv public.invitations%rowtype;   -- rowtype (not record) so it's readable even when no invite matched
  v_token uuid;
  v_role text;
  v_client uuid;
  v_meta jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
begin
  begin
    v_token := nullif(coalesce(v_meta ->> 'invitation_token', v_meta ->> 'invite_token'), '')::uuid;
  exception when others then v_token := null;
  end;

  -- 1) the invite this person was sent (token from the link), email must match
  if v_token is not null then
    select * into inv from public.invitations
     where token = v_token and lower(email) = lower(new.email)
       and accepted_at is null and (expires_at is null or expires_at > now());
  end if;
  -- 2) staff invites still match by email alone (as before); client invites never do
  if inv.id is null then
    select * into inv from public.invitations
     where lower(email) = lower(new.email) and role <> 'client'
       and accepted_at is null and (expires_at is null or expires_at > now())
     order by created_at desc limit 1;
  end if;

  v_role := case
    when inv.id is not null then inv.role
    when coalesce(v_meta ->> 'account_type', '') = 'client' then 'client'
    -- a client invite link that has expired / been used still means "this is a client"
    when v_token is not null and exists (select 1 from public.invitations where token = v_token and role = 'client') then 'client'
    else 'pending' end;

  insert into public.profiles (id, email, full_name, phone, job_title, organisation, role)
  values (new.id, new.email,
          v_meta ->> 'full_name', v_meta ->> 'phone', v_meta ->> 'job_title', v_meta ->> 'organisation',
          v_role)
  on conflict (id) do nothing;

  if inv.id is not null then
    update public.invitations set accepted_at = now() where id = inv.id;
    if inv.role = 'client' then
      perform set_config('goh.client_link', 'on', true);
      update public.clients set user_id = new.id where id = inv.client_id and user_id is null;
      perform set_config('goh.client_link', '', true);
    end if;
  end if;

  -- a client account that isn't linked by now gets its own fresh file to fill in
  if v_role = 'client' and not exists (select 1 from public.clients where user_id = new.id) then
    insert into public.clients (full_name, email, phone, source, status)
    values (coalesce(nullif(btrim(v_meta ->> 'full_name'), ''), split_part(new.email, '@', 1)),
            lower(new.email), nullif(btrim(v_meta ->> 'phone'), ''), 'self_signup', 'new')
    returning id into v_client;
    perform set_config('goh.client_link', 'on', true);
    update public.clients set user_id = new.id where id = v_client;
    perform set_config('goh.client_link', '', true);
    insert into public.client_intake (client_id) values (v_client) on conflict do nothing;
  end if;
  return new;
end $$;

-- 9. invites -------------------------------------------------------------------------------------
-- Staff: get (or reuse) the client's invite link. Works even when the person already has a client
-- account — the link then asks them to sign in and connects them (claim_client_invite).
create or replace function invite_client_to_app(p_client_id uuid, p_email text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c clients%rowtype; v_email text; inv invitations%rowtype; v_exists boolean;
begin
  if not is_clinician() then
    return jsonb_build_object('ok', false, 'message', 'Only a dietitian can invite a client to the app.');
  end if;
  select * into c from clients where id = p_client_id;
  if not found then return jsonb_build_object('ok', false, 'message', 'Client not found.'); end if;
  if c.user_id is not null then
    return jsonb_build_object('ok', false, 'message', 'This client is already connected to the app.');
  end if;
  v_email := lower(btrim(coalesce(nullif(btrim(p_email), ''), c.email)));
  if v_email is null or v_email = '' then
    return jsonb_build_object('ok', false, 'message', 'Add the client''s email address first.');
  end if;
  if v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    return jsonb_build_object('ok', false, 'message', 'That email address doesn''t look right.');
  end if;
  if exists (select 1 from profiles where lower(email) = v_email and role not in ('client', 'pending')) then
    return jsonb_build_object('ok', false, 'message', 'That email belongs to a staff login. Use the client''s personal email.');
  end if;
  if coalesce(btrim(c.email), '') = '' then
    update clients set email = v_email where id = p_client_id;
  end if;
  select * into inv from invitations
   where client_id = p_client_id and lower(email) = v_email and accepted_at is null and expires_at > now()
   order by created_at desc limit 1;
  if not found then
    insert into invitations (email, role, client_id, invited_by)
    values (v_email, 'client', p_client_id, auth.uid()) returning * into inv;
  end if;
  v_exists := exists (select 1 from profiles where lower(email) = v_email);
  return jsonb_build_object('ok', true, 'token', inv.token, 'email', inv.email, 'expires_at', inv.expires_at,
    'full_name', c.full_name, 'first_name', split_part(btrim(c.full_name), ' ', 1),
    'practice_name', app_setting('practice_name'),
    'sender_name', (select coalesce(nullif(btrim(full_name), ''), email) from profiles where id = auth.uid()),
    'account_exists', v_exists,
    'message', case when v_exists
      then 'Invite ready. ' || split_part(btrim(c.full_name), ' ', 1) || ' already has an account, so the link will ask them to sign in and connect.'
      else 'Invite ready. Send it to ' || split_part(btrim(c.full_name), ' ', 1) || '.' end);
end $$;

-- Public (token holder): what the /register page needs for a CLIENT invite. found=false → not a
-- client invite (the page falls back to get_invitation for staff invites).
create or replace function get_client_invitation(p_token uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare inv invitations%rowtype; c clients%rowtype;
begin
  select * into inv from invitations where token = p_token and role = 'client';
  if not found then return jsonb_build_object('found', false, 'valid', false); end if;
  select * into c from clients where id = inv.client_id;
  return jsonb_build_object(
    'found', true,
    'valid', inv.accepted_at is null and coalesce(inv.expires_at, 'infinity') > now() and c.user_id is null,
    'reason', case when inv.accepted_at is not null or c.user_id is not null then 'used'
                   when coalesce(inv.expires_at, 'infinity') <= now() then 'expired' end,
    'email', inv.email,
    'full_name', c.full_name,
    'first_name', split_part(btrim(c.full_name), ' ', 1),
    'practice_name', app_setting('practice_name'),
    'practice_email', app_setting('practice_email'),
    'account_exists', exists (select 1 from profiles where lower(email) = lower(inv.email)),
    'expires_at', inv.expires_at);
end $$;

-- Signed-in client (or not-yet-approved) account accepts a client invite. If the account already
-- has its own fresh sign-up file, that file is folded into the dietitian's one.
create or replace function claim_client_invite(p_token uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v_role text; inv invitations%rowtype; c clients%rowtype; v_cur uuid; res jsonb;
begin
  if v_uid is null then return jsonb_build_object('ok', false, 'message', 'Please sign in first.'); end if;
  select role into v_role from profiles where id = v_uid;
  if coalesce(v_role, '') not in ('client', 'pending') then
    return jsonb_build_object('ok', false,
      'message', 'You''re signed in with a staff account. Sign in with your personal account to accept this invitation.');
  end if;
  select * into inv from invitations where token = p_token and role = 'client' for update;
  if not found then
    return jsonb_build_object('ok', false, 'message', 'We couldn''t find that invitation. Ask your dietitian for a new link.');
  end if;
  select * into c from clients where id = inv.client_id for update;
  if c.user_id = v_uid then
    update invitations set accepted_at = coalesce(accepted_at, now()) where id = inv.id;
    return jsonb_build_object('ok', true, 'message', 'You''re already connected.');
  end if;
  if inv.accepted_at is not null or c.user_id is not null then
    return jsonb_build_object('ok', false, 'message', 'This invitation has already been used. Ask your dietitian for a new link if you need one.');
  end if;
  if coalesce(inv.expires_at, 'infinity') <= now() then
    return jsonb_build_object('ok', false, 'message', 'This invitation has expired. Ask your dietitian for a new link.');
  end if;

  select id into v_cur from clients where user_id = v_uid;
  if v_cur is not null then
    res := _merge_client_records(v_cur, c.id);
    if not (res ->> 'ok')::boolean then
      return jsonb_build_object('ok', false,
        'message', 'Your account already has details saved, so your dietitian needs to connect this invitation for you. Please get in touch with them.');
    end if;
  else
    perform set_config('goh.client_link', 'on', true);
    update clients set user_id = v_uid where id = c.id;
    perform set_config('goh.client_link', '', true);
  end if;
  if v_role = 'pending' then update profiles set role = 'client' where id = v_uid; end if;
  update invitations set accepted_at = now() where id = inv.id;
  insert into client_intake (client_id) values (c.id) on conflict do nothing;
  return jsonb_build_object('ok', true, 'message', 'You''re connected to ' || coalesce(app_setting('practice_name'), 'your dietitian') || '.');
end $$;

-- client_app_status gains what the share dialog needs (+ source / intake status)
create or replace function client_app_status(p_client_id uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare c clients%rowtype; acc profiles%rowtype; inv invitations%rowtype;
begin
  if not can_access_client(p_client_id) then return null; end if;
  select * into c from clients where id = p_client_id;
  if c.user_id is not null then select * into acc from profiles where id = c.user_id; end if;
  select * into inv from invitations
   where client_id = p_client_id and accepted_at is null and expires_at > now()
   order by created_at desc limit 1;
  return jsonb_build_object(
    'linked', c.user_id is not null,
    'account', case when acc.id is null then null else jsonb_build_object('email', acc.email, 'full_name', acc.full_name, 'created_at', acc.created_at) end,
    'invite', case when inv.id is null then null else jsonb_build_object(
                 'email', inv.email, 'expires_at', inv.expires_at,
                 'token', case when is_clinician() then inv.token end,
                 'account_exists', exists (select 1 from profiles where lower(email) = lower(inv.email))) end,
    'numbers_allowed', c.numbers_allowed,
    'client_shows_numbers', c.client_shows_numbers,
    'source', c.source,
    'client_status', c.status,
    'intake_status', coalesce((select status from client_intake where client_id = p_client_id), 'open'),
    'first_name', split_part(btrim(c.full_name), ' ', 1),
    'practice_name', app_setting('practice_name'),
    'sender_name', (select coalesce(nullif(btrim(full_name), ''), email) from profiles where id = auth.uid()));
end $$;

-- 10. client: intake ---------------------------------------------------------------------------
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
    'sections', '[{"key":"about","title":"About you"},{"key":"goals","title":"Your goals"},{"key":"food","title":"Food"},{"key":"health","title":"Health"},{"key":"lifestyle","title":"Lifestyle"},{"key":"consent","title":"Almost done"}]'::jsonb,
    'questions', (select coalesce(jsonb_agg(jsonb_build_object('key', q.key, 'section', q.section, 'label', q.label, 'help', q.help,
                     'kind', q.kind, 'options', q.options, 'required', q.required)
                     order by array_position(array['about','goals','food','health','lifestyle','consent'], q.section), q.position), '[]'::jsonb)
                  from intake_questions q where q.active),
    'options', jsonb_build_object(
       'sexes', '[{"key":"female","label":"Female"},{"key":"male","label":"Male"},{"key":"other","label":"Another sex or intersex"},{"key":"unspecified","label":"Prefer not to say"}]'::jsonb,
       'activity_levels', (select coalesce(jsonb_agg(jsonb_build_object('key', key, 'label', label) order by position), '[]'::jsonb) from activity_levels where active),
       'goal_types', (select coalesce(jsonb_agg(jsonb_build_object('key', key, 'label', label) order by position), '[]'::jsonb) from goal_types where active),
       'avoid',  (select coalesce(jsonb_agg(jsonb_build_object('tag_id', id, 'label', label) order by label), '[]'::jsonb) from tags where client_tag_kind(id) = 'avoid'),
       'diet',   (select coalesce(jsonb_agg(jsonb_build_object('tag_id', id, 'label', label) order by label), '[]'::jsonb) from tags where client_tag_kind(id) = 'diet'),
       'prefer', (select coalesce(jsonb_agg(jsonb_build_object('tag_id', id, 'label', label) order by label), '[]'::jsonb) from tags where client_tag_kind(id) = 'prefer')),
    'missing', intake_missing(v_id));
end $$;

-- Save any part of the intake. Keys (all optional): about {full_name, phone, date_of_birth, sex,
-- height_cm, activity_level}, weight_kg, goal {goal_type, detail, target_date} | null,
-- requirements_add [tag_id], requirements_remove [tag_id], supplements_add [{name, dose, timing}],
-- supplements_remove [id], answers {question_key: value | null}.
create or replace function save_my_intake(p_changes jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid(); v_id uuid; c clients%rowtype; ci client_intake%rowtype; g client_goals%rowtype;
  a jsonb; e jsonb; k text; v jsonb; v_new jsonb; v_answers jsonb; v_text text; v_num numeric; v_date date;
  v_tag uuid; v_kind text; v_n int; v_skipped text[] := '{}'; v_label text;
  v_today date := (now() at time zone coalesce(app_setting('timezone'), 'Australia/Sydney'))::date;
begin
  if coalesce(current_staff_role(), '') <> 'client' then
    return jsonb_build_object('ok', false, 'message', 'Client accounts only.');
  end if;
  v_id := my_client_id();
  if v_id is null then return jsonb_build_object('ok', false, 'message', 'Your account isn''t connected yet.'); end if;
  if p_changes is null or jsonb_typeof(p_changes) <> 'object' then
    return jsonb_build_object('ok', false, 'message', 'Nothing to save.'); end if;
  if length(p_changes::text) > 60000 then
    return jsonb_build_object('ok', false, 'message', 'That''s a lot of text. Please shorten your answers.'); end if;

  insert into client_intake (client_id) values (v_id) on conflict do nothing;
  select * into ci from client_intake where client_id = v_id for update;
  select * into c from clients where id = v_id for update;
  if ci.status = 'reviewed' and exists (select 1 from jsonb_object_keys(p_changes) as x(k) where x.k <> 'requirements_add') then
    return jsonb_build_object('ok', false,
      'message', 'Your dietitian has reviewed your details. To change something, send them a change request.');
  end if;

  begin
    -- about you
    if p_changes ? 'about' then
      a := p_changes -> 'about';
      if jsonb_typeof(a) <> 'object' then raise exception 'Please check your details.'; end if;
      if a ? 'full_name' then
        v_text := btrim(a ->> 'full_name');
        if coalesce(v_text, '') = '' or length(v_text) > 120 then raise exception 'Please enter your full name.'; end if;
        if v_text is distinct from c.full_name then
          perform _log_client_change(v_id, 'full_name', 'set', c.full_name, v_text);
          update clients set full_name = v_text where id = v_id;
        end if;
      end if;
      if a ? 'phone' then
        v_text := nullif(btrim(a ->> 'phone'), '');
        if length(v_text) > 40 then raise exception 'Please check your phone number.'; end if;
        if v_text is distinct from c.phone then
          perform _log_client_change(v_id, 'phone', 'set', c.phone, v_text);
          update clients set phone = v_text where id = v_id;
        end if;
      end if;
      if a ? 'date_of_birth' then
        begin v_date := nullif(a ->> 'date_of_birth', '')::date;
        exception when others then raise exception 'Please check your date of birth.'; end;
        if v_date is not null and (v_date < date '1900-01-01' or v_date > v_today - 365) then
          raise exception 'Please check your date of birth.'; end if;
        if v_date is distinct from c.date_of_birth then
          perform _log_client_change(v_id, 'date_of_birth', 'set', c.date_of_birth::text, v_date::text);
          update clients set date_of_birth = v_date where id = v_id;
        end if;
      end if;
      if a ? 'sex' then
        v_text := coalesce(nullif(a ->> 'sex', ''), 'unspecified');
        if v_text not in ('female', 'male', 'other', 'unspecified') then raise exception 'Please choose an option for sex.'; end if;
        if v_text is distinct from c.sex then
          perform _log_client_change(v_id, 'sex', 'set', c.sex, v_text);
          update clients set sex = v_text where id = v_id;
        end if;
      end if;
      if a ? 'height_cm' then
        begin v_num := nullif(a ->> 'height_cm', '')::numeric;
        exception when others then raise exception 'Please check your height (cm).'; end;
        if v_num is not null and (v_num < 50 or v_num > 272) then raise exception 'Please check your height (cm).'; end if;
        v_num := round(v_num, 1);
        if v_num is distinct from c.height_cm then
          perform _log_client_change(v_id, 'height_cm', 'set', c.height_cm::text, v_num::text);
          update clients set height_cm = v_num where id = v_id;
        end if;
      end if;
      if a ? 'activity_level' then
        v_text := nullif(a ->> 'activity_level', '');
        if v_text is not null and not exists (select 1 from activity_levels where key = v_text and active) then
          raise exception 'Please choose how active you are.'; end if;
        if v_text is distinct from c.activity_level then
          perform _log_client_change(v_id, 'activity_level', 'set', c.activity_level, v_text);
          update clients set activity_level = v_text where id = v_id;
        end if;
      end if;
    end if;

    -- current weight (one client entry per day; a later save the same day replaces it)
    if p_changes ? 'weight_kg' and nullif(p_changes ->> 'weight_kg', '') is not null then
      begin v_num := round((p_changes ->> 'weight_kg')::numeric, 1);
      exception when others then raise exception 'Please check your weight (kg).'; end;
      if v_num < 20 or v_num > 400 then raise exception 'Please check your weight (kg).'; end if;
      update client_weights set weight_kg = v_num
       where client_id = v_id and recorded_on = v_today and source = 'client' and entered_by = v_uid;
      get diagnostics v_n = row_count;
      if v_n = 0 then
        insert into client_weights (client_id, weight_kg, recorded_on, source, entered_by)
        values (v_id, v_num, v_today, 'client', v_uid);
      end if;
      perform _log_client_change(v_id, 'weight_kg', 'set', null, v_num::text);
    end if;

    -- main goal (the client may set or change it only if they set it themselves)
    if p_changes ? 'goal' then
      a := p_changes -> 'goal';
      select * into g from client_goals where client_id = v_id and is_primary and ended_on is null for update;
      if g.id is not null and g.set_by is distinct from v_uid then
        raise exception 'Your dietitian has set your goal. Send them a change request if you''d like to change it.';
      end if;
      if a is null or jsonb_typeof(a) = 'null' then
        if g.id is not null then
          delete from client_goals where id = g.id;
          perform _log_client_change(v_id, 'goal', 'remove', g.goal_type, null);
        end if;
      else
        if jsonb_typeof(a) <> 'object' or not exists (select 1 from goal_types where key = a ->> 'goal_type' and active) then
          raise exception 'Please choose your main goal.'; end if;
        if length(a ->> 'detail') > 500 then raise exception 'Please shorten your goal.'; end if;
        begin v_date := nullif(a ->> 'target_date', '')::date;
        exception when others then raise exception 'Please check your goal date.'; end;
        if g.id is not null then
          update client_goals set goal_type = a ->> 'goal_type', detail = nullif(btrim(a ->> 'detail'), ''), target_date = v_date
           where id = g.id;
        else
          insert into client_goals (client_id, goal_type, detail, target_date, is_primary, set_by)
          values (v_id, a ->> 'goal_type', nullif(btrim(a ->> 'detail'), ''), v_date, true, v_uid);
        end if;
        perform _log_client_change(v_id, 'goal', 'set', g.goal_type,
          concat_ws(' · ', a ->> 'goal_type', nullif(btrim(a ->> 'detail'), ''), v_date::text));
      end if;
    end if;

    -- must-avoid / way of eating / health focus
    if p_changes ? 'requirements_add' then
      if jsonb_typeof(p_changes -> 'requirements_add') <> 'array' then raise exception 'Please check your food needs.'; end if;
      for e in select * from jsonb_array_elements(p_changes -> 'requirements_add') loop
        begin v_tag := (e #>> '{}')::uuid; exception when others then continue; end;
        v_kind := client_tag_kind(v_tag);
        if v_kind is null or (ci.status = 'reviewed' and v_kind <> 'avoid') then continue; end if;
        insert into client_requirements (client_id, tag_id, added_by) values (v_id, v_tag, v_uid) on conflict do nothing;
        get diagnostics v_n = row_count;
        if v_n > 0 then
          perform _log_client_change(v_id, 'requirement', 'add', null, (select label from tags where id = v_tag));
        end if;
      end loop;
    end if;
    if p_changes ? 'requirements_remove' then
      if jsonb_typeof(p_changes -> 'requirements_remove') <> 'array' then raise exception 'Please check your food needs.'; end if;
      for e in select * from jsonb_array_elements(p_changes -> 'requirements_remove') loop
        begin v_tag := (e #>> '{}')::uuid; exception when others then continue; end;
        v_label := (select label from tags where id = v_tag);
        delete from client_requirements where client_id = v_id and tag_id = v_tag and added_by is not distinct from v_uid;
        get diagnostics v_n = row_count;
        if v_n > 0 then
          perform _log_client_change(v_id, 'requirement', 'remove', v_label, null);
        elsif exists (select 1 from client_requirements where client_id = v_id and tag_id = v_tag) then
          v_skipped := v_skipped || v_label;
        end if;
      end loop;
    end if;

    -- supplements
    if p_changes ? 'supplements_add' then
      if jsonb_typeof(p_changes -> 'supplements_add') <> 'array' then raise exception 'Please check your supplements.'; end if;
      for e in select * from jsonb_array_elements(p_changes -> 'supplements_add') loop
        v_text := btrim(e ->> 'name');
        if coalesce(v_text, '') = '' or length(v_text) > 100 or length(e ->> 'dose') > 60 or length(e ->> 'timing') > 60 then
          raise exception 'Please check your supplements.'; end if;
        if (select count(*) from client_supplements where client_id = v_id) >= 30 then
          raise exception 'That''s a lot of supplements. Please talk to your dietitian.'; end if;
        insert into client_supplements (client_id, name, dose, timing, position, added_by)
        values (v_id, v_text, nullif(btrim(e ->> 'dose'), ''), nullif(btrim(e ->> 'timing'), ''),
                coalesce((select max(position) + 1 from client_supplements where client_id = v_id), 0), v_uid);
        perform _log_client_change(v_id, 'supplement', 'add', null, concat_ws(' · ', v_text, e ->> 'dose', e ->> 'timing'));
      end loop;
    end if;
    if p_changes ? 'supplements_remove' then
      if jsonb_typeof(p_changes -> 'supplements_remove') <> 'array' then raise exception 'Please check your supplements.'; end if;
      for e in select * from jsonb_array_elements(p_changes -> 'supplements_remove') loop
        begin v_tag := (e #>> '{}')::uuid; exception when others then continue; end;
        v_label := (select name from client_supplements where id = v_tag and client_id = v_id);
        delete from client_supplements where id = v_tag and client_id = v_id and added_by is not distinct from v_uid;
        get diagnostics v_n = row_count;
        if v_n > 0 then perform _log_client_change(v_id, 'supplement', 'remove', v_label, null);
        elsif v_label is not null then v_skipped := v_skipped || v_label; end if;
      end loop;
    end if;

    -- questionnaire answers
    if p_changes ? 'answers' then
      if jsonb_typeof(p_changes -> 'answers') <> 'object' then raise exception 'Please check your answers.'; end if;
      v_answers := ci.answers;
      for k, v in select key, value from jsonb_each(p_changes -> 'answers') loop
        if not exists (select 1 from intake_questions where key = k and active) then continue; end if;
        v_new := _intake_normalise(k, v);
        if v_new is null then
          if v_answers ? k then
            perform _log_client_change(v_id, 'answer:' || k, 'remove', v_answers ->> k, null);
            v_answers := v_answers - k;
          end if;
        elsif (v_answers -> k) is distinct from v_new then
          perform _log_client_change(v_id, 'answer:' || k, 'set', v_answers ->> k,
                                     case when jsonb_typeof(v_new) = 'string' then v_new #>> '{}' else v_new::text end);
          v_answers := jsonb_set(v_answers, array[k], v_new);
        end if;
      end loop;
      update client_intake set answers = v_answers where client_id = v_id;
    end if;
  exception when raise_exception then
    -- friendly validation message; nothing from this call is kept
    return jsonb_build_object('ok', false, 'message', sqlerrm);
  end;

  update client_intake set updated_at = now(), updated_by = v_uid where client_id = v_id;
  return jsonb_build_object('ok', true,
    'message', case when cardinality(v_skipped) > 0
      then 'Saved. Some items were set by your dietitian, so they''ve stayed: ' || array_to_string(v_skipped, ', ') || '.'
      else 'Saved.' end,
    'skipped', to_jsonb(v_skipped),
    'intake', my_intake());
end $$;

create or replace function submit_my_intake() returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_id uuid; ci client_intake%rowtype; v_missing jsonb;
begin
  if coalesce(current_staff_role(), '') <> 'client' then
    return jsonb_build_object('ok', false, 'message', 'Client accounts only.');
  end if;
  v_id := my_client_id();
  if v_id is null then return jsonb_build_object('ok', false, 'message', 'Your account isn''t connected yet.'); end if;
  insert into client_intake (client_id) values (v_id) on conflict do nothing;
  select * into ci from client_intake where client_id = v_id for update;
  if ci.status = 'reviewed' then
    return jsonb_build_object('ok', true, 'message', 'Your dietitian has already reviewed your details.', 'status', 'reviewed');
  end if;
  v_missing := intake_missing(v_id);
  if jsonb_array_length(v_missing) > 0 then
    return jsonb_build_object('ok', false, 'message', 'A few things still need an answer.', 'missing', v_missing);
  end if;
  update client_intake set status = 'submitted', submitted_at = now(), updated_at = now(), updated_by = auth.uid()
   where client_id = v_id;
  perform _log_client_change(v_id, 'intake', 'set', ci.status, 'submitted');
  return jsonb_build_object('ok', true, 'status', 'submitted',
    'message', 'Thanks! Your details are with your dietitian.');
end $$;

-- the extra areas of the client app (locked tiles until the practice turns them on)
create or replace function my_areas() returns jsonb
language sql stable security definer set search_path = public as $$
  select case when coalesce(current_staff_role(), '') <> 'client' then '[]'::jsonb else
    coalesce((select jsonb_agg(jsonb_build_object('key', key, 'title', title, 'blurb', blurb, 'icon', icon, 'status', status) order by position)
              from client_areas where status <> 'hidden'), '[]'::jsonb) end
$$;

-- my_details gains the file/intake state (rest unchanged from 0039c)
create or replace function my_details() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_id uuid;
  c clients%rowtype;
  v_num boolean;
  v_diet record;
  v_contact text;
begin
  if coalesce(current_staff_role(), '') <> 'client' then
    return jsonb_build_object('ok', false, 'message', 'Client accounts only.');
  end if;
  v_id := my_client_id();
  if v_id is null then
    return jsonb_build_object('linked', false,
      'practice_name', app_setting('practice_name'), 'practice_email', app_setting('practice_email'));
  end if;
  select * into c from clients where id = v_id;
  v_num := c.numbers_allowed and c.client_shows_numbers;
  select full_name, email into v_diet from profiles where id = c.assigned_dietitian;
  v_contact := case when app_setting('client_contact') = 'dietitian'
                    then coalesce(nullif(btrim(v_diet.email), ''), app_setting('practice_email'))
                    else app_setting('practice_email') end;
  return jsonb_build_object(
    'linked', true,
    'full_name', c.full_name,
    'first_name', split_part(btrim(c.full_name), ' ', 1),
    'practice_name', app_setting('practice_name'),
    'practice_email', app_setting('practice_email'),
    'contact_email', v_contact,
    'dietitian_name', v_diet.full_name,
    'client_status', c.status,
    'intake_status', coalesce((select status from client_intake where client_id = v_id), 'open'),
    'intake_missing_count', jsonb_array_length(intake_missing(v_id)),
    'primary_goal', (select jsonb_build_object('label', gt.label, 'detail', g.detail, 'target_date', g.target_date)
                     from client_goals g join goal_types gt on gt.key = g.goal_type
                     where g.client_id = v_id and g.is_primary and g.ended_on is null limit 1),
    'requirements', coalesce((select jsonb_agg(jsonb_build_object('label', t.label,
                       'kind', case when t.kind = 'allergen' then 'avoid'
                                    when exists (select 1 from tag_blockers b where b.tag_id = t.id) then 'diet'
                                    else 'prefer' end) order by t.label)
                     from client_requirements r join tags t on t.id = r.tag_id where r.client_id = v_id), '[]'::jsonb),
    'foods_to_avoid', coalesce((select jsonb_agg(f.display_name order by f.display_name)
                       from client_food_rules fr join foods f on f.food_id = fr.food_id
                       where fr.client_id = v_id and fr.rule = 'avoid'), '[]'::jsonb),
    'foods_disliked', coalesce((select jsonb_agg(f.display_name order by f.display_name)
                       from client_food_rules fr join foods f on f.food_id = fr.food_id
                       where fr.client_id = v_id and fr.rule = 'dislike'), '[]'::jsonb),
    'supplements', coalesce((select jsonb_agg(jsonb_build_object('name', s.name, 'dose', s.dose, 'timing', s.timing)
                       order by s.position, s.name)
                     from client_supplements s
                     where s.client_id = v_id
                       and (s.ended_on is null or s.ended_on >= (now() at time zone app_setting('timezone'))::date)), '[]'::jsonb),
    'numbers_allowed', c.numbers_allowed,
    'show_numbers', v_num,
    'targets', case when v_num then (
        select jsonb_agg(jsonb_build_object('day_type', t.day_type, 'kcal', t.kcal, 'protein_g', t.protein_g,
                 'carb_g', t.carb_g, 'fat_g', t.fat_g, 'fibre_g', t.fibre_g)
                 order by array_position(array['default','hard','moderate','rest'], t.day_type))
        from client_current_targets t where t.client_id = v_id) end);
end $$;

-- 11. staff: intake review, sign-up queue, merge ------------------------------------------------
create or replace function client_intake_for_staff(p_client_id uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare c clients%rowtype; ci client_intake%rowtype; v_clin boolean := is_clinician();
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
    'sections', '[{"key":"about","title":"About"},{"key":"goals","title":"Goals"},{"key":"food","title":"Food"},{"key":"health","title":"Health"},{"key":"lifestyle","title":"Lifestyle"},{"key":"consent","title":"Consent"}]'::jsonb,
    'questions', (select coalesce(jsonb_agg(jsonb_build_object('key', q.key, 'section', q.section, 'label', q.label,
                     'kind', q.kind, 'options', q.options, 'clinical', q.clinical, 'active', q.active,
                     'answer', coalesce(ci.answers, '{}'::jsonb) -> q.key)
                     order by array_position(array['about','goals','food','health','lifestyle','consent'], q.section), q.position), '[]'::jsonb)
                  from intake_questions q
                  where (q.active or coalesce(ci.answers, '{}'::jsonb) ? q.key) and (v_clin or not q.clinical)),
    'hidden_clinical_count', case when v_clin then 0 else
        (select count(*) from intake_questions q where q.clinical and coalesce(ci.answers, '{}'::jsonb) ? q.key) end,
    'changes', case when v_clin then
        (select coalesce(jsonb_agg(x order by x.changed_at desc), '[]'::jsonb) from (
           select l.field, l.action, l.old_value, l.new_value, l.changed_at,
                  l.changed_by = c.user_id as by_client,
                  (select coalesce(nullif(btrim(full_name), ''), email) from profiles where id = l.changed_by) as changed_by_name
           from client_intake_log l where l.client_id = p_client_id order by l.changed_at desc limit 100) x)
      else '[]'::jsonb end,
    'changes_since_review', case when v_clin and ci.reviewed_at is not null then
        (select count(*) from client_intake_log l where l.client_id = p_client_id and l.changed_at > ci.reviewed_at
           and l.changed_by is distinct from ci.reviewed_by) else 0 end);
end $$;

-- clinicians fill in / correct answers on the client's behalf (logged)
create or replace function save_client_intake_answers(p_client_id uuid, p_answers jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare ci client_intake%rowtype; k text; v jsonb; v_new jsonb; v_answers jsonb;
begin
  if not (is_clinician() and can_access_client(p_client_id)) then
    return jsonb_build_object('ok', false, 'message', 'Only a dietitian can edit intake answers.'); end if;
  if p_answers is null or jsonb_typeof(p_answers) <> 'object' then
    return jsonb_build_object('ok', false, 'message', 'Nothing to save.'); end if;
  insert into client_intake (client_id) values (p_client_id) on conflict do nothing;
  select * into ci from client_intake where client_id = p_client_id for update;
  v_answers := ci.answers;
  begin
    for k, v in select key, value from jsonb_each(p_answers) loop
      if not exists (select 1 from intake_questions where key = k) then continue; end if;
      v_new := _intake_normalise(k, v);
      if v_new is null then
        if v_answers ? k then
          perform _log_client_change(p_client_id, 'answer:' || k, 'remove', v_answers ->> k, null);
          v_answers := v_answers - k;
        end if;
      elsif (v_answers -> k) is distinct from v_new then
        perform _log_client_change(p_client_id, 'answer:' || k, 'set', v_answers ->> k,
                                   case when jsonb_typeof(v_new) = 'string' then v_new #>> '{}' else v_new::text end);
        v_answers := jsonb_set(v_answers, array[k], v_new);
      end if;
    end loop;
  exception when raise_exception then
    return jsonb_build_object('ok', false, 'message', sqlerrm);
  end;
  update client_intake set answers = v_answers, updated_at = now(), updated_by = auth.uid() where client_id = p_client_id;
  return jsonb_build_object('ok', true, 'message', 'Saved.');
end $$;

-- 'reviewed' locks the client's form (they can still add a must-avoid); 'open' asks them to update
create or replace function set_client_intake_status(p_client_id uuid, p_status text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare ci client_intake%rowtype;
begin
  if not (is_clinician() and can_access_client(p_client_id)) then
    return jsonb_build_object('ok', false, 'message', 'Only a dietitian can change this.'); end if;
  if p_status not in ('open', 'reviewed') then
    return jsonb_build_object('ok', false, 'message', 'Choose open or reviewed.'); end if;
  insert into client_intake (client_id) values (p_client_id) on conflict do nothing;
  select * into ci from client_intake where client_id = p_client_id for update;
  if p_status = 'reviewed' then
    update client_intake set status = 'reviewed', reviewed_at = clock_timestamp(), reviewed_by = auth.uid(), updated_at = now()
     where client_id = p_client_id;
  else
    update client_intake set status = 'open', updated_at = now() where client_id = p_client_id;
  end if;
  perform _log_client_change(p_client_id, 'intake', 'set', ci.status, p_status);
  return jsonb_build_object('ok', true, 'status', p_status,
    'message', case when p_status = 'reviewed' then 'Marked as reviewed.' else 'The client can update their details again.' end);
end $$;

-- new self sign-ups + intakes waiting for review, with possible duplicates
create or replace function client_signup_queue() returns jsonb
language sql stable security definer set search_path = public as $$
  select case when not is_clinician() then '[]'::jsonb else coalesce((
    select jsonb_agg(row_to_json(q)::jsonb order by q.sort_at desc) from (
      select c.id as client_id, c.full_name, c.email, c.phone, c.source, c.status as client_status, c.created_at,
             c.user_id is not null as has_account,
             coalesce(ci.status, 'open') as intake_status, ci.submitted_at,
             coalesce(ci.submitted_at, c.created_at) as sort_at,
             (select coalesce(jsonb_agg(jsonb_build_object('client_id', o.id, 'full_name', o.full_name, 'email', o.email,
                        'has_account', o.user_id is not null,
                        'reasons', array_remove(array[
                           case when lower(btrim(o.email)) = lower(btrim(c.email)) then 'same email' end,
                           case when length(regexp_replace(coalesce(o.phone, ''), '\D', '', 'g')) >= 8
                                 and regexp_replace(o.phone, '\D', '', 'g') = regexp_replace(coalesce(c.phone, ''), '\D', '', 'g') then 'same phone' end,
                           case when lower(btrim(o.full_name)) = lower(btrim(c.full_name)) then 'same name' end], null))), '[]'::jsonb)
                from clients o
               where c.source = 'self_signup' and o.id <> c.id
                 and (lower(btrim(o.email)) = lower(btrim(c.email))
                      or (length(regexp_replace(coalesce(o.phone, ''), '\D', '', 'g')) >= 8
                          and regexp_replace(o.phone, '\D', '', 'g') = regexp_replace(coalesce(c.phone, ''), '\D', '', 'g'))
                      or lower(btrim(o.full_name)) = lower(btrim(c.full_name)))) as matches
      from clients c left join client_intake ci on ci.client_id = c.id
      where c.status = 'new' or ci.status = 'submitted') q), '[]'::jsonb) end
$$;

create or replace function merge_client_into(p_from uuid, p_into uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare res jsonb;
begin
  if not is_clinician() then return jsonb_build_object('ok', false, 'message', 'Only a dietitian can merge clients.'); end if;
  res := _merge_client_records(p_from, p_into);
  if (res ->> 'ok')::boolean then
    update invitations set accepted_at = now()
     where client_id = p_into and accepted_at is null and exists (select 1 from clients where id = p_into and user_id is not null);
  end if;
  return res;
end $$;

-- 12. client_overview: + source / intake / app account (appended columns) ----------------------
create or replace view client_overview with (security_invoker = true) as
 select c.id as client_id,
    c.full_name,
    c.status,
    c.assigned_dietitian,
    coalesce(nullif(btrim(pr.full_name), ''::text), pr.email) as assigned_dietitian_name,
    g.goal_type as primary_goal,
    gt.label as primary_goal_label,
    w.weight_kg as latest_weight_kg,
    w.recorded_on as latest_weight_on,
    ck.checkin_on as latest_checkin_on,
    t.kcal as default_kcal,
    (( select count(*) as count from meal_plans mp where mp.client_id = c.id))::integer as plan_count,
    c.source,
    ci.status as intake_status,
    ci.submitted_at as intake_submitted_at,
    c.user_id is not null as has_app_account
   from clients c
     left join profiles pr on pr.id = c.assigned_dietitian
     left join client_goals g on g.client_id = c.id and g.is_primary and g.ended_on is null
     left join goal_types gt on gt.key = g.goal_type
     left join lateral ( select cw.weight_kg, cw.recorded_on from client_weights cw
          where cw.client_id = c.id order by cw.recorded_on desc, cw.created_at desc limit 1) w on true
     left join lateral ( select cc.checkin_on from client_checkins cc
          where cc.client_id = c.id order by cc.checkin_on desc limit 1) ck on true
     left join client_current_targets t on t.client_id = c.id and t.day_type = 'default'::text
     left join client_intake ci on ci.client_id = c.id;

-- 13. backfill: client accounts that signed up before this (no file yet) get their own file ------
do $bf$
declare p record; v_client uuid;
begin
  for p in select * from profiles pr where pr.role = 'client' and not exists (select 1 from clients c where c.user_id = pr.id) loop
    insert into clients (full_name, email, phone, source, status)
    values (coalesce(nullif(btrim(p.full_name), ''), split_part(p.email, '@', 1)), lower(p.email),
            nullif(btrim(p.phone), ''), 'self_signup', 'new')
    returning id into v_client;
    perform set_config('goh.client_link', 'on', true);
    update clients set user_id = p.id where id = v_client;
    perform set_config('goh.client_link', '', true);
    insert into client_intake (client_id) values (v_client) on conflict do nothing;
  end loop;
end $bf$;

-- 14. grants ---------------------------------------------------------------------------------------
revoke execute on function client_tag_kind(uuid), _log_client_change(uuid, text, text, text, text),
  _intake_normalise(text, jsonb), intake_missing(uuid), _merge_client_records(uuid, uuid)
  from public, anon, authenticated;
revoke execute on function invite_client_to_app(uuid, text), claim_client_invite(uuid), client_app_status(uuid),
  my_intake(), save_my_intake(jsonb), submit_my_intake(), my_areas(), my_details(),
  client_intake_for_staff(uuid), save_client_intake_answers(uuid, jsonb), set_client_intake_status(uuid, text),
  client_signup_queue(), merge_client_into(uuid, uuid), get_client_invitation(uuid)
  from public, anon;
grant execute on function invite_client_to_app(uuid, text), claim_client_invite(uuid), client_app_status(uuid),
  my_intake(), save_my_intake(jsonb), submit_my_intake(), my_areas(), my_details(),
  client_intake_for_staff(uuid), save_client_intake_answers(uuid, jsonb), set_client_intake_status(uuid, text),
  client_signup_queue(), merge_client_into(uuid, uuid), get_client_invitation(uuid)
  to authenticated;
grant execute on function get_client_invitation(uuid) to anon;
