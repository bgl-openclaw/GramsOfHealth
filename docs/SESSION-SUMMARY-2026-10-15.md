# Grams of Health — session summary (13–15 Oct 2026)

Everything built in this Claude Code session, the current state, and what is still open.
Written to hand to another Claude. Verify live before trusting any count — the team works in the app daily.

---

## 0. Where everything lives

| What | Where |
|---|---|
| Database (live) | Supabase project **`xtbjbaliyrswleggezkm`** ("Recipe Builder", Sydney). The only project the Supabase MCP sees. Never touch MyTenure `uvftrmdtoufyfgkcfqny`. |
| Front-end | Lovable project **"Grams Editor"** `7b5c1c56-b6a0-432e-a803-5611a11fc39e`, published at https://grams-recipe-editor.lovable.app. TanStack Start + React. Latest commit at time of writing: `45163e34`. |
| Repo (canonical backend) | https://github.com/bgl-openclaw/GramsOfHealth.git — `supabase/migrations/`, `packages/engine` (untouchable), `packages/adjust`, `packages/energy`, `tests/`, `scripts/`, `docs/`. Latest: see `git log`. |
| Lovable prompts sent this session | `docs/lovable-prompts/*.txt` (C4a, C4a.1, C4b, C4c, N1, F1, E1) + `docs/lovable-build-checklist.md` (P4, P5). |
| Backend contract for the client module | `docs/clients-contract.md` |
| Orientation for the next session | `HANDOVER.md` (repo root; top block points here) |

**Working rules the owner expects:** plan first → build on explicit "go" → report with real numbers. Destructive DB changes only after showing exact rows and getting a go, with a snapshot in `seed/archive/`. Never trust Lovable's self-report — read the code at its commit. Machines never set `verified = true`. No auto-tagging of foods. Engine (`packages/engine`, and its tests: Lentil Tuna Salad 369 kcal, Salmon Fish Cakes 226 — `npm run verify` reads the SEED CSVs, not the live DB) is never changed by feature work.

---

## 1. Live numbers (15 Oct 2026, end of session)

| | |
|---|---|
| Recipes | 374 · **AI Verified 26** (was 19 at start; peaked at 31, then 5 dropped in U1 because they relied on estimated weights) · Dietitian Verified 0 |
| Foods | 517 (includes a stray test food "aaa test" — delete it) · 311 verified · 15 with a default size · 1 with a protein family (the test food) |
| Ingredient lines | 3,211 · **197 can't be weighed** (was 413) |
| Recipes with a `data_issue` note | 21 |
| Clients | 1 real client · 2 target rows |
| Change log | 38 entries · 8 unreviewed (the 8 density fixes) |
| Staff | 6, all `admin` |
| Tests | `npm test` 42 green (engine 10, adjust 16, energy 16) + SQL tests in `tests/sql/` (all pass, all self-rolling-back) |

---

## 2. What was built (in order)

