-- 0031_line_priceability_from_grams.sql
-- Bug fix: line_priceability (0022) treated density_g_ml = 0 as a usable density,
-- so tsp/tbsp/cup/ml lines of those foods counted as "priced" — but the engine
-- (`if (food.density)`) treats 0 as no density and cannot resolve them.
-- 14 lines affected on 2026-10-15 (red curry paste, apple cider vinegar,
-- lactose-free milk); no AI Verified recipe was affected.
-- line_priceability now derives from line_grams (0030), the single SQL replica
-- of packages/engine toGrams. Same columns, so dependent views
-- (recipe_readiness, recipe_verification, conversion_gaps, food_leverage) are unchanged.

create or replace view line_priceability with (security_invoker = on) as
select lg.id, lg.recipe_id, lg.food_id, lg.unit, lg.grams is not null as priced
from line_grams lg;
