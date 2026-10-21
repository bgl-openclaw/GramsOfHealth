# AUSNUT 2023 package + brief: review against the live database (21 Oct 2026)

Reviewed: `claude_code_brief_ausnut_verification.md`, `ausnut2023/README.md`, every CSV in `ausnut2023/`, against the live tables, triggers and views (read-only). Nothing was written. Scripts: scratchpad `ausnut/check_package.py`, `check2.py`, `check3.py`.

Verdict: the package is well built (no id collisions, no duplicate rows, every tag label and unit name passes the database rules, B2/B3 lists line up) but **it can't be loaded as-is**: one blocker would make the database refuse 278 of the 291 import rows, two settled decisions would put inconsistent numbers in the library, and a few rules would mark wrong foods "AI verified" or break existing recipe lines. Fixes below, most are small.

## A. Blockers (the load fails or breaks recipes)

1. **"Buy as" is refused for 278 of 291 rows.** `foods_purchase_unit_validate` (migration 0036) only accepts a Buy-as unit that is a measure on the food. The package sets `purchase_unit` = each / packet / can / bunch / punnet but writes no matching measure (e.g. milk "each", cheese "packet"). Fix: leave `purchase_unit` blank unless the food has that measure (a pack weight, e.g. `carton (1 L)` = 1030 g), and set it after the conversions are loaded (same ordering as `default_size`).
2. **Density removed on existing foods.** For re-points the package writes `density_g_ml` = blank where the live food has one: `tomato_paste` (1.1 → none, 27 recipe lines use tbsp/cup through density) and `tomato_passata` (1.05 → none, 10 lines; this one is "ESTIMATE"-exempt from the gate so it *would* be written). Those 37 lines would become "can't be calculated". Rule to add: never null an existing density; treat a density change > 10 % like a macro change (queue it). Note the engine/`line_grams` rule: **density always wins over an explicit tsp/tbsp/cup measure**, so any new or changed density changes every spoon/cup line of that food (24 re-points change density; e.g. soy sauce 1.15 → 1.05 shifts 66 lines by ~9 %).
3. **Setting a default size rewrites "each".** `foods_default_size_sync` copies the default size's grams into the food's `each` measure. `swiss_brown_mushroom` would go from each = 100 g to 35 g (medium). Rule: on existing foods, don't set `default_size` where it would change an existing `each`; queue it.
4. **`source` enum value can't be used in the migration that adds it.** `ALTER TYPE food_source ADD VALUE 'ausnut'` must be its own migration (Postgres won't use a new enum value in the same transaction). Also the Lovable app types `source` as `'afcd' | 'custom'`: don't write `source = 'ausnut'` on any food until the app handles it (G5 type change first), or badges and filters will misbehave.

## B. Two "settled decisions" are wrong against the data

5. **Carbohydrate column: use "without sugar alcohols", not "with".** AUSNUT and AFCD share 1,201 keys. On the 29 where the two AUSNUT carb columns actually differ (apples, apricots, cherries, prunes …), AFCD `carb_avail` matches **without SA 29/29, with SA 0/29**. The "agrees on all 191" claim only holds because, for those foods, the two columns are equal. Import rows affected include prunes (45 vs 32.3 g), dried apricots (48.4 vs 43), celeriac (5 vs 2.8), nashi, plum, canned peaches, dried apple.
6. **Folate: the library stores TOTAL folate, not DFE.** On the 75 shared keys where DFE ≠ total (fortified breads/cereals), `afcd_master.folate_ug` equals AUSNUT **total** on 71 and DFE on 0. Loading DFE would mix two units in `folate_100g` (12 import rows differ: breads, rolls, crumpets, flour, croutons). Load `folate_total_ug`, or move the whole column to DFE as a separate, labelled change.

## C. Clinical safety

7. **Oats.** The brief says oats get no Gluten tag, but the dietitians have tagged the live `rolled_oats` and `quick_oats` (both verified) **Gluten**. The package leaves `oat_bran`, `oat_milk` and `oats_gluten_free` untagged. A gluten-free/coeliac client screen blocks the Gluten tag, so untagged oats would pass. Tag them Gluten (matching the dietitians) until a dietitian decides; note Australian rules don't allow oats to be sold as gluten free, so "oats_gluten_free" needs a dietitian look.
8. **Keep client screening on dietitian verification.** `client_recipe_screen` marks a recipe "unconfirmed" for clients with requirements when it has foods that aren't `verified`. The brief changes readiness to `verified OR ai_verified` but says nothing about the screen. Make it explicit that the screen stays on `verified` (human): machine-derived tags (no High-FODMAP, rule-based allergens) must not be trusted for allergy screening.
9. **"Exact key" matches would AI-verify wrong foods.** Several unverified foods carry an AFCD key for a different food, and their numbers were copied from it, so the plausibility gate passes them: `oyster_mushroom` → "Oyster, raw" (seafood numbers on a mushroom), `olive_oil_kewpie_mayonnaise` → "Oil, olive" (883 kcal), `sauce` → "Sauce, barbecue", `tomato_based_pizza_sauce` → "salsa". None is in B1/B2/B3. Add them to B1 (or the queue), and make exact-key matches pass a name check or a quick dietitian skim before `ai_verified`. Same issue for decision 2a: `light_cream` (verified) is keyed to "Cream, sour, light" and its numbers are within 10 %, so it would get `checked_verified` with misleading evidence.

