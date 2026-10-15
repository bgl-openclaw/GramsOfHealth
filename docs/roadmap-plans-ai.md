# Grams of Health — Meal plans & AI: combined roadmap (draft v1)

_15 Oct 2026. Merges "Claude Code — Meal plans and the AI layer" (the plans roadmap) with Claude Code's AI-features proposal from the same day. Status: **draft for the owner's review — nothing here is approved or built.**_

---

## 1. Outcome

**For dietitians, today's practice:** open a client, press **Generate**, and within seconds get a draft plan built only from verified recipes — screened against the client's requirements and dislikes, spread across protein families, respecting repetition and meal structure, fitted to each day type's targets. The dietitian rearranges, swaps and nudges; every number comes from the engine. An AI panel takes plain-English requests ("Tuesday's short on protein and she hates mushrooms") and returns approvable diffs. Nothing applies until the dietitian accepts.

**Around that, AI assistants that remove grunt work:** reading food labels into draft foods, summarising check-ins before a consult, pulling blood-test / DEXA values out of PDFs, cleaning up imported recipes. Later, a client-facing assistant in the client app.

The shape of every AI feature is the same: **AI proposes → the dietitian decides → the engine does the maths.**

---

## 2. The charter (fixed; applies to every phase and every AI feature)

1. **The engine is the only source of macro numbers.** The generator and the AI never compute macros themselves.
2. **Placement is deterministic code.** Same client, same pool, same seed → same plan. AI never places recipes directly; it calls the generator and solver as tools.
3. **AI translates and explains; it proposes, never applies.** Every AI output is a structured request echoed back, a proposal rendered as a diff, a draft record awaiting approval, or a plain refusal.
4. **AI never invents nutrition data, never sets clinical targets, never touches any verified flag,** never suggests a food that isn't in the foods table (`swap_suggestions` suggest-to-add rows excepted, shown as such). AI-extracted values (labels, blood tests) are drafts a human confirms.
5. **When the data can't support an answer, the AI says so and names what is missing** ("3 ingredients unverified, cannot confirm gluten-free").
6. **Every AI call is logged** — feature, who, client (if any), input, structured interpretation, tools called, proposal, accepted or not, latency, tokens, cost.
7. **Data minimisation.** The model sees only what the task needs: client id not name; never staff notes; clinical records only for the clinical-document feature. Client consent / privacy wording updated before any client data is sent (Stage 3).
8. **One server-side brain.** Generator, roll-up and AI run server-side (Supabase Edge Functions, TypeScript) from the repo's tested packages; the API key is a server secret, never in the browser. Lovable calls them; it doesn't re-implement them.

---

## 3. Live facts (verified 15 Oct 2026)

| Fact | Value | Why it matters |
|---|---|---|
| Recipes a generator may use (AI Verified or Dietitian Verified) | **31** of 374 | Plans will be thin until this grows |
| …of those with a meal-type tag | **12** | Slot fit needs meal types |
| All recipes with a meal-type tag | 72 — Breakfast 21 · Dinner 27 · **Lunch 5** · Snack 20 (tags in `recipe_tags`, source auto/manual) | Lunch is the weakest slot |
| Foods with a protein family | **1** (a test food) — 98 foods carry the `adjustable_protein` role | Protein spread can't work yet |
| `meal_plan_items.servings_override` | **integer** | 1.5 serves can't be stored |
| Plans | 5 (1 linked to a client) | Migration is low-risk |
| Built and tested | client module (screening, targets per day type, structure, slots, spread, food rules), `packages/adjust` (solver, `achievableRange`, `parseTargetRequest`), `packages/energy`, `line_grams` (engine parity 3,211/3,211), change log, AI Verified | Most building blocks exist |

---

## 4. How the two plans compared

| Area | Plans roadmap | Claude Code AI proposal | Combined |
|---|---|---|---|
| Who places recipes | **Deterministic generator; AI only calls it** | AI picks via tools | **Adopt the plans roadmap.** Reproducible, testable, explainable. |
| Plan model, roll-up, generator, edit ops | Detailed (P1–P4) | Not covered | Kept as the core (Stages 1–2) |
| Plan AI (translator / strategist / explainer / refusals) | Detailed (P5) | "Draft meal plans" | Kept (Stage 3) |
| Food label reader, recipe import & clean-up | — | Proposed | **Added to Stage 0** — they grow the verified pool, which is the generator's bottleneck |
| Check-in summaries, clinical-document reader | — (listed as "later" in the clients roadmap) | Proposed | Stage 4 |
| Client-app assistant | — | Proposed (later) | Stage 5 |
| Privacy / consent | — | Raised | Charter rule 7 |
| AI cost & evaluation | Log table | Cost table, logging | One `ai_requests` log for every feature + an eval set |

