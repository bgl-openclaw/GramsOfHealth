-- 0039b_invite_token_key.sql — the app's invite page already sends the token as
-- raw_user_meta_data.invitation_token (0039 read only invite_token, so client
-- invite links would have produced UNLINKED accounts). Accept both keys.
-- Only the token line changes from 0039. Idempotent.
create or replace function handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  inv public.invitations%rowtype;   -- rowtype (not record) so it's readable even when no invite matched
  v_token uuid;
  v_role text;
begin
  begin
    v_token := nullif(coalesce(new.raw_user_meta_data ->> 'invitation_token',
                               new.raw_user_meta_data ->> 'invite_token'), '')::uuid;
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
