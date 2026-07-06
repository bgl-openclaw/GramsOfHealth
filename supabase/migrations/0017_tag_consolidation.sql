-- Tag consolidation, Stage 1 (insert-only; nothing deleted).
--
-- One tag system: food_diet_flags' 357 curated "contains" facts migrate into
-- food_tags so recipe_effective_tags (union for contains-type, all-must-qualify
-- for dietary, per-recipe overrides) becomes the single source of truth.
--
-- - Creates the three contains-type tags the legacy vocabulary had and the tag
--   registry lacked: Meat, Honey, High-FODMAP. (kind 'allergen' = the
--   contains/union combine rule, not a clinical claim; the UI groups these
--   under "Contains".)
-- - Copies every flag to its tag via an explicit label map. Both drifted
--   spellings ('tree nut', 'high-FODMAP') collapse into the canonical tags,
--   curing the vocabulary-drift bug structurally (food_tags FKs the registry;
--   free-text flags cannot drift again).
-- - Auto/manual origin is intentionally dropped: tags become plain,
--   dietitian-editable facts. Tag correctness is reviewed as part of the
--   existing foods.verified sign-off.
-- - food_diet_flags is left fully intact; retiring it is a later, separately
--   approved step. Idempotent throughout.

insert into tags (label, category, kind) values
  ('Meat',        'allergen', 'allergen'),
  ('Honey',       'allergen', 'allergen'),
  ('High-FODMAP', 'allergen', 'allergen')
on conflict (category, label) do update set kind = excluded.kind;

with mapping (flag, label) as (
  values
    ('meat',        'Meat'),
    ('fish',        'Fish'),
    ('shellfish',   'Shellfish'),
    ('dairy',       'Dairy'),
    ('egg',         'Egg'),
    ('gluten',      'Gluten'),
    ('tree_nut',    'Tree nuts'),
    ('tree nut',    'Tree nuts'),      -- drifted spelling → canonical
    ('peanut',      'Peanuts'),
    ('soy',         'Soy'),
    ('sesame',      'Sesame'),
    ('honey',       'Honey'),
    ('high_fodmap', 'High-FODMAP'),
    ('high-FODMAP', 'High-FODMAP')     -- drifted spelling → canonical
)
insert into food_tags (food_id, tag_id)
select f.food_id, t.id
  from food_diet_flags f
  join mapping m on m.flag = f.flag
  join tags t on t.label = m.label and t.kind = 'allergen'
on conflict (food_id, tag_id) do nothing;
