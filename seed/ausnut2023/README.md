# AUSNUT 2023 import package for Grams of Health

Built 21 October 2026 from the official FSANZ AUSNUT 2023 release (`AUSNUT_2023_all_files_FSANZ.zip`, files dated 25 March 2026) and the live `foods` table (517 rows, 311 verified) read the same day. Everything here is a seed file for Claude Code to load through gated migrations and scripts. Nothing in this folder writes to the database by itself.

Rebuild: `python3 -I build_import_package.py "<AUSNUT 2023 - All Files dir>" <work dir with our_foods.json> <this folder>`.

## reference/  (load as read-only reference tables)

| File | Rows | What it is |
| --- | --- | --- |
| `ausnut_master.csv` | 3,741 | One row per AUSNUT food: key, survey id, name, derivation, classification code and name, specific gravity, edible portion, discretionary flag, the 17 nutrient columns we use, and the long description. `energy_kcal` = kJ (with fibre) / 4.184. Both carbohydrate columns and both folate columns are included. `carb_avail_100g` loads from "without sugar alcohols" and `folate_100g` from total folate: on every shared key where the AUSNUT columns differ, AFCD Release 3 (and therefore the library) matches those two. |
| `ausnut_measures.csv` | 9,816 | One row per household measure: descriptors, gram amount, volume, plus derived flags `is_density`, `is_brand_pack`, `size_word`, `suggested_unit`. Brand pack rows (descriptor 4 has a brand) are flagged so they can be skipped. |
| `ausnut_classifications.csv` | 662 | AUSNUT 2023 classification codes at 2, 3 and 5 digits. |

## rules/  (deterministic mapping tables, for dietitian sign-off before anything loads)

`rule_aisle.csv` (3-digit group to one of our seven aisles, plus 5-digit overrides and the "frozen" name rule), `rule_tags.csv` (allergen tags by group and name, the derived dietary tags, and what is only flagged for review), `rule_protein_family.csv`, `rule_purchase_unit.csv`. These rules exist only for importing new foods from AUSNUT. They never run over existing foods afterwards.

## lists/  (the agreed scope)

| File | Rows | Action |
| --- | --- | --- |
| `list_A_create.csv` | 4 | Ingredients lost in the recipe ingest: gelatine (create), coconut flakes (reuse existing), olive oil spray (create), pickled veg (sub-recipe, no food). |
| `list_B1_repoint.csv` | 41 | Unverified foods sitting on a stand-in or an estimate: re-point `ausnut_key`, load numbers from AUSNUT, mark AI verified. `food_id` is kept so recipes are untouched. |
| `list_B2_relink_verified.csv` | 23 | Verified foods whose stored key points at the wrong food. Numbers are correct and are not touched; only the reference key, source and match note change. |
| `list_B3_merge_delete.csv` | 19 | Parse-artefact duplicates, all unverified: re-point any ingredient line to the canonical food, snapshot, delete. |
| `list_B3b_verified_duplicates_dietitian.csv` | 3 | Three verified foods that look like duplicates (egg mayo, a second lemon juice, a second orange juice). No machine action; a dietitian decides. |
| `list_C_import.csv` | 248 | New pantry foods agreed on 21 October, less radish and Brussels sprouts, which already exist as verified foods on the same keys. |
| `verify_linked_foods.csv` | 256 | Every existing food that already carries an AUSNUT-compatible key, with AUSNUT values side by side and a status: 169 match on the core macros, 87 "Check". |
| `suggested_matches_unlinked.csv` | 710 | Top three AUSNUT candidates for each of the 245 foods with no key, with a 0 to 1 score and High / Medium / Low confidence (114 High). |
| `size_gap_fills.csv` | 238 | AUSNUT measures that would fill the 86 open conversion gaps. |

## import/  (ready-to-load rows for A creates, B1 re-points and all of C: 291 foods)

| File | Rows | Columns |
| --- | --- | --- |
| `import_foods.csv` | 291 | `action` (create or repoint), `food_id`, `display_name`, `source` = ausnut, `ausnut_key`, nutrients per 100 g (kcal, protein, fat, carb_avail without sugar alcohols, fibre, sugars, satfat, sodium, potassium, calcium, iron, zinc, magnesium, total folate, B12; the with-sugar-alcohols carb and DFE folate are carried as reference columns), `density_g_ml` with `density_note`, `default_size`, `aisle`, `protein_family`, `purchase_unit` (set only where the food has a measure of that name, 13 rows) and `purchase_unit_suggested` (the rule's answer, for the dietitian), the allergen and dietary tags as text, `review_flags`, `ai_evidence`, `verified` = 0, `ai_verified` = 1. For `repoint` rows the live aisle, density and default size are kept and a flag is raised where the rule disagrees. |
| `import_food_tags.csv` | 1,362 | One row per (food_id, tag label, kind). Labels match the live `tags` table exactly. Load only for `create` rows; for `repoint` rows (existing foods) these are suggestions a dietitian may compare against the tags already set, never written by machine. |
| `import_unit_conversions.csv` | 308 | One row per (food_id, unit, grams) with the AUSNUT measure id in `basis`, `estimated` = 0 throughout (the olive oil spray measure is an AUSNUT row, 5 g per spray). Spoons and cups are not written where a density is set, because the engine derives them. |
| `import_review_flags.csv` | 51 | Rows a dietitian should look at before or after load: oats, oat bran and oat milk (tagged Gluten to match the existing oats; gluten status to confirm), commercial seasonings, sauces and meat alternatives, chocolate, protein powders, processed meats, the olive oil spray measure (AUSNUT says 5 g per spray), and foods where brand pack sizes were skipped. |

### How the measure rules work

- Density (`density_g_ml`) is set only for liquids and for dry goods measured by the cup (flours, grains, pasta, cereals, dried fruit, seeds, nuts, sugar, spices, legumes). Meat, fish, fruit and vegetables get no density, so a "cup of chicken" cannot be entered.
- Where AUSNUT gives a grated, shredded, sliced or chopped density, a `cup (grated)` style conversion is written instead (250 mL x density). Block or wedge densities are ignored.
- Small, medium and large pieces become units of the same name; `default_size` is medium where it exists. A single piece row (egg, spear, chop) becomes `regular` and the default size for fruit, vegetables, eggs, meat and fish only.
- Pack and serve measures (bottle, carton, tub, single serve, snack size, millilitres) are skipped. Plain `can` and `pouch` rows are kept for the shopping list.
- Any measure under 0.5 g is skipped.

### What is deliberately not here

- No numbers for branded products (protein powders, wraps, sugar-free syrups): label entry.
- No High-FODMAP tags: dietitians only.
- `size_gap_fills.csv`: a blank `Fit` means the AUSNUT measure name did not match the missing unit name exactly and a person must confirm it is the same measure; a filled `Fit` means the names matched.
- No `role` values: frozen until a dietitian sets them.
- No changes to the 311 verified foods beyond the reference key fix in B2. The three verified look-alikes in `list_B3b` wait for a dietitian.
- Measures are loaded where AUSNUT publishes a household measure. 35 of the 291 foods (31 new foods and 4 re-points: lean raw meat cuts, some seafood, a few leafy vegetables and canned tomatoes) have gram weights only, because AUSNUT gives them no household measure; they still compute in recipes by grams.
