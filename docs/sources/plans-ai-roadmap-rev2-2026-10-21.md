# Claude Code — Meal plans and the AI layer: roadmap (revision 2, 21 October 2026)

Plan first, then build phase by phase on an explicit go, with a report at each gate. Read the code and live schema before proposing; argue where you would do it differently. Lovable builds screens only after each backend phase lands, from a prompt you write. This revision replaces the 15 October roadmap. It is informed by `research_meal_plan_generation_logic.md` (read it; it carries the evidence and the acceptance criteria) and by decisions Ben took on 21 October, recorded below as fixed.

## Outcome

A dietitian opens a client and presses Generate. Within seconds a draft plan appears: the client's required meals and snacks for each day of the cycle, filled from verified recipes that pass the client's screen, with a serving multiplier on each meal (1.0, 1.25, 1.5 and so on) chosen so each day lands on its day-type targets, protein first. Beside the plan is a report: what hit target, what missed and by how much, which rule was relaxed because the recipe pool was too small, and a short ranked list of suggestions ("swap the beef for chicken to bring fat down 9 g", "add 60 g quinoa to Tuesday's salad for 220 kcal", "cook 300 g extra mince on Monday for Wednesday's wraps"). The dietitian swaps, locks, nudges, accepts or ignores suggestions, adds notes, and confirms. Only then does the plan go to the client. Claude is the front line of the second pass: it reads the report, explains it in plain words, and proposes fixes as diffs. It never applies anything.

## Principles (fixed)

1. The builder works off the client's required meals and snacks per day. It fills those slots and nothing else. Free-choice slots stay free.
2. Filtering is simple: verified recipes, then the client screen (blocked and unconfirmed out, disliked penalised), then the recipe's meal type must match the slot. No clever matching.
3. Targets are hit with serving multipliers in 0.25 steps (0.5 to 2.0) on some or all meals, and with the existing adjust slider when a recipe's ingredients need to move rather than its whole serve. The engine chooses the multipliers that land the day closest to target; the dietitian sees and can override every one.
4. The engine is the only source of macro numbers. The builder reads per-serve vectors the engine computed and hands the finished plan to the roll-up for the authoritative totals. It never computes nutrition.
5. Deterministic: same client, same pool snapshot, same settings, same seed gives the same plan. Ties break on recipe id; a seeded PRNG is used only to shuffle ties; no time limits in any loop.
6. Repetition and batch cooking are features. Leftovers are planned deliberately (cook extra, use tomorrow), and the report shows between-day variance rather than forcing variety. Variety is enforced where it protects adequacy: protein family rotation per cycle, and later food-group serves.
7. Nothing reaches a client without a dietitian's confirmation and notes. Client screening (`client_recipe_screen`) stays on human `verified`; `ai_verified` and rule-derived tags are never used for allergy screening.
8. AI translates, explains and proposes diffs. It never places recipes, never computes, never writes. Every call is logged.
9. Allergen tags are neutral facts. Report wording is plain and calm.

## Live facts (21 October, read directly)

- 374 recipes. 356 carry allergen or dietary tags (derived from foods). **0** carry a meal type that the app can see: the 73 meal tags (Dinner 27, Breakfast 21, Snack 20, Lunch 5) sit in the legacy `recipe_tags` table, which nothing reads. 301 recipes have no meal type anywhere.
- `foods.protein_family` is set on 2 of 98 `adjustable_protein` foods.
- Recipe pool a generator may draw from today (AI or dietitian verified): about 30; the AUSNUT verification pass under way will raise this to most of the library.
- `meal_plan_items.servings_override` is an integer; 1.25 serves cannot be stored.
- Client module is complete: targets per day type, screen, structure, meal slots, protein spread, food rules, supplements, check-ins.

## Phases

### P0 — Tag the library (blocker, start now, runs alongside the AUSNUT pass)

Every recipe must end up with a meal type, every protein food with a protein family, and treats with a discretionary flag. First pass by you; a dietitian verifies only where you are not certain.

- **Meal type.** New table `recipe_meal_types(recipe_id, meal_type breakfast|lunch|dinner|snack, source machine|dietitian, confidence high|medium|low, reason text)`; a recipe may have more than one. Seed from the 73 legacy tags as `dietitian` rows. For the rest, derive from title, ingredients, kcal per serve and existing course tags (Smoothie and overnight oats are breakfast; Salad and Bowl are lunch and often dinner; Curry, Stir-fry and anything over about 600 kcal a serve is dinner; under about 250 kcal is snack). Write every recipe a row with a confidence and a one-line reason. Produce `meal_types_for_review.csv` containing only medium and low rows, sorted by recipe title, with your suggestion pre-filled, for the dietitians to tick or change. Load high rows straight away as `machine`; load reviewed rows as `dietitian`. Report: distribution per meal type, counts by confidence, and the list of recipes you could not place at all.
- **Protein family.** Same pattern on `foods.protein_family` for the 98 adjustable protein foods and any others that are a main protein (eggs, dairy, tofu, legumes): high-confidence rows load, the rest go to `protein_family_for_review.csv`.
- **Discretionary.** Add tag `Discretionary` under a new category `pattern` and suggest it for desserts, bliss balls, sweet bakes and treats, same review pattern.
- **Nutrient completeness.** A per-recipe flag, derived, true when every ingredient's tracked nutrients are present and no food is unverified or AI-queued.
- Repeat the meal-type pass automatically for any new recipe at save time, as a `machine` row with confidence, so the library never drifts untagged. Dietitians can change it in the recipe editor.
- Staff-only RLS on recipes, foods, conversions, tags and the plan tables, as before.
Report pool coverage per slot after each load. Nothing in P3 produces useful plans until this lands, so this phase gates P3.

