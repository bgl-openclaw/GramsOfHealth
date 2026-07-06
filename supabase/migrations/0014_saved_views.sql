-- Saved filter views per user (synced across devices), one per list screen.
create table if not exists saved_views (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references auth.users (id) on delete cascade,
  screen     text not null,            -- 'recipes' | 'foods' | …
  name       text not null,
  state      jsonb not null,           -- the URL-synced filter state snapshot
  created_at timestamptz not null default now()
);
create index if not exists saved_views_user_screen_idx on saved_views (user_id, screen);
alter table saved_views enable row level security;
drop policy if exists "own saved views" on saved_views;
create policy "own saved views" on saved_views
  for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
