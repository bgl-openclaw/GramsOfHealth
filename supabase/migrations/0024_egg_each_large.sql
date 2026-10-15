-- 0024_egg_each_large.sql
-- Owner decision (2026-10-15): an egg written as "each" means a LARGE egg.
-- Adds an "each" conversion copied from the food's existing "large" row, for whole
-- egg (large = 51 g) and egg yolk (large = 16 g). Fixes every current "each" egg
-- line (62 at the time) and any future one; recipe lines themselves are untouched.
-- Explicit sizes ("small", "extra large", …) keep their own conversions.
-- If a dietitian later changes the "large" weight, update "each" to match.
-- Idempotent: never overwrites an existing "each" row.

insert into unit_conversions (food_id, unit, grams)
select uc.food_id, 'each', uc.grams
from unit_conversions uc
where uc.food_id in ('egg', 'egg_yolk') and uc.unit = 'large'
on conflict (food_id, unit) do nothing;
