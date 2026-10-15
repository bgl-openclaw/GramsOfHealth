-- 0027_clients_schema.sql  (Clients roadmap C1 — schema)
--
-- Everything here is entered by staff (dietitians/admin; interns on allocated
-- clients). Access rules come from 0026: can_access_client / can_view_checkins /
-- is_clinician. Clinical records and targets are clinician-only to write;
-- clinical records clinician-only to read. No recipe macros are stored —
-- only the dietitian's targets (plus the calculator's working when a
-- suggestion is accepted). Old target/restriction columns on clients are KEPT
-- until Lovable has switched (C5 drops them on approval).
-- Idempotent.

-- 0. Lookups (staff read, admin write) -----------------------------------------
create table if not exists activity_levels (
  key text primary key, label text not null, factor numeric not null check (factor between 1 and 3),
  position int not null default 0, active boolean not null default true);
insert into activity_levels (key, label, factor, position) values
  ('sedentary',         'Sedentary',         1.2,   1),
  ('lightly_active',    'Lightly active',    1.375, 2),
  ('moderately_active', 'Moderately active', 1.55,  3),
  ('very_active',       'Very active',       1.725, 4),
  ('extra_active',      'Extra active',      1.9,   5)
on conflict (key) do nothing;

create table if not exists goal_types (
  key text primary key, label text not null,
  category text not null check (category in ('body_composition', 'performance', 'clinical', 'general')),
  position int not null default 0, active boolean not null default true);
insert into goal_types (key, label, category, position) values
  ('fat_loss',    'Fat loss',          'body_composition', 1),
  ('maintenance', 'Maintenance',       'body_composition', 2),
  ('muscle_gain', 'Muscle gain',       'body_composition', 3),
  ('performance', 'Performance',       'performance',      4),
  ('clinical',    'Clinical / medical','clinical',         5)
on conflict (key) do nothing;

create table if not exists protein_families (
  key text primary key, label text not null, position int not null default 0, active boolean not null default true);
insert into protein_families (key, label, position) values
  ('chicken', 'Chicken', 1), ('turkey', 'Turkey', 2), ('beef', 'Beef', 3), ('lamb', 'Lamb', 4),
  ('pork', 'Pork', 5), ('kangaroo', 'Kangaroo', 6), ('fish', 'Fish', 7), ('seafood', 'Seafood', 8),
  ('egg', 'Egg', 9), ('dairy', 'Dairy', 10), ('tofu_tempeh', 'Tofu & tempeh', 11),
  ('legumes', 'Legumes', 12), ('other', 'Other', 13)
on conflict (key) do nothing;

-- Diet tag → the "contains" tags that disqualify a recipe (was Lovable's
-- RESTRICTION_BLOCKERS). An allergen tag used as a requirement blocks itself.
create table if not exists tag_blockers (
  tag_id uuid not null references tags(id) on delete cascade,
  blocks_tag_id uuid not null references tags(id) on delete cascade,
  primary key (tag_id, blocks_tag_id));
insert into tag_blockers (tag_id, blocks_tag_id)
select d.id, a.id
from (values
  ('Vegetarian', 'Meat'), ('Vegetarian', 'Fish'), ('Vegetarian', 'Shellfish'),
  ('Vegan', 'Meat'), ('Vegan', 'Fish'), ('Vegan', 'Shellfish'), ('Vegan', 'Dairy'), ('Vegan', 'Egg'), ('Vegan', 'Honey'),
  ('Pescatarian', 'Meat'),
  ('Gluten-free', 'Gluten'), ('Dairy-free', 'Dairy'), ('Egg-free', 'Egg'),
  ('Nut-free', 'Tree nuts'), ('Nut-free', 'Peanuts'),
  ('Low-FODMAP', 'High-FODMAP')) m(diet, blocks)
join tags d on d.label = m.diet and (d.kind = 'dietary' or d.category = 'diet')
join tags a on a.label = m.blocks and a.kind = 'allergen'
on conflict do nothing;

do $$
declare t text;
begin
  foreach t in array array['activity_levels', 'goal_types', 'protein_families', 'tag_blockers'] loop
    execute format('alter table %I enable row level security', t);
    execute format('drop policy if exists %I on %I', t || '_read', t);
    execute format('create policy %I on %I for select to authenticated using (is_staff())', t || '_read', t);
    execute format('drop policy if exists %I on %I', t || '_admin_write', t);
    execute format('create policy %I on %I for all to authenticated using (is_admin()) with check (is_admin())', t || '_admin_write', t);
    execute format('revoke all on %I from anon', t);
  end loop;
end $$;

-- Protein family is set on foods by dietitians (never auto-assigned).
alter table foods add column if not exists protein_family text
  references protein_families(key) on update cascade on delete set null;

