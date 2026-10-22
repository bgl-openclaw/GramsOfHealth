-- 0048_staff_compliance_clinician_view.sql — dietitians see the whole team's compliance (owner, 22 Oct 2026).
-- APPLIED live 22 Oct 2026 (apply_migration "0048_staff_compliance_clinician_view"); staff_profiles_0045 and p0_lockdown pass live.
-- Owner: "admin and dietitians see everything; admin can upload documents for them".
--   Read: admins and dietitians see every staff member's credentials in full (numbers, dates, certificates).
--         Interns still see only their own.
--   Write: unchanged. A person edits their own; admins edit, upload for and tick "Checked" for anyone.
--          (The database already let admins upload into anyone's folder; this only widens reading.)
--   team_compliance(): everyone for clinicians, with full details; returns supervisor_id and is_my_intern so
--   the app can still show "My interns".
-- Test: tests/sql/staff_profiles_0045.test.sql (updated for this change)

drop policy if exists staff_credentials_read on staff_credentials;
create policy staff_credentials_read on staff_credentials for select
  using ((profile_id = auth.uid() and is_staff()) or is_clinician());

drop policy if exists "staff-documents own or admin read" on storage.objects;
drop policy if exists "staff-documents own or clinician read" on storage.objects;
create policy "staff-documents own or clinician read" on storage.objects for select to authenticated
  using (bucket_id = 'staff-documents' and (((storage.foldername(name))[1] = auth.uid()::text and public.is_staff()) or public.is_clinician()));

create or replace function team_compliance() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_me uuid := auth.uid(); v_clin boolean := is_clinician();
  v_today date := (now() at time zone coalesce(app_setting('timezone'), 'Australia/Sydney'))::date;
  v_people jsonb;
begin
  if not is_staff() then return jsonb_build_object('ok', false, 'message', 'Staff only.'); end if;
  with people as (
    select p.* from profiles p
    where p.role in ('admin', 'dietitian', 'intern') and (v_clin or p.id = v_me)),
  items as (
    select p.id as pid, t.key, t.label, t.position, p.role = any (t.required_for) as required, c.id as cid,
           coalesce(c.expires_on, (c.issued_on + make_interval(months => t.renew_months))::date) as due,
           c.expires_on is null and c.issued_on is not null and t.renew_months is not null as due_estimated,
           c.number, c.issuer, c.state, c.issued_on, c.expires_on, c.file_path, c.checked_at,
           (select coalesce(nullif(btrim(full_name), ''), email) from profiles where id = c.checked_by) as checked_by_name
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
                'id', s.cid, 'number', s.number, 'issuer', s.issuer, 'state', s.state,
                'issued_on', s.issued_on, 'expires_on', s.expires_on,
                'has_file', s.file_path is not null, 'file_path', s.file_path,
                'checked_at', s.checked_at, 'checked_by_name', s.checked_by_name)
              order by s.position), '[]'::jsonb) from scored s where s.pid = p.id) as items,
           (select count(*) from scored s where s.pid = p.id and s.status in ('expired', 'due_30', 'missing')) as urgent,
           (select count(*) from scored s where s.pid = p.id and s.status = 'due_60') as soon
    from people p)
  select coalesce(jsonb_agg(jsonb_build_object(
           'profile_id', pp.id, 'name', pp.name, 'role', pp.role, 'is_me', pp.id = v_me,
           'supervisor_id', pp.supervisor_id, 'is_my_intern', pp.role = 'intern' and pp.supervisor_id is not distinct from v_me,
           'placement_start', pp.placement_start, 'placement_end', pp.placement_end, 'placement', pp.placement,
           'needs_attention', pp.urgent > 0 or pp.placement is not null, 'urgent_count', pp.urgent, 'due_60_count', pp.soon,
           'items', pp.items) order by (pp.id <> v_me), pp.name), '[]'::jsonb)
    into v_people from per_person pp;
  return jsonb_build_object(
    'ok', true,
    'people', v_people,
    'needs_attention', (select count(*) from jsonb_array_elements(v_people) x where (x ->> 'needs_attention')::boolean and not (x ->> 'is_me')::boolean),
    'mine_needs_attention', coalesce((select (x ->> 'needs_attention')::boolean from jsonb_array_elements(v_people) x where (x ->> 'is_me')::boolean), false));
end $$;

revoke execute on function team_compliance() from public, anon;
grant execute on function team_compliance() to authenticated;
