-- 0035_food_value_guards.sql — owner go 2026-10-15 ("go density fix").
-- 8 verified foods carried impossible densities (old values, also captured in change_log):
--   Light Cream Cheese -9  (cause of HIGH PROTEIN NO BAKE CHEESECAKE: 0.5 cup = -1125 g, negative kcal)
--   Honey Mustard Dressing -1 · Lime Juice, freshly squeezed -1
--   Apple cider vinegar 0 · Balsamic glaze 0 · Lactose Free Milk 0 · Low Fat Mayo 0 · Red curry paste 0
-- Density 0 already behaved as "no density" (engine: `if (food.density)`), so only the
-- negative ones change any number. Clearing them fires the 0032 rule (density changed on a
-- verified food → unverified), so all 8 land in the Changes inbox for a dietitian re-check.
-- Guards: density blank or > 0; per-100 g kcal/protein/fat/carbs/fibre never negative;
-- unit conversion grams > 0. The food form saves a blank density as null, so normal saves
-- are unaffected; an impossible value is refused with a database error.
-- Idempotent.

update foods set density_g_ml = null where density_g_ml <= 0;

alter table foods drop constraint if exists foods_density_positive;
alter table foods add constraint foods_density_positive check (density_g_ml is null or density_g_ml > 0);
alter table foods drop constraint if exists foods_macros_not_negative;
alter table foods add constraint foods_macros_not_negative check (
  energy_kcal_100g >= 0 and protein_100g >= 0 and fat_100g >= 0 and carb_avail_100g >= 0 and fibre_100g >= 0);
alter table unit_conversions drop constraint if exists unit_conversions_grams_positive;
alter table unit_conversions add constraint unit_conversions_grams_positive check (grams > 0);
