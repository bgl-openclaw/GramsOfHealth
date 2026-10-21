# Meal plans + AI layer (roadmap rev 2): report back

21 October 2026. A response to `claude_code_roadmap_plans_ai.md` (revision 2) and `research_meal_plan_generation_logic.md`. I read the code and the live database before writing this. Nothing has been built or changed yet.

## Bottom line

I agree with the design: filter, then assign, then fit servings exactly, then report. Several things change the plan, though:
- Some of the roadmap's "live facts" are out of date. Quarter serves, day types and sealed published versions are already live (migration 0037).
- Half of P0 is already built inside the AUSNUT changeset.
- The roadmap misses one real gap. A plan item can't carry ingredient adjustments, yet both the adjust slider and the "swap beef for chicken" suggestions need it.
- The generator can't produce useful plans until two things happen: the AUSNUT pass is applied (26 → about 201 usable recipes) and meal types are tagged. Today's pool is 26 recipes, 16 of them under 250 kcal a serve.

## Live facts, corrected

| Roadmap says | Live today |
|---|---|
| `servings_override` is an integer | Already numeric in 0.25 steps (0037, 21 Oct). Nothing to change. |
| 0 recipes have a meal type the app can see | Confirmed. 72 recipes carry the 73 legacy tags (Dinner 27, Breakfast 21, Snack 20, Lunch 5) in the unread `recipe_tags` table; 302 recipes have none. 47 of the 374 recipes are variants of another recipe. |
| `protein_family` set on 2 of 98 adjustable proteins | Confirmed. But the AUSNUT rev 3 changeset (not yet applied) sets it on 88 existing foods and on 70 of the 250 new foods. Afterwards 86 of the 98 are covered. The 12 left are mostly milks, which by the owner's rule have no family. |
| About 30 usable recipes | 26 pass every check (24 base recipes, 2 variants). 0 are dietitian-signed. AUSNUT projects about 201. Of the 26: 16 are under 250 kcal a serve, 8 are 250–600, 2 are over 600. |
| Plan fields to add: status, cycle length, day types | Most exist. Status is draft/published, publishing seals a snapshot the client sees, `meal_plans.days` holds the cycle length, and `meal_plan_days` plus the client's weekly pattern give per-day day types. `plan_slots()` returns the client's own slots. |
| Client module complete | Confirmed: cycle length, minimum gap between repeats, maximum repeats per cycle, batch cooking, weekly day-type pattern, slots (kind, free choice), protein spread, protein likes and dislikes, food rules, per-day-type targets. **Missing: energy share per slot.** |
| — | **Gap: any staff member, interns included, can publish a plan to a client today.** Principle 7 says only after a dietitian confirms. |
| — | Plan items must be recipes (`recipe_id not null`). They can take a profile but not ingredient adjustments. |
| — | The engine computes 5 nutrients (kcal, protein, fat, carbs, fibre). Saturated fat, sodium and the micronutrients are not in it, and only about 77% of the 460 foods used in recipes have them. |
| — | No edge functions exist. The AI-0 groundwork from the v1 AI roadmap (API key, function, run log, spend guard) hasn't been built. |
| — | The 25 `swap_suggestions` rows are allergy swaps. Nothing groups foods for macro swaps (beef mince ↔ chicken mince). |

## Where I'd do it differently

1. **Protein family is an AUSNUT review, not a new pass.** The 88 fills are already on the dietitian's AUSNUT review page (part 3, "Protein family and shopping aisle"), and the new foods carry theirs. After AUSNUT is applied I'll list only the 12 leftovers. No separate `protein_family_for_review.csv`.

2. **Meal types: the table as proposed, with four rules.**
   - Meal type values match `client_meal_slots.slot_kind` exactly (breakfast, lunch, dinner, snack).
   - Variants inherit their base recipe's meal type unless a dietitian overrides it, so there are 47 fewer rows to review and no drift.
   - The classifier is written once, as a SQL function `suggest_meal_types(recipe_id)`. It runs the first pass now as a read-only query (no database change), and the app calls it when a recipe is saved. The first pass and the save-time suggestion can never disagree.
   - The kcal it uses is a hint computed from `line_grams`. It is never shown or used as a nutrition number.
   - **I recommend the generator uses only dietitian rows and high-confidence machine rows.** Medium and low rows wait for review, and the pool-health panel says how many are waiting.