## D. Gaps in the brief's mechanics

10. **Auto-unverify vs `ai_verified`.** If the trigger clears `ai_verified` whenever numbers change, the import's own UPDATE (numbers + `ai_verified = true`) clears itself. Clear it only when numbers change *and* `ai_verified_at` isn't being set in the same statement (or use a session flag like the existing `goh.uc_sync`).
11. **Recipe status is driven by `reasons`.** In `recipe_verification` a recipe is AI Verified only when `reasons` is empty. "3 foods AI verified" must go in a new column, not in `reasons`, or every such recipe drops to Needs review.
12. **Deleting a food cascades.** FKs to `foods` are ON DELETE CASCADE for `ingredient_lines`, `client_food_rules`, `swap_suggestions` (trigger side), `food_tags`, `unit_conversions`, `food_unit_exclusions`. B3 must re-point **client food rules and swaps** as well as lines, and check zero references in the same transaction before deleting (a missed line is silently deleted, not refused). Today there are 0 client food rules, but that will change once dietitians use the client tab.
13. **B3 `tin_tuna_in_spring_water` → `tuna_springwater`**: the duplicate's line uses `x85g`, which only the duplicate has. Copy the `x85g` measure to the canonical food first or the line becomes "can't be calculated". (No tags would be lost in any B3 merge.)
14. **change_log "summary names the AUSNUT key"**: the triggers build summaries themselves; add a session note (e.g. `goh.change_note`) that the trigger appends, or the requirement can't be met for tags/conversions.
15. **B2 leaves the wrong AFCD key in place.** Setting `ausnut_key` while the wrong `afcd_key` stays (e.g. peas → split peas, Labneh → olive oil) keeps a misleading "AFCD · key" badge. Clear or correct `afcd_key` when `ausnut_key` is set, or show `ausnut_key` first.

## E. Stale facts / list corrections

16. Live today: **315 verified foods** (brief: 311), 613 conversions (611). Verified since the package was built: `whiite_chocolate`, `white_wine`, `wholemeal_english_muffin`, **`wholemeal_roll` (in B1 — must be skipped)**. Re-read verification state at run time; never trust the list's flag.
17. **Duplicate creates**: `radish_ausnut` duplicates the verified `radish` (same key, same numbers); `brussels_sprouts` duplicates the verified `brussel_sprout`. Drop them (or reuse the existing food).
18. Live foods keyed to a *different* state than their name, all verified, that 2a will flag (good) and the dietitians should expect: `fig` (fresh, keyed to dried fig), `apple_sauce` (dried apple), `wholemeal_pasta` cooked (uncooked key), `beetroot` (canned key).
19. Re-points also overwrite `aisle` on 6 foods (mostly fixes, e.g. butter beans "Dairy & eggs" → Pantry). Not covered by the settled decisions; confirm it's wanted.

## F. Smaller clean-ups

20. Unit names that leaked through the pack/brand filter: `cup (cup)` (feta, a parse artefact), `babybel` (brand), `dixie cup`, `jar`, `microwave bag`, `microwavable cup`, `packet (family pack)`, `packet (small)`. These would show in the unit dropdowns.
21. Plausibility gate noise: add an absolute floor to the kcal rule (e.g. > 10 % **and** > 10 kcal). `tomato` 22 → 17.4 and `pepper` 251 → 276 queue today. Expect **24 of 39 re-points** to fail the gate as written (5 of them ESTIMATE-exempt); several are genuine state mix-ups (rosemary fresh vs dried, chilli flakes, mixed berries = goji numbers, tasty cheese reduced-fat vs regular).
22. `size_gap_fills.csv` "Fit" is blank on 209 of 238 rows: say what blank means.
23. README says 35 foods are grams-only; the import has 31 creates with no measure and no density.

## G. What checked out

No `food_id` collisions; no duplicate rows; all 1,361 tag rows use live labels; all 320 unit names pass the database's unit rules and none clash with existing measures; every `default_size` names one of the food's measures; aisles and protein families are valid; no negative numbers; energy (kJ with fibre ÷ 4.184) agrees with AFCD on 1,128 of 1,201 shared keys; B2's 22 foods are all verified; B3's 19 duplicates are unverified and their canonical foods exist; spoons/cups are correctly omitted where a density is set; no High-FODMAP tags written.

## H. Interaction with the work committed this week

No conflicts with migrations 0036–0040 beyond A1/A3 (0036 rules). Client app (0039/0040) only reads tags through `client_tag_kind`; the import adds no tags, so nothing changes there. Published plan snapshots are frozen and unaffected. Re-run `scripts/check-line-grams.ts` (engine parity) after G3/G4, since density and measures change grams. The G5 Lovable work touches the foods browser, which the owner's in-progress "The Table" restyle also touches; run G5 after the restyle is published.
