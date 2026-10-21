# Grams of Health: combined roadmap (22 October 2026)

One roadmap from four sources:
- the owner's **build roadmap and specs** (21 Oct, four stages; `docs/sources/build-roadmap-and-specs-2026-10-21.md`)
- the **AI roadmap v1** (15 Oct; `docs/AI-ROADMAP.md`)
- the **meal plans + AI layer roadmap rev 2** with its research (21 Oct; `docs/sources/plans-ai-roadmap-rev2-2026-10-21.md`, `docs/sources/research-meal-plan-generation-2026-10-21.md`)
- my report back (`docs/PLANS-AI-REV2-PLAN.md`)

**How they fit.** The four stages and gates of the build roadmap are the backbone and stay as written:
1. Polish
2. Working app
3. Client app
4. SaaS

Rev 2 replaces the detail of the build roadmap's 2A (plan model), 2B (generator and edit tools) and AI-5 (plan co-pilot), because it is newer and research-backed. AI-0 to AI-4 are the same items in the v1 AI roadmap and the build roadmap. AI-6 and the client assistant stay as the build roadmap has them. Stages 3 and 4 are unchanged.

## 1. Where we actually are (22 Oct)

| Roadmap item | State |
|---|---|
| 1E.1 staff-only library tables | **Done** (0038), leak-tested |
| 1E.2 password reset, leaked-password protection | **Done**. Still open: retire the legacy anon/service-role keys (K1 prompt) |
| 1C.6 per-client "show numbers" | **Done** (clients.numbers_allowed / client_shows_numbers) |
| 1D.1 P1 backend on GitHub | **Pushed** to branch `recipe-units-and-plans-p1`, 13 commits ahead of `main` and not merged. A pull request would make `main` canonical |
| C0 client accounts, invites, self sign-up, intake; client-questions editor | **Done** (0039, 0040, 0044; Lovable built) |
| Staff profiles and credentials (not in any roadmap; closest to 2D.9 and T6) | **Phase 1 done** (0045 + Lovable). Phase 2: CPD log and email reminders, after Resend (2F) |
| 1A.1 and 1A.2 verification, measures, estimates | **AUSNUT rev 3 built and dry-run**, awaiting the dietitian's review. Projection: 26 → about 201 usable recipes |
| 1A.3 protein families | Inside the AUSNUT changeset (86 of 98 adjustable proteins); in the dietitian's review |
| 1A.4 meal types | **First pass done**: all 374 recipes in the dietitian's review list; classifier is draft 0046 |
| Swap groups (rev 2 suggestions) | **Drafted**: 45 groups, 382 rows, in the dietitian's review |
| 1B.1 energy-vs-macro check | Not built. The swap-group draft found **40 foods with suspect values** (e.g. haloumi 1,050 kcal, egg white 197 kcal, high-protein pasta 505 g carbs) |
| 2A plan model | **P1b live** (0047, applied 22 Oct, gate C): food items, top-ups, item ingredient changes, leftovers, slot states, alternatives behind Swap, release dates, generator runs, confirm with notes, edit log, slot energy shares. Lovable screens next |
| 2A.7 rollupPlan | **Built** (`packages/rollup`, 11 tests) |
| Supabase region (decision 15) | **Confirmed Sydney** (ap-southeast-2) |

## 2. Where the documents disagree (owner to settle)

| # | Topic | Build roadmap | Rev 2 / live / owner decisions | Recommendation |
|---|---|---|---|---|
| 1 | Interns | 2D.8: intern edits go to the supervising dietitian; interns never approve AI diffs | Owner, 21 Oct: interns can confirm and publish plans | Keep the 21 Oct decision for plans. Decide separately whether interns may approve AI diffs and see AI-3 summaries (build-roadmap decision 10) |
| 2 | Disliked recipes | 2B.1: excluded | Rev 2: penalised, used only when the pool is thin, and listed in the report | Penalise while pools are small; switch to exclude per client if wanted |
| 3 | Plan status | 2A.4: draft, active, archived | Live: draft → published (sealed version), plus confirm-with-notes once there's a generator report | Keep the live model; add archived later |
| 4 | Options per slot | 2A.6: 2–3 alternatives per slot, each within tolerance; the client flips them (C1, C4 bounded swaps) | Not in rev 2 | **Keep.** Add an "option of" link on plan items to 0047 **before** gate C, so Stage 3's bounded swaps don't need another plan-model change |
| 5 | Release date | 2B.6: a generated plan has a release date; nothing reaches the client before it | Live: the client sees it as soon as it's published | **Add** an optional release date to publish in 0047 (the client sees the version from that date) |
| 6 | Lunch eligibility | Decision 4: lunch slots accept lunch or dinner recipes by default | Meal-type list marks many cooked mains dinner-only | **Adopt** as a practice setting, on by default, so dinner-only mains still fill lunch |
| 7 | Readiness bars | Gate 2: pool 120 (25 breakfast / 30 lunch / 40 dinner / 20 snack) | Rev 2: accuracy is pass/fail only from about 100 tagged, verified recipes | Use the build roadmap's bars, which already cover rev 2's 100 |
| 8 | AI log table | `ai_requests` | v1 called it `ai_runs` | One table, `ai_requests` |
| 9 | Swapping a recipe | 2B.10: the solver re-fits the incoming recipe to the slot | Rev 2: every edit re-fits the day's serves | Both: re-fit serves first, then the adjust solver if serves alone can't land the day |
| 10 | Typed requests | AI-5: "grammar first (parseTargetRequest)" | Two copies have drifted (repo and app); both miss "increase protein by 10", "40 g protein", "at least 30 g protein", "less fat", "under 500 calories" | One shared grammar in `packages/adjust`, copied to the app with parity tests (item G below). No drafted fix existed |