-- 1. Client identity ------------------------------------------------------------
alter table clients add column if not exists date_of_birth date;
alter table clients add column if not exists sex text not null default 'unspecified';
alter table clients add column if not exists equation_sex text;
alter table clients add column if not exists height_cm numeric;
alter table clients add column if not exists activity_level text
  references activity_levels(key) on update cascade on delete set null;
alter table clients add column if not exists assigned_dietitian uuid references profiles(id) on delete set null;
alter table clients add column if not exists status text not null default 'active';
alter table clients add column if not exists protein_g_per_kg numeric;

alter table clients drop constraint if exists clients_sex_check;
alter table clients add constraint clients_sex_check check (sex in ('female', 'male', 'other', 'unspecified'));
alter table clients drop constraint if exists clients_equation_sex_check;
alter table clients add constraint clients_equation_sex_check check (equation_sex is null or equation_sex in ('female', 'male'));
alter table clients drop constraint if exists clients_height_check;
alter table clients add constraint clients_height_check check (height_cm is null or height_cm between 50 and 272);
alter table clients drop constraint if exists clients_status_check;
alter table clients add constraint clients_status_check check (status in ('active', 'paused', 'finished'));
alter table clients drop constraint if exists clients_protein_gkg_check;
alter table clients add constraint clients_protein_gkg_check check (protein_g_per_kg is null or protein_g_per_kg between 0 and 5);
alter table clients drop constraint if exists clients_dob_check;
alter table clients add constraint clients_dob_check check (date_of_birth is null or date_of_birth >= '1900-01-01');

comment on column clients.equation_sex is 'Mifflin-St Jeor constant the dietitian chose when sex is other/unspecified.';
comment on column clients.notes is 'Staff-only notes. Never expose to a client-facing app.';

