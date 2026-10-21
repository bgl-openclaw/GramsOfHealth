# AUSNUT 2023 — revision 3: ready for sign-off (21 Oct 2026)

**Nothing has been applied.** **Dietitian review page:** https://claude.ai/artifact/JNqBi3w2f8WE5MNpAog2Hn. Share it as a Contributor so they can answer; every decision saves to the page, and I read the answers back into `scripts/ausnut/decisions.py` before the run.

**Final pass, 21 Oct (evening):** everything was rebuilt from the live library and the full machinery was dry-run again on 105 real changes across every batch, including the new splits. Every check passed and the run rolled back. The owner's rulings are in: salt and pepper are separate; milk is not a protein.

**Earlier:** Everything below was built from the live library today (read-only). The full machinery (0041 + 0042 + 0043) was dry-run on 64 changes taken from the real changeset, covering every kind of change and every batch, in a transaction that rolled back. Every check passed, and the only skip was the one I forced: a food edited after the build, which the run correctly refused to overwrite. Afterwards I confirmed nothing persisted.

This replaces the open items in `AUSNUT-G0-PLAN.md`. R1–R8 are all handled in the build (section 6).

## 1. What will change

| | Count | What it means |
|---|---|---|
| Verified foods checked against AUSNUT | **141** | AUSNUT agrees (same food, within the gate). The dietitian badge stays and the numbers don't change. They get "AUSNUT checked". |
| Verified foods flagged for a later look | **160** | No AUSNUT key (90), AUSNUT differs (62), name doesn't match the key (7), wrong key (1). Numbers untouched. List: `review/verified_flags.csv` (145 are used in recipes). |
| Verified foods with impossible or mistyped numbers | **9** | The **badge is removed**; numbers untouched; queued as urgent (3a). |
| Unverified foods given AUSNUT numbers + AI verified | **101** | Each carries its AUSNUT key and a one-line evidence. List: `review/ai_verified.csv`. |
| New foods created from AUSNUT | **250** | List A + C, AI verified, with measures, tags, aisle, protein family. I corrected 12 rows of the package (section 2). |
| Duplicates merged into the main food | **37** | Every recipe line, client rule and swap is moved first. A food is only deleted when nothing points at it. |
| Junk/test rows deleted | **12** | All unused. |
| Measures added | **97** + 282 on new foods | 357 are exact (AUSNUT measures, pack sizes, or the food's own measures); 22 are marked as estimates. |
| Placeholder measures corrected | **34** | The import set many `each` measures to 100 g. Examples: 16 sun-dried tomatoes were counted as 1.6 kg (now 77 g), 2 star anise as 200 g, 5 large garlic cloves as 900 g, 10 slider buns as 1 kg; small taco tortillas were 80 g each (AUSNUT 30 g). |
| Estimated measures that AUSNUT confirms | **4** | Pear medium, button mushroom, fig, apple medium. |
| Default sizes | 9 + 53 on new foods | `each` follows a named size. |
| Aisles corrected | **34** | Only clearly wrong ones (stock in Meat & seafood, sauces in Produce…). |
| Protein family filled | **88** | Chicken, beef, fish, dairy, legumes… Milk and composite products are left out on purpose (section 4). |
| Allergen tags added | **16** | Haloumi had no Dairy tag; pesto had no Tree nuts; pancake, waffle and pikelet had no Gluten or Egg; couscous had no Gluten. |
| False "Vegan" claims removed | **2** | Feta and unsalted butter. |
| Combined ingredients split | **28 lines** | Salt & pepper → separate salt and pepper lines, half each (one duplicate removed). Four more pairs the import glued together: "1 tbsp each paprika and cumin" had lost the cumin; the same for onion + garlic powder, ginger + garlic, and soy sauce + sesame oil. The 4 verified combined foods are left unused for a dietitian to delete. |
| Recipe repairs | 4 yield lines removed, 2 lost lines restored, 3 line fixes, 1 prep-note fix, 27 data-issue notes | Section 2. Notes: 8 cleared (informational), 6 new, 13 made precise. |

**Recipes ready (AI verified): 26 → 201** of 374. The projection uses the same rules as the database view and reproduces today's 26 exactly. **No recipe that is ready today becomes unready.** The other 173 stay in Needs review. Of those, 55 are held only by an unverified food (mostly the label and proposal items in section 3), 41 only by an estimated weight, 15 only by a note or missing title/image/steps, and 60 by more than one thing.

Clients are not affected: their screens keep using dietitian verification only. You said yes to dietitians signing off recipes whose foods are only AI verified. The G5a screen change lists those foods in the sign-off dialog, so the dietitian sees what they're vouching for.

## 2. What the second pass found (on top of rev 2)

- **Yield lines counted as ingredients.**
  - WAFFLES: "68 each waffle" = 6.8 kg.
  - FLUFFY JAPANESE SOUFFLE PANCAKES and PROTEIN PANCAKES: "6 each pancake".
  - PIKELETS: "12 each pikelet".

  All four lines are removed.
- **Recipes missing ingredients the method uses.** These get a note, which keeps them in review:
  - WAFFLES: no flour.
  - Soufflé pancakes: no flour or cream.
  - CAPRICCIOSA PIZZA: no dough or cheese, and "2 each pizza".
  - PROTEIN PANCAKES: the yoghurt version's lines.
  - BANANA OAT MUFFINS: 5½ cups of oats and of flour.
  - THERMOMIX LENTIL SOUP: 41 servings and duplicate water.
- **100 g placeholder measures:** 34 corrected, from AUSNUT where it has the measure.
- **Wrong keys the gate couldn't catch:**
  - "Lemon" was keyed to *preserved* lemon.
  - "Fried shallot" carries cooked-shallot numbers.
  - "Mozzarella ball" now links to bocconcini (fresh) instead of pizza mozzarella.
  - "Soba noodles" is keyed to boiled soba, but the recipe weight is dry. It is held.
- **Verified foods with impossible numbers:**
  - haloumi 1,050 kcal
  - Farmers Union Greek yoghurt 513 kcal
  - white chocolate 546 g carbs
  - "Lentils/Kidney Bean" carries dried-bean numbers but is used as "1 can, drained" (3× too high)
  - plus the 5 from rev 2

  The badge comes off; the numbers wait for a dietitian.
- **Package tag errors on new foods:**
  - "Squash, button or scallopini" was tagged Shellfish ("scallop").
  - Honeydew melon was tagged Honey.
  - Mixed nuts had no Tree nuts tag.
  - Corn flakes were tagged Gluten-free (they contain barley malt).
  - Mixed seeds had no Sesame tag.
  - Natural muesli claimed Nut-free.
  - Lobster's family was set to fish; coconut yoghurt's to dairy.
- **Lines that would silently compute wrong:**
  - With a default size, "2 each iceberg lettuce" in a 2-wrap recipe would count 2 whole lettuces. It is fixed to 2 leaves.
  - "1¼ each self-raising flour" is fixed to 1¼ cups.
  - "dates_dried" no longer gets a 5 g default. Those recipes are probably Medjool (~20 g each), so the lines stay visible as "can't be calculated" instead of being under-counted 4×.

## 3. Needs your call (nothing here is applied; each sits in the dietitians' queue)

### 3a. Urgent: verified foods with wrong numbers (badge removed, numbers untouched)

| Food | Ours | AUSNUT | Used in | Suggested |
|---|---|---|---|---|
| Leek | 313 kcal | 30.6 | 4 | typo: load AUSNUT F005164 |
| Gluten-free pasta, cooked | 361 (dry numbers) | 152.7 | 5 | AUSNUT F006429 |
| Lentils/Kidney Bean | 299 (dried) | 105.4 (canned, drained) | 4 | AUSNUT F000448, or merge into kidney beans |
| Haloumi | 1,050 | 305.2 | 2 | AUSNUT F002466 |
| Egg white | 197 | 46.8 | 2 | typo: AUSNUT F003706 |
| Lamb leg steak | 553 (fat 57.6 g) | 130.5 | 1 | AUSNUT F005095 |
| Milk chocolate | 81 (chocolate-milk numbers) | 520.8 | 1 | merge into "Chocolate, milk" (verified, 521) |
| White chocolate | carbs 546 g | 54.6 | 1 | fix the typo |
| Greek style yoghurt, Farmers Union | 513 | 131.5 | 0 | AUSNUT F009655 |

### 3b. Proposals (29): suggested action, not applied
The full list with reasons and use counts is in `review/proposals.csv`. These have the most effect:
- **Vermicelli noodles** (11 lines), **vermicelli rice noodle**, **pad thai noodles** ×2, **soba**: recipe weights look **dry**, but AUSNUT only has boiled. → Enter label numbers for dry noodles, or link the uncooked row where AUSNUT has one (soba F006043).
- **Red / tikka curry paste**, **vegetable stock pot** (concentrate, now 28 g each): label numbers.
- **Spiral pasta** (450 g), **pear/pearl couscous**: almost certainly dry. → link the uncooked rows.
- **Pre-cooked BBQ chicken**: skin on or off. **Short cut bacon**: AUSNUT only has cooked. **Sardine In**: canned, not raw.
- **Milk chocolate chip almond flake**: two ingredients merged into one; split the lines.
- **Tub cherry bocconcini**: "1 each" means one tub. → merge into bocconcini, ~200 g.
- Smaller ones: low-carb potato, Moroccan seasoning, packet ravioli, peri peri sauce, pickle, pork scotch fillet, slider bun, thyme/oregano mix, vanilla Greek / high-protein yoghurts, wholegrain wok-ready noodle, protein pita, pulse pasta.

### 3c. Label entries (22): numbers from the pack
Protein powder (13 lines), mini wholemeal wrap (8), sugar-free maple syrup (7), orange zest (3), plant-based feta, whey protein, both Chobani tubs, both Vetta pastas, Nesquik ×2, balsamic glaze, low-carb bagel, two low-GI wraps, mustard seed, nutritional yeast (current fat 52 g is wrong), protein electrolyte, red pesto, sandwich thin, red bean paste.

### 3d. Recipe lines whose unit looks wrong (24): not changed
List with suggestions: `review/line_proposals.csv`.
- The pattern is "each" where the recipe means cups: LCM bars "1.5 each rice bubbles", cookies "0.5 each brown sugar", protein balls "0.25 each oats" and "0.33 each walnuts", sausage rolls "1.5 each tasty cheese".
- Other examples: "5 each garam masala"; "1 each beef stock (crumbled)", which is a stock cube; "4 each spinach"; "15 each water"; Medjool vs dried dates in 4 recipes; LEMON CHEESECAKE MILLE FEUILLE's cream-cheese line, whose note says protein powder.

### 3e. Small leftovers
- 2 foods with clashing tags, already in the library: ladyfinger biscuit (Dairy + Dairy-free) and low-GI wrap (Dairy + Vegan).
- 6 lines still can't be calculated: dates "each" ×5, butter "each" ×1.
- 5 foods keep their own spoon measures; AUSNUT density isn't added because it disagrees by more than 10 %: pepper, salt & pepper, taco seasoning, mixed dried herbs, icing sugar. This was R2.

## 4. Calls I made at ≥ 95 % (overrule any)
- **Salt and pepper are separate ingredients (owner's call).** Combined lines are split half and half.
- **Milk is not a protein (owner's call).** No protein family for milk or composite products. Milk's role in the adjust-to-targets engine (currently "adjustable protein") is a question for the dietitian.
- **Role for the 250 new foods is suggested, not applied.** Every food has a role; without one the adjust-to-targets engine never scales it.
  - `scripts/ausnut/role_rules.py` follows the team's conventions and reproduces 505 of the 510 existing roles.
  - 10 new foods are left for the dietitian's judgement: milks, coconut yoghurt, hummus, konjac noodles, banana chips, coconut water.
  - Roles are written only after approval (`NEW_FOOD_ROLES_APPROVED` in decisions.py).
- **Density only where nothing conflicts.** Density overrides hand-entered spoon measures, so it's added only on re-pointed foods that had none, and on new foods.
- **Allergens: when unsure, keep the allergen and drop the "-free" claim.** Over-warning is safe; under-warning isn't.
- **A tag change removes dietitian verification (by design).** This touches haloumi and danish feta (both used), plus labneh, furikake and unsalted butter (unused).

## 5. Run order on "go" (each step reports before the next)
0. Read the dietitian's answers from the review page into `decisions.py` (urgent fixes, proposals, line fixes, splits, roles, label numbers, flags). Rebuild, and show you the diff.
1. `python3 -I scripts/ausnut/snapshot.py pre-ausnut`. This is the restore point.
2. **G1:**
   - apply 0041, then 0042;
   - `python3 -I scripts/ausnut/load_reference.py`;
   - run `tests/sql/ausnut_g1.test.sql`;
   - regenerate `supabase/types.ts`.
3. **G5a:** paste `docs/lovable-prompts/G5a-ai-verified.txt` into Lovable and **Publish**. Check that the foods list shows the new filter.
4. **G3/G4:**
   - apply 0043;
   - `python3 -I scripts/ausnut/build_changeset.py`, rebuilt right before the run so every precondition matches the live library;
   - then for each of g3a → g3b → g3c → g3d → g4a → g4b → g4c, run:
     - `apply_changeset.py upload`
     - `dry-run` (read the skipped rows)
     - `apply`
   - Each batch is one transaction: any error, and nothing in that batch is applied.
5. Regenerate types, re-run the readiness numbers, and report.

## 6. Rev-2 items: where each is handled
- **R1** (duplicate feta cup): duplicate units are skipped when foods are created.
- **R2** (density vs spoon measures): held where they disagree by more than 10 % (5 foods).
- **R3** (Buy-as on existing foods): never set; only on new foods (6).
- **R4** (wrong identities): fixed by link, merge or delete:
  - snow peas, white potato, white sugar;
  - soy → soy sauce;
  - McMuffin and "sauce" deleted;
  - stock pot held.
- **R5** (head-noun rule): implemented.
- **R6** (B1 rows that fail the gate): the link is written, numbers wait. All B1 rows were decided by hand, so none remain.
- **R7** (passata spoon rows): not added where the food has a density.
- **R8** (brief text): superseded by this document.

## 7. Files
- `scripts/ausnut/decisions.py`: every hand decision, with its reason.
- `scripts/ausnut/build_changeset.py`: decisions + package + live library → `seed/ausnut2023/changeset/*.jsonl`. It stops if anything would fail.
- `scripts/ausnut/apply_changeset.py`: upload / dry-run / apply, one batch at a time.
- `supabase/drafts/0043_ausnut_apply.sql`: the change machinery and the dietitians' queue (`ausnut_review_queue`).
- `tests/sql/ausnut_apply.test.sql`: generated from the real changeset by `make_apply_test.py`.
- `seed/ausnut2023/changeset/review/*.csv`: every list above, plus:
  - `recipes_after.csv`: each recipe, before and after;
  - `measure_fixes.csv`;
  - `newly_calculable.csv`: 191 lines that start calculating, with grams;
  - `grams_changed.csv`;
  - `big_lines_after.csv`.

## 8. Sign-off
- [ ] Sections 1, 2 and 4 are OK to apply as described.
- [ ] Section 3 is understood. Those items stay queued for the dietitians and don't block the run.
- [ ] G5a will be published between G1 and G3.
- [ ] **Go**: say "go G1", and I'll stop for your check before G5a and again before G3.