### 2.1 AI Verified badge + dietitian sign-off — migrations 0023, 0023b
- View **`recipe_verification`** (derived, never stored): `status` = `needs_review | ai_verified | dietitian_verified`, `reasons text[]` in plain words ("2 unverified foods: Salt; Water", "3 ingredients can't be calculated: Carrot (each)…", "no image", "data issue flagged: …"). Names capped at 5 with "+N more", semicolon-separated (AFCD names contain commas).
- AI Verified = title + image + ≥1 ingredient + ≥1 method step + every food verified + every line resolves to grams + no `data_issue`. "Untitled recipe" counts as no title.
- Dietitian sign-off: table **`recipe_signoffs`** (append-only history), written only through RPCs **`sign_off_recipe`** / **`revoke_recipe_signoff`** by a signed-in admin/dietitian (guard trigger refuses machine inserts). Sign-off is only allowed on an AI Verified recipe; if the recipe later breaks it shows Needs review with `signoff_on_hold`. Status is computed at read time (the editor's save deletes and re-inserts lines, so write-time triggers would wipe sign-offs).
- Lovable: badges in library + editor, reasons popover, sign-off / remove-sign-off, "Mark data issue resolved", Dirty-tracking fixes (commits `c821d2b9`, `07fe5e38`, `14f12183`).

### 2.2 Sizes — eggs, default sizes, Lamb Kofta — migrations 0024, 0025
- Owner rule: an egg written "each" = **large** (whole 51 g, yolk 16 g).
- **`foods.default_size`**: the size a recipe's "each" means. Triggers keep the food's `each` conversion equal to that size's grams (follow edits; clear on delete/manual edit; refuse invalid). Lovable food page has a Default size dropdown + "Make this the default size" on new sizes; review-queue SizeFix sets the default (commit `b3145300`).
- **The team has since set defaults** on 13 foods (medium: avocado, banana, brown onion, capsicum, green capsicum, carrot, chicken breast & thigh, cucumber, eggplant, leek, pear, zucchini) + eggs large, and removed Rocket's placeholder "large = 180 g".
- LAMB KOFTA WRAPS: egg line changed small → regular (owner request).

### 2.3 Clients module (roadmap C0–C5) — migrations 0026–0031, 0033, 0034
Owner decisions: interns are allocated per client (separate tick for check-ins), may edit allocated clients except targets / team access / delete / clinical; dislike "main ingredient only" = ≥10% of recipe weight; protein families live on foods (dietitian-set); repetition = both "not within N days" and "max N per cycle", batch cooking allows next-day leftovers; check-ins use 1–5 scales + Bristol 1–7 + open `answers` jsonb for the future check-in build; goals are an editable list (incl. Performance) with one primary.
- **C0 access (0026):** roles `admin | dietitian | intern | pending`; helpers `is_clinician`, `is_staff`, `can_access_client`, `can_view_checkins`, `can_access_plan`; table `client_staff_access`; clients / meal plans no longer open to pending users.
- **C1 schema (0027):** client identity fields; lookups `activity_levels`, `goal_types`, `protein_families`, `tag_blockers` (diet → blocked "contains" tags, replacing Lovable's hard-coded list); `client_goals`, `client_weights`, `client_checkins`, `client_targets` (append-only history) + view `client_current_targets`, `client_requirements` (tags) + views `client_blocked_tags` / `client_preferred_tags`, `client_food_rules`, `client_protein_preferences`, `client_supplements`, `client_structure`, `client_meal_slots`, `client_protein_spread`, `client_clinical_records` + private bucket **`clinical-records`** (clinician-only). `foods.protein_family`.
- **0028:** security-advisor fixes (pinned search paths; anon can't call admin RPCs).
- **C2 calculator (0029 + `packages/energy`):** Mifflin–St Jeor `estimateEnergy` (BMR, TDEE, nearest-10 display, protein g/kg, full working with dates, warnings for stale weight / under 18 / no activity; missing inputs → no result, message names them). The roadmap's 5 fixtures pass exactly. RPC `client_energy_inputs(client, as_of)` gathers inputs; logic lives only in TS. Lovable keeps a **byte-identical** copy at `src/lib/energy.ts` (verified).
- **C3 contract (0030, 0031):** `line_grams` (SQL replica of the engine's grams — `scripts/check-line-grams.ts` proves parity on every live line), `recipe_protein_families`, **`client_recipe_screen(client)`** → `blocked > unconfirmed > disliked > ok` with reasons (allergy screen only trusts verified ingredients), `save_client_structure` (one transaction), `client_overview`. 0031 fixed a badge bug: density 0 counted as usable.
- **C4 (Lovable):** full client editor — Identity, Goals, Weight log, Targets (4 day types, history, calculator with "Accept" saving its working), Requirements (tag chips + recipe-fit summary), Preferences (food avoid/dislike, protein likes, supplements), Variety & structure, Team access, Clinical (files via 5-minute signed links), Check-ins (timeline, trend strip, weight → weight log), Plans; clients list from `client_overview`; plan editor + print + recipe picker switched to new targets and screening badges; library "Suitable for" reads `tag_blockers`; intern role in Users/Invite (commits `c9fa38cb`, `f7c81341`, `640a15d9`, `c4e42391`, `d93b68a1`). 0033: meal slot names required.
- **C5 (0034):** dropped `clients.kcal_target / protein_target_g / carb_target_g / fat_target_g / fibre_target_g / restrictions` (owner go; snapshot `seed/archive/clients_legacy_targets_snapshot.csv`, ids + values only).

### 2.4 "Nothing changes silently" — migration 0032 + Lovable N1
- **`change_log`** written by triggers on foods, unit conversions and food tags (who / when / old → new in plain words; deleting a food logs one entry). View `changes_to_review`, RPC `mark_changes_reviewed` (clinicians).
- Rule: a **verified food whose kcal/protein/fat/carbs/fibre per 100 g, density, or allergen/diet tags change becomes unverified** (never the reverse).
- Lovable N1 (`6e41b6ba`): "Changes" menu with count badge, `/changes` inbox, per-food change history, warning on verified foods, recipe-editor notes (red "can't be weighed").

### 2.5 Food page save modes — Lovable F1 (`adae9f77`, `45163e34`)
- "Save draft" (does not verify) and "Save & verify" (saves, then verifies in a second step so the un-verify rule can't undo it). Anyone may verify (owner decision).
- **Open:** follow-up `45163e34` makes Save draft un-verify on ANY change (name, aisle, sodium…), stricter than the database rule. Recommended: revert to the database rule (prompt "F1.1" in the conversation). Owner hasn't chosen yet.

### 2.6 Engine guessing removed — Lovable E1 (`9c5f000b`)
- Lovable's `engine.ts` had (since Aug) a hidden fallback: "each" → medium → large → small. Removed. **The app now calculates grams exactly like the database on all 3,211 lines** (checked by running Lovable's code against `line_grams`).

### 2.7 Impossible food values — migration 0035
- Root cause of the old "negative-calorie cheesecake": **Light Cream Cheese density −9** (½ cup = −1,125 g). 8 verified foods had density ≤ 0; cleared and auto-unverified (they're the 8 items in the Changes inbox). New guards: density blank or > 0, per-100 g macros ≥ 0, conversion grams > 0.

### 2.8 Recipe units (U1) — migration 0036 + Lovable prompt `docs/lovable-prompts/U1-recipe-units.txt`
- Owner: "remove kg" · estimated weights → Needs review · add "Buy as".
- **kg retired**: the 5 "1 kg" lines are now "1000 g" (no number changed); the app stops offering kg.
- **Estimated weights**: 88 conversions were import placeholders (61 × "each = 100 g", e.g. ¼ watermelon = 25 g). `unit_conversions.estimated` flags them; a line weighed through one adds the reason "uses an estimated weight" (109 recipes; AI Verified 31 → 26). Typing new grams or pressing Confirm clears it (logged). Default-size "each" copies its size's flag.
- **Unit names** stored trimmed/lower-case; g/gram/grams/kg refused as measure names; 10 untidy names renamed (none used in recipes).
- **Buy as** (`foods.purchase_unit`): shopping list counts the food in that measure, rounded up. Backfilled on 37 obvious foods (whole produce with a default size, herb bunches, punnets, cans, pouches, packets) — logged in the Changes inbox.
- Lovable U1 (pending): dropdown shows only measures that weigh something (carrot: sizes + g; olive oil: spoons/cups/mL), grams shown in each option, estimate notes + Confirm, add-size popup no longer treats mL as water, Buy as on the food page and shopping list.
- Dietitian work list: `docs/units-review.csv` (re-run `npx tsx scripts/units-review.ts`). Tests: `tests/sql/recipe_units_u1.test.sql` (all pass); parity 3,211 lines, 0 mismatches.

### 2.9 Measure suggestions (U1.1) — Lovable `bd823678`
- Visible suggestion chips (no typing needed, hide measures the food already has) in the "+" add-size popup and the food page; clear "Enter a measure name / weight" messages instead of silent Save; Buy as hint wording fixed. Verified in code; engine untouched.

### 2.10 Plans P1 for full clients (21 Oct) — migration 0037 + Lovable prompt `docs/lovable-prompts/P1-plans-dates-slots-publish.txt`
- Owner: publishing allowed with Needs-review recipes (warning names them; recorded on the version); start date required to publish a client plan. P2 (fitness-challenge templates/bulk) later.
- Quarter serves (`servings_override` numeric, 0.25 steps — half serves previously couldn't be saved).
- `meal_plans.start_date`, `status` draft|published; `meal_plan_days` (day-type overrides); `plan_days()` (date, weekday, day type from override › client's Mon–Sun pattern › default, and that day's targets — falls back to Default targets and says so); `plan_slots()` (client's own slots, default four otherwise, plus orphan item slots).
- `meal_plan_versions` append-only: app builds the snapshot, `publish_meal_plan` checks it matches the saved plan (items, serves, days, day types), records Needs-review recipes, locks the plan; `start_new_plan_version` reopens. Published booklets/shopping lists render from the snapshot only.
- Tests: `tests/sql/plans_p1.test.sql` (11 checks, all pass live); `npm test` 42 green.

### 2.11 Client app P0 — security lockdown (21 Oct) — migration 0038
- Owner: one build window (this one) for the client app; the original backend window stood down.
- The 13 library tables (recipes, lines, steps, foods, conversions, tags, food tags, overrides, profiles/deltas, swaps, exclusions, legacy recipe_tags) → staff-only read/write; AFCD → staff read-only. Profiles: own row or staff. Recipe sign-offs: staff read. Recipe photos: public read, staff-only writes. Role `client` added.
- Test `tests/sql/p0_lockdown.test.sql`: every role × every table (staff unchanged; pending/client see and change nothing).
- Owner still to do (Supabase dashboard): rotate DB password + service-role key; leaked-password protection. Old test login already gone.

### 2.12 Client app P1a — accounts + client read surface (21 Oct) — migrations 0039, 0039b + Lovable prompt `docs/lovable-prompts/P1a-client-area.txt`
- Owner: client area inside the same app; dietitians/admins invite, link and allow numbers; numbers on both sides (dietitian allows → client chooses); copy-and-send invite links; "Request a change" → assigned dietitian, fallback info@gramsofhealth.com; Lovable designs it warm and on brand. Subdomain can come later (decide before P1b).
- `app_settings` (practice name/email, timezone, client_contact). `clients.user_id / numbers_allowed / client_shows_numbers` with a guard trigger. Client invites (role client + client_id) — accepting REQUIRES the invite token (email confirmation is off, so email matching alone would be unsafe); staff invites unchanged. Self-registration (`account_type: client`) → unlinked client account; dietitian links it.
- Staff RPCs: invite_client_to_app, link_client_account, unlink_client_account, client_app_status, client_app_signups. Client RPCs (the only things a client can read): my_details, my_plans, my_plan_version (published snapshots; calories/macros/targets stripped in the database unless allowed AND chosen), set_my_show_numbers.
- 0039b: the app's invite page sends `invitation_token` — both keys now accepted.
- Test `tests/sql/client_accounts_p1a.test.sql` (8 checks, all pass live).
- Next: P1b (magic link, Google, emailed invites via Resend, email confirmation on — needs owner setup + final domain), P1c (pre-filled intake sheet → dietitian review; HighLevel later).

---

## 3. Open items

**Owner decisions pending**
- F1.1: un-verify only on calorie-relevant changes (recommended) vs on any change.
- Clients seeing calories/macros in the future client app — parked.

**For the dietitian (via the app)**
- Re-check + enter real densities for the 8 foods in the Changes inbox (light cream cheese, honey mustard dressing, lime juice, apple cider vinegar, balsamic glaze, lactose-free milk, low fat mayo, red curry paste), then Save & verify.
- Default sizes still needed: Iceberg lettuce ("medium head"), Celery ("medium stalk"). Rocket: 4 recipes use "2 large" with no weight now.
- Verify the high-leverage foods (Salt, Soy sauce, Water, Oregano, Tomato, Paprika, Pepper, Tomato paste, Sugar, Rice wine vinegar…).
- Suspect placeholder sizes "large = 180 g" (wraps, peach, orange, stalk celery, prawn dumpling); capsicum vs red-capsicum sizes disagree; pear has "large" and "Large"; mismatched "each" weights (red onion 110 g, Lebanese cucumber 130 g, …); 97 spoon/cup lines with no density; pack sizes with no weight (x400g, x250g …); import leftovers (Sake Small Pinch Salt And Pepper, Sesame Seed Tomato, Powder, Protein Electrolyte); 6 incomplete recipes; 21 `data_issue` notes to review and "Mark resolved". (Full list was written as a message to the dietitian.)
- Protein family is set on 0 real foods — needed before protein preferences/spread mean anything.
- Delete the test food "aaa test".

**Security (owner: "at the end")**
- Rotate the Supabase DB password and service-role key (both exposed in an old chat; key is in gitignored `.env`). Delete auth user `goh.codetest@gmail.com`. Turn on leaked-password protection (Supabase → Auth).
- **Recommended soon, independent of white-label:** recipes, foods, conversions, tags, AFCD and ~13 other tables still allow any signed-in account (including `pending`) full read/write through the API. A small migration can restrict them to staff.

**Deferred by owner**
- **Foundation / white-label** (organisations, per-practice data, branding, onboarding): plan written (phases T1–T4, 5 decisions) but parked until Grams of Health itself is further along.
- **Client app** (phone-friendly web app first, App Store wrap later): after Foundation.

---

## 4. How to check things quickly
- Badge / reasons: `select status, reasons from recipe_verification where title = '…'`
- Unweighable lines: `select * from line_grams where grams is null`
- Engine parity (repo root): `npx tsx scripts/check-line-grams.ts` → expect 0 mismatches.
- SQL tests: paste any `tests/sql/*.test.sql` into the Supabase SQL editor — each ends with `ALL PASS (rolled back)` and changes nothing.
- Lovable: `get_project` → latest commit, then `get_diff` / `read_file` at that commit. Never rely on Lovable's own report.
