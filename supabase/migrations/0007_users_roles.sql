-- Users, roles, and invite-only registration.
--
-- profiles: one row per auth user with profile fields + a role
--   ('admin' | 'dietitian' | 'pending'). 'pending' = signed up but not granted
--   access (uninvited); promote to dietitian/admin to activate.
-- invitations: an admin creates one per email; its token drives the
--   registration link. On signup the trigger reads the matching invitation and
--   sets the new user's role from it (else 'pending').
--
-- Random self-signup is prevented in the UI (login-only when logged out;
-- registration only via /register?token=...). Uninvited accounts land as
-- 'pending' with no role, so tightening data-table RLS to role IN
-- ('admin','dietitian') later (Phase 5) fully locks them out.

create table if not exists profiles (
  id           uuid primary key references auth.users (id) on delete cascade,
  email        text,
  full_name    text,
  phone        text,
  job_title    text,
  organisation text,
  role         text not null default 'pending' check (role in ('admin','dietitian','pending')),
  created_at   timestamptz not null default now()
);

create table if not exists invitations (
  id          uuid primary key default gen_random_uuid(),
  email       text not null,
  role        text not null default 'dietitian' check (role in ('admin','dietitian')),
  token       uuid not null default gen_random_uuid() unique,
  invited_by  uuid references auth.users (id),
  created_at  timestamptz not null default now(),
  expires_at  timestamptz default (now() + interval '14 days'),
  accepted_at timestamptz
);

-- Is the current user an admin? SECURITY DEFINER so policies can call it
-- without recursing through profiles' own RLS.
create or replace function public.is_admin()
returns boolean language sql security definer stable set search_path = public as $$
  select exists (select 1 from public.profiles where id = auth.uid() and role = 'admin');
$$;

-- Validate a registration token without exposing the invitations table to anon.
create or replace function public.get_invitation(p_token uuid)
returns table (email text, role text, valid boolean)
language sql security definer stable set search_path = public as $$
  select i.email, i.role,
         (i.accepted_at is null and (i.expires_at is null or i.expires_at > now())) as valid
  from public.invitations i
  where i.token = p_token;
$$;
grant execute on function public.get_invitation(uuid) to anon, authenticated;

-- On new auth user: create their profile, taking role + fields from a matching
-- unaccepted invitation (by email) when present, and mark that invite accepted.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
declare inv record;
begin
  select * into inv from public.invitations
   where lower(email) = lower(new.email)
     and accepted_at is null
     and (expires_at is null or expires_at > now())
   order by created_at desc limit 1;

  insert into public.profiles (id, email, full_name, phone, job_title, organisation, role)
  values (
    new.id,
    new.email,
    new.raw_user_meta_data ->> 'full_name',
    new.raw_user_meta_data ->> 'phone',
    new.raw_user_meta_data ->> 'job_title',
    new.raw_user_meta_data ->> 'organisation',
    coalesce(inv.role, 'pending')
  )
  on conflict (id) do nothing;

  if inv.id is not null then
    update public.invitations set accepted_at = now() where id = inv.id;
  end if;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- RLS
alter table profiles    enable row level security;
alter table invitations enable row level security;

-- Everyone signed in can view the Users tab.
drop policy if exists "profiles read" on profiles;
create policy "profiles read" on profiles
  for select to authenticated using (true);

-- Only admins manage profiles (role changes etc.). The trigger inserts as
-- SECURITY DEFINER and bypasses RLS, so normal signup still works.
drop policy if exists "profiles admin write" on profiles;
create policy "profiles admin write" on profiles
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- Only admins see/manage invitations (invitees validate via get_invitation RPC).
drop policy if exists "invitations admin" on invitations;
create policy "invitations admin" on invitations
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- Backfill profiles for any pre-existing auth users (land as 'pending').
insert into public.profiles (id, email, role)
select u.id, u.email, 'pending' from auth.users u
on conflict (id) do nothing;