3. **No new "nutrient completeness" flag.** `recipe_verification` already requires every food verified, every line calculable, no estimated weights and no data issue. A second definition would drift. The pool gate is that view's status (AI-verified or dietitian-verified). Micronutrient coverage becomes a per-recipe percentage used only for the report's confidence line.

4. **P1 builds on 0037 rather than redefining status.**
   - Keep draft → published. Publishing already is "send": it seals the snapshot the client sees.
   - Add confirmation. `confirm_plan(plan, notes)` is for dietitians and admins only. Any edit clears it, like the credential "checked" mark. Publishing requires a current confirmation, which also closes the intern gap above.
   - New:
     - food items (recipe or food + quantity + unit, exactly one)
     - **item-level ingredient adjustments** (same shape as profile deltas; needed by the adjust slider and ingredient-swap suggestions)
     - a sparse slot-state table (plan, day, slot: free choice or empty, reason, locked)
     - leftover links (`batch_group`, cook or eat)
     - `boosts_item_id` for top-ups
     - `plan_generations` (seed, settings snapshot, pool hash, report), so every regenerate is kept rather than overwritten
     - `plan_edits`
     - energy share per client slot
   - The publish snapshot the app builds must then include adjustments and food items. The database check that compares it with the saved plan grows to match.

5. **Split P2.**
   - **P2a:** kcal, protein, carbs, fat and fibre with the engine as it is. Per-day deviations against the day-type target, weekly averages, between-day variance, distinct recipes/ingredients/cook events, and the confidence flag.
   - **P2b (later):** saturated fat, sodium and micronutrients against NRVs. This needs the engine and its copy in the app extended, the NRV values checked on eatforhealth.gov.au, and a life-stage field on clients (pregnancy and breastfeeding aren't recorded). With 77% coverage it would mostly report "incomplete data", so it's better after AUSNUT.

6. **The planner runs in one place.** A Supabase Edge Function `planner` bundles the engine, roll-up and planner packages. These are pure TypeScript, tested here.
   - The app calls it for the pre-check, generation and every edit. The AI function calls the same code.
   - Lovable gets no copy of the planner, so there's no third copied module to keep in step. The app keeps its engine copy for live totals while editing.
   - It reads with the caller's login, so access rules still apply.
   - Pool snapshots are stored once per distinct content hash, so any run can be reproduced.
   - The trade-off: each edit is a network round trip, roughly 0.3–0.8 s.

7. **Suggestions ship in two steps.**
   - First: serving change, profile switch, top-up item, cook-extra leftover, cross-day top-up.
   - Ingredient swaps follow once a small swap-group list exists (mince, steak, fillet, yoghurt, legumes…). I'd draft it from roles and protein families for the dietitians to approve.

8. **One Lovable prompt per phase** as each backend lands (P1 screens → generator and report → edit tools → Claude panel), not one P6 handoff at the end. That's how we've worked, and smaller prompts review better.

9. **The AI layer needs groundwork first.** That means the v1 AI-0 items (API key as a Supabase secret, the function, one log table merging `ai_runs` and `ai_requests`, a spend guard).
   - The explainer sends a client's targets and screen reasons to Anthropic. That's health information, so the privacy wording must cover it before a pilot.
   - Model: Opus 5.5 for the strategist. Try Sonnet 5.5 for the explainer if the accuracy check holds (about half the cost, faster).

## Gate order

| Gate | Work | Depends on |
|---|---|---|
| **A (now)** | P0 meal-type first pass → `meal_types_for_review.csv` (read-only query, no DB change). P1 schema written and dry-run. P2a package with fixtures. | your go |
| **B** | AUSNUT applied. Meal-type table loaded (legacy tags as dietitian rows, high machine rows), 12 protein-family leftovers, discretionary suggestions, pool coverage per slot. | dietitian AUSNUT review; CSV back |
| **C** | P1 live (confirm + notes, food items, adjustments, slot states, leftovers, generations, edits, slot energy shares) + Lovable prompt. | B not required |
| **D** | P3 generator + `planner` edge function. Acceptance fixtures written first and agreed with you. | A, C; B for useful output |
| **E** | P4 edit operations + Lovable prompt. | D |
| **F** | AI-0 groundwork, then P5 explainer / translator / strategist + Lovable prompt. | D, E; API key; privacy wording |
| later | P2b micronutrients, ingredient-swap suggestions. | NRV check, swap groups |

The intern publishing gap can be closed on its own straight away (a small migration) if you don't want to wait for gate C.

## Risks

- **Pool.** Until gate B, every run is in degraded mode, mostly snacks. How meal types split across the ~201 recipes is unknown until the first pass runs.
- **Meal-type review volume.** Many mains are honestly "lunch or dinner". Allowing both keeps them high confidence; the medium and low pile will be clear once the pass runs.
- **Exact enumeration.** Up to 6 filled slots a day (7⁶ = 117,649 combinations per candidate day) is fast. More slots, or several recipes in one slot, need branch-and-bound or the `highs` solver (MIT, wasm).
- **Determinism.** One production runtime removes most of the risk. Golden tests run in Node and Deno anyway.
- **Snapshot parity.** The publish snapshot is built by the app's engine copy. Food items and adjustments make that code bigger, and the database check must cover them.
- **Cost and latency.** The explainer costs a few cents per plan. Opus can take 10–20 s, so stream the answer.

## Owner decisions (21 Oct 2026)

- **Go on gate A.**
- **Interns keep publishing.** The intern gap stays open by choice. Confirm-with-notes (P1) is open to any staff member who can publish the plan, not dietitians only.
- **The generator uses every meal type, whatever its confidence.** The dietitian does one large pass over all recipes before the planner is used, so the review list holds every recipe, not just medium and low rows.
- **Protein spread counts lunch and dinner.** Snacks are the flexible slot used to top up the day's energy, protein, carbs and fat. The generator fills them last against what the day still needs (food items such as yoghurt or nuts allowed as snacks).

## Gate A status (21 Oct 2026)

- **P0 meal types: first pass done.** The review list is `seed/meal_types/meal_types_for_review.csv` (all 374 recipes; how to review: `seed/meal_types/HOW-TO-REVIEW.md`).
  - Confidence: 322 high, 51 medium, 1 untitled.
  - Old meal tags are kept and merged in.
  - 45 recipes are suggested as discretionary.
  - The classifier is draft migration `0046_recipe_meal_types.sql` (not applied). The first pass ran read-only from the same SQL.
  - Today's usable pool by meal type: 8 dinners, 7 lunches, 5 breakfasts, 15 snacks.
- **P1 plan model: draft migration `0047_plans_p1b.sql`, dry-run, not applied** (gate C).
  - New test `tests/sql/plans_p1b.test.sql`: 10 groups pass. The existing `plans_p1` test still passes with it applied, so the current app's publishing is unaffected.
  - Choices made:
    - Confirmation is required only once a plan has a planner report. Hand-built plans publish exactly as today.
    - Item ingredient changes use whole-recipe quantities, like profiles and the adjust solver.
    - Food items and ingredient changes need the Lovable screens before the planner creates any.
- **P2a roll-up: `packages/rollup`** (pure TypeScript on the engine).
  - 11 tests cover a free-choice day, a leftover pair, a top-up, ingredient changes, an ingredient that can't be weighed (named, never zero), the tolerance bands and repeatability.
  - The whole suite (53 tests) passes.

## Decisions needed (original list; 1, 2, 3 and 6 answered above)

1. **Go** on gate A (meal-type first pass and CSV, P1 schema dry-run, P2a package).
2. Medium- and low-confidence meal types stay out of the generator until reviewed? (recommended: yes)
3. Protein spread counts **lunch and dinner only**? By grams, yoghurt makes most breakfasts "dairy".
4. Default energy share per slot: breakfast 25%, lunch 30%, dinner 30%, snacks 15% between them? These are editable per client.
5. A dietitian to confirm the tolerances: energy ±10% daily, protein never under and at most +15%, carbs and fat ±10% daily. The research says these are policy, not a standard.
6. Close the intern publishing gap now, or with P1?
7. Owner: add the Anthropic API key as a Supabase secret when we reach gate F (I won't handle the key), and update the privacy wording.
8. OK for me to draft the swap groups for dietitian approval?
9. The roadmap mentions a "typed-request grammar fix already drafted". It isn't in the repo. Where is it?
10. Does rev 2 replace the v1 AI roadmap's AI-1 to AI-4 (label reader, recipe import, transcripts, clinical documents), or only AI-5 (plans)?
