-- 0028_function_hardening.sql — Supabase security-advisor fixes (2026-10-15).
-- 1. Pin search_path on functions created in 0023/0025 (lint 0011).
-- 2. Signed-out (anon) callers may not execute SECURITY DEFINER functions that
--    are not meant to be public (lint 0028). get_invitation stays anon-callable:
--    the /register page needs it before sign-in.
-- Idempotent.

alter function public.recipe_signoffs_guard() set search_path = public;
alter function public.reason_list(text[], int) set search_path = public;
alter function public.foods_default_size_validate() set search_path = public;
alter function public.foods_default_size_sync() set search_path = public;
alter function public.unit_conversions_default_size_sync() set search_path = public;

revoke execute on function public.delete_user(uuid) from public, anon;
revoke execute on function public.handle_new_user() from public, anon, authenticated;
revoke execute on function public.is_admin() from public, anon;
grant execute on function public.delete_user(uuid) to authenticated;
grant execute on function public.is_admin() to authenticated;