**Where Claude Code argues for a change to the plans roadmap**
1. **Grow the pool before building the generator's polish.** 31 recipes / 12 with meal types can't fill a 7-day plan with variety. Stage 0 attacks this with data work *and* the first AI feature (label reader → faster food verification).
2. **Lunch eligibility.** Only 5 recipes are tagged Lunch. Add a per-client (default practice-wide) slot-eligibility rule — e.g. lunch accepts Lunch **or** Dinner recipes; batch-cooked dinners naturally become next-day lunches.
3. **One implementation, server-side.** `rollupPlan`, the generator and edit operations live in `packages/planner`, run in an Edge Function; Lovable calls them (its existing engine copy still powers instant on-screen totals, parity-checked). Avoids a third copy of planning logic in the front end.
4. **AMDR bands are data, not code.** Store the bands (e.g. protein / fat / carbohydrate % of energy) in an editable table the dietitians confirm, rather than hard-coding them.
5. **"Suggested" lists stay suggestions.** Meal-type and protein-family CSVs are reviewed by dietitians; only confirmed rows load, and the change log records who confirmed them (consistent with "no auto-tagging").
6. **An eval set, not just 10 test conversations.** Turn the P5 test conversations (incl. refusals) into a re-runnable eval so every prompt or model change is measured.

---

## 5. The combined roadmap

Each stage stops with a report and needs an explicit **go**. Lovable builds screens only after the backend for that stage lands, from a prompt Claude Code writes and then verifies in code.

### Stage 0 — Safety, data and the AI foundation

| # | Item | Notes |
|---|---|---|
| 0.1 | **Staff-only access** on recipes, foods, conversions, tags, AFCD and the other open tables (any signed-in account, incl. `pending`, can currently write them via the API). Show the policies before applying. | Needed before any new AI write paths |
| 0.2 | **Meal-type suggestions** CSV for the 302 untagged recipes → dietitian review → load confirmed rows | Suggestion only |
| 0.3 | **Protein-family suggestions** CSV for the ~98 protein foods → review → load confirmed rows | Suggestion only |
| 0.4 | **AI foundation:** Edge Function scaffold, Claude API key as a Supabase secret, `ai_requests` log (feature, who, input, interpretation, tools, proposal, accepted, latency, tokens, cost), privacy wording draft | Reused by every AI feature |
| 0.5 | **AI #1 — Food label reader:** photo of a nutrition panel → structured per-100 g values, serving size, likely allergens → **draft, unverified** food for the dietitian to check and Save & verify | No client data; directly speeds up verification |
| Gate | **Pool coverage report:** pool size; pool recipes per slot kind; protein families set; foods verified | Repeated at every later gate |

**Ready bar (proposed) before Stage 2 can produce useful plans:** ≥ 60 pool recipes, with ≥ 12 breakfast, ≥ 12 lunch-eligible, ≥ 20 dinner, ≥ 10 snack options, and protein families on all protein foods.

### Stage 1 — Plan model and roll-up (plans roadmap P1 + P2)