### P1 — Plan model

Extend the plan schema:
- `servings_override` to numeric, snapped to 0.25 in the UI and by check constraint.
- An item is a recipe (with optional `profile_id`) or a food with quantity and unit (snacks, top-ups such as "extra 100 g chicken").
- Slot state: filled, free_choice, empty; `reason` text on free_choice and empty; `locked` boolean.
- Leftovers: `batch_group` id linking the cooked item to the items that eat it; cooked servings equal the sum consumed; shopping counts it once, repetition counts it once.
- Top-ups: an item may reference the item it boosts ("extra chicken in Tuesday's salad") so the report can show the protein it added.
- Per-day day type on the plan, defaulted from the client's weekly pattern.
- Plan fields: `cycle_length_days`, `status` (draft, confirmed, sent, archived), `origin` (generated, manual), `seed`, `settings_snapshot` jsonb, `pool_snapshot_id`, `report` jsonb, `dietitian_notes` text, `confirmed_by`, `confirmed_at`, `sent_at`.
- `plan_edits(plan_id, operation, actor, diff jsonb, created_at)` so a dietitian can see what changed.
Report migrations and how existing plans migrate.

### P2 — Roll-up (shared truth for UI, report and AI)

One pure function `rollupPlan(plan, targets) → per item, per slot, per day, per cycle` via the engine. Returns totals and the comparison object the report needs: per-day signed deviation for energy, protein, carbohydrate and fat against the day-type target with band status; weekly averages for fibre, saturated fat and the tracked micronutrients against the client's NRV set (EAR, RDI, UL banding; verify iron, calcium, B12, iodine and sodium values from eatforhealth.gov.au before coding them); between-day energy standard deviation per day type; distinct recipes, distinct ingredients and cook events per cycle; a `confidence` flag false when any item lacks complete nutrient data. Free choice excluded from totals and never a shortfall. Fixtures: a free-choice day, a leftover pair, a top-up item.

### P3 — Deterministic generator (`packages/planner`)

`generate(profile, poolSnapshot, settings, seed) → { plan, report }`. Steps, in order:
1. Resolve settings: expand the weekly day-type pattern into per-day targets; apply slots, soft energy share per slot (editable defaults), free-choice slots, repetition rules, batch flag, protein spread, tolerances. Record settings and seed.
2. Build the pool: verified (human or AI) recipes with nutrient completeness, through the client screen, partitioned by meal type per slot. Unverified never enters, even on request; the dietitian can add one by hand afterwards and the report marks it.
3. Pre-check: eligible recipes per slot; maximum and minimum achievable energy and protein per day at the serving bounds. If a target is unreachable, say so before solving ("Cannot reach 140 g protein on hard days from 6 eligible dinners; maximum 112 g"). If protein families cover under 80 % of the pool, declare the spread unenforceable. Mark the plan `degraded` where a rule will be relaxed and name it.
4. Place anchors: locked slots, free-choice allowances, and leftover chains when batch cooking is on.
5. Assign recipes, variety first, by beam search (top 4 candidates per slot, beam width 8 per day): score on fit to the slot's remaining allowance at 1.0 serve, repetition penalty (look-back window and per-cycle cap), protein-family penalty once the family's count is met, dislike penalty, batch bonus, favourite bonus. Seeded shuffle of ties, then recipe id.
6. Fit serving multipliers per day by exact enumeration over 0.25 steps in [0.5, 2.0] for each filled slot, minimising the worst normalised deviation across energy, protein, carbohydrate and fat plus a tenth of their sum, protein under-shoot weighted double; prefer 1.0 on ties. This is small enough to brute force (a five-slot day is 16,807 combinations) and needs no solver library. Note in your plan that `highs` (MIT, wasm) is the fallback if slots ever hold several recipes.
7. Fall back to recipe profiles (High protein, Low fat, Higher fibre, Lighter) one slot at a time where a day is still outside the accept band; keep the change only if the score improves.
8. Repair: replace the worst unlocked slot with the next candidate and re-fit, to a fixed iteration cap. Leave a slot `empty` with a reason rather than fill it badly.
9. Roll up through P2 and compare at the right cadence (daily for energy and protein; weekly for the rest).
10. Report and suggest. The report lists per day and per nutrient the deviation and band; each rule met, relaxed or unenforceable with the count that caused it; multipliers outside 0.75 to 1.5 flagged; and up to five ranked suggestions, never applied, each with its effect on the day. Suggestion kinds: serving change on one meal; ingredient swap within a swap group ("beef mince to chicken mince, fat −9 g"); ingredient top-up from the adjustable roles ("add 60 g quinoa to the salad, +220 kcal"); cook-extra leftover ("cook 300 g extra mince Monday for Wednesday"); cross-day protein top-up ("extra 100 g chicken into Tuesday's salad, +31 g protein"); profile switch. Suggestions come from the swap groups, roles and `packages/adjust`; they are deterministic, not model-generated.

