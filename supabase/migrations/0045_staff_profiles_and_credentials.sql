-- 0045_staff_profiles_and_credentials.sql — staff profiles, credentials with expiry, team compliance (phase 1).
-- Owner decisions (21 Oct 2026): two phases (CPD log, email reminders and intern auto-expiry later);
-- nothing required by default (an admin can mark credential types required per role); interns whose
-- placement has ended are only flagged to admins and their supervisor.
--   1. profiles: roles stay on profiles (every permission check reads them there). Hardened instead:
--      nobody changes their own role; only admins change roles; admin accounts and your own account
--      can't be deleted; signed-out visitors lose write grants; staff may edit their own details.
--      New details: preferred name, pronouns, bio, photo, university, supervisor, placement dates.
--   2. credential_types: the list of credentials (admins edit; renew period, which roles, required for)
--   3. staff_credentials: one row per person and type; files in the private staff-documents bucket;
--      only the person and admins see numbers and files; admins mark documents checked
--   4. team_compliance(): status per person and item (current / due in 60 / due in 30 / expired /
--      missing when required / not added), placement warnings, and counts for the menu.
--      Admins see everyone; dietitians see themselves and their interns (status only); others themselves.
-- Test: tests/sql/staff_profiles_0045.test.sql

-- 1. profiles ----------------------------------------------------------------------------------------
revoke insert, update, delete on profiles from anon;

alter table profiles
  add column if not exists preferred_name text,
  add column if not exists pronouns text,
  add column if not exists bio text,
  add column if not exists photo_path text,
  add column if not exists university text,
  add column if not exists supervisor_id uuid references profiles (id) on delete set null,
  add column if not exists placement_start date,
  add column if not exists placement_end date;
alter table profiles drop constraint if exists profiles_detail_lengths;
alter table profiles add constraint profiles_detail_lengths check (
  coalesce(length(preferred_name), 0) <= 60 and coalesce(length(pronouns), 0) <= 30 and coalesce(length(bio), 0) <= 800
  and coalesce(length(university), 0) <= 120);
alter table profiles drop constraint if exists profiles_placement_dates;
alter table profiles add constraint profiles_placement_dates check (placement_end is null or placement_start is null or placement_end >= placement_start);
comment on column profiles.photo_path is 'Object path in the private staff-documents bucket: {profile_id}/photo-…';
comment on column profiles.supervisor_id is 'Interns: the dietitian (or admin) supervising their placement. That person sees the intern''s compliance status.';

-- staff edit their own row (the guard below keeps role and email out of reach)
drop policy if exists profiles_update_own on profiles;
create policy profiles_update_own on profiles for update
  using (id = auth.uid() and is_staff()) with check (id = auth.uid() and is_staff());

create or replace function profiles_guard() returns trigger
language plpgsql set search_path = public as $$
declare v_app boolean := current_user in ('authenticated', 'anon');   -- sign-up and other server functions run as the owner
begin
  if not v_app then return coalesce(new, old); end if;
  if tg_op = 'DELETE' then
    if old.id = auth.uid() then raise exception 'You can''t delete your own account.'; end if;
    if old.role = 'admin' then raise exception 'Admin accounts can''t be deleted. Change the role first.'; end if;
    return old;
  end if;
  if new.id <> old.id then raise exception 'A profile''s id can''t change.'; end if;
  if new.role is distinct from old.role then
    if old.id = auth.uid() then raise exception 'You can''t change your own role.'; end if;
    if not is_admin() then raise exception 'Only an admin can change roles.'; end if;
  end if;
  if new.email is distinct from old.email and not is_admin() then
    raise exception 'Your email is your sign-in, so only an admin can change it.'; end if;
  if new.supervisor_id is distinct from old.supervisor_id and new.supervisor_id is not null then
    if new.supervisor_id = new.id then raise exception 'You can''t be your own supervisor.'; end if;
    if not exists (select 1 from profiles p where p.id = new.supervisor_id and p.role in ('admin', 'dietitian')) then
      raise exception 'The supervisor must be a dietitian or an admin.'; end if;
  end if;
  return new;
end $$;
drop trigger if exists profiles_guard on profiles;
create trigger profiles_guard before update or delete on profiles for each row execute function profiles_guard();