-- 2. Goals ----------------------------------------------------------------------
create table if not exists client_goals (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references clients(id) on delete cascade,
  goal_type text not null references goal_types(key) on update cascade,
  detail text, target_date date,
  is_primary boolean not null default false,
  ended_on date,
  set_by uuid references profiles(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now());
create unique index if not exists client_goals_one_primary
  on client_goals (client_id) where is_primary and ended_on is null;

-- 3. Check-ins (before weights: a check-in can carry the day's weight) ------------
create table if not exists client_checkins (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references clients(id) on delete cascade,
  checkin_on date not null,
  feeling smallint check (feeling between 1 and 5),        -- 1 very poor … 5 great
  hunger  smallint check (hunger between 1 and 5),         -- 1 never hungry … 5 always hungry
  energy  smallint check (energy between 1 and 5),         -- 1 very low … 5 high
  sleep   smallint check (sleep between 1 and 5),          -- 1 very poor … 5 great
  bowels_bristol smallint check (bowels_bristol between 1 and 7),
  bowels_notes text, training text, likes text, dislikes text, changes_wanted text, notes text,
  answers jsonb not null default '{}'::jsonb,              -- future custom questions / automation
  source text not null default 'dietitian' check (source in ('dietitian', 'client')),
  entered_by uuid references profiles(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now());
create index if not exists client_checkins_client_on on client_checkins (client_id, checkin_on desc);

-- 4. Weights --------------------------------------------------------------------
create table if not exists client_weights (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references clients(id) on delete cascade,
  weight_kg numeric not null check (weight_kg between 20 and 400),
  recorded_on date not null,
  note text,
  checkin_id uuid references client_checkins(id) on delete set null,
  source text not null default 'dietitian' check (source in ('dietitian', 'client')),
  entered_by uuid references profiles(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now());
create index if not exists client_weights_client_on on client_weights (client_id, recorded_on desc, created_at desc);

-- 5. Targets (append-only history; current = latest per day type) ----------------
create table if not exists client_targets (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references clients(id) on delete cascade,
  day_type text not null check (day_type in ('default', 'hard', 'moderate', 'rest')),
  kcal numeric check (kcal >= 0), protein_g numeric check (protein_g >= 0),
  carb_g numeric check (carb_g >= 0), fat_g numeric check (fat_g >= 0), fibre_g numeric check (fibre_g >= 0),
  source text not null check (source in ('dietitian', 'calculator_accepted')),
  calc_inputs jsonb,
  note text,
  set_by uuid references profiles(id) on delete set null default auth.uid(),
  set_on timestamptz not null default now(),
  constraint client_targets_calc_snapshot check (source <> 'calculator_accepted' or calc_inputs is not null));
create index if not exists client_targets_current on client_targets (client_id, day_type, set_on desc);
comment on column client_targets.calc_inputs is
  'Calculator working when accepted: weight_kg + weighed_on, height_cm, age_years, as_of, sex constant used, activity key + factor, bmr, tdee, protein g/kg.';

create or replace view client_current_targets with (security_invoker = on) as
select distinct on (client_id, day_type)
  id, client_id, day_type, kcal, protein_g, carb_g, fat_g, fibre_g, source, calc_inputs, note, set_by, set_on
from client_targets
order by client_id, day_type, set_on desc, id;

-- Backfill: existing five columns → one "default" row (only where none exists yet).
insert into client_targets (client_id, day_type, kcal, protein_g, carb_g, fat_g, fibre_g, source, note, set_by)
select c.id, 'default', c.kcal_target, c.protein_target_g, c.carb_target_g, c.fat_target_g, c.fibre_target_g,
       'dietitian', 'migrated from clients target columns (0027)', null
from clients c
where coalesce(c.kcal_target, c.protein_target_g, c.carb_target_g, c.fat_target_g, c.fibre_target_g) is not null
  and not exists (select 1 from client_targets t where t.client_id = c.id and t.day_type = 'default');

-- 6. Requirements (tags) + food rules ----------------------------------------------
create table if not exists client_requirements (
  client_id uuid not null references clients(id) on delete cascade,
  tag_id uuid not null references tags(id) on delete cascade,
  note text,
  added_by uuid references profiles(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  primary key (client_id, tag_id));
comment on table client_requirements is
  'Allergen tag = avoid it. Diet tag = avoid its tag_blockers. Tag with neither (e.g. Heart-healthy) = prefer.';

-- Migrate clients.restrictions text[] → tag ids (label match; "X-free" → allergen X).
insert into client_requirements (client_id, tag_id, note, added_by)
select distinct c.id, coalesce(diet.id, alg.id), 'migrated from clients.restrictions (0027)', null::uuid
from clients c
cross join lateral unnest(c.restrictions) r
left join tags diet on lower(diet.label) = lower(btrim(r)) and (diet.kind = 'dietary' or diet.category = 'diet')
left join tags alg on alg.kind = 'allergen'
  and lower(alg.label) = lower(regexp_replace(btrim(r), '-free$', '', 'i'))
where coalesce(diet.id, alg.id) is not null
on conflict do nothing;

create or replace view client_blocked_tags with (security_invoker = on) as
select cr.client_id, b.blocked_tag_id, bt.label as blocked_label, cr.tag_id as because_tag_id, src.label as because_label
from client_requirements cr
join tags src on src.id = cr.tag_id
cross join lateral (
  select src.id as blocked_tag_id where src.kind = 'allergen'
  union
  select tb.blocks_tag_id from tag_blockers tb where tb.tag_id = src.id
) b
join tags bt on bt.id = b.blocked_tag_id;

create or replace view client_preferred_tags with (security_invoker = on) as
select cr.client_id, cr.tag_id, t.label
from client_requirements cr join tags t on t.id = cr.tag_id
where t.kind is distinct from 'allergen'
  and not exists (select 1 from tag_blockers tb where tb.tag_id = cr.tag_id);

create table if not exists client_food_rules (
  client_id uuid not null references clients(id) on delete cascade,
  food_id text not null references foods(food_id) on update cascade on delete cascade,
  rule text not null check (rule in ('avoid', 'dislike')),
  primary_only boolean not null default false,
  note text,
  added_by uuid references profiles(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  primary key (client_id, food_id),
  constraint client_food_rules_primary_only check (rule = 'dislike' or not primary_only));
comment on table client_food_rules is
  'avoid = never in any amount (hard). dislike = soft; with primary_only the food is only excluded where it is ≥10% of the recipe''s total weight.';

-- 7. Preferences ----------------------------------------------------------------
create table if not exists client_protein_preferences (
  client_id uuid not null references clients(id) on delete cascade,
  protein_family text not null references protein_families(key) on update cascade on delete cascade,
  preference text not null check (preference in ('like', 'dislike')),
  primary key (client_id, protein_family));

create table if not exists client_supplements (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references clients(id) on delete cascade,
  name text not null, dose text, timing text, notes text,
  started_on date, ended_on date,
  position int not null default 0,
  created_at timestamptz not null default now());

-- 8. Structure / variety ------------------------------------------------------------
create table if not exists client_structure (
  client_id uuid primary key references clients(id) on delete cascade,
  cycle_length_days int check (cycle_length_days between 1 and 28),
  repeat_min_gap_days int check (repeat_min_gap_days between 0 and 28),
  repeat_max_per_cycle int check (repeat_max_per_cycle between 1 and 28),
  batch_cooking boolean not null default false,
  day_type_pattern text[] not null default array['default','default','default','default','default','default','default'],
  updated_at timestamptz not null default now(),
  constraint client_structure_pattern check (
    cardinality(day_type_pattern) = 7
    and day_type_pattern <@ array['default', 'hard', 'moderate', 'rest']));
comment on column client_structure.day_type_pattern is 'Monday..Sunday → day type whose targets apply.';
comment on column client_structure.repeat_min_gap_days is 'Same recipe not again within N days (batch_cooking exempts next-day leftovers).';
comment on column client_structure.repeat_max_per_cycle is 'Same recipe at most N times per cycle.';

create table if not exists client_meal_slots (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references clients(id) on delete cascade,
  position int not null,
  name text not null,
  slot_kind text not null check (slot_kind in ('breakfast', 'lunch', 'dinner', 'snack')),
  time_of_day time,
  free_choice boolean not null default false,
  unique (client_id, position),
  unique (client_id, name));

create table if not exists client_protein_spread (
  client_id uuid not null references clients(id) on delete cascade,
  protein_family text not null references protein_families(key) on update cascade on delete cascade,
  count_per_cycle int not null check (count_per_cycle between 0 and 56),
  primary key (client_id, protein_family));

-- 9. Clinical records (clinician-only, private bucket) ------------------------------
create table if not exists client_clinical_records (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references clients(id) on delete cascade,
  kind text not null check (kind in ('dexa', 'bloods', 'other')),
  recorded_on date not null,
  summary text,
  measurements jsonb,           -- optional key values for trending (e.g. body fat %, ferritin)
  file_path text,               -- object path in the private clinical-records bucket: {client_id}/{file}
  uploaded_by uuid references profiles(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now());

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('clinical-records', 'clinical-records', false, 20971520,
        array['application/pdf', 'image/jpeg', 'image/png', 'image/heic'])
on conflict (id) do update set public = false;

drop policy if exists "clinical-records clinician read" on storage.objects;
create policy "clinical-records clinician read" on storage.objects for select to authenticated
  using (bucket_id = 'clinical-records' and public.is_clinician());
drop policy if exists "clinical-records clinician insert" on storage.objects;
create policy "clinical-records clinician insert" on storage.objects for insert to authenticated
  with check (bucket_id = 'clinical-records' and public.is_clinician());
drop policy if exists "clinical-records clinician update" on storage.objects;
create policy "clinical-records clinician update" on storage.objects for update to authenticated
  using (bucket_id = 'clinical-records' and public.is_clinician())
  with check (bucket_id = 'clinical-records' and public.is_clinician());
drop policy if exists "clinical-records clinician delete" on storage.objects;
create policy "clinical-records clinician delete" on storage.objects for delete to authenticated
  using (bucket_id = 'clinical-records' and public.is_clinician());

-- 10. RLS for client tables ------------------------------------------------------------
do $$
declare t text;
begin
  -- staff with access to the client: full read/write
  foreach t in array array['client_goals', 'client_weights', 'client_requirements', 'client_food_rules',
                           'client_protein_preferences', 'client_supplements', 'client_structure',
                           'client_meal_slots', 'client_protein_spread'] loop
    execute format('alter table %I enable row level security', t);
    execute format('drop policy if exists %I on %I', t || '_access', t);
    execute format('create policy %I on %I for all to authenticated using (can_access_client(client_id)) with check (can_access_client(client_id))', t || '_access', t);
    execute format('revoke all on %I from anon', t);
  end loop;
end $$;

-- Targets: anyone with client access reads; only clinicians set them.
alter table client_targets enable row level security;
drop policy if exists client_targets_read on client_targets;
create policy client_targets_read on client_targets for select to authenticated using (can_access_client(client_id));
drop policy if exists client_targets_write on client_targets;
create policy client_targets_write on client_targets for all to authenticated
  using (is_clinician()) with check (is_clinician());
revoke all on client_targets from anon;

-- Check-ins: per-client tick for interns; delete clinician-only.
alter table client_checkins enable row level security;
drop policy if exists client_checkins_read on client_checkins;
create policy client_checkins_read on client_checkins for select to authenticated using (can_view_checkins(client_id));
drop policy if exists client_checkins_insert on client_checkins;
create policy client_checkins_insert on client_checkins for insert to authenticated with check (can_view_checkins(client_id));
drop policy if exists client_checkins_update on client_checkins;
create policy client_checkins_update on client_checkins for update to authenticated
  using (can_view_checkins(client_id)) with check (can_view_checkins(client_id));
drop policy if exists client_checkins_delete on client_checkins;
create policy client_checkins_delete on client_checkins for delete to authenticated using (is_clinician());
revoke all on client_checkins from anon;

-- Clinical: clinicians only, every operation.
alter table client_clinical_records enable row level security;
drop policy if exists client_clinical_records_clinician on client_clinical_records;
create policy client_clinical_records_clinician on client_clinical_records for all to authenticated
  using (is_clinician()) with check (is_clinician());
revoke all on client_clinical_records from anon;

-- Views
revoke all on client_current_targets, client_blocked_tags, client_preferred_tags from anon;
grant select on client_current_targets, client_blocked_tags, client_preferred_tags to authenticated;
