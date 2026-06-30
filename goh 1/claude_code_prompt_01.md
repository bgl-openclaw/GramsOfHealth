# Claude Code — first prompt (Phase 0 and 1: backend foundation and engine)

Paste this into Claude Code with the `seed` folder available in the project.

---

You are building the backend and the calculation engine for an internal recipe tool for Grams of Health, a dietitian-led health business in Sydney, Australia. The team stores, analyses and builds recipe cards. Each recipe's macros are computed from the Australian Food Composition Database (AFCD) and recalculated from grams. This prompt builds **only the database and the engine**. No UI, no auth, no export yet.

## Stack

- Supabase (Postgres) for the database. Use the Supabase CLI with SQL migrations.
- TypeScript throughout. Node for the import scripts, using `@supabase/supabase-js`.
- The engine is a standalone package with no framework or database dependencies, so the front-end (built later in Lovable) can import it.

## Inputs — in the `seed` folder

- `afcd_master_core.csv` — 1,588 AFCD foods, the reference table. Columns include `Public Food Key`, `Food Name`, `Classification`, `Specific Gravity`, `Energy with dietary fibre (kcal)`, `Protein (g)`, `Fat, total (g)`, `Available carbohydrate, without sugar alcohols (g)`, `Total sugars (g)`, `Total dietary fibre (g)`, `Sodium (Na) (mg)`.
- `foods.csv` — the starter ingredient library (61 foods). Columns: `food_id, display_name, afcd_key, source, energy_kcal_100g, protein_100g, fat_100g, carb_avail_100g, fibre_100g, density_g_ml, verified, match_note`.
- `unit_conversions.csv` — columns: `food_id, unit, grams, basis`.
- `au_measures_reference.csv` — the Australian volume standards.
- `recipes_validation.json` — two encoded recipes (four-field ingredient lines: food_id, quantity, unit, plus prep and optional section).
- `recalc_engine.py` — the reference implementation of the engine. Port its logic exactly.
- `validation_report.md` — the expected per-serve numbers to test against.

## Rules that must hold — non-negotiable

- Australian measures: tsp = 5 mL, tbsp = 20 mL, cup = 250 mL.
- Every macro is computed from grams. There is no manual override of a final macro number anywhere. Corrections happen only by editing a food, its unit weight, the quantity or the size, or by adding a custom food.
- "Carbs" means available carbohydrate, excluding fibre. Fibre is always computed and stored separately.
- Liquids convert mL to grams using the food's density. Solids measured by descriptive or count units use the `unit_conversions` weight. The pack unit `x95g` means quantity times 95 grams.

## Tasks

1. **Repo.** A TypeScript project. Suggested layout: `supabase/` (migrations), `packages/engine/` (the engine), `scripts/` (import), `seed/` (the CSVs).

2. **Schema** as SQL migrations. Normalise all column names to snake_case. Tables:
   - `afcd_master` — `public_food_key` (PK, text), `food_name`, `classification`, `specific_gravity` (numeric, null), `energy_kcal`, `protein`, `fat`, `satfat`, `carb_avail`, `sugars`, `fibre`, `sodium_mg`.
   - `foods` — `food_id` (PK, text), `display_name`, `afcd_key` (text, null, references `afcd_master.public_food_key` logically), `source` (enum: `afcd`, `custom`), `energy_kcal_100g`, `protein_100g`, `fat_100g`, `carb_avail_100g`, `fibre_100g`, `density_g_ml` (numeric, null), `verified` (bool, default false), `match_note`.
   - `unit_conversions` — `id` (PK), `food_id` (FK → foods), `unit` (text), `grams` (numeric), `basis` (text). Unique on (`food_id`, `unit`).
   - `recipes` — `id` (PK), `title`, `servings` (int), `time_minutes` (int), `show_macros_export` (bool, default true), `variant_of` (FK → recipes, null), `image_url_1` (text, null), `image_url_2` (text, null).
   - `ingredient_lines` — `id` (PK), `recipe_id` (FK → recipes), `food_id` (FK → foods), `section` (text, null), `position` (int), `quantity` (numeric), `unit` (text), `prep_note` (text, null).
   - `method_steps` — `id` (PK), `recipe_id` (FK → recipes), `position` (int), `text` (text).

3. **Import scripts** in TypeScript. Load each seed file into its table. Make them idempotent so they can be re-run. Map the CSV headers to the snake_case columns.

4. **Engine** in `packages/engine`. Port `recalc_engine.py` exactly as pure functions, taking plain food and conversion data (no DB calls inside):
   - `toGrams(food, qty, unit)` — g and kg direct; `x95g` is qty × 95; volume units use density when present else the unit-conversion grams; descriptive and count units use the unit-conversion grams.
   - `compute(lines, servings)` → `{ totals, perServe, rows }`, where each macro contribution is `grams / 100 × per-100g value`, and `perServe = totals / servings`.
   - `atwater(perServe)` = `4×protein + 4×carb + 9×fat + 2×fibre` kcal, for an internal consistency check.

5. **Tests.** Load the two validation recipes and assert per-serve energy of about 369 and about 226 kcal (tolerance ±2), and that Atwater is within one percent of computed energy. Mirror `validation_report.md`.

6. **A `verify` command** (`npm run verify`) that prints, per recipe, the per-serve macros and the Atwater figure.

## Definition of done

- Migrations apply cleanly to a fresh Supabase project.
- All seed data imports.
- `npm test` passes, reproducing the seed numbers.
- `npm run verify` prints both recipes' per-serve macros matching the validation report.

## Out of scope — do not build yet

- No UI or front-end. That is built in Lovable from Claude Design against this schema and engine.
- No authentication. That is phase 5.
- No PDF or PNG export. That is phase 3.
- No parsing of the 750 recipes. Cowork produces that file; phase 4 imports it.
