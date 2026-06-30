-- Track whether a recipe-tag was auto-suggested (heuristic, needs dietitian
-- review) or manually confirmed. The UI shows 'auto' tags as "suggested" and a
-- confirm action flips them to 'manual'.

alter table recipe_tags
  add column if not exists source text not null default 'manual'
  check (source in ('manual', 'auto'));