-- 2. credential types --------------------------------------------------------------------------------
create table if not exists credential_types (
  key          text primary key check (key ~ '^[a-z][a-z0-9_]*$'),
  label        text not null check (length(btrim(label)) between 1 and 80),
  help         text,
  renew_months integer check (renew_months is null or renew_months between 1 and 120),
  has_number   boolean not null default true,
  has_issuer   boolean not null default false,
  has_state    boolean not null default false,
  roles        text[] not null default '{admin,dietitian,intern}' check (roles <@ array['admin', 'dietitian', 'intern']),
  required_for text[] not null default '{}' check (required_for <@ array['admin', 'dietitian', 'intern']),
  position     integer not null default 0,
  active       boolean not null default true
);
comment on column credential_types.renew_months is 'Usual validity. Used as the due date when someone records an issue date but no expiry.';
comment on column credential_types.roles is 'Which roles are asked for this credential.';
comment on column credential_types.required_for is 'Roles for which a missing credential shows as Missing. Empty = optional for everyone (owner''s choice, Oct 2026).';
insert into credential_types (key, label, help, renew_months, has_number, has_issuer, has_state, roles, position) values
  ('apd', 'APD (Accredited Practising Dietitian)', 'Your Dietitians Australia APD number and renewal date.', 12, true, false, false, '{dietitian}', 10),
  ('ahpra', 'AHPRA registration', 'Only for professions AHPRA registers.', 12, true, false, false, '{admin,dietitian,intern}', 20),
  ('indemnity', 'Professional indemnity insurance', 'Insurer, policy number and expiry date.', 12, true, true, false, '{admin,dietitian}', 30),
  ('public_liability', 'Public liability insurance', 'Insurer, policy number and expiry date.', 12, true, true, false, '{admin,dietitian}', 40),
  ('first_aid', 'First aid (HLTAID011)', 'Usually renewed every 3 years.', 36, true, true, false, '{admin,dietitian,intern}', 50),
  ('cpr', 'CPR (HLTAID009)', 'Renew every year.', 12, true, true, false, '{admin,dietitian,intern}', 60),
  ('wwcc', 'Working with Children Check', 'Check number, state and expiry date.', 60, true, false, true, '{admin,dietitian,intern}', 70),
  ('police_check', 'Police check', 'Record the reference number and date. Uploading the certificate is optional.', 36, true, true, true, '{admin,dietitian,intern}', 80),
  ('food_safety', 'Food safety certificate', 'Helpful for cooking classes.', 60, true, true, false, '{admin,dietitian,intern}', 90)
on conflict (key) do nothing;

alter table credential_types enable row level security;
drop policy if exists credential_types_read on credential_types;
create policy credential_types_read on credential_types for select using (is_staff());
drop policy if exists credential_types_admin_insert on credential_types;
create policy credential_types_admin_insert on credential_types for insert with check (is_admin());
drop policy if exists credential_types_admin_update on credential_types;
create policy credential_types_admin_update on credential_types for update using (is_admin()) with check (is_admin());
revoke all on credential_types from anon;
revoke delete, truncate on credential_types from authenticated;       -- switch a type off instead

-- 3. staff credentials -------------------------------------------------------------------------------
create table if not exists staff_credentials (
  id          uuid primary key default gen_random_uuid(),
  profile_id  uuid not null references profiles (id) on delete cascade,
  type        text not null references credential_types (key),
  number      text check (number is null or length(number) <= 80),
  issuer      text check (issuer is null or length(issuer) <= 120),
  state       text check (state is null or state in ('NSW', 'VIC', 'QLD', 'WA', 'SA', 'TAS', 'ACT', 'NT')),
  issued_on   date,
  expires_on  date,
  file_path   text,
  checked_by  uuid references profiles (id) on delete set null,
  checked_at  timestamptz,
  note        text check (note is null or length(note) <= 500),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (profile_id, type),
  check (expires_on is null or issued_on is null or expires_on >= issued_on)
);
comment on column staff_credentials.file_path is 'Object path in the private staff-documents bucket: {profile_id}/{type}-…';
comment on column staff_credentials.checked_by is 'Admin who checked (sighted) the document. Cleared automatically when the person changes the details.';
create index if not exists staff_credentials_expiry on staff_credentials (expires_on);

alter table staff_credentials enable row level security;
drop policy if exists staff_credentials_read on staff_credentials;
create policy staff_credentials_read on staff_credentials for select
  using ((profile_id = auth.uid() and is_staff()) or is_admin());
drop policy if exists staff_credentials_insert on staff_credentials;
create policy staff_credentials_insert on staff_credentials for insert
  with check ((profile_id = auth.uid() and is_staff()) or is_admin());