## 3. The order from here

### Stage 1, Polish (remaining)

| # | Item | Who | Depends on |
|---|---|---|---|
| D1 | Dietitian review pack: AUSNUT, meal types, swap groups, planner rules (`docs/DIETITIAN-REVIEW-PACK.md`) | Dietitian | — |
| D2 | Apply AUSNUT (G1 → G4c) and fold in the review | Me, then owner check | D1 (AUSNUT part) |
| D3 | Load meal types (0046) and the 12 protein-family leftovers; pool report per slot | Me | D1, D2 |
| D4 | Fix the 40 suspect food values; build **1B.1** (energy-vs-macro check on every food save) so new ones can't appear | Dietitian + me | D1 |
| G | One shared typed-request grammar (repo + app, parity tests) | Me + Lovable | — |
| S1 | 1E remaining: retire legacy keys (K1), staff two-factor (1E.3), clinical access log (1E.4), staging branch + CI (1E.5), restore test (1E.6), monitoring (1E.7) | Me + owner (keys) | — |
| P | 1D.3 to 1D.5: publish warnings, shopping list by date range, booklet numbers and kJ | Me + Lovable | — |
| M | Merge the branch into `main` (pull request) | Owner's go | — |

**Gate 1** stays as written: pool at the Gate 1 bar, 1E closed, P1 front end live, every dietitian has used the tool on a real client.

### Stage 2, Working app

Plans (rev 2 replaces 2A/2B):

| Gate | Work | Depends on |
|---|---|---|
| **C** | **Done 22 Oct**: 0047 live with alternatives and release dates; Lovable prompt P1b for the screens | — |
| **D** | P3 generator in a `planner` Edge Function: pre-check, beam search, exact serve fitting, profile fallback, repair, report with suggestions. Acceptance fixtures agreed first | C; D2–D3 for useful plans |
| **E** | P4 edit tools (swap with ranked options, nudge, fix day, dislike, lock, move, leftover, top-up, free choice, regenerate) + Lovable plan board (2B.9) | D |
| **F** | AI-0 groundwork, then the P5 co-pilot (AI-5): grammar first, Translator, Strategist, Explainer (dietitian and client wording), Refusals, `ai_requests` | D, E; API key; consent 2D.7 for client data |

AI (build roadmap 2E, unchanged):
- **AI-0 straight after gate C.** AI-1 and AI-2 speed up verification, so they come early in Stage 2.
- AI-1 label reader, AI-2 recipe import: no client data, so no consent needed.
- AI-3 consult transcripts, AI-4 clinical documents, AI-6 check-in briefs: after 2D.7 consent.

The rest of Stage 2 is unchanged: 2C templates and groups, 2D intake/notes/documents (the client-questions editor already covers part of 2D.1), 2F Cliniko, Fireflies and Resend (Resend unblocks staff-credential email reminders), and 2G.

**Gate 2** stays as written: ten real plans generated, edited and published with the report; AI-0 to AI-2 live; consent in place.

### Stages 3 and 4

Unchanged from the build roadmap. The plan model work in gate C (options per slot, release date, slot states, food items) is what C1 and C4 need, which is why items 4 and 5 above are worth adding now.

## 4. Owner answers (22 Oct 2026)

1. **Options per slot and release date: yes**, with the plan looking set. One recipe per slot is shown, and alternatives stay behind Swap and are used only if needed. Both are now in draft 0047 (`option_of`, `release_on`) and dry-run; the roll-up ignores alternatives.
2. **Lunch eligibility: yes.** Lunch slots also take dinner recipes (a planner setting, on by default).
3. **Disliked recipes: always excluded**, like blocked ones. This overrides rev 2's "penalise". A thin pool shows up in the report's pre-check instead.
4. **Interns: yes.** Interns may approve AI suggestions and see AI-3 consult summaries for clients they are allocated to.
5. **Merge to `main`: yes.** A pull request is open.

Dietitian answers are collected on live pages Claude reads back:
- AUSNUT: https://claude.ai/artifact/JNqBi3w2f8WE5MNpAog2Hn
- Planner set-up (rules, meal types, swap groups): https://claude.ai/artifact/6KzWBgS79BtL1FueRJ9e5z

## 5. Decisions still open (from the build roadmap)

   - F1.1 (un-verify only on calorie changes)
   - readiness bars (Nikki)
   - energy bands
   - private-notes scope
   - transcript retention
   - Cliniko as the booking system
   - the FoodWorks price check
