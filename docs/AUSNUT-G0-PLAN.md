# AUSNUT 2023 — G0 plan (brief revision 2, 21 Oct 2026)

> **Superseded for sign-off by [AUSNUT-REV3-SIGNOFF.md](AUSNUT-REV3-SIGNOFF.md)** (rev 3: R1–R8 handled in the build, second pass, final numbers). This file stays as the rev-2 record.

Nothing has been applied. Everything below was checked against the live database today (read-only), and the G1 SQL was dry-run in a transaction that rolled back (10/10 checks, verified afterwards that nothing persisted).

## 1. Ready to go

| Item | Where | State |
|---|---|---|
| Package rev 2 in the repo | `seed/ausnut2023/` | identical copy of `Downloads/ausnut2023 2` |
| G1a enum migration | `supabase/drafts/0041_ausnut_source_enum.sql` | draft, dry-run OK |
| G1b schema migration | `supabase/drafts/0042_ausnut_reference_ai_verified.sql` | draft, dry-run OK |
| G1 test | `tests/sql/ausnut_g1.test.sql` | 10/10 in the dry run |
| Snapshot script | `scripts/ausnut/snapshot.py` | written (read-only) |
| Reference loader | `scripts/ausnut/load_reference.py` | `--check` passes: 662 classifications, 3,741 foods, 9,802 measures (14 AUSNUT measures have no master row; skipped and listed) |
| Per-food projection of G3 | `docs/ausnut/g3_projection_2026-10-21.csv` | 517 foods, one outcome each |

## 2. Revision 2 against my review

