-- Admin-only user deletion. The actual account lives in auth.users (the client
-- can't delete it directly), so deletion goes through this SECURITY DEFINER RPC
-- which enforces the rules in the database:
--   * caller must be an admin
--   * admins cannot be deleted (any admin, including yourself)
-- Deleting the auth user cascades to public.profiles (FK on delete cascade).

create or replace function public.delete_user(target_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare target_role text;
begin
  if not public.is_admin() then
    raise exception 'Only admins can delete users';
  end if;

  select role into target_role from public.profiles where id = target_id;
  if target_role is null then
    raise exception 'User not found';
  end if;
  if target_role = 'admin' then
    raise exception 'Admin accounts cannot be deleted';
  end if;

  delete from auth.users where id = target_id;
end $$;

grant execute on function public.delete_user(uuid) to authenticated;

-- Defensive: if a user who once sent an invitation is deleted, null the
-- reference rather than block the delete (only admins send invites, and admins
-- can't be deleted — but keep this safe regardless).
alter table invitations drop constraint if exists invitations_invited_by_fkey;
alter table invitations
  add constraint invitations_invited_by_fkey
  foreign key (invited_by) references auth.users (id) on delete set null;
