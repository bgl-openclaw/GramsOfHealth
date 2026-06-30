# Cowork brief: build the Grams of Health foods library

## Goal

Scale the seed in this folder to cover the full set of recipe files (PDF or PNG), a few hundred recipes. The output is three complete, dietitian-ready files in the **exact same format** as the seed: `recipes.json` (every recipe), `foods.csv` (every unique ingredient) and `unit_conversions.csv` (every size-to-grams weight needed). These become the data the web app and the recalculation engine run on.

## Inputs you will be given

- The folder of recipe files (PDF or PNG).
- This seed folder, which now includes the AFCD reference itself:
  - `afcd_master_core.csv` — the 1,588 AFCD foods to match against. **Match against this file directly. Do not re-download AFCD.** Each row has a `Public Food Key`, the food name, and per-100g energy, protein, fat, available carbohydrate, fibre, sodium and a specific-gravity density.
  - `foods.csv`, `unit_conversions.csv`, `au_measures_reference.csv` — the seed library and the format to extend.
  - `recalc_engine.py`, `recipes_validation.json`, `validation_report.md` — the engine and two worked examples to copy.

## What to produce

1. **`recipes.json`** — every recipe parsed into the four-field line format: `quantity`, `unit` (the "size"), `food_id`, `prep`, plus `section` where the card groups lines (To serve, Marinade, and so on), plus `title`, `servings`, `time_minutes`. Method steps captured as ordered text. Use the structure in `recipes_validation.json`.
2. **`foods.csv`** — one row per unique ingredient across the full set. Match to a `Public Food Key` in `afcd_master_core.csv` where a clean match exists (`source = afcd`, record the `afcd_key`). Where there is no good match (branded or composite items like tzatziki, the rice pouches, the wraps), create a `custom` row and flag it. Keep every column the seed uses. Set `verified = FALSE` on every row; the dietitian flips these.
3. **`unit_conversions.csv`** — for every (food, size) combination that appears, a grams weight. Reuse the seed's defaults; add new household and item weights as new sizes appear. Liquids with a density in `foods.csv` do not need rows; the engine derives grams from density.

## Rules that must hold

- Australian measures only: tsp = 5 mL, tbsp = 20 mL, cup = 250 mL. Never US 15 mL tablespoons.
- Available carbohydrate excludes fibre. Fibre is a separate field, always populated.
- Garnish flourishes that appear only in the method ("add a lemon wedge") are not ingredient rows.
- Do not invent nutrition values. If AFCD has no match and there is no product label, leave the custom row's macros blank and flag it for the dietitian rather than guessing.
- After building, run `recalc_engine.py` over a sample of recipes and report, for each, the computed per-serve macros and the Atwater consistency figure. Flag any recipe whose ingredients fail to resolve to grams, and any (like the salmon fish cakes) where an ingredient named in the method is missing from the list.

## Definition of done

`recalc_engine.py` runs over every recipe with no unresolved units, `foods.csv` has a row for every unique ingredient with AFCD matches recorded and custom items flagged, and a short coverage report lists how many foods matched AFCD versus need dietitian entry, plus every recipe with a data issue to fix.
