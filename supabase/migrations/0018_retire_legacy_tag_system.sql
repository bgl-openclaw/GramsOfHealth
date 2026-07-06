-- Tag consolidation, final stage (approved): retire the legacy system.
-- Pre-conditions verified before running: the app has zero references to
-- food_diet_flags or the recipe_tags diet rows (planner, chips, and filters
-- all read recipe_effective_tags); every legacy flag's (food, tag) pair exists
-- in food_tags; a full snapshot lives at seed/archive/food_diet_flags_snapshot.csv.

-- Gate 1: the auto-seeded diet classification rows (superseded by derived tags).
-- Manual diet rows are preserved (there are none at time of writing);
-- course/meal/cuisine rows are untouched.
delete from recipe_tags rt
 using tags t
 where t.id = rt.tag_id
   and t.category = 'diet'
   and rt.source = 'auto';

-- Gate 2: the legacy flag table itself.
drop table if exists food_diet_flags;