- `servings_override` → numeric (UI snaps to 0.25).
- Item kinds: recipe (optional profile) **or** food + quantity + unit (snacks).
- Slot state: filled · free_choice (excluded from roll-up, never a shortfall) · empty.
- Leftovers: an item may reference the item it's cooked with — shopping and repetition count it once.
- Per-day day type on the plan (defaults from the client's weekly pattern).
- Plan fields: cycle length, status (draft / active / archived), origin (generated / manual), generator seed + settings snapshot, spare recipes.
- **`rollupPlan(plan)`** — per item, slot, day and week: engine numbers vs that day's targets, AMDR flags, plain-English shortfalls. Fixtures include a free-choice day and a leftover pair. The single truth for the UI, the generator's scoring and the AI's explanations.
- Report: migrations and how the 5 existing plans migrate.

### Stage 2 — Generator, edit operations, plan board (P3 + P4 + Lovable P6a)

- **`packages/planner` generator**, in order: pool (screened; disliked excluded; unconfirmed only if ticked, flagged) → protein variety across lunch/dinner → slot fit (with the eligibility rule) → repetition (incl. deliberate leftovers) → target fit (0.25-serve steps, then a recipe profile, else report — never distort) → score and explain (one-line reason per placement; unmet constraints with causes). Deterministic per seed; "Regenerate" changes the seed; written only on Save.
- **Acceptance fixtures (agreed before code):** 7-day plan from a 20-recipe fixture pool meeting spread and repetition; a peanut-blocked client never gets a peanut recipe; a disliked main ingredient is excluded; an infeasible spread returns the plan plus a clear unmet-constraint list; same seed → identical plan.
- **Edit operations** (return diffs, never write): `swapInSlot`, `nudgePlan`, `fixDay`, `applyDislike`.
- **Lovable (P6a):** Generate on the client; plan board with a per-day green zone; per-slot swap; nudge slider; leftovers / free-choice rendering; spare recipes; shopping list and export reading the new item kinds; QA script.

### Stage 3 — Plan AI co-pilot (P5 + Lovable P6b)

- One Edge Function; Claude with tool use over **read/propose-only** tools: client overview, recipe screen, roll-up, generator, the four edit operations, recipe solver, swap candidates and swap suggestions. **No tool writes.**
- **Grammar first:** the existing `parseTargetRequest` runs first; the model is called only when it fails.
- Modes: **Translator** (echo the structured request before anything runs) · **Strategist** (chained tool calls returned as individually approvable diffs) · **Explainer** (lookups in plain English) · **Refusals** (clinical judgement, unsupported data, anything outside the tools — naming what's missing).
- Report: system prompt, tool schemas, the eval set (≥ 10 conversations incl. 3 refusals) with logged tool calls, cost and latency.
- **Lovable (P6b):** AI panel — echo line, diffs with Approve per step, calm grey refusals.
- **Before go-live:** client consent / privacy wording updated (charter rule 7).

### Stage 4 — Clinical AI assistants

| # | Feature | Output | Notes |
|---|---|---|---|
| 4.1 | **Check-in summaries** | One-page brief before a consult: trends, flags, talking points | Weekly batch (50% cheaper) or on demand |
| 4.2 | **Clinical-document reader** | Blood-test / DEXA PDF → structured values into the clinical record, confirmed by the dietitian | Clinician-only, like the clinical section |
| 4.3 | **Recipe import & clean-up** | Paste text / PDF / link → draft recipe mapped to your foods in Australian measures; proposals for import leftovers into the Changes inbox | Can move earlier if the pool needs new recipes rather than verification |

### Stage 5 — Later

Client-app assistant (answers only from the client's plan and your library, escalates to the dietitian), automated nudges, and the parked Foundation / white-label work.

---

## 6. What the team needs to do (Stage 0 → before Stage 2 is useful)

1. Review the meal-type CSV (302 recipes) and the protein-family CSV (~98 foods).
2. Keep verifying foods — the high-leverage list: Salt, Soy sauce, Water, Oregano, Tomato, Paprika, Pepper, Tomato paste, Sugar, Rice wine vinegar…; the 8 foods in the Changes inbox; defaults for iceberg lettuce and celery.
3. Review the 21 `data_issue` notes ("Mark resolved").
4. Confirm the AMDR bands and per-slot energy shares the generator should use.
5. Approve updated privacy / consent wording before Stage 3 goes live.

---

## 7. Risks

| Risk | Mitigation |
|---|---|
| Pool too small → thin, repetitive plans | Stage 0 ready bar; pool report at every gate; generator reports unmet constraints instead of bending rules |
| Protein families / meal types not set | CSV review in Stage 0; generator degrades gracefully (variety step skipped, flagged) |
| `servings_override` type change | 5 plans only; migrate in place; Lovable updated in the same stage |
| AI misreads a request | Translator echo before anything runs; diffs need approval; grammar first |
| AI overreach (clinical advice, invented data) | Read/propose-only tools; refusal rules; eval set re-run on every change |
| Health data sent overseas | Data minimisation; consent wording; ask Anthropic about data-retention options |
| Cost / latency | Logged per call; prompt caching; batch for summaries; grammar-first avoids most model calls |
| Third copy of planning logic in the front end | Server-side `packages/planner` (charter rule 8) |

---

## 8. Cost (rough; measured for real once Stage 0 ships)

Claude Opus 5.5 at $4 / $20 per million input / output tokens; prompt-cache reads ≈ 10% of input; Batch API 50% off. For ~100 active clients: food labels ≈ $5 one-off; plan AI (most requests answered by the grammar, the rest a few tool calls) ≈ $20–40 / month; check-in summaries ≈ $10–20 / month; clinical PDFs ≈ $3 / month; client assistant later ≈ $50 / month. **Total ≈ $50–150 / month** — tracked per feature in `ai_requests`.

---

## 9. Decisions needed from the owner

1. Adopt this combined roadmap (stage order, charter) — or adjust?
2. The Stage 0 ready bar (≥ 60 pool recipes etc.) — accept, or set your own numbers?
3. Lunch eligibility: lunch slots accept Lunch **or** Dinner recipes by default?
4. Start Stage 0 with 0.1 (staff-only access) immediately?