drop policy if exists staff_credentials_update on staff_credentials;
create policy staff_credentials_update on staff_credentials for update
  using ((profile_id = auth.uid() and is_staff()) or is_admin()) with check ((profile_id = auth.uid() and is_staff()) or is_admin());
drop policy if exists staff_credentials_delete on staff_credentials;
create policy staff_credentials_delete on staff_credentials for delete
  using ((profile_id = auth.uid() and is_staff()) or is_admin());
revoke all on staff_credentials from anon;

create or replace function staff_credentials_guard() returns trigger
language plpgsql set search_path = public as $$
declare v_app boolean := current_user in ('authenticated', 'anon');
begin
  new.updated_at := now();
  if not v_app or is_admin() then return new; end if;
  if tg_op = 'INSERT' then
    if new.checked_by is not null or new.checked_at is not null then raise exception 'Only an admin can mark a document as checked.'; end if;
    return new;
  end if;
  if new.profile_id <> old.profile_id then raise exception 'A credential can''t move to another person.'; end if;
  if new.checked_by is distinct from old.checked_by or new.checked_at is distinct from old.checked_at then
    raise exception 'Only an admin can mark a document as checked.'; end if;
  -- the person changed what was checked → it needs checking again
  if (new.type, new.number, new.issuer, new.state, new.issued_on, new.expires_on, new.file_path)
     is distinct from (old.type, old.number, old.issuer, old.state, old.issued_on, old.expires_on, old.file_path) then
    new.checked_by := null; new.checked_at := null;
  end if;
  return new;
end $$;
drop trigger if exists staff_credentials_guard on staff_credentials;
create trigger staff_credentials_guard before insert or update on staff_credentials for each row execute function staff_credentials_guard();

create or replace function mark_credential_checked(p_id uuid, p_checked boolean) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not is_admin() then return jsonb_build_object('ok', false, 'message', 'Only an admin can mark documents as checked.'); end if;
  update staff_credentials set checked_by = case when p_checked then auth.uid() end,
                               checked_at = case when p_checked then now() end
   where id = p_id;
  if not found then return jsonb_build_object('ok', false, 'message', 'Credential not found.'); end if;
  return jsonb_build_object('ok', true, 'message', case when p_checked then 'Marked as checked.' else 'Check removed.' end);
end $$;

-- 4. private storage for staff documents and photos ----------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('staff-documents', 'staff-documents', false, 10485760,
        array['application/pdf', 'image/jpeg', 'image/png', 'image/webp', 'image/heic'])
on conflict (id) do update set public = false;

drop policy if exists "staff-documents own or admin read" on storage.objects;
create policy "staff-documents own or admin read" on storage.objects for select to authenticated
  using (bucket_id = 'staff-documents' and (((storage.foldername(name))[1] = auth.uid()::text and public.is_staff()) or public.is_admin()));
drop policy if exists "staff-documents own or admin insert" on storage.objects;
create policy "staff-documents own or admin insert" on storage.objects for insert to authenticated
  with check (bucket_id = 'staff-documents' and (((storage.foldername(name))[1] = auth.uid()::text and public.is_staff()) or public.is_admin()));
drop policy if exists "staff-documents own or admin update" on storage.objects;
create policy "staff-documents own or admin update" on storage.objects for update to authenticated
  using (bucket_id = 'staff-documents' and (((storage.foldername(name))[1] = auth.uid()::text and public.is_staff()) or public.is_admin()))
  with check (bucket_id = 'staff-documents' and (((storage.foldername(name))[1] = auth.uid()::text and public.is_staff()) or public.is_admin()));
drop policy if exists "staff-documents own or admin delete" on storage.objects;
create policy "staff-documents own or admin delete" on storage.objects for delete to authenticated
  using (bucket_id = 'staff-documents' and (((storage.foldername(name))[1] = auth.uid()::text and public.is_staff()) or public.is_admin()));

-- 5. status and the team view --------------------------------------------------------------------------
-- 'current' | 'due_60' | 'due_30' | 'expired' | 'no_date'
create or replace function credential_status(p_due date) returns text
language sql stable set search_path = public as $$
  select case when p_due is null then 'no_date'
              when p_due < t.d then 'expired'
              when p_due <= t.d + 30 then 'due_30'
              when p_due <= t.d + 60 then 'due_60'
              else 'current' end
  from (select (now() at time zone coalesce(app_setting('timezone'), 'Australia/Sydney'))::date as d) t
$$;

