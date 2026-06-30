# Seed validation report

Built from your eleven sample pages, the AFCD Release 3 nutrient data, and the recalculation engine. Purpose: prove the format and the maths before any app is built.

## What the seed contains

| File | What it is |
| --- | --- |
| `foods.csv` | The ingredient library. 61 foods drawn from the eleven pages: 19 matched to AFCD Release 3, 42 marked custom or branded for a dietitian to verify. Holds per-100g energy, protein, fat, available carbohydrate, fibre, and density. |
| `unit_conversions.csv` | Size-to-grams weights per food (1 clove garlic = 3g, 1 slice bread = 30g, "4 x 95g" = 95g each, and so on). |
| `au_measures_reference.csv` | The Australian volume standards the engine uses: tsp = 5 mL, tbsp = 20 mL, cup = 250 mL. |
| `recalc_engine.py` | The reusable engine. Resolves every line to grams, sums contributions, divides by servings. |
| `recipes_validation.json` | Two recipes encoded in the four-field format (quantity, size, food, prep). |

## Finding 1 — the engine is internally correct

For every recipe, the energy computed from grams matches the 4/4/9/2 Atwater sum of that recipe's own macros within about one percent.

| Recipe | Computed energy | Atwater from macros |
| --- | --- | --- |
| Lentil Tuna Salad | 369 kcal/serve | 365 |
| Salmon Fish Cakes (listed) | 226 kcal/serve | 223 |

The grams-to-macros maths is sound.

## Finding 2 — the printed cards cannot be rebuilt from their ingredients

| Recipe | Computed per serve | Printed per serve |
| --- | --- | --- |
| Lentil Tuna Salad | 369 kcal, C 20, P 34, F 15 | 405 kcal, C 38, P 29, F 13 |
| Salmon Fish Cakes (listed only) | 226 kcal, C 9, P 11, F 15 | 332 kcal, C 11, P 29, F 18 |

The salad is within roughly ten percent on energy but diverges on carbohydrate. The salmon card is far lower because **the salmon is missing from its printed ingredient list** while appearing in the method, so its main protein source is absent: computed protein is 11g against a printed 29g. Adding salmon back overshoots, which means the printed figure itself was produced from a different quantity or database.

The conclusion is not that the engine is wrong; the Atwater check shows it is right. It is that the legacy numbers were generated elsewhere and are not internally consistent. This is the evidence for the workflow you chose: compute fresh AFCD numbers, then have a dietitian reconcile. The seed replaces inconsistent legacy figures with one defensible baseline.

## Notes for the dietitian pass

- Every value with `verified = FALSE` in `foods.csv` needs a dietitian to confirm or correct. The 42 custom rows (tzatziki, sugar-free maple syrup, light coconut milk, the rice pouches, the wraps, light mozzarella) need nutrition entered from the product label.
- Available carbohydrate excludes fibre, per the Australian and AFCD convention you confirmed. Fibre is always carried separately.
- `unit_conversions.csv` weights are sensible defaults, not gospel. A dietitian should confirm item weights such as "1 medium sweet potato = 150g".
