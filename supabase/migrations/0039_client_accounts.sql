-- 0039_client_accounts.sql — client app P1a backend (owner go 2026-10-21).
-- Owner decisions: client area inside the same app; only dietitians/admins invite
-- clients, link accounts and allow numbers; numbers switchable on both sides
-- (dietitian allows → client chooses); invites are copy-and-send links for now;
-- "Request a change" goes to the assigned dietitian, falling back to the practice
-- email. Magic link / Google / emailed invites (P1b) and the pre-filled intake
-- sheet (P1c) come later.
--
-- 1. app_settings: practice name/email, timezone and client-contact mode live in
--    data, not code (white-label rule).
-- 2. clients.user_id (the client's login), numbers_allowed (dietitian, default off),
--    client_shows_numbers (client's own switch, used only when allowed).
--    Guard: user_id changes only through link/unlink/invite acceptance; only
--    dietitians/admins change numbers_allowed; only the client changes their switch.
-- 3. Client invitations: invitations.role may be 'client' with a client_id.
--    Accepting a client invite REQUIRES the invite token (sent by the app in the
--    sign-up metadata) — email confirmation is off, so email matching alone would let
--    anyone who knows a client's email claim their plan. Staff invites keep working
--    by email as before (and by token once the app sends it).
-- 4. Self-registration: a sign-up with account_type = 'client' (and no valid invite)
--    becomes an UNLINKED client account. It sees nothing until a dietitian links it.
-- 5. Staff RPCs: invite_client_to_app, link_client_account, unlink_client_account,
--    client_app_status, client_app_signups.
-- 6. Client RPCs (the ONLY things a client can read — every table stays closed to
--    them): my_details, my_plans, my_plan_version, set_my_show_numbers. Everything
--    plan-related comes from PUBLISHED frozen snapshots. Without numbers, calories,
--    macros and targets are removed here, before anything leaves the database.
-- Idempotent.

-- 1. Settings -------------------------------------------------------------------------
create table if not exists app_settings (
  key text primary key,
  value text not null,
  description text);
alter table app_settings enable row level security;
drop policy if exists app_settings_staff_read on app_settings;
create policy app_settings_staff_read on app_settings for select to authenticated using (is_staff());
drop policy if exists app_settings_admin_write on app_settings;
create policy app_settings_admin_write on app_settings for all to authenticated using (is_admin()) with check (is_admin());
revoke all on app_settings from anon;

insert into app_settings (key, value, description) values
  ('practice_name', 'Grams of Health', 'Shown to clients in the client area.'),
  ('practice_email', 'info@gramsofhealth.com', 'Client contact fallback; "Request a change" uses it when no dietitian is assigned.'),
  ('timezone', 'Australia/Sydney', 'Practice timezone — decides which plan is "current" for a client.'),
  ('client_contact', 'dietitian', '"dietitian" = clients email their assigned dietitian (fallback practice email); "practice" = always the practice email.')
on conflict (key) do nothing;

-- Non-secret settings only: any signed-in user can read one through app_setting().
create or replace function app_setting(p_key text) returns text
language sql stable security definer set search_path = public as $$
  select value from app_settings where key = p_key
$$;

-- 2. Client columns + guard --------------------------------------------------------------
alter table clients add column if not exists user_id uuid unique references profiles(id) on delete set null;
alter table clients add column if not exists numbers_allowed boolean not null default false;
alter table clients add column if not exists client_shows_numbers boolean not null default true;
comment on column clients.user_id is 'The client''s own app login (profiles.role = client). Set only by invite acceptance or link_client_account.';
comment on column clients.numbers_allowed is 'Dietitian/admin: may this client see calories, macros and targets in the client app? Default off.';
comment on column clients.client_shows_numbers is 'The client''s own "Show calories & macros" switch; only matters when numbers_allowed.';

create or replace function clients_app_guard() returns trigger
language plpgsql set search_path = public as $$
begin
  if auth.uid() is null then return new; end if;              -- service role / migrations / sign-up trigger
  if tg_op = 'INSERT' then
    if new.user_id is not null then raise exception 'Link an app account with "Link account", not on create.'; end if;
    if new.numbers_allowed and not is_clinician() then raise exception 'Only a dietitian can allow numbers.'; end if;
    return new;
  end if;
  if new.user_id is distinct from old.user_id
     and coalesce(current_setting('goh.client_link', true), '') <> 'on'
     and not (new.user_id is null and not exists (select 1 from profiles where id = old.user_id)) then
    raise exception 'App accounts are linked and unlinked with Link / Unlink account.';
  end if;
  if new.numbers_allowed is distinct from old.numbers_allowed and not is_clinician() then
    raise exception 'Only a dietitian can change whether this client sees numbers.';
  end if;
  if new.client_shows_numbers is distinct from old.client_shows_numbers
     and coalesce(current_setting('goh.client_pref', true), '') <> 'on' then
    raise exception 'The client chooses this in their own app.';
  end if;
  return new;
end $$;

drop trigger if exists clients_app_guard on clients;
create trigger clients_app_guard before insert or update on clients
  for each row execute function clients_app_guard();

-- 3. Client invitations ----------------------------------------------------------------------
alter table invitations add column if not exists client_id uuid references clients(id) on delete cascade;
alter table invitations drop constraint if exists invitations_role_check;
alter table invitations add constraint invitations_role_check check (role in ('admin', 'dietitian', 'intern', 'client'));
alter table invitations drop constraint if exists invitations_client_link;
alter table invitations add constraint invitations_client_link check ((role = 'client') = (client_id is not null));

-- 4. Sign-up: staff invite / client invite (token required) / self-registered client / pending
create or replace function handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  inv public.invitations%rowtype;   -- rowtype (not record) so it's readable even when no invite matched
  v_token uuid;
  v_role text;
begin
  begin
    v_token := nullif(new.raw_user_meta_data ->> 'invite_token', '')::uuid;
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
    when coalesce(new.raw_user_meta_data ->> 'account_type', '') = 'client' then 'client'
    else 'pending' end;

  insert into public.profiles (id, email, full_name, phone, job_title, organisation, role)
  values (new.id, new.email,
          new.raw_user_meta_data ->> 'full_name', new.raw_user_meta_data ->> 'phone',
          new.raw_user_meta_data ->> 'job_title', new.raw_user_meta_data ->> 'organisation',
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
  return new;
end $$;

-- 5. Staff RPCs ---------------------------------------------------------------------------------
create or replace function invite_client_to_app(p_client_id uuid, p_email text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c clients%rowtype; v_email text; inv invitations%rowtype;
begin
  if not is_clinician() then
    return jsonb_build_object('ok', false, 'message', 'Only a dietitian can invite a client to the app.');
  end if;
  select * into c from clients where id = p_client_id;
  if not found then return jsonb_build_object('ok', false, 'message', 'Client not found.'); end if;
  if c.user_id is not null then
    return jsonb_build_object('ok', false, 'message', 'This client already has an app account.');
  end if;
  v_email := lower(btrim(coalesce(nullif(btrim(p_email), ''), c.email)));
  if v_email is null or v_email = '' then
    return jsonb_build_object('ok', false, 'message', 'Add the client''s email address first.');
  end if;
  if exists (select 1 from profiles where lower(email) = v_email) then
    return jsonb_build_object('ok', false,
      'message', 'An app account with this email already exists — link it from "App sign-ups waiting".');
  end if;
  select * into inv from invitations
   where client_id = p_client_id and lower(email) = v_email and accepted_at is null and expires_at > now()
   order by created_at desc limit 1;
  if not found then
    insert into invitations (email, role, client_id, invited_by)
    values (v_email, 'client', p_client_id, auth.uid()) returning * into inv;
  end if;
  return jsonb_build_object('ok', true, 'token', inv.token, 'email', inv.email, 'expires_at', inv.expires_at,
    'message', 'Invite link ready — copy it and send it to the client.');
end $$;

create or replace function link_client_account(p_client_id uuid, p_user_id uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_role text; v_cur uuid;
begin
  if not is_clinician() then
    return jsonb_build_object('ok', false, 'message', 'Only a dietitian can link app accounts.');
  end if;
  select role into v_role from profiles where id = p_user_id;
  if v_role is distinct from 'client' then
    return jsonb_build_object('ok', false, 'message', 'That account isn''t a client app account.');
  end if;
  if exists (select 1 from clients where user_id = p_user_id) then
    return jsonb_build_object('ok', false, 'message', 'That app account is already linked to a client.');
  end if;
  select user_id into v_cur from clients where id = p_client_id for update;
  if not found then return jsonb_build_object('ok', false, 'message', 'Client not found.'); end if;
  if v_cur is not null then
    return jsonb_build_object('ok', false, 'message', 'This client already has an app account — unlink it first.');
  end if;
  perform set_config('goh.client_link', 'on', true);
  update clients set user_id = p_user_id where id = p_client_id;
  perform set_config('goh.client_link', '', true);
  return jsonb_build_object('ok', true, 'message', 'App account linked.');
end $$;

create or replace function unlink_client_account(p_client_id uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not is_clinician() then
    return jsonb_build_object('ok', false, 'message', 'Only a dietitian can unlink app accounts.');
  end if;
  perform set_config('goh.client_link', 'on', true);
  update clients set user_id = null where id = p_client_id and user_id is not null;
  perform set_config('goh.client_link', '', true);
  if not found then return jsonb_build_object('ok', false, 'message', 'This client has no linked app account.'); end if;
  return jsonb_build_object('ok', true, 'message', 'App account unlinked. The login still exists but sees nothing.');
end $$;

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
                 'token', case when is_clinician() then inv.token end) end,
    'numbers_allowed', c.numbers_allowed,
    'client_shows_numbers', c.client_shows_numbers);
end $$;

create or replace function client_app_signups()
returns table (user_id uuid, email text, full_name text, phone text, created_at timestamptz)
language sql stable security definer set search_path = public as $$
  select p.id, p.email, p.full_name, p.phone, p.created_at
  from profiles p
  where is_clinician() and p.role = 'client'
    and not exists (select 1 from clients c where c.user_id = p.id)
  order by p.created_at desc
$$;

-- 6. Client RPCs ---------------------------------------------------------------------------------
create or replace function my_client_id() returns uuid
language sql stable security definer set search_path = public as $$
  select c.id from clients c join profiles p on p.id = c.user_id
  where c.user_id = auth.uid() and p.role = 'client'
$$;

create or replace function my_details() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_id uuid := my_client_id();
  c clients%rowtype;
  v_num boolean;
  v_diet record;
  v_contact text;
begin
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

create or replace function my_plans()
returns table (plan_id uuid, title text, start_date date, days int, end_date date,
               version_no int, published_at timestamptz, is_current boolean)
language sql stable security definer set search_path = public as $$
  with latest as (
    select distinct on (v.meal_plan_id) v.meal_plan_id, v.version_no, v.published_at, v.snapshot
    from meal_plan_versions v join meal_plans p on p.id = v.meal_plan_id
    where p.client_id = my_client_id()
    order by v.meal_plan_id, v.version_no desc),
  rows as (
    select l.meal_plan_id, coalesce(l.snapshot -> 'plan' ->> 'title', 'Your meal plan') as title,
           nullif(l.snapshot -> 'plan' ->> 'start_date', '')::date as start_date,
           greatest(coalesce((l.snapshot -> 'plan' ->> 'days')::int, jsonb_array_length(l.snapshot -> 'days')), 1) as days,
           l.version_no, l.published_at,
           (now() at time zone app_setting('timezone'))::date as today
    from latest l),
  ranked as (
    select r.*, r.start_date + r.days - 1 as end_date,
           row_number() over (order by
             case when r.start_date <= r.today and r.today <= r.start_date + r.days - 1 then 0
                  when r.start_date > r.today then 1 else 2 end,
             case when r.start_date > r.today then r.start_date end asc,
             r.start_date desc nulls last, r.published_at desc) as rk
    from rows r)
  select meal_plan_id, title, start_date, days, end_date, version_no, published_at, rk = 1
  from ranked order by rk
$$;

create or replace function my_plan_version(p_plan_id uuid, p_version_no int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_id uuid := my_client_id();
  c clients%rowtype;
  v meal_plan_versions%rowtype;
  s jsonb;
  v_num boolean;
  v_items jsonb;
  v_days jsonb;
begin
  if v_id is null or not exists (select 1 from meal_plans where id = p_plan_id and client_id = v_id) then
    return null;
  end if;
  select * into c from clients where id = v_id;
  v_num := c.numbers_allowed and c.client_shows_numbers;
  select * into v from meal_plan_versions
   where meal_plan_id = p_plan_id and (p_version_no is null or version_no = p_version_no)
   order by version_no desc limit 1;
  if not found then return null; end if;
  s := v.snapshot;

  select coalesce(jsonb_agg(
           case when v_num then e.i - 'version_status'
                else (e.i - 'version_status' - 'per_serve' - 'totals')
                     || jsonb_build_object('show_macros_export', false,
                          'lines', coalesce((select jsonb_agg(l.x - 'kcal' - 'protein' - 'carb' - 'fat' - 'fibre' order by l.n)
                                             from jsonb_array_elements(e.i -> 'lines') with ordinality as l(x, n)), '[]'::jsonb))
           end order by e.n), '[]'::jsonb)
    into v_items
    from jsonb_array_elements(coalesce(s -> 'items', '[]'::jsonb)) with ordinality as e(i, n);

  select coalesce(jsonb_agg(case when v_num then d.x else d.x - 'targets' - 'totals' - 'targets_day_type' end order by d.n), '[]'::jsonb)
    into v_days
    from jsonb_array_elements(coalesce(s -> 'days', '[]'::jsonb)) with ordinality as d(x, n);

  return jsonb_build_object(
    'plan_id', p_plan_id,
    'version_no', v.version_no,
    'published_at', v.published_at,
    'show_numbers', v_num,
    'plan', (s -> 'plan') - 'client_id',
    'slots', coalesce(s -> 'slots', '[]'::jsonb),
    'days', v_days,
    'items', v_items,
    'week_average', case when v_num then s -> 'week_average' end,
    'shopping', coalesce(s -> 'shopping', '[]'::jsonb),
    'unresolved', coalesce(s -> 'unresolved', '[]'::jsonb));
end $$;

create or replace function set_my_show_numbers(p_show boolean) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_id uuid := my_client_id(); c clients%rowtype;
begin
  if v_id is null then return jsonb_build_object('ok', false, 'message', 'Your account isn''t linked yet.'); end if;
  perform set_config('goh.client_pref', 'on', true);
  update clients set client_shows_numbers = coalesce(p_show, true) where id = v_id returning * into c;
  perform set_config('goh.client_pref', '', true);
  return jsonb_build_object('ok', true, 'numbers_allowed', c.numbers_allowed,
    'show_numbers', c.numbers_allowed and c.client_shows_numbers,
    'message', case when not c.numbers_allowed then 'Your dietitian hasn''t turned numbers on for you.' end);
end $$;

-- 7. Grants ----------------------------------------------------------------------------------------
revoke execute on function app_setting(text), invite_client_to_app(uuid, text), link_client_account(uuid, uuid),
  unlink_client_account(uuid), client_app_status(uuid), client_app_signups(), my_client_id(), my_details(),
  my_plans(), my_plan_version(uuid, int), set_my_show_numbers(boolean) from public, anon;
grant execute on function app_setting(text), invite_client_to_app(uuid, text), link_client_account(uuid, uuid),
  unlink_client_account(uuid), client_app_status(uuid), client_app_signups(), my_client_id(), my_details(),
  my_plans(), my_plan_version(uuid, int), set_my_show_numbers(boolean) to authenticated;
revoke execute on function clients_app_guard() from public, anon, authenticated;
