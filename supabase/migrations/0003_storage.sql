-- Supabase Storage: bucket for recipe + media-library images.
--
-- Public bucket (images render via public URL on the A4 card / PDF without a
-- session). Writes are restricted to the authenticated dietitian team; reads
-- are public. Idempotent.

insert into storage.buckets (id, name, public)
values ('recipe-images', 'recipe-images', true)
on conflict (id) do update set public = excluded.public;

-- Public read (anon + authenticated) — needed for <img src=publicUrl> on cards.
drop policy if exists "recipe-images public read" on storage.objects;
create policy "recipe-images public read" on storage.objects
  for select to public
  using (bucket_id = 'recipe-images');

-- Authenticated team can upload.
drop policy if exists "recipe-images insert" on storage.objects;
create policy "recipe-images insert" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'recipe-images');

-- Authenticated team can replace.
drop policy if exists "recipe-images update" on storage.objects;
create policy "recipe-images update" on storage.objects
  for update to authenticated
  using (bucket_id = 'recipe-images')
  with check (bucket_id = 'recipe-images');

-- Authenticated team can delete.
drop policy if exists "recipe-images delete" on storage.objects;
create policy "recipe-images delete" on storage.objects
  for delete to authenticated
  using (bucket_id = 'recipe-images');