Adopted and confirmed in the data:
- carbs "without sugar alcohols"
- total folate
- Buy as only where a measure exists (13 rows, all valid at the moment they're set)
- density never nulled, and > 10 % changes kept and flagged (soy sauce, pizza sauce)
- no default size where `each` exists (2 flagged)
- aisles kept (8 flagged)
- oats/oat bran/oat milk tagged Gluten, none Gluten-free
- `client_recipe_screen` unchanged
- `wholemeal_roll` moved to B2
- radish and Brussels sprouts dropped
- oyster mushroom, Kewpie and pizza sauce added to B1
- pack/brand unit names removed
- the enum gets its own migration and `source` waits for G5
- the kcal gate has a 10 kcal floor
- B3 re-points every reference and copies the tuna `x85g` measure first
- the change note is passed through a session setting
- `reasons` stays empty, with the note in a new column
- `Fit` is documented

## 3. Still to fix before G3 (rev 2)

| # | Issue | Evidence | Fix |
|---|---|---|---|
| R1 | **Duplicate measure → load fails.** `cheese_feta_reduced_fat` has two `cup` rows (157.5 g each; the "cup (cup)" fix collided with the density cup). | import_unit_conversions.csv | Drop one row. (My G4 loader will skip exact duplicates anyway.) |
| R2 | **New density silently overrides existing spoon measures.** When a food gains a density, the engine uses it ahead of its explicit tsp/tbsp/cup measures. The rule only compares old vs new *density*. | taco seasoning 11 g → **24 g per tbsp** (6 lines, ESTIMATE-exempt so it *would* write); salt & pepper 22 g → **48 g per 2 tbsp** (13 lines); icing sugar 17.6 → 11.2 g per tbsp | Compare a new density against the food's *effective* spoon/cup grams (explicit measures included). > 10 % → queue. |
| R3 | **Buy as written on 7 existing foods** (`each` on water, oregano, tomato, two mushrooms, stock pot, sun-dried tomato). It contradicts decision 10, and "buy 1 each water" isn't useful. | import_foods.csv repoint rows | Never set `purchase_unit` on existing foods; carry it in `purchase_unit_suggested`. |
| R4 | **Wrong identities that no name rule can catch.** Current numbers already equal the wrong food's, so the gate passes them. | `snow_peas` → split peas, boiled (exact key, 2 recipes); `white_potato` → white-flesh *sweet* potato (500 g in Cottage pie); `sugar_white` → icing sugar (High, 22 lines); `mcmuffin` → cake-style berry muffin (High); `sauce` → BBQ sauce; **`soy` → soy lecithin granules, 626 kcal, used as "2 tsp soy" in Spaghetti Bolognese**; `vegetable_stock_pot` (a concentrate, "1 each" = 100 g) → prepared liquid stock, 4 kcal (B1) | Put correct keys for these in B1 (or delete `sauce`, which is unused). **And** have a dietitian skim every proposed machine verification (~59 rows, one line each) at the G2 sign-off. |
| R5 | **"Head noun" needs a precise rule.** Read as "same first word", it rejects good matches (Mozzarella vs "Cheese, mozzarella"; Beef mince vs "Beef, mince"). | projection | Definition: *the last word of the food's name before any comma (singular, ignoring raw/dried/cooked etc.) must appear somewhere in the AUSNUT name.* With that, 3 unverified exact-key foods are held, plus 8 verified foods flagged in 2a. |
| R6 | **The wrong-key B1 foods stay wrong.** Oyster mushroom, Kewpie and pizza sauce currently carry the wrong food's numbers, so the gate queues them, as it should. | gate | For B1 rows the gate queues, still write `ausnut_key`, clear the wrong `afcd_key` and set `match_note`. The numbers wait for the dietitian, and the queue row says the current numbers are from the wrong food. |
| R7 | Passata keeps its density but also gets explicit tbsp/cup rows. Harmless (density wins), but contradicts the README. | import_unit_conversions.csv | Drop the two rows. |
| R8 | Brief text left over from rev 1: the Outcome says 311/206/250; decision 3 says 22 rows and that `source` changes, while G3.1 says 23 and that source waits. G3.1 says "all 311 verified" (315 live) and "55 without a key" (95 live: no key, or an AFCD key AUSNUT doesn't carry). | brief | Reword (no code impact). |

## 4. What G3 will do (projection on today's data, rules as above)

Verified foods (315), decision 2a:

| Outcome | Foods |
|---|---|
| `checked_verified` | 127 |
| Flagged: AUSNUT differs | 85 |
| Flagged: name doesn't match key | 8 |
| Flagged: no key / not in AUSNUT | 95 |

That leaves **188 on the dietitians' flag list**. It's large; sort it by recipe use (column `recipes_using` in the CSV).

Unverified foods (202):

| Outcome | Foods |
|---|---|
| **AI verified** | **59** (30 exact key, 21 agreed list, 8 High match; 10 of them via the ESTIMATE exemption) |
| Queued: Low match | 57 |
| Queued: Medium match | 22 |
| Queued: B1 gate | 19 |
| Queued: wrong identity (R4) | 7 |
| Queued: no candidate | 7 |
| Queued: name rule | 3 |
| Queued: gate | 2 |
| Label queue (branded) | 7 |
| B3 duplicates (deleted at G4) | 19 |

Recipes: AI Verified **26 → about 60** after G3. Before G4 the remaining blockers are concentrated. A dietitian verifying these six foods by hand unlocks the most:

| Food | Otherwise-ready recipes it blocks |
|---|---|
| pepper | 15 |
| soy sauce | 14 |
| tasty cheese | 13 |
| paprika | 13 |
| white sugar | 10 |
| tomato paste | 9 |

Recipe lines whose grams move in G3: 144 lines across the re-points that gain or change a density. Almost all are unchanged or within ±10 %. The exceptions are R2 (taco seasoning, salt & pepper, icing sugar). Apple cider vinegar's 9 lines become calculable.

## 5. G1 — what runs on "go G1"

Order:
1. `python3 -I scripts/ausnut/snapshot.py pre-ausnut`. It archives foods, food_tags, unit_conversions, ingredient_lines, client_food_rules, swap_suggestions, food_unit_exclusions and recipes to `seed/archive/<date>-pre-ausnut/`.
2. Apply **0041** (enum value only).
3. Apply **0042**:
   - the three reference tables (staff read only; anon none; no API writes);
   - the `foods` columns `ausnut_key` (FK), `ai_verified`, `ai_verified_at`, `ai_match_confidence`, `ai_evidence`, with checks: AI verified always carries key, date, confidence and a one-line evidence (≤ 400 chars, since every screen loads foods with `select *`);
   - the clearing rules (below);
   - change-log notes via `goh.change_note`;
   - `recipe_verification`, `recipe_readiness`, `food_leverage` and `changes_to_review` counting `verified OR ai_verified`, with new columns appended only and `reasons` unchanged;
   - `client_recipe_screen` untouched.
4. `python3 -I scripts/ausnut/load_reference.py`, then run `tests/sql/ausnut_g1.test.sql`, then regenerate `supabase/types.ts`.
5. Report:
   - row counts;
   - the proofs below;
   - the column-by-column comparison of our foods' shared keys;
   - `recipe_verification` for 3 recipes (no change expected yet, because no food is AI verified until G3).

The clearing rules: AI verification is cleared when a person changes kcal/macros/fibre/density, changes a tag, **or removes dietitian verification**. The last one is needed because the editor's "Mark as unverified" only sends `verified = false`. The import keeps its flag because it sets `ai_verified_at` in the same statement.

Proofs to run after the load:
```sql
-- carbohydrate: on keys where the two AUSNUT columns differ, which one does AFCD match?
select count(*) filter (where abs(a.carb_avail - m.carb_avail_without_sa_g) <= 0.3) as afcd_matches_without_sa,
       count(*) filter (where abs(a.carb_avail - m.carb_avail_with_sa_g)    <= 0.3) as afcd_matches_with_sa,
       count(*) as keys_where_columns_differ
from afcd_master a join ausnut_master m using (public_food_key)
where abs(m.carb_avail_with_sa_g - m.carb_avail_without_sa_g) > 0.5;          -- today, from the CSVs: 29 / 0 / 29
-- folate: same test, total vs DFE (today: AFCD = total on 71 of 75, DFE on 0)
select count(*) filter (where abs(a.folate_ug - m.folate_total_ug) <= 2) as total, count(*) filter (where abs(a.folate_ug - m.folate_dfe_ug) <= 2) as dfe, count(*)
from afcd_master a join ausnut_master m using (public_food_key) where abs(m.folate_total_ug - m.folate_dfe_ug) > 5;
```

## 6. Gate order — one change proposed

G0 → G1 → G2 (rule sign-off **plus the ~59-row skim of proposed machine verifications**) → **G5a** → G3 → G4 → G5b.

The app reads `foods.verified` directly in six places: the foods list filters and pill, the editor badge, Quality's "Unverified foods", the recipe editor's ticks, the shopping list, and Needs attention. Once G3 runs, recipes will say "AI Verified" while their foods still say "Draft — not verified". G5a is a small Lovable change to run before G3:
- the "AI verified" pill and evidence on the editor;
- "AI verified" in the foods list filter and pill;
- the `ausnut_key` badge;
- a "Remove AI verification" action.

G5b (the AUSNUT tab and import, the `source = 'ausnut'` switch, the queue filter) stays after the restyle is published. Until G5b, new AUSNUT foods are created with `source = 'custom'` plus `ausnut_key`, so the editor badge reads "Custom".

## 7. Risks

- **Enum change:** isolated in 0041. Nothing writes `ausnut` until G5b, and the app's source filters would hide those foods until then.
- **Readiness change:** tested. Existing view columns and `reasons` are unchanged. Two server functions shift meaning automatically:
  - `plan_publish_check`: fewer recipes are flagged as needing review.
  - `sign_off_recipe`: a dietitian can now sign off a recipe whose foods are only AI verified, giving it a "Dietitian verified" badge. **Decision needed** (see 8).
- **Thresholds:** they queue 19 of 41 re-points. Several are real state mix-ups (rosemary fresh vs dried, chilli flakes, goji numbers on mixed berries, reduced-fat cheese row on tasty cheese), which is the gate working.
- **Queue size:** ~117 unverified foods to queue and 188 verified foods to flag.
- **Keys:** the scripts use the server key in `.env`. If the legacy keys are disabled before G1, add the new `sb_secret_…` key as `SUPABASE_SECRET_KEY` (the scripts prefer it).

## 8. Needed from the team before G3

1. G2 sign-off of `rules/*.csv`, and the skim of the ~59 proposed machine verifications (CSV rows marked `ai_verified …`).
2. Rev-3 package fixes R1–R7 from the other window, or approval for me to enforce them in the G3/G4 loader.
3. **Sign-off decision:** may a dietitian sign off a recipe whose foods are only AI verified? My recommendation: yes, but the sign-off result lists those foods so the dietitian sees what they're vouching for.
4. Optional quick win: hand-verify pepper, soy sauce, tasty cheese, paprika, white sugar and tomato paste.
5. Go for G1.