Tolerances (policy, to confirm with a dietitian; the research found no published standard): energy ±10 % daily (±5 % shown as stretch), protein never below target daily and up to +15 %, carbohydrate and fat ±10 % daily and within AMDR on the weekly average, fibre and saturated fat and micronutrients on the weekly average, about one discretionary serve a day once the tag exists. Energy share per slot is a soft default.

Acceptance fixtures, written first and agreed with us: a 7-day plan from a 20-recipe fixture pool meeting spread and repetition; a client with a peanut block never receives a peanut recipe, including via leftovers and after every edit; a disliked main ingredient is excluded; an unreachable protein target returns a plan plus the pre-check message; same seed reproduces the identical plan and report byte for byte; working totals equal roll-up totals; a small-pool run declares degraded mode and names the relaxed rules. Accuracy bands (share of days inside ±10 % energy, 100 % at or above protein) are measured and shown on the pool-health screen from day one and become pass/fail only once the pool passes about 100 tagged, verified recipes.

### P4 — Edit operations (deterministic tools the UI and AI share)

Each takes a plan, returns a diff plus a fresh report, is logged to `plan_edits`, and by default re-fits the affected day's multipliers (visible toggle): `swapInSlot` (ranked alternatives with their effect on the day), `swapEverywhere`, `nudgePlan` (percentage or absolute on energy or protein, plan or day), `fixDay`, `applyDislike` (writes to the profile, refills affected slots, reports the variety cost), `applySuggestion(id)`, `lock`/`unlock`, `moveSlot`, `markLeftover`, `addTopUp`, `setFreeChoice`, `regenerate(seed+1)` (locks held), `regenerateExcluding(recipeIds)`. Nothing writes to a confirmed or sent plan without unconfirming it first, with a log row.

### P5 — Sign-off and AI layer

- **Sign-off**: `confirmPlan(plan_id, notes)` requires a dietitian or admin role, stores notes, confirmer and time, freezes the plan snapshot; `sendPlan` requires confirmed. The client export (PDF, shopping list) reads the frozen snapshot and the notes.
- **AI edge function** (Claude API, key as a server secret): tools are read-only plus the P4 operations in propose mode: client overview, screen, roll-up, generator, pre-check, the edit operations (returning diffs, never applying), swap candidates, swap suggestions, the adjust solver.
  - Front line second pass: when a plan is generated or edited, the explainer reads the report and writes two short registers, dietitian (rules and numbers) and client (why the week looks like this, what to do when life intervenes). It restates nothing that is not in the report.
  - Translator: free-text brief or request to a settings object or an operation list, echoed back for confirmation before anything runs. Grammar-first with `parseTargetRequest`; the model only when the grammar fails.
  - Strategist: chains operations ("make Tuesday lighter and move the salmon to Thursday") into individually approvable diffs.
  - Refusals: clinical judgement, overriding a blocked allergen, anything outside the tools; logged with the reason.
  - `ai_requests` log: who, client, plan id, report hash, text, interpretation, tools called, proposal, accepted, latency, cost, model version.
  Report: system prompt, tool schemas, 10 test conversations with logged tool calls including three refusals.

### P6 — Lovable handoff

Write the Lovable prompt: pool-health panel before generation (eligible recipes per slot after the screen, maximum achievable energy and protein, rules that will degrade); Generate on the client; plan grid with per-day totals against the day-type target and multipliers visible per meal; the report as a checklist (met, relaxed, unenforceable) with the suggestion list and Apply per item; swap picker with ranked alternatives and their effect; lock, move, leftover and top-up controls; nudge slider; Claude panel with the two registers and approvable diffs; dietitian notes and Confirm, then Send; edit log; client export in Australian household measures with a shopping list and pantry check-off. Include the typed-request grammar fix already drafted. QA script required.

## Report back first

Your plan, divergences and risks (the servings type change, pool size, meal-type confidence thresholds, the exact-enumeration bound if slots grow, model cost and latency), the gate order, and what you need from the team. For P0, send the two review CSVs as soon as they exist; the dietitians can work on them while the AUSNUT pass finishes.