create or replace function team_compliance() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_me uuid := auth.uid(); v_role text := current_staff_role(); v_admin boolean := is_admin();
  v_today date := (now() at time zone coalesce(app_setting('timezone'), 'Australia/Sydney'))::date;
  v_people jsonb;
begin
  if not is_staff() then return jsonb_build_object('ok', false, 'message', 'Staff only.'); end if;
  with people as (
    select p.* from profiles p
    where p.role in ('admin', 'dietitian', 'intern')
      and (v_admin or p.id = v_me or (v_role = 'dietitian' and p.role = 'intern' and p.supervisor_id = v_me))),
  items as (
    select p.id as pid, t.key, t.label, t.position, p.role = any (t.required_for) as required, c.id as cid,
           coalesce(c.expires_on, (c.issued_on + make_interval(months => t.renew_months))::date) as due,
           c.expires_on is null and c.issued_on is not null and t.renew_months is not null as due_estimated,
           c.number, c.issuer, c.state, c.issued_on, c.expires_on, c.file_path, c.checked_at,
           (select coalesce(nullif(btrim(full_name), ''), email) from profiles where id = c.checked_by) as checked_by_name,
           (v_admin or p.id = v_me) as full
    from people p
    join credential_types t on t.active and p.role = any (t.roles)
    left join staff_credentials c on c.profile_id = p.id and c.type = t.key),
  scored as (
    select i.*, case when i.cid is null then case when i.required then 'missing' else 'not_added' end
                     else credential_status(i.due) end as status
    from items i),
  per_person as (
    select p.id, p.role, coalesce(nullif(btrim(p.preferred_name), ''), nullif(btrim(p.full_name), ''), p.email) as name,
           p.placement_start, p.placement_end, p.supervisor_id,
           case when p.role <> 'intern' or p.placement_end is null then null
                when p.placement_end < v_today then 'ended'
                when p.placement_end <= v_today + 7 then 'ends_soon' end as placement,
           (select coalesce(jsonb_agg(jsonb_build_object(
                'type', s.key, 'label', s.label, 'required', s.required, 'status', s.status,
                'due', s.due, 'due_estimated', s.due_estimated, 'checked', s.checked_at is not null,
                'id', case when s.full then s.cid end,
                'number', case when s.full then s.number end, 'issuer', case when s.full then s.issuer end,
                'state', case when s.full then s.state end, 'issued_on', case when s.full then s.issued_on end,
                'expires_on', case when s.full then s.expires_on end,
                'has_file', s.file_path is not null, 'file_path', case when s.full then s.file_path end,
                'checked_at', case when s.full then s.checked_at end, 'checked_by_name', case when s.full then s.checked_by_name end)
              order by s.position), '[]'::jsonb) from scored s where s.pid = p.id) as items,
           (select count(*) from scored s where s.pid = p.id and s.status in ('expired', 'due_30', 'missing')) as urgent,
           (select count(*) from scored s where s.pid = p.id and s.status = 'due_60') as soon
    from people p)
  select coalesce(jsonb_agg(jsonb_build_object(
           'profile_id', pp.id, 'name', pp.name, 'role', pp.role, 'is_me', pp.id = v_me,
           'placement_start', pp.placement_start, 'placement_end', pp.placement_end, 'placement', pp.placement,
           'needs_attention', pp.urgent > 0 or pp.placement is not null, 'urgent_count', pp.urgent, 'due_60_count', pp.soon,
           'items', pp.items) order by (pp.id <> v_me), pp.name), '[]'::jsonb)
    into v_people from per_person pp;
  return jsonb_build_object(
    'ok', true,
    'people', v_people,
    -- for the menu dot: people other than me who need attention (expired, due in 30 days, missing, placement ending)
    'needs_attention', (select count(*) from jsonb_array_elements(v_people) x where (x ->> 'needs_attention')::boolean and not (x ->> 'is_me')::boolean),
    'mine_needs_attention', coalesce((select (x ->> 'needs_attention')::boolean from jsonb_array_elements(v_people) x where (x ->> 'is_me')::boolean), false));
end $$;

-- 6. grants ----------------------------------------------------------------------------------------------
revoke execute on function profiles_guard(), staff_credentials_guard() from public, anon, authenticated;
revoke execute on function mark_credential_checked(uuid, boolean), team_compliance(), credential_status(date) from public, anon;
grant execute on function mark_credential_checked(uuid, boolean), team_compliance(), credential_status(date) to authenticated;
