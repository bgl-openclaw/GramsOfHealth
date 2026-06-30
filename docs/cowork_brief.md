# Cowork brief: build the Grams of Health foods library

## Goal

Scale the seed in this folder to cover all 750 recipe PDFs. The output is two complete, dietitian-ready files in the **exact same format** as the seed: `foods.csv` (every unique ingredient) and `unit_conversions.csv` (every size-to-grams weight needed). These become the data the web app and the recalculation engine run on.

## Inputs you will be given

- The folder of 750 recipe PDFs (the user is gathering these locally).
- This seed folder: `foods.csv`, `unit_conversions.csv`, `au_measures_reference.csv`, `recalc_engine.py`, `recipes_validation.json`, `validation_report.md`.
- AFCD Release 3 nutrient data, downloadable free as Excel from Food Standards Australia New Zealand (Food Details and Nutrient profiles files). The seed used these two.

## What to produce

1. **`recipes.json`** — every recipe parsed into the four-field line format: `quantity`, `unit` (the "size"), `food_id`, `prep`, plus `section` where the card groups lines (To serve, Marinade, and so on), plus `title`, `servings`, `time_minutes`. Method steps captured as ordered text. Use the structure in `recipes_validation.json`.
2. **`foods.csv`** — one row per unique ingredient across all 750. Match to AFCD Release 3 where a clean match exists (`source = afcd`, record the `afcd_key`). Where AFCD has no good match (branded or composite items), create a `custom` row and flag it. Keep every column the seed uses. Set `verified = FALSE` on every row; the dietitian flips these.
3. **`unit_conversions.csv`** — for every (food, size) combination that appears, a grams weight. Reuse the seed's defaults; add new household and item weights as new sizes appear. Liquids with a density in `foods.csv` do not need rows; the engine derives grams from density.

## Rules that must hold

- Australian measures only: tsp = 5 mL, tbsp = 20 mL, cup = 250 mL. Never US 15 mL tablespoons.
- Available carbohydrate excludes fibre. Fibre is a separate field, always populated.
- Garnish flourishes that appear only in the method ("add a lemon wedge") are not ingredient rows.
- Do not invent nutrition values. If AFCD has no match and there is no product label, leave the custom row's macros blank and flag it for the dietitian rather than guessing.
- After building, run `recalc_engine.py` over a sample of recipes and report, for each, the computed per-serve macros and the Atwater consistency figure. Flag any recipe whose ingredients fail to resolve to grams, and any (like the salmon fish cakes) where an ingredient named in the method is missing from the list.

## Definition of done

`recalc_engine.py` runs over every recipe with no unresolved units, `foods.csv` has a row for every unique ingredient with AFCD matches recorded and custom items flagged, and a short coverage report lists how many foods matched AFCD versus need dietitian entry, plus every recipe with a data issue to fix.
