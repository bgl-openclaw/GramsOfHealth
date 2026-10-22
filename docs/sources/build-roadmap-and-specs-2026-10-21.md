# Grams of Health: build roadmap and companion documents

21 October 2026. Four documents in one file. Suggested filing in the repo: docs/build-roadmap.md, docs/competitor-foodzilla-d2.md, docs/forms-spec.md, docs/platform-spec.md.

---

# Grams of Health build roadmap

21 October 2026 · Ben Leghissa

From today's internal staff tool to a client app and then a multi-practice product, in four stages with a gate between each. It builds on the 21 October product brief, the repo's 15 October roadmap and the three Foodzilla research rounds. Every item keeps the eight principles in the brief: numbers from grams, human verification, AI that proposes, nothing silent, Australian first, the dietitian first.

## Where we are

The foundations are unusually strong for a product this young, and the content pool is unusually thin. Every one of 3,211 ingredient lines computes identically in the database and the app, verification states have plain-English reasons, and changes to verified foods are logged and un-verify automatically. Against that, only 26 recipes are AI Verified, none is Dietitian Verified, and protein families are set on no real food. The next six weeks are about data as much as code.

**Live on 21 October 2026 (from the brief)**

| Area | State | What it blocks |
| --- | --- | --- |
| Foods | 517 (271 AFCD, 246 custom), 311 verified, 15 with a default size, 37 with Buy as, protein family on almost none | 323 recipes sit in Needs review because of unverified foods |
| Recipes | 374, 26 AI Verified, 348 Needs review, 0 Dietitian Verified; 141 recipes have lines that can't be weighed, 109 use estimated weights, 21 carry data-issue notes | The generator's pool |
| Measures | 611 unit measures, 88 flagged as estimates; 197 lines can't be weighed | Same |
| Tags | 12 allergen, 5 dietary, 25 classification; Lunch tag thin | Slot fit in the generator |
| Clients | Full module live; 1 real client | Nothing technical; needs use |
| Plans | 7 drafts; P1 backend (dates, day types, own slots, quarter serves, publish and freeze) live and tested, Lovable front end in progress | P2 to P4 |
| Staff | 6 accounts, all admin; roles exist for dietitian, intern, pending | Role testing needs real role assignments |
| Changes inbox | 56 unreviewed | Dietitian time |
| Security | Recipe, food, conversion, tag and AFCD tables still writable by any signed-in account including pending; key rotation, leaked-password protection and two-factor pending | Must close before any client login or AI write path |

**Mid-flight this week**: Plans P1 front end in Lovable, the dietitians' food verification week with a work list (88 estimates, 197 unweighable lines), and the recipe units clean-up, which is done.

**Two things to reconcile**

- The GitHub repo's last push is 15 October. The brief says the P1 backend is live and tested on 21 October, so that work exists in Supabase and locally but not in the canonical repo. Push it before anything else builds on it.
- The brief counts 26 AI Verified recipes today; the 15 October session summary counted 31. Food edits during verification week un-verify foods and drop recipes out of AI Verified, which is the system working as designed, but it means the pool report should be run and dated at each gate rather than quoted from memory.

**What is already decided and should not be reopened**: the eight principles, interns allocated per client, dislike as main ingredient at 10% of recipe weight, repetition as both "not within N days" and "max N per cycle", eggs "each" means large, the engine package is never changed by feature work, and Lovable builds only from a prompt Claude Code writes and then verifies in code.

## What authentically Grams of Health means

The three Foodzilla rounds settle the positioning: Foodzilla sells speed and an all-in-one practice suite, FoodWorks sells analysis rigour, Nutrium sells practice management. Our space is FoodWorks-grade Australian rigour with Foodzilla-grade plan speed, built around one dietitian relationship. Three things make that true rather than a slogan.

**1. Every number is traceable, and the product shows it.** Foodzilla's most repeated review complaint is totals that don't add up and portion changes that don't carry through. Our engine makes that impossible, but today the product only proves it in a test script. The polish stage should put the proof on screen: a per-line contribution view the client-facing booklet can inherit, a plan-level invariant check, and an always-visible "computed from grams, AFCD Release 3" line.

**2. Verification is a human act with a visible trail.** Foodzilla's "dietitian-approved" label has no public audit trail, user-created foods go live instantly, and AI-generated recipes save with no verification state. Ours has three states with reasons, sign-off history, and automatic un-verification. Keep that as the headline feature of the SaaS tier, and never let a convenience feature (import, AI draft, client scan) bypass it.

**3. The tool defers to the dietitian at every point Foodzilla automates past her.** Foodzilla sets goals from a form on a fixed 30/30/40 split, saves a new energy target the moment a formula is picked, publishes a generated plan on Save, lets clients edit plans with no approval, and lets an external AI write recipes and foods straight into the account. Each of those is a place our product stops and asks. That is slower by one click and it is the product.

**Rules every stage keeps (from the brief, restated as build tests)**

| Principle | Test any new feature must pass |
| --- | --- |
| Numbers from grams | No table stores a macro; every number on screen can be traced to line grams and a per-100 g food row |
| Australian measures | 5, 20 and 250 mL; AFCD or AUSNUT only; kJ shown alongside kcal where clients see numbers |
| No guessing | A line with no real weight is flagged, never estimated; AI-drafted values arrive unverified |
| Human sign-off | No machine path sets verified; an AI draft, an import and a client-uploaded value all land as drafts |
| No auto-tagging | Allergen and diet tags on foods are set by people; AI may suggest tags for a person to tap |
| Nothing silent | Every write to foods, measures, tags, targets, consent and clinical records is logged with who, when, old and new |
| Published means frozen | A client never sees a plan version that can change under them |
| AI proposes | Every AI output is a diff a person accepts; AI never sets targets or applies a change |

**What we deliberately will not copy**: client self-generation of plans, co-planning edits that land without approval, smart forms that set targets, an open online-recipe pool with USDA numbers, bookings and payments inside the tool (Cliniko, Xero and Stripe already exist on the practice's accounts), and AI connectors that write into the account.

## The four stages at a glance

| Stage | Duration | Focus | Gate to leave it |
| --- | --- | --- | --- |
| 1. Polish (underway, today 21 Oct 2026) | 4 to 6 weeks | Verify foods and lines, security hardening, finish Plans P1 | Pool at the ready bar, security closed |
| 2. Working app | 3 to 4 months | Generator and diffs; intake, notes, documents; AI-0 to AI-5 | Ten real plans shipped, AI-0 to AI-2 live |
| 3. Client app | 3 to 4 months | Own plan, check-ins, messaging, logging, App Store wrap | 20 clients for 4 weeks, zero leak findings |
| 4. SaaS | 4 to 6 months | Organisations and isolation, branding, onboarding, billing, compliance | Second practice live, billing end to end |

Stages run in order and each gate is a report with numbers, not a date: the pool report and security checks open Stage 2, ten real plans and the first AI assistants open Stage 3, twenty active clients and clean leak tests open Stage 4. The durations are estimates for one backend builder plus Lovable, with dietitian time running alongside; Stage 4's T1 and T2 can start earlier because they are pure backend.

## Stage 1, Polish: the internal tool as good as it can be

Goal: a tool the dietitians use for every client without workarounds, with a verified pool large enough to plan from. Nothing here is a new module; it is finishing, hardening and data. Suggested duration four to six weeks, running alongside verification week. Effort is Claude Code plus Lovable days unless marked as dietitian time.

**1A. Data readiness (dietitian time, with tooling from us)**

| # | Item | Detail | Effort |
| --- | --- | --- | --- |
| 1A.1 | Verification work list, ranked | The Quality page already ranks by recipes unblocked. Add a "next 20" queue per dietitian with one-click open, so the 323 unverified-food recipes clear in order of leverage (Salt, Soy sauce, Water, Oregano, Tomato, Paprika, Pepper, Tomato paste, Sugar, Rice wine vinegar first) | 1 day build, 1 to 2 weeks dietitian |
| 1A.2 | Estimated weights and unweighable lines | 88 estimates to weigh or confirm, 197 lines to resolve by adding the named measure. Work list says which measure, never the grams | 1 week dietitian |
| 1A.3 | Protein families | Suggestion CSV for the \~98 protein foods, dietitian confirms, confirmed rows load with change-log entries naming the confirmer | 1 day build, 2 hours dietitian |
| 1A.4 | Meal-type tags | Suggestion CSV for the 302 untagged recipes; Lunch is the weak slot, so also adopt the lunch-eligibility rule (Lunch or Dinner recipes fit lunch) as a practice default | 1 day build, half a day dietitian |
| 1A.5 | Default sizes and Buy as | Default size on the remaining common "each" foods (iceberg lettuce, celery, rocket); Buy as on every food that appears on a shopping list | Half a day dietitian |
| 1A.6 | Data-issue notes | Review the 21 notes and the 56 Changes inbox entries; delete the test food | Half a day dietitian |
| 1A.7 | First Dietitian Verified recipes | Sign off the AI Verified pool as it grows; target the ready bar below | Ongoing |

**1B. Foods and recipes (product polish)**

| # | Item | Why | Effort |
| --- | --- | --- | --- |
| 1B.1 | Energy-vs-macro consistency check on every food write | 4/4/9 kcal (17/17/37 kJ) tolerance, warn on save, block Save and verify until resolved. Foodzilla warns on manual entry; their reviewers' top complaint is totals that don't add up | 1 day |
| 1B.2 | Settle F1.1 | Un-verify only on calorie-relevant changes (kcal, protein, fat, carbs, fibre per 100 g, density, allergen and diet tags), not on name or aisle. Matches the database rule; the Lovable follow-up made it stricter | Half a day |
| 1B.3 | Food page: per-100 g and per-serve side by side with kJ | Australian panels read per 100 g and per serve in kJ; dietitians think in both | 1 day |
| 1B.4 | Recipe editor: contribution view polished and exportable | Already exists; make it the default second tab and let the A4 card include it | 1 day |
| 1B.5 | Recipe variations: stale banner and one-click re-solve | Variations go stale when the base changes; show the diff and re-run the solver on request | 1 day |
| 1B.6 | Swap suggestions: filter by profile tab | High protein, Low fat and so on, reusing the tabs; better than Foodzilla's diet-label filter | 1 day |
| 1B.7 | Library: saved views per dietitian and a "pool" view | The pool view is the generator's input (AI or Dietitian Verified, with meal type) | Half a day |
| 1B.8 | Nutrition table export in FSANZ layout | Per serve and per 100 g, kJ, carbohydrate excluding fibre. Foodzilla explicitly cannot do this ("a nutrition table, not a legal label") | 1 day |

**1C. Clients (product polish)**

| # | Item | Why | Effort |
| --- | --- | --- | --- |
| 1C.1 | Calculator explainer page | Show maintenance, day-type targets and each step; Accept stays explicit. Foodzilla's explainer is good, its apply-on-select is not | 1 day |
| 1C.2 | Activity level as a custom multiplier | When the bands don't fit, type a multiplier; every day-type target recomputes on Accept | Half a day |
| 1C.3 | Serving-size layer (AGTHE food groups) | Optional per-client daily food-group targets (grains, vegetables, fruit, dairy, protein foods). Foodzilla has it; ours maps from AFCD food groups | 2 days |
| 1C.4 | Needs-attention list | Clients with no check-in or weight for N days (default 14), on the clients list | Half a day |
| 1C.5 | Check-in trend strip exported to PDF | A one-page pre-consult brief, hand-built now, AI-summarised in AI-6 | 1 day |
| 1C.6 | Per-client "show numbers" flag stored now | Default hidden. Costs nothing now and the client app needs it in C1 | Half a day |
| 1C.7 | Consent register model | Policy version, consent forms, who agreed, when; captured now by staff on the client's behalf, by the client in C1 | 1 day |

**1D. Plans (finishing P1)**

| # | Item | Why | Effort |
| --- | --- | --- | --- |
| 1D.1 | Push the P1 backend to GitHub and tag it | The canonical repo is a week behind the database | Hours |
| 1D.2 | Plan totals invariant | A test that plan totals equal the sum of computed slot totals after every edit op; run in CI and once in the app on publish | 1 day |
| 1D.3 | Publish warnings as a constraint report | Unverified recipes, blocked or unconfirmed screening, days outside tolerance, repeats; the dietitian signs the report, not just the plan | 1 day |
| 1D.4 | Shopping list by date range and serving count | Pick days, scale household servings; Australian aisle order; pack-size rounding later | 1 day |
| 1D.5 | Booklet: show-numbers switch and kJ | Respects 1C.6; booklet never shows verification status | Half a day |

**1E. Security hardening (before any client login or AI write path)**

| # | Item | Effort |
| --- | --- | --- |
| 1E.1 | Staff-only policies on recipes, foods, conversions, tags, AFCD and the \~13 other open tables; show policies before applying; leak test with a pending account | 1 day |
| 1E.2 | Rotate the database password and service-role key; delete the stray auth user; turn on leaked-password protection | Hours |
| 1E.3 | Two-factor sign-in for staff (Supabase MFA), required for admin and dietitian | 1 day |
| 1E.4 | Clinical-records access log (who opened which file, when) and signed-URL expiry audit | 1 day |

**1F. Added after the review pass**

| # | Item | Why | Effort |
| --- | --- | --- | --- |
| 1B.9 | FSANZ claim check on recipes | Flags per serve and per 100 g against Standard 1.2.7 thresholds (source of protein, good source of fibre, low fat and so on) as informational badges a dietitian can show on the card. Principle 5 names them; nobody else does them | 2 days |
| 1C.8 | Energy formula choice | Katch-McArdle from a DEXA lean-mass reading when one exists in clinical records, Mifflin-St Jeor otherwise; a per-dietitian default; Accept stays explicit and the working is saved | 1 day |
| 1C.9 | Health-label vocabulary | Preferred tags beyond Heart-healthy: Anti-inflammatory, Low histamine, Low FODMAP, Renal, Perimenopause, Longevity, GLP-1 friendly. Set by people on recipes, inherited rules as today | Half a day plus dietitian tagging |
| 1C.10 | Client lifecycle | Archive, deactivate and reactivate; transfer a client between dietitians with full history; bulk archive and re-invite from the list | 1 day |
| 1D.6 | Household scaling on the booklet | Scale recipes and the shopping list for N people on export without touching the client's plan; pack-size rounding on Buy as units | 1 day |
| 1E.5 | Staging and CI | A Supabase branch as staging; CI runs the engine parity script, the SQL tests and the fixtures on every push; Lovable prompts are verified against the branch first | 2 days |
| 1E.6 | Backups and restore test | Point-in-time recovery confirmed, a restore rehearsed once into a branch, snapshot before every destructive migration (already the rule, now automated) | 1 day |
| 1E.7 | Monitoring | Edge Function errors, slow queries and auth failures to one channel; a weekly health digest | 1 day |

**Gate 1, to leave Stage 1**: pool report at or above the ready bar (section 8); 1E done; P1 front end live and QA'd; every dietitian has used the tool on at least one real client end to end.

## Stage 2, Working app: the practice runs on it

Goal: a dietitian opens a client, presses Generate, gets a draft plan from verified recipes within seconds, edits with diffs, and publishes a frozen version; intake, notes and documents live in the tool; the first AI assistants remove grunt work. This is the repo's Stages 1 to 4 plus the intake, notes and documents layer that Foodzilla showed is table stakes. Suggested duration three to four months. Order within the stage matters and is given.

**2A. Plan model and roll-up (repo Stage 1; P1 done, P2 here)**

| # | Item | Detail |
| --- | --- | --- |
| 2A.1 | Item kinds | Recipe with optional variation, or food plus quantity and unit for snacks and sides |
| 2A.2 | Slot states | Filled, free choice (excluded from roll-up, never a shortfall), empty |
| 2A.3 | Leftovers | An item references the item it was cooked with; shopping and repetition count it once |
| 2A.4 | Plan fields | Cycle length, status (draft, active, archived), origin (generated, manual, template), generator seed and settings snapshot, spare recipes, release date |
| 2A.5 | Locks | Lock at slot, day and week; regenerate touches only unlocked slots. Foodzilla's most-praised editing feature |
| 2A.6 | Options per slot | Two or three alternatives per slot, each within the slot's tolerance, so any choice keeps the day on target. Foodzilla allows ten, which breaks targets |
| 2A.7 | rollupPlan | Per item, slot, day and week: engine numbers against that day's targets, AMDR flags from an editable bands table, plain-English shortfalls. The single truth for the UI, the generator's scoring and the AI's explanations |
| 2A.8 | Migration | The 7 drafts migrate in place; snapshot first |

**2B. Generator and edit tools (repo Stage 2; roadmap P3 and P4)**

| # | Item | Detail |
| --- | --- | --- |
| 2B.1 | Pool | Screened recipes only: blocked never, unconfirmed only if ticked and flagged, disliked excluded, pool status AI or Dietitian Verified |
| 2B.2 | Placement order | Protein variety across lunch and dinner, slot fit with the lunch-eligibility rule, repetition (not within N days, max N per cycle, deliberate leftovers), target fit in 0.25-serve steps then a variation, else report. Never distort a recipe |
| 2B.3 | Fine-tune controls | Variety strength, energy share per slot (editable defaults per practice), nutrient focus (fibre, protein), own-library priority. Foodzilla documents these in its help centre but hides them in demos; dietitians expect them |
| 2B.4 | Determinism | Same client, pool, settings and seed give the same plan; Regenerate changes the seed; the seed is stored on the plan |
| 2B.5 | Constraint report | Targets hit per day type with tolerance, exclusions applied with reasons, unconfirmed items, repeats, unmet constraints with causes. The dietitian approves the report; this is what Foodzilla lacks |
| 2B.6 | Draft with release date | A generated plan is a draft with a release date; nothing reaches a client before approval. Mirrors Foodzilla's three-day Auto Plans window, applied to every plan |
| 2B.7 | Edit operations returning diffs | swapInSlot (filtered by profile tab and screening), nudgePlan, fixDay, applyDislike, regenerateDay, regenerateUnlocked. None writes; the UI applies accepted diffs |
| 2B.8 | Acceptance fixtures | 7-day plan from a 20-recipe fixture pool meeting spread and repetition; peanut-blocked client never gets peanut; disliked main ingredient excluded; infeasible spread returns the plan plus unmet list; same seed gives identical plan; totals invariant holds after each edit op |
| 2B.9 | Lovable plan board | Generate on the client, per-day green zone, per-slot swap, options chooser, nudge slider, locks, leftovers and free-choice rendering, spare recipes, constraint report panel, QA script |

**2C. Templates, groups and bulk (brief B2)**

| # | Item | Detail |
| --- | --- | --- |
| 2C.1 | Template plans | Structure plus recipes, named by energy band and diet; converting a client plan to a template strips client data |
| 2C.2 | Energy bands | Practice-defined bands (for example 1,500, 1,800, 2,100, 2,400 kcal); applying a template to a client re-solves portions against that client's day-type targets rather than copying. Foodzilla copies |
| 2C.3 | Groups and programmes | A programme with a start date and a cohort; assign a template to everyone; each person gets their band or individual scaling; bulk booklets per person or per band, shopping list per band |
| 2C.4 | Participant record | Lighter record (name, email, band, allergens, consent) upgradeable to a full client; recommended in the brief, confirmed here |
| 2C.5 | Template changes | A push button sends the new version to all or chosen participants; never automatic |
| 2C.6 | Recurrence | Repeat a plan across weeks, with the repeat count stored, as Foodzilla's walkthrough shows |

**2D. Intake, notes and documents (new; from rounds two and three)**

| # | Item | Detail |
| --- | --- | --- |
| 2D.1 | Form builder | Eleven field types (short text, long text, number, date, single choice, multiple choice, dropdown, scale, yes/no, signature, info block) plus file upload; required flag and helper line; single-trigger conditional follow-ups that nest; preview; type (intake, consent, questionnaire, check-in); archive |
| 2D.2 | Templates | Initial intake, consent, weekly check-in, meal plan preferences, 3 and 7-day food diary, health history, PAR-Q, medications and supplements. Templates are copies the practice edits |
| 2D.3 | Delivery and tracking | Send to a client (staff fills on their behalf until the client app exists), auto-send on client creation, sent and completed counts, awaiting status, reminders at 48 hours and 5 days (Foodzilla has none) |
| 2D.4 | Draft-state answers | Goals, allergens and requirements land as drafts the dietitian confirms; preferences, dislikes, cuisine, budget and household size write directly with a client-sourced flag; weight and measurements write to the logs with a client-sourced flag; no form ever sets a target |
| 2D.5 | Notes | Templates SOAP, ADIME, Initial Consultation, Follow-up; private means the assigned dietitian and owner, not all staff; shared notes visible to the client later; sign and lock with dated addendums; attachments |
| 2D.6 | Documents | Three buckets: client-documents, client-clinical (restricted, already exists), practice-resources; documents table with version and supersedes; signed URLs; 100 MB per file; PDF, DOCX, images; access log on clinical reads (1E.4) |
| 2D.7 | Consent | Consent forms versioned; recorded per client with who, what, when; required before any client-facing feature or AI processing of client data |

**2E. AI assistants (repo Stages 0, 3 and 4; brief AI-0 to AI-5)**

| # | Feature | Gate before it lands | Client data |
| --- | --- | --- | --- |
| AI-0 | Groundwork: Edge Function scaffold, key as a secret, ai\_requests log (feature, who, input, interpretation, tools, proposal, accepted, latency, tokens, cost), monthly spend guard, per-user weekly caps, feature switches, eval harness | None needed | No |
| AI-1 | Food label reader: photo or supplier spec to draft food; per-100 g and per-serve detection; kJ to kcal; energy-vs-macro check; suggested tags to tap | Draft food, unverified, dietitian saves and verifies | No |
| AI-2 | Recipe import and clean-up: paste, PDF, photo or link to draft recipe matched to our foods in Australian measures; unknown foods become "new food needed"; proposals accepted one by one | Draft recipe in Needs review | No |
| AI-3 | Consult transcript to summary: Fireflies, Zoom, Teams, pasted notes; summary in the practice template; proposed record updates each with a source quote; flags for clinical judgement | Draft note; each proposed update is a diff; targets never touched | Yes, after 2D.7 |
| AI-4 | Clinical document reader: pathology and DEXA PDFs to analyte, value, unit, range, flag; trends over time | Draft values confirmed into the clinical record | Yes, clinician only |
| AI-5 | Plan co-pilot: grammar first (parseTargetRequest), then Claude over read and propose tools only; Translator echoes the structured request before anything runs; Strategist returns chained diffs approved per step; Explainer; Refusals that name what is missing; eval set with at least ten conversations and three refusals | Every output is a diff; no tool writes | De-identified profile |
| AI-6 | Check-in summaries: one-page brief before a consult, weekly batch | Draft brief | Yes |

**2F. Integrations, read-only first**

- Cliniko: import clients and practitioners, link a client, show upcoming appointments on the client page. One-way, as Foodzilla's is. Confirm with Nikki that Cliniko remains the booking and billing system.
- Fireflies: list transcripts for a client's consult date and feed AI-3.
- Resend: booklet and plan emails from the app, with a plain link and PDF attachment, no unsubscribe link in practice emails.

**2G. Added after the review pass**

| # | Item | Detail |
| --- | --- | --- |
| 2B.10 | Swap re-solves the replacement | swapInSlot runs the solver on the incoming recipe against the outgoing slot's profile within the usual 30% bounds, and reports when it can't; this is the behaviour Foodzilla calls smart swap, done through our engine |
| 2B.11 | Macro entry as percent or grams | Targets accept a percent split that the calculator converts to grams on Accept; grams remain the stored truth |
| 2B.12 | Nutrient popover in the planner | Per item and per day, the ten nutrients alongside macros, computed live |
| 2B.13 | Per-client generation cadence | Weekly or fortnightly auto-generation for ongoing clients, each plan a draft with a release date the dietitian approves or rebuilds; pauses when the client is archived |
| 2C.7 | Recipe collections and client recipe books | Ordered collections, exported as a booklet or shared read-only to the client app later |
| 2D.8 | Intern supervision flow | Intern edits to plans, notes and forms land as drafts routed to the supervising dietitian; interns never approve AI diffs or set verified |
| 2D.9 | Staff onboarding | Invite, role, a short in-app checklist (principles, how verification works, how to approve a diff), one shadow client, first allocation by the owner |
| 2D.10 | Client nutrition report, staff side | Day, week and custom range from client logs once C4 exists; built now for staff-entered diaries from the 7-day form |
| 2D.11 | GLP-1 support | A dose log on the client record drawn as bands on the weight chart; the GLP-1 friendly label (1C.9) as a generator input; protein guidance surfaced in the calculator explainer |
| 2F.4 | Medicare and GPCCMP | Decision needed: if Cliniko tracks referrals and session counts, show them read-only on the client page; if not, a referral record with sessions used of five (ten for Aboriginal and Torres Strait Islander clients) and the plan's expiry |

**Gate 2, to leave Stage 2**: generator fixtures green; ten real plans generated, edited and published for real clients with the constraint report; intake form auto-sent on client creation; AI-0 to AI-2 live with the eval harness; AI-3 to AI-5 live or consciously deferred; 2D.7 consent in place; security 1E complete and re-tested.

## Stage 3, Client app

Goal: a phone-first web app on the same database where each client sees only their own published plan, recipes, shopping list and check-ins, with what they see controlled per client by their dietitian. Wrapped for the App Store later, not rebuilt. Suggested duration three to four months after Gate 2. The brief's C0 to C6 shape stands; the Foodzilla rounds add the per-client toggles, the portal-and-app pairing, bounded swaps, label scanning and onboarding detail.

**C0. Security and separation (nothing visible yet)**

- A client role in auth, separate from staff roles; row-level policies that let a client read only their own published plan versions, recipes in those plans, shared notes, their own logs and consent; never drafts, verification status, clinical records, staff notes or other clients.
- Leak tests with two fake clients and a pending staff account.
- Invite flow: the dietitian creates the client, the system emails an invite; the client sets a password on first sign-in; consent forms shown before anything else (2D.7). One client identity, invited by one practice.

**C1. Sign in and the plan (first visible release)**

| Item | Detail |
| --- | --- |
| Plan view | This week's published version by day and slot; options per slot flipped with arrows (2A.6); recipes scaled to the client's servings with method and photos; leftovers labelled |
| Numbers | Hidden by default; the per-client "show numbers" flag (1C.6) reveals kcal and kJ and macros. Foodzilla's own stated use is eating-disorder care; ours is the default |
| Shopping list | By aisle, date range and household servings; tick off items; never editable in a way that changes the plan |
| Per-client feature toggles | Mobile app access, plan, recipes library, shopping list, numbers, food groups, check-ins, weight, photos, messaging, forms, documents; before and after preview for the dietitian; practice-wide defaults |
| Onboarding | Four screens: consent, who your dietitian is, how the plan works, where to log; no wearables, no targets, no goals entry |
| Guides | Short in-app guide cards per feature, as Foodzilla's 19 clips do, written by Nikki |

**C2. Check-ins, weight and forms in the app**

- Weekly or fortnightly check-in (1 to 5 scales, Bristol, training, likes, dislikes, changes wanted, notes, optional weight) landing as a client-sourced entry on the existing timeline; dietitian inbox with a Needs-attention list (1C.4).
- Intake and consent forms from 2D completed by the client; answers follow 2D.4's draft rules.
- Progress photos, up to five per weight entry, private bucket, visible to the client and the assigned dietitian.

**C3. Messaging and notifications**

- One-to-one messaging between client and assigned dietitian; the owner and a covering dietitian can be given visibility per client (Foodzilla reviewers complained chats were invisible during leave); interns only if allocated.
- Push notifications through the home-screen web app: new plan version, check-in due, message received. No marketing broadcasts.
- Templates for check-in reminders, designable by the practice.

**C4. Logging and bounded swaps**

- Meal ticks against the plan with a time of day; a day view that shows what was planned and what was ticked.
- Swaps from the dietitian-approved option set only (2A.6), logged and visible to the dietitian; no free edits to a published plan. This is the authentic version of Foodzilla's co-planning.
- Food logging by search over the practice library and AFCD, with grams or the food's own measures; estimated measures flagged exactly as in the staff tool.
- Label scan: the client photographs a nutrition panel; the AI reads it per 100 g or per serve, kJ or kcal; nothing saves until the client confirms each field; the entry is unverified and visible to the dietitian, who can promote it to a draft food (AI-1). Barcode lookup only when an Australian source is confirmed.
- Habit goals set by the dietitian (water, steps, vegetables), ticked by the client.

**C5. Automation and client-facing AI**

- Scheduled check-in reminders and plan-release notifications; weekly brief to the dietitian (AI-6).
- In-app assistant, off by default, enabled per client by the dietitian: answers only from the client's published plan, shared notes and the practice library; explains and logs; never advises on targets, never edits the plan; escalates to the dietitian with a drafted message the dietitian sends.
- Food-diary analysis (Foodzilla's smart-form idea): free-text meals mapped to foods IDs as estimates, labelled unverified, pushed to the log only on the dietitian's click.

**C6. App Store and health data**

- Wrap the same app (Capacitor or similar) for iOS and Android; push through native channels; Apple Health and Health Connect for steps and weight only, imported as client-sourced entries.
- Payments stay in Cliniko, Stripe and Xero unless Nikki decides otherwise; the app never takes card details.

**C7. Added after the review pass**

- Client document upload and client notes to the dietitian, with attachments; uploads land in a pending state the dietitian files into client-documents or client-clinical (C2).
- Client nutrition reports from their own logs, day and week, shown only when "show numbers" is on; the dietitian's copy always available (C4).
- GLP-1 dose logging by the client when the dietitian enables it (C2).
- Staff tablet and phone view of the client page, check-in inbox and messaging, so a dietitian can work between consults; the recipe editor stays desktop (C3).
- Client transfer between dietitians carries messaging history and visibility (C3).

**Gate 3, to leave Stage 3**: twenty active clients using the app for four weeks; zero cross-client reads in the leak tests; consent recorded for every active client; check-in completion and plan-open rates reported; a client-app privacy notice published.

## Stage 4, SaaS: other practices on the same product

Goal: one app and one database serving many Australian practices, each seeing only its own data and branding, with a starter library as the licensing lever and verification as the headline. Suggested duration four to six months after Gate 3, with T1 and T2 startable earlier because they are pure backend.

**T1. Organisations**

- Organisations table; a platform-owner role distinct from practice admin; every practice record stamped with its organisation; existing data assigned to Grams of Health; one practice per login.
- Shared reference data (AFCD rows, AMDR bands, measure conventions, tag vocabularies) owned by the platform and read-only to practices.

**T2. Isolation**

- Every policy rewritten per organisation; leak tests with a fake second practice run in CI; storage buckets prefixed per organisation; Edge Functions take the organisation from the session, never from the request.
- Each practice has its own food and recipe library, optionally seeded from the Grams of Health library at onboarding (a copy, so later edits never cross).
- No platform access to a practice's data by default; a support-access grant per practice, time-boxed and logged.

**T3. Branding and settings**

- Branding from the web address: name, logo, colours, carried into the staff app, client app, booklets and emails. A practice settings page: measure conventions, default slots, day types, AMDR bands, energy shares, form templates, consent texts, client-app defaults.
- Custom domains later.

**T4. Onboarding and support**

- Create a practice, invite its admin, choose a starter library, set branding, invite staff, import clients (CSV, Cliniko), send the first intake form. Target: a new practice planning for a client within a day.
- Help centre and short guide videos, written in the same register as the product; a changelog page.

**T5. Billing and packaging**

- Stripe subscriptions per practice; tiers by active clients and seats; usage caps on AI per tier; invoices in AUD with GST.
- Suggested tiers to test, not commit to: Solo (1 seat, 50 active clients), Practice (5 seats, 200 clients, client app, AI assistants), Clinic (unlimited seats, groups and programmes, Cliniko, white-label client app). Price against Foodzilla's AUD 59 entry and USD 56 to 126 tiers, FoodWorks Professional at AUD 58 to 77 a month per user, and Nutrium's roughly USD 28 to 35.
- A licensing lever Foodzilla cannot match: the verified Australian library with sign-off history, licensed as a starter library or a premium tier.

**T6. Compliance and trust**

- Sydney hosting stated plainly (confirm the Supabase region in project settings); Australian Privacy Principles statement; data processing terms; export and deletion per practice and per client; retention rules; access logs for clinical data; AI data-use statement that names the model provider and what is sent.

**Positioning for the marketplace**

| Them | Us |
| --- | --- |
| Foodzilla: fast plans, 100K recipes, all-in-one practice suite, Singapore hosting, AUSNUT 2011-13 inside a US-weighted pool | Fast plans from a verified Australian pool with a constraint report, Sydney hosting, AFCD Release 3, Cliniko for the practice side |
| FoodWorks: analysis rigour, no planning speed, no client app | Same rigour, plus a generator, variations and a client app |
| Nutrium: practice management, generic food data | Dietitian-first clinical tool with Australian data and human verification |

**T7. Added after the review pass**

- Public API (read first, then write with the same draft rules) and a Zapier app, both keyed per practice with usage logging.
- Bulk CSV import of foods and recipes at onboarding, every row landing unverified with the energy-vs-macro check applied.
- White-label client app listings per practice in the App Store and Google Play, offered as a paid add-on with a six to eight week lead time, after the shared branded app is proven.
- Australian branded products: a decision on licensing a branded database or building one from AI-1 label reads, each product verified before it reaches a plan.
- Product analytics per practice: plans generated, approved and published, check-in completion, client app opens, AI acceptance rate, all without client identities.

**Gate 4, launch**: a second real practice live for one month with no cross-practice leak, billing working end to end, onboarding under a day, support and privacy pages published.

## Data readiness bars

The generator is only as good as the pool, so each gate carries a dated pool report. The bars below are the repo's proposed numbers with two additions (Dietitian Verified and Buy as); Nikki should confirm or replace them.

| Measure | Today | Gate 1 (plan by hand well) | Gate 2 (generate well) | Gate 3 (clients see it) |
| --- | --- | --- | --- | --- |
| Pool recipes (AI or Dietitian Verified) | 26 | 60 | 120 | 150 |
| Dietitian Verified | 0 | 20 | 80 | 120 |
| Breakfast, lunch-eligible, dinner, snack in pool | thin | 12, 12, 20, 10 | 25, 30, 40, 20 | same |
| Foods verified | 311 of 517 | 400 | all foods used by pool recipes | all |
| Lines that can't be weighed | 197 | 50 | 0 in pool recipes | 0 |
| Estimated weights | 88 | 0 confirmed or replaced | 0 | 0 |
| Protein families on protein foods | 0 | all \~98 | all | all |
| Default size on "each" foods | 15 | all foods used as "each" | all | all |
| Buy as on foods that reach shopping lists | 37 | all in pool recipes | all | all |
| Data-issue notes and Changes inbox | 21 and 56 | 0 open | 0 open | 0 open |

Who moves them: the dietitians, with a ranked queue from us (1A.1). AI-1 and AI-2 speed verification and import once AI-0 lands, which is why they sit early in Stage 2 rather than at its end.

## Decisions needed

In the order they block work. Each is a yes, no or a number.

1. **Push the P1 backend to GitHub now** so the repo is canonical again. Blocks 2A.
2. **F1.1**: un-verify only on calorie-relevant changes (recommended). Blocks 1B.2.
3. **Ready bars**: accept the Gate 1 and Gate 2 numbers above or set Nikki's own. Blocks the generator's go.
4. **Lunch eligibility**: lunch slots accept Lunch or Dinner recipes by default. Blocks 1A.4 and 2B.2.
5. **Security now, not "at the end"**: 1E before any AI write path or client login. Blocks AI-0 and C0.
6. **Participants in programmes**: lighter upgradeable record (recommended). Blocks 2C.4.
7. **Energy bands**: how many and which values. Blocks 2C.2.
8. **Intake questions**: Nikki writes the initial intake, consent and check-in templates in her words; we build the fields. Blocks 2D.2.
9. **Private notes scope**: assigned dietitian and owner (recommended) or all clinicians. Blocks 2D.5.
10. **Interns and consult notes**: can interns see AI-3 summaries for their allocated clients. Blocks AI-3.
11. **Transcript retention**: how long consult transcripts are kept after summarising. Blocks AI-3.
12. **AMDR bands and energy shares per slot**: dietitians confirm the editable defaults. Blocks 2A.7 and 2B.3.
13. **Show numbers default**: hidden (recommended) for every client unless the dietitian switches it on. Blocks C1.
14. **Cliniko stays the booking and billing system**: if yes, 2F is read-only and T5 is practice subscriptions only. Blocks 2F.
15. **Supabase region**: confirm Sydney in project settings so the hosting claim is true in writing. Blocks T6.
16. **Grace's FoodWorks figure**: confirm where "about $850 a month" comes from, since Xyris lists AUD 58 to 77 per user. Affects T5 pricing.

Also needed after the review pass:

- Does Cliniko already track Medicare referrals and session counts for the practice? Decides 2F.4.
- Branded products: licence a database or build one from label reads? Decides T7.
- White-label app-store listings as a paid add-on, or shared branded app only? Decides T7.
- Staff mobile view in Stage 3, or deferred? Decides C7.
- Interns and supervision: every intern edit routed to a dietitian (recommended) or only plans and notes? Decides 2D.8.

## Companion documents

Three documents carry the specifics this roadmap only names. They are written for Claude Code and filed the way its docs folder is organised.

- Foodzilla comparison in D2 format: every function worth adding as a D2 block, the top five, what Foodzilla does worse, and pricing for white-label. For docs/competitor-foodzilla-d2.md.
- Intake and check-in form specification: field-by-field templates, screening gateways, draft rules, reminders and the client-profile mapping. For docs/forms-spec.md.
- Engineering foundations and SaaS platform specification: staging, CI, backups, monitoring, analytics, API and Zapier, bulk import, client lifecycle and the white-label app process. For docs/platform-spec.md.

## Sources

- Product brief for a competitor comparison, 21 October 2026 (attached in this conversation).
- Repo bgl-openclaw/GramsOfHealth at its 15 October 2026 head: docs/SESSION-SUMMARY-2026-10-15.md, docs/roadmap-plans-ai.md, docs/AI-ROADMAP.md, migrations 0001 to 0035.
- Foodzilla research round one (product map, generator, client app, pricing), round two (forms, files, onboarding, AI) and round three ([Foodzilla Round 3: Videos and Help Centre](https://claude.ai/artifact/XMe1jVtmG1YxdxBCTyh7je), 24 transcripts and 25 help-centre articles).
- Competitor pricing as found on 21 October 2026: Foodzilla USD 42, 56 and 126 a month billed yearly, AUD "from 59" on its Australian page; FoodWorks Professional AUD 58 a month per user billed annually or 77 monthly, ex GST, from Xyris; Nutrium roughly USD 28 to 35 from third-party listings, unverified against Nutrium's own page.

Nothing in Supabase, Lovable or the repo was changed in preparing this roadmap. The repo was cloned read-only for reference.


---

# Foodzilla comparison in D2 format

21 October 2026 · Ben Leghissa

File as docs/competitor-foodzilla-d2.md. This is Part D of the 21 October product brief, answered from three research rounds: every Foodzilla function worth adding, one D2 block each, grouped by the area of our app it touches. Roadmap references (1B.9, 2B.10, C7, T7) point at the Grams of Health build roadmap. Priority: must, should, could. Every block names the principle conflict, if any, and the version that fits.

## Top five additions

1. Lock and regenerate with a constraint report (roadmap 2A.5, 2B.5): the editing loop dietitians praise, with the evidence Foodzilla lacks.
2. Draft with a release date (2B.6, 2B.13): generated plans wait for approval, the shape of Foodzilla's Auto Plans applied to every plan.
3. Form builder with smart forms that draft rather than write (2D.1 to 2D.4): intake, consent and check-ins with conditional follow-ups, auto-send and reminders.
4. Per-client app toggles with numbers hidden by default (1C.6, C1): the single most dietitian-friendly idea in their product.
5. AI review gates as diffs (AI-1 to AI-5): their words-to-plan preview and ingredient-match review, done through our engine with an audit log and no silent save.

The template for each block below is the brief's D2 block: function, what it does, who uses it, closest thing we have or have planned, why it matters, priority, principle conflict, notes.

## D2 blocks: planning and generation

| Function | What it does | Who | Closest we have or plan | Why it matters | Priority | Principle conflict and the fitting version | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Auto-generate | Builds a plan in seconds from targets, meal count, days, diet labels, exclusions and dislikes; scales portions to the energy target | Dietitian | Roadmap P3, 2B | Their whole pitch; dietitians expect seconds | Must | None if deterministic and from the verified pool. Theirs publishes on Save; ours drafts with a release date | Their diet or allergy filter was capped at three per run in 2024; exclusion is name matching |
| Fine-tune settings | Variety strength, energy distribution across meals, nutrient focus, own-library priority | Dietitian | 2B.3 | Documented in their help centre, hidden in demos; expected by power users | Should | None | Store the settings snapshot on the plan |
| Lock and regenerate | Lock a slot, day or week; regenerate the rest | Dietitian | 2A.5, 2B.7 | Most-praised editing feature | Must | None | Regenerate re-runs the solver on unlocked slots only |
| Regenerate a day | Rebuild one day, leave others | Dietitian | 2B.7 regenerateDay | Pro-tier feature there | Must | None | |
| Smart swap | Replace a recipe and rescale the replacement to the original slot's profile | Dietitian, later client | 2B.10 | Keeps the day on target after a swap | Must | None; our solver does the rescale within 30% bounds and reports when it can't | Filter swaps by profile tab and screening |
| Options per slot | Several alternatives per slot the client flips through | Dietitian builds, client chooses | 2A.6 | Flexibility without rebuilding | Should | None if each option sits within tolerance; theirs allows ten and breaks targets | Cap at three |
| Daily-average card and per-day row | Week against target and each day's numbers | Dietitian | rollupPlan 2A.7 | Their only compliance view | Must | None | Add tolerance bands and AMDR flags they lack |
| Constraint report | None in Foodzilla | Dietitian | 2B.5 | Our differentiator; turns trust into evidence | Must | None | Signed with the plan |
| Templates by energy band | Reusable plans named by band and diet; convert a client plan to a template | Dietitian | 2C.1, 2C.2 | Programmes and challenges | Should | Theirs copies; ours re-solves to the client's day-type targets | Strip client data on convert |
| Repeat plan | Repeat a week N times | Dietitian | 2C.6 | Simple time saver | Could | None | Store the repeat count |
| Auto Plans | Weekly or monthly generation per client, ready three days early | Dietitian | 2B.13 | Ongoing clients without rebuilding | Should | Theirs ties to store subscriptions; ours to client status | Pause on archive |
| Plan-local recipe edits | Edit a recipe inside a plan without touching the library | Dietitian | Duplicate-to-variant, variations | Avoids library sprawl | Could | None | Our variation model already covers most cases |
| Groups and programmes | Assign a template to a cohort with individual scaling; cohort chat; gated lessons | Dietitian, admin | 2C.3 | Fitness challenges, the practice's stated need | Should | Cohort chat is group messaging, not wanted; lessons via practice resources | Lighter participant record |
| Grocery list by date range and servings | Choose days, scale household, group by aisle, editable group names | Dietitian, client | 1D.4, 1D.6 | Clients notice it | Should | None | Australian aisle order; pack-size rounding |
| Household scaling on PDF | Scale recipes and list for N people without changing the plan | Dietitian | 1D.6 | Family clients | Could | None | |
| Macro entry as percent | Enter a split in percent, converted to grams | Dietitian | 2B.11 | Dietitian habit | Could | None; grams stay the truth | |
| Nutrient popover | Micronutrients per recipe in the planner | Dietitian | 2B.12 | Clinical clients | Could | None | Ten nutrients today |

## D2 blocks: clients, intake and clinical

| Function | What it does | Who | Closest we have or plan | Why it matters | Priority | Principle conflict and the fitting version | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Form builder | Eleven field types, required and helper text, conditional follow-ups, preview, type, archive | Dietitian, admin | 2D.1; forms spec | Intake today is outside the tool | Must | None | Add file upload, which they lack |
| Form templates | 23 read-only templates copied with Use template | Dietitian | 2D.2 | Fast start | Should | None | Nikki writes ours |
| Auto-send on client creation | Intake and consent go out when a client is added | Admin | 2D.3 | Nobody forgets intake | Must | None | |
| Sent and completed tracking | Counts, awaiting status, who and when | Dietitian | 2D.3 | Chasing | Should | None | Add reminders at 48 hours and 5 days, which they lack |
| Meal Plan Preferences smart form | Likes, dislikes and restrictions written to the profile for the generator | Client | 2D.4 | Saves copying | Should | Allergens written without review conflict with human sign-off; ours drafts allergens and requirements, writes preferences with a client-sourced flag | |
| Progress Check smart form | Weight, waist, hips, body fat, ratings into measurement history | Client | 2D.4, C2 | Trend data without typing | Should | None with a client-sourced flag | |
| Health and Body Goals smart form | Sets calorie and macro goals from age, sex, height, weight, activity on a 30/30/40 split | Client | Calculator with Accept | Speed | Not wanted | Conflicts with Principle 7; the fitting version is inputs to the calculator, the dietitian accepts | |
| Food and Symptom Diary | Free-text meals plus ratings; practitioner clicks Analyse for an AI estimate; Push to diary | Client, dietitian | 2D.10, C5 | Dietary recall between sessions | Should | Fits if estimates map to foods IDs and stay unverified; pushed only on dietitian click | |
| Booking questions | Questions attached to a booking type | Admin | None; Cliniko | Pre-consult data | Not wanted | Bookings stay in Cliniko | |
| Notes templates | SOAP, ADIME, Initial Consultation, Follow-up, with section prompts | Dietitian, intern | 2D.5 | Consistent records | Must | None | |
| Sign and lock with addendums | Signed note locks; dated addendums; banner with who and when | Dietitian | 2D.5 | Audit-ready records | Must | None | Private means assigned dietitian and owner, not all staff |
| Shared notes | Note visible to the client in app | Dietitian | 2D.5, C1 | Consult summaries | Should | None | |
| Note attachments | One file per note up to 100 MB, six formats | Dietitian, client | 2D.6 | Everything in one place | Must | None; allow several per note | |
| Client-written notes and uploads | Client sends a note with a file | Client | C7 | Documents between sessions | Should | Lands pending until filed | |
| Four-tab goals page | Health, Nutrition, Serving Sizes, Diet Preferences | Dietitian | Client page tabs | Structure | Have | None | Serving Sizes is the gap |
| Serving Sizes (food groups) | Daily food-group targets | Dietitian | 1C.3 | AGTHE-aligned advice | Could | None | Map from AFCD groups |
| Diet Preferences detail | Cuisines, cooking confidence, weekly budget, household size | Dietitian, client | Preferences; forms spec | Generator realism | Should | None | |
| BMR formula choice and explainer | Mifflin, Harris-Benedict, Katch-McArdle, Automatic; step-by-step explainer; default per practitioner | Dietitian | 1C.1, 1C.8 | Lean clients and DEXA data | Should | Theirs saves the target on selection; ours keeps Accept | |
| Custom activity multiplier | Type a multiplier when bands don't fit | Dietitian | 1C.2 | Edge cases | Could | None; Accept | |
| Protein slider keeping energy constant | Move protein, carbs and fat rebalance, Apply | Dietitian | Targets | Fast target tuning | Could | None; Apply is explicit | |
| Health labels | Longevity, Perimenopause, Renal, GLP-1, Anti-inflammatory, Low histamine as generation inputs | Dietitian | 1C.9 | Clinical presentations | Should | None; set by people on recipes | |
| GLP-1 tracking | Client logs doses; bands on the weight chart | Client, dietitian | 2D.11, C7 | Growing cohort | Could | None | Confirm with Nikki |
| Needs Attention | Clients with no log in 14 days | Dietitian | 1C.4 | Retention | Should | None | |
| Client nutrition report | Day, week, custom PDF from logs | Dietitian | 2D.10 | Pre-consult review | Should | None | |
| Consent management | Policy link plus consent forms, required or optional, agreed at first sign-in, recorded on the profile | Admin | 1C.7, 2D.7 | Required before client data reaches AI or the app | Must | None | |
| Medicare and GPCCMP | None in Foodzilla | Dietitian, admin | 2F.4 | Opportunity | Could | None | Depends on Cliniko |

## D2 blocks: foods, recipes and AI

| Function | What it does | Who | Closest we have or plan | Why it matters | Priority | Principle conflict and the fitting version | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Energy-vs-macro warning | Warns when kcal and macros disagree on a food | Dietitian | 1B.1 | Their reviewers' top complaint is totals that don't add up | Must | None; ours blocks verification until resolved | 4/4/9 kcal, 17/17/37 kJ |
| Import a food from a label or link | AI reads macros, serving, ingredients and allergens into a preview | Dietitian | AI-1 | Speeds verification | Must | Theirs goes live on save; ours lands unverified | Suggested tags are tapped by a person |
| Custom measurements and base measure | Cup, tbsp, piece, scoop; first custom measure can be the base | Dietitian | Measures, default size | Have | Have | None | Add a per-client custom cup later |
| Estimated measures marked | Asterisk on one-fixed-weight estimates; prompt to use grams | Dietitian | Estimated-weight flag | Have, ours is stricter | Have | None | |
| Database dropdown and clone-and-edit | Switch databases, compare at the same weight, clone a row | Dietitian | AFCD import, custom foods | Have | Have | None | We stay AFCD-only |
| Bulk add ingredients | One pasted line per ingredient matched to foods | Dietitian | AI-2 | Recipe entry speed | Should | Matches are reviewed before save | |
| Generate a recipe | Describe a dish; ingredients matched to the database; review matches; steps and photo generated | Dietitian | AI-2 (import and clean-up) | Content growth | Could | Saved recipe has no verification state there; ours lands Needs review | Photo generation not wanted |
| Recipe collections and books | Ordered collections exported as a magazine PDF or shared read-only | Dietitian | 2C.7 | Client resources | Could | None | |
| Nutrition table export | Per serve and whole recipe, all nutrients, PDF or link | Dietitian | 1B.8 | Theirs is "not a legal label"; ours can be FSANZ layout | Should | None | kJ, carbohydrate excluding fibre |
| FSANZ claim badges | None in Foodzilla | Dietitian | 1B.9 | Differentiator | Could | None | Standard 1.2.7 |
| Describe a plan in words | Brief parsed to generator inputs, previewed before generation | Dietitian | AI-5 Translator | Convenience | Should | Fits; the preview is our diff | |
| Smart Summary after a call | Transcript, summary, suggested actions applied one by one, draft note | Dietitian | AI-3 | Consult write-up | Should | One-click actions conflict with diff-and-approve; ours shows each as a diff with its source quote | Fireflies in |
| Autopilot MCP | External Claude or ChatGPT creates recipes, templates, forms, foods and store items in the account | Practitioner | Read-only connector today | Power users | Not wanted as built | Writes conflict with Principles 4 and 7; the fitting version is read tools plus propose tools that create drafts | Keep usage meters and per-device revocation |
| Client AI connection | Client's own assistant reads plan and logs meals | Client | C5 assistant | Convenience | Could | Default-on conflicts with the dietitian-first principle; ours is off until enabled | |
| AI request log and usage meters | Weekly meters for requests, changes, generations | Admin | AI-0 | Cost control | Must | None | |
| Label scan by client | Photograph a panel; confirm every field before saving | Client | C4 | Logging accuracy | Should | Fits; entry stays unverified | |
| Photo food recognition | Recognise foods from a photo | Client | None | Logging speed | Could | Fits only as candidates the client confirms, mapped to foods IDs | Undocumented by Foodzilla |

## D2 blocks: client app, team and platform

| Function | What it does | Who | Closest we have or plan | Why it matters | Priority | Principle conflict and the fitting version | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Per-client app toggles | 25 features switched per client or globally with previews | Dietitian | 1C.6, C1 | Eating-disorder-informed care; lighter memberships | Must | None | Numbers hidden by default |
| Client portal plus app | Desktop mirror of the app, invited separately | Client | C1 (web app serves both) | Reach | Have by design | None | |
| Co Planning | Client adds, removes and moves meals; syncs to the practitioner | Client | C4 bounded swaps | Ownership | Not wanted as built | Direct edits conflict with Published means frozen; ours allows swaps from the approved option set only | |
| Client plan generation | Clients press Generate | Client | None | Self-service | Not wanted | Conflicts with dietitian-first | |
| Meal ticks and meal times | Tick a planned meal, log the time | Client | C4 | Adherence | Should | None | |
| Weight, water, sleep, exercise, photos | Logs with up to five photos per weight entry | Client | C2 | Progress | Should | None | |
| Wearables | Apple Health and Health Connect sync | Client | C6 | Steps and weight | Could | None; client-sourced entries | |
| Messaging and group chat | 1:1 and cohort chat, reactions, unread | Client, dietitian | C3 | Relationship | Should for 1:1 | Group chat not wanted | Covering dietitian visibility |
| Push notifications | Plan updates, forms, messages | Client | C3 | Engagement | Should | No marketing broadcasts | |
| Client guide videos | 19 short clips under a minute | Client | C1 guide cards | Onboarding | Could | None | Nikki writes |
| Content Hub | Posts with video, photos, PDFs; tags; pinned; pay per view | Admin | Practice resources bucket, 2C.7 | Education | Could | Paywall not wanted | Shared handouts only |
| Team roles and transfer | Owner, Admin, Practitioner, Assistant; transfer with history | Admin | Roles, 1C.10 | Practice growth | Should | None | Intern supervision flow is ours |
| Bulk archive and re-invite | Tick clients, act in bulk | Admin | 1C.10 | Admin time | Could | None | |
| Cliniko integration | Import clients and practitioners, link, appointments, treatment notes | Admin | 2F | The practice runs on Cliniko | Should | None; one-way read | 10% discount is their pricing, not ours |
| Halaxy, Zapier, Developer API | Other integrations and a public API | Admin | T7 | SaaS expectations | Could | Write paths follow the draft rules | |
| Branding and white-label app | Logo and colour in app, PDFs, emails; own App Store listing in 6 to 8 weeks | Admin | T3, T7 | SaaS tier | Should for branding, Could for app-store listings | None | Paid add-on |
| Store, bookings, invoices | Sell packages, take bookings, invoice with GST | Admin | None; Cliniko, Xero, Stripe | All-in-one pitch | Not wanted | Out of scope by owner decision | Revisit only if Cliniko is dropped |
| Two-step sign-in | MFA with a nag banner | Staff | 1E.3 | Security | Must | None | |
| Consent at first sign-in | Policy and consent forms before the app opens | Client | C0, 2D.7 | Legal basis | Must | None | |

## What Foodzilla does worse that we keep doing our way

- **Totals that don't reconcile.** Their most repeated review complaint. Ours are computed from grams on every read; keep the invariant test and never store a macro.
- **Portion edits that don't carry through to ingredients.** Our lines are the only input, so a serving change rescales every line by construction.
- **Allergen exclusion by ingredient name.** "Onion" removes red onion; fish needs a group label; their own advice is to read every recipe yourself. Ours screens on tags set by people and refuses to trust unverified ingredients (the unconfirmed state).
- **Foods and recipes that go live on save.** User-created foods, label imports and AI recipes carry no verification state. Ours land unverified with a change log.
- **Targets set by a form or a formula click.** Their Health and Body Goals form applies a 30/30/40 split and choosing a BMR formula saves the target. Ours proposes and the dietitian accepts, with the working stored.
- **Generate then Save publishes.** No gate between generation and the client's app except Auto Plans' three-day window. Ours drafts with a release date on every plan.
- **AI that writes into the account.** Autopilot creates recipes, templates, forms, foods and store items with no diff and only gates spending or overwriting. Ours proposes, logs and never applies.
- **A US-weighted pool.** 500K foods across USDA, CoFID and AUSNUT 2011-13; online recipes computed from USDA regardless of country; carbohydrate definitions mixed. Ours is AFCD Release 3 only, available carbohydrate, Australian measures.
- **Hosting in Singapore** described as APAC. Ours is Sydney, once confirmed in project settings.
- **"Private" notes visible to the whole team.** Ours restrict to the assigned dietitian and owner, with clinical records separately gated.
- **No reminders on forms, no file-upload field, no FSANZ-format nutrition table, no Medicare workflow.** Each is a small, cheap gap for us to fill.

## Pricing and packaging insight for white-label

| Product | Price found on 21 October 2026 | What it tells us |
| --- | --- | --- |
| Foodzilla Starter | USD 42 a month billed yearly, USD 56 monthly, 5 to 50 clients; AUD "from 59" on the Australian page | Entry is priced per practitioner with a client cap; forms, branding, chat and AI need the next tier |
| Foodzilla Professional | USD 56 yearly, USD 75 monthly, 20 to 100 clients | Unlocks Autopilot, forms, bookings, app branding, advanced planning; the tier most dietitians would need |
| Foodzilla White Label | USD 126 yearly, USD 168 monthly, 20 to 500 clients | Own App Store app in 6 to 8 weeks, client plan generation, content hub; platform fee 5% on store sales (7% on Professional) |
| Foodzilla Team | Small 2 members and 75 clients, Medium 3 and 150, Large 5 and 300; prices not shown | Seats and active clients are the two dials; enterprise gets a chosen hosting region |
| FoodWorks Professional (Xyris) | AUD 58 a month per user billed annually (AUD 695), AUD 77 monthly, ex GST | The analysis benchmark is cheaper than remembered; confirm Grace's "about $850 a month" figure |
| Nutrium | Roughly USD 28 to 35 a month from third-party listings, unverified | Practice-management positioning at a lower price |

**Packaging implications for Stage 4**

- Two dials, seats and active clients, are what the market understands. Price on both and keep AI usage inside the tier with a cap rather than metered billing.
- Put forms, consent, notes with sign and lock, and the client app in the middle tier, where Foodzilla puts them; put verification, the constraint report and Australian data in every tier, because they are the reason to choose us.
- Charge AUD inclusive of GST on the Australian page and say so; Foodzilla's AUD page and USD pricing page disagree, which reads badly.
- A starter library licence (the verified Grams of Health library seeded into a new practice) is a lever no competitor has; price it as an add-on or as the difference between tiers.
- White-label app-store listings are a paid add-on with a lead time, not a tier; Foodzilla's 6 to 8 weeks is the market expectation.
- Cliniko users are a known segment in Australia; a discount for them is cheap acquisition if the integration is solid.


---

# Intake and check-in form specification

21 October 2026 · Ben Leghissa

File as docs/forms-spec.md. Roadmap items 2D.1 to 2D.4, 2D.8, C2. The builder is Foodzilla's scope plus file upload and reminders; the templates are starting points for Nikki to reword; the draft rules are ours and fixed: no form ever sets a target, and allergens and requirements always land as drafts a dietitian confirms.

## Data model and draft rules

**Tables**

| Table | Columns (key ones) | Notes |
| --- | --- | --- |
| forms | id, org_id (Stage 4), title, type (intake, consent, questionnaire, check_in, diary), description, auto_send_on_create, status (active, archived), version, created_by | Templates are rows with is_template true, copied on Use template |
| form_questions | form_id, position, kind, label, helper, required, options jsonb, parent_question_id, show_when_option, maps_to | kind in short_text, long_text, number, date, single_choice, multiple_choice, dropdown, scale, yes_no, signature, info, file. maps_to names the profile field or draft target |
| form_sends | form_id, form_version, client_id, sent_by, sent_at, channel (app, email, staff), due_at, reminder_1_at, reminder_2_at, status (sent, opened, completed, expired) | One row per send; a client can be sent the same form again later |
| form_responses | send_id, client_id, submitted_at, submitted_by (client or staff on behalf), answers jsonb, signature_name, signature_at, locked true | Read-only after submit; corrections are a new send |
| form_drafts | response_id, client_id, target (requirement, food_rule, goal, allergen_tag, supplement, measurement), payload jsonb, status (pending, accepted, rejected), decided_by, decided_at | The draft queue the dietitian works through |

All five tables carry row-level policies: staff by role, clients only their own sends and responses, interns only for allocated clients. Every accept or reject writes to change_log with the response as its source.

**Draft rules (fixed)**

| Answer category | On submit |
| --- | --- |
| Targets of any kind | Never written. Forms collect inputs only; the calculator proposes, the dietitian accepts |
| Allergens, intolerances, diet requirements | form_drafts rows, status pending, shown on the client's Requirements tab as "from intake, unconfirmed". The screening treats a pending allergen as blocked until decided, which is the safe direction |
| Goals | form_drafts rows; the dietitian confirms and sets the primary |
| Dislikes, avoids, favourite foods, cuisines, cooking confidence, budget, household size | Written directly to client preferences with source = form and the response id |
| Height, current weight, date | Written to the weight log with source = form, flagged client-reported |
| Measurements (waist, hips, body fat) | Written to measurements with source = form |
| Medications, supplements, conditions | Supplements to client_supplements with source = form; medications and conditions to a draft for the clinical record, clinician-only |
| Check-in scales and notes | Written to client_checkins with source = form |
| Files | Stored in client-documents as pending until filed; pathology and referrals filed into client-clinical by a clinician |
| Signature | Name typed, timestamp, form version, IP, stored on the response and mirrored to the consent register when the form type is consent |

## Template 1: Initial intake

About ten minutes to complete, as Foodzilla's own guidance suggests. Deeper assessments (24-hour recall, food frequency) are separate forms. Wording is a starting point for Nikki; field kinds and mappings are the spec.

| # | Question (paraphrased) | Kind | Required | Maps to | Follow-up |
| --- | --- | --- | --- | --- | --- |
| 1 | Date of birth | date | yes | client.dob | |
| 2 | Sex recorded at birth, and the sex to use for energy calculations if different | single_choice, single_choice | yes | client.sex, client.energy_sex | |
| 3 | Height (cm) | number | yes | client.height_cm | |
| 4 | Current weight (kg) and the date weighed | number, date | yes | weight log, client-reported | |
| 5 | What brings you to see a dietitian | long_text | yes | goal draft | |
| 6 | Main goal | single_choice from goal_types (incl. Performance) | yes | goal draft, primary | If Performance: sport, training days per week, session times (short_text, number, multiple_choice) feeding day-type pattern |
| 7 | Typical activity outside training | single_choice from activity_levels | yes | client.activity_level | |
| 8 | Do you have any food allergies or intolerances | yes_no | yes | | If yes: which foods and what happens (long_text) plus tag picker of allergen tags (multiple_choice) to allergen draft |
| 9 | Do you follow a particular way of eating | yes_no | yes | | If yes: diet tag picker (vegan, vegetarian, gluten-free, halal, kosher, low FODMAP and so on) to requirement draft |
| 10 | Foods you will not eat | multiple_choice over foods with free text | no | food rules, avoid | |
| 11 | Foods you would rather not eat | same | no | food rules, dislike | |
| 12 | Foods and meals you love | long_text | no | preferences.favourites | |
| 13 | Cuisines you enjoy | multiple_choice | no | preferences.cuisines | |
| 14 | Diagnosed medical conditions | yes_no | yes | | If yes: multiple_choice (diabetes type 1, type 2, gestational, PCOS, coeliac, IBS, kidney disease, heart disease, thyroid, other) plus long_text, to clinical draft; triggers gateways in section 5 |
| 15 | Are you pregnant, breastfeeding or planning pregnancy | single_choice | yes | clinical draft, gateway | |
| 16 | Medications | yes_no | yes | | If yes: long_text to clinical draft; a tick for GLP-1 medication opens the GLP-1 gateway |
| 17 | Supplements | yes_no | yes | | If yes: repeating rows (name, dose, when) to client_supplements |
| 18 | History of disordered eating or a difficult relationship with food | single_choice (yes, no, prefer not to say) | yes | gateway only, clinician-visible | |
| 19 | A typical day of eating | long_text | yes | intake notes | |
| 20 | Meals and snacks you usually have | multiple_choice (breakfast, morning snack, lunch, afternoon snack, dinner, supper) with times | yes | meal slot suggestions, confirmed by dietitian | |
| 21 | Who cooks and who shops | single_choice | no | preferences | |
| 22 | Time to cook on a weeknight | single_choice (under 15, 15 to 30, 30 to 60, over 60 minutes) | yes | preferences.cook_time | |
| 23 | Cooking confidence | scale 1 to 5 | yes | preferences.cooking_confidence | |
| 24 | Weekly food budget | single_choice bands | no | preferences.budget | |
| 25 | Household size, adults and children | number, number | yes | preferences.household | |
| 26 | Usual supermarkets | multiple_choice (Woolworths, Coles, Aldi, IGA, Harris Farm, markets, other) | no | preferences.supermarkets, shopping aisles | |
| 27 | Sleep hours and quality | number, scale | no | check-in baseline | |
| 28 | Stress | scale 1 to 5 | no | check-in baseline | |
| 29 | Alcohol per week | single_choice bands | no | intake notes | |
| 30 | Upload recent blood tests, referral or care plan | file, several | no | client-documents pending; clinician files to client-clinical | |
| 31 | Anything else your dietitian should know | long_text | no | intake notes | |
| 32 | GP name and practice, referral date | short_text, date | no | clinical record; Medicare item 2F.4 | |

## Template 2: Consent, and Template 3: Meal plan preferences

**Consent to nutrition services** (type consent, auto-send on creation, required before the client app opens)

| # | Content | Kind | Maps to |
| --- | --- | --- | --- |
| 1 | What the service is and is not (not medical diagnosis; dietitian scope) | info | |
| 2 | Privacy: what is stored, where (Sydney), who sees it (assigned dietitian, allocated interns, the practice owner), retention | info with a link to the policy version | consent register, policy_version |
| 3 | I agree to the privacy policy | yes_no, required yes | consent register |
| 4 | I agree that consults may be recorded and transcribed for note-taking, and that transcripts are processed by an AI service outside Australia with identifying details removed | yes_no, optional | consent register, ai_transcripts |
| 5 | I agree that documents I upload may be read by an AI service to draft values my dietitian checks | yes_no, optional | consent register, ai_documents |
| 6 | I agree that my dietitian may share my plan with a supervising intern | yes_no, optional | consent register, intern_access |
| 7 | Signature: full name typed | signature | response.signature_name, signature_at |

Each optional consent is its own flag the app checks before the matching AI feature runs on that client. Revoking a consent is a new response that supersedes the old one; the register keeps both.

**Meal plan preferences** (type questionnaire; the one Foodzilla calls a smart form)

| # | Question | Kind | Maps to |
| --- | --- | --- | --- |
| 1 | Meals and snacks you want in your plan, with usual times | multiple_choice with times | meal slot suggestions, confirmed by the dietitian in Variety and structure |
| 2 | How much variety do you like | scale 1 to 5 (same meals weekly to something different every day) | structure.variety suggestion |
| 3 | Happy to cook once and eat leftovers the next day | yes_no | structure.batch_cooking |
| 4 | Days you train hard, moderately, rest | weekly grid of single_choice | day-type pattern suggestion |
| 5 | Proteins you enjoy and proteins you avoid | multiple_choice from protein_families, two questions | protein likes and dislikes |
| 6 | Foods you avoid and foods you dislike | as intake 10 and 11 | food rules |
| 7 | Dishes you would like to see | long_text | intake notes |
| 8 | Breakfast on the go or sit-down | single_choice | slot kind |
| 9 | Any free-choice meals you want left open (eating out, family dinner) | multiple_choice over slots and days | slot state free_choice |

Slot and day-type suggestions appear on the client's Variety and structure tab as a proposal the dietitian applies with one click, so the generator's inputs are always dietitian-set.

## Template 4: Check-in, and Template 5: Food and symptom diary

**Weekly check-in** (type check_in, scheduled per client weekly or fortnightly, due the day before the consult when one is booked)

| # | Question | Kind | Maps to |
| --- | --- | --- | --- |
| 1 | How did the week feel overall | scale 1 to 5 | checkins.feeling |
| 2 | Hunger | scale 1 to 5 | checkins.hunger |
| 3 | Energy | scale 1 to 5 | checkins.energy |
| 4 | Sleep | scale 1 to 5 | checkins.sleep |
| 5 | Digestion, Bristol chart with pictures | scale 1 to 7 | checkins.bristol |
| 6 | Training sessions completed | number, with planned shown | checkins.training |
| 7 | Weight, optional | number | weight log, client-reported |
| 8 | Meals you liked | long_text or picker over the plan's recipes | checkins.likes; recipe feedback |
| 9 | Meals you did not like or skipped | same | checkins.dislikes; feeds applyDislike as a proposal |
| 10 | What you would like changed | long_text | checkins.changes |
| 11 | Wins and barriers | long_text | checkins.notes |
| 12 | Progress photo, optional, up to five | file (image) | progress photos |
| 13 | GLP-1 dose this week, shown only when the GLP-1 flag is on | number, date | dose log |

The trend strip reads these directly. Nothing in a check-in changes a plan; dislikes become proposals in the plan's edit tools.

**Food and symptom diary** (type diary, 3-day and 7-day variants; the Multi-day recall is the same form without symptoms)

| # | Per meal | Kind | Maps to |
| --- | --- | --- | --- |
| 1 | Time | time | diary entry |
| 2 | What you ate and drank, in your words, with rough amounts | long_text | diary entry text |
| 3 | Hunger before and fullness after | scale 1 to 5, two | diary entry |
| 4 | Symptoms after, if any | multiple_choice (bloating, pain, reflux, urgency, headache, other) with onset time | diary entry |
| 5 | Photo, optional | file | diary entry |

Per day: sleep hours, bowel motions with Bristol, stress, notes. On submit nothing is computed. The dietitian presses Analyse: AI-2's matcher maps each line to foods IDs with grams in Australian measures, every match shown for correction, totals computed by the engine and labelled estimate, nothing written to the food log unless the dietitian presses Push to log. The analysis is saved as a draft note on the client.

## Screening gateways

A gateway is an intake answer that changes what the system does next. None sets a target or a requirement by itself; each raises a flag the dietitian sees first.

| Gateway | Trigger | What happens on submit | What the dietitian sees |
| --- | --- | --- | --- |
| Allergy | Q8 yes | Allergen drafts; screening treats them as blocked until decided | Requirements tab banner: N allergens from intake to confirm |
| Diet requirement | Q9 yes | Requirement drafts | Same banner |
| Pregnancy or breastfeeding | Q15 | Clinical draft; calculator shows a warning and will not propose a deficit; generator excludes recipes tagged raw fish, soft cheese, deli meat once those tags exist | Red flag on the client header until reviewed |
| Diabetes or gestational diabetes | Q14 | Clinical draft; carbohydrate distribution per slot surfaced in the generator settings | Flag |
| Kidney disease | Q14 | Clinical draft; protein g/kg default lowered in the calculator's proposal with the reason shown; Renal label suggested | Flag |
| Coeliac | Q14 | Gluten-free requirement draft, blocked until decided | Flag plus requirement banner |
| GLP-1 medication | Q16 tick | Clinical draft; GLP-1 flag on the client; check-in shows the dose question; protein guidance line in the calculator explainer; GLP-1 friendly label suggested | Flag |
| Disordered eating history | Q18 yes or prefer not to say | Clinician-only flag; client app show-numbers forced hidden and locked until a dietitian unlocks; check-in hides the weight question by default | Flag visible to dietitians only, never to interns |
| Under 18 | Q1 | Calculator warns (already built); consent requires a guardian name field | Flag |
| Performance goal | Q6 | Day-type pattern suggestion from training days | Proposal on Variety and structure |

Flags live in a client_flags table (client_id, flag, source response, raised_at, reviewed_by, reviewed_at). Reviewing a flag never deletes it; it records who looked and when.

## Delivery, reminders, tracking and the staff path

**Delivery**

- Auto-send on client creation for forms with the flag set (intake and consent by default). Each send gets a signed link valid 14 days, emailed through Resend with the practice's branding and no unsubscribe link, and shown in the client app once it exists.
- Manual send from the client page or the forms list; the same form can be sent again later (a new send, a new response).
- Scheduled sends for check-ins: per client, weekly or fortnightly on a chosen weekday, due before the next consult when one is known from Cliniko.
- Staff on behalf: a dietitian or intern can open any send and complete it with the client during a consult; the response records submitted_by as staff and the client's name as the subject. Until the client app exists this is the main path.

**Reminders**: 48 hours and 5 days after sending if not completed, then the send expires at 14 days and shows as expired; the dietitian can resend. Reminders are email now, push later. Foodzilla has none; this is a cheap win.

**Tracking**: the forms list shows sent, opened, completed and expired counts per form; the client page shows a Forms section with each send's status; a Needs-attention item for intake not completed within 7 days of creation.

**Responses**: read-only after submit; shown as the question list with answers; the draft queue beside it with Accept and Reject per row; accepted rows write to the profile with change_log entries citing the response. The client can see their own completed forms in the app.

**Versions**: editing a form bumps its version; sends carry the version they went out with; responses render against that version so old answers never misalign with new questions.

## Acceptance tests

- A form with a required follow-up hidden behind a No answer submits without it; with Yes it refuses until answered.
- Submitting intake with two allergens creates two pending drafts, and client_recipe_screen returns blocked for recipes containing either tag before any decision.
- Rejecting an allergen draft removes the block and logs who rejected it and when.
- No column in client_targets changes as a result of any form submission; a test submits every template and asserts the targets table is untouched.
- A disordered-eating gateway hides numbers in the client app and the check-in weight question, and the flag is invisible to an intern account.
- A consent response with AI transcription declined blocks AI-3 for that client; accepting a later consent unblocks it, and both responses remain.
- Reminders fire at 48 hours and 5 days for an uncompleted send and not for a completed one; the send expires at 14 days.
- A form edited after a send still renders the old response against the old version.
- Staff-on-behalf responses show submitted_by as the staff user and appear in the client's own list of completed forms.
- Row-level security: a client reads only their own sends and responses; an intern reads only allocated clients' forms and never the disordered-eating flag.


---

# Engineering foundations and SaaS platform specification

21 October 2026 · Ben Leghissa

File as docs/platform-spec.md. Roadmap items 1E.5 to 1E.7, 1C.10, 2D.8, 2D.9, T1 to T7. Everything here is backend and operations; none of it changes what a dietitian sees except the lifecycle screens. Stage 1 items can start now; the organisation model can start once Gate 2 is in sight, because it is pure schema work.

## Environments, CI and release

**Environments**

| Environment | What it is | Data | Who |
| --- | --- | --- | --- |
| Local | Supabase CLI stack from supabase/migrations plus seed CSVs | Seed only | Claude Code |
| Staging | A Supabase branch of the live project, reset from a sanitised snapshot weekly (client names, contacts and clinical files replaced; foods and recipes real) | Sanitised copy | Claude Code, Lovable preview, dietitian QA |
| Live | Project xtbjbaliyrswleggezkm, Sydney | Real | Staff |

Lovable publishes a preview build pointed at staging for every prompt; the live build switches only after the QA script in that prompt passes on staging and Claude Code has read the code at the commit.

**CI on every push (GitHub Actions)**

1. npm test: engine, adjust, energy, planner fixtures (the generator's acceptance fixtures once 2B lands).
2. Migrations applied to a fresh local stack, then every tests/sql/*.test.sql, each self-rolling-back.
3. Engine parity: scripts/check-line-grams.ts against the staging branch, expect 0 mismatches.
4. Plan totals invariant (1D.2) over every plan in staging.
5. Lovable copy check: src/lib/energy.ts and the engine copy byte-identical to the packages.
6. Policy leak tests: a pending account, a client account and a second-practice account each attempt reads and writes on every table; any row returned fails the build.
7. Type generation (supabase/types.ts) diffed and committed.

**Release rules**

- Migrations are forward-only, numbered, with a snapshot into seed/archive before any destructive step (already the rule; CI refuses a migration containing DROP or DELETE without a matching archive file).
- A release note per migration batch in docs/releases, dated, in plain words, is what the Changes inbox links to.
- Edge Functions deploy from the repo only; secrets are set through the dashboard and listed by name in docs, never by value.
- The engine package has a CODEOWNERS entry requiring explicit approval for any change.

## Backups, monitoring and analytics

**Backups**

- Point-in-time recovery on the live project confirmed in the dashboard; retention set to the plan's maximum.
- A restore rehearsal once a quarter into a branch, timed, with the result noted in docs/ops-log.md.
- Storage buckets (clinical-records, client-documents, practice-resources, media) versioned, with a nightly copy to a second bucket in the same region.
- Before every destructive migration, the existing seed/archive snapshot rule.

**Monitoring**

| Signal | Source | Where it goes |
| --- | --- | --- |
| Edge Function errors and p95 latency | Supabase logs | One alert channel (email to Ben now, a chat channel later) |
| Auth failures, new sign-ups, role changes | auth logs and change_log | Same |
| Slow queries over 2 seconds | pg_stat_statements | Weekly digest |
| AI spend against the monthly guard | ai_requests | Alert at 80% and 100% |
| Security advisors | Supabase advisors | Weekly digest |
| Uptime of the Lovable app and the PDF renderer | External ping | Alert |

**Analytics (no client identities)**

- Events table: plan_generated, plan_approved, plan_published, swap_applied, ai_proposal_accepted or rejected, form_sent, form_completed, checkin_submitted, client_app_opened, booklet_exported; each with org, staff role, timestamp, and the client's id hashed.
- A weekly digest per practice: plans generated to published, average edits per plan, AI acceptance rate, check-in completion, intake completion within 7 days, pool size and verification counts.
- Gate reports (the pool report) are a query over the same tables, dated and stored.

## Client and staff lifecycle

**Client states**: lead (from a discovery form or Cliniko import, no plan yet), active, paused, archived, deletion_requested, deleted. Transitions are logged. Archived clients keep all data and drop out of lists, the generator and the client app; paused keeps the app but stops scheduled check-ins and auto-generation.

**Transfer between dietitians**: a transfer writes the new assignment, keeps every plan, note, check-in and message, grants the new dietitian visibility of the message history, and records the handover in change_log. Interns allocated to the client stay allocated unless the new dietitian removes them. A covering dietitian can be set per client with a start and end date for leave, which answers the Foodzilla complaint about invisible chats.

**Deletion**: a client or a practice admin can request deletion; a 30-day hold follows during which the record is read-only and flagged; then personal data is removed, clinical files purged from storage, and anonymised rows kept for the analytics counts only. The consent register keeps a tombstone (hashed id, dates, what was agreed) for the record. Export before deletion is a zip of plans as PDFs, notes, check-ins, forms and files.

**Intern supervision**: every intern write on plans, notes and forms creates a draft owned by the supervising dietitian (the client's assigned dietitian), shown in a Supervision inbox with approve, edit and reject; interns never see clinical records, the disordered-eating flag, AI diffs or verification controls; the intern's name stays on the accepted draft as its author.

**Staff onboarding**: invite by email with a role; the link expires in 7 days; first sign-in walks through a checklist (the eight principles, how verification works, how to read a constraint report, how to approve a diff), then a shadow client seeded on staging for a practice run, then the owner allocates the first real client. Two-factor is required before the first real client appears for admin and dietitian roles. Removing a member keeps their authored data and transfers their clients in one step.

## Multi-practice isolation

**Model**: organisations (id, name, slug, region, plan_tier, branding jsonb, settings jsonb, status). Every practice-owned table gains org_id not null with a foreign key; reference tables (AFCD rows, AMDR bands, tag vocabularies, measure conventions, activity levels, goal types, protein families) stay global and read-only to practices, with an org-level override table where a practice needs its own entries (custom tags, slot names).

**Policies**: one helper, current_org(), reads the organisation from the session's JWT claim set at sign-in; every policy is org_id = current_org() AND the existing role rule. The platform-owner role has no read on practice tables by default; a support_grants table (org, granted_by, expires_at, reason) opens time-boxed access, logged on every read.

**Storage**: bucket paths prefixed org_id/; policies match the prefix; signed URLs expire in 5 minutes for clinical, 60 for documents.

**Edge Functions**: the organisation comes from the verified JWT, never from the request body; every function asserts it before any query.

**Libraries**: each practice owns its foods and recipes. Onboarding can copy the Grams of Health starter library (foods, measures, tags, recipes, variations, verification states) into the new organisation as a one-time copy with provenance (source_recipe_id, copied_at); later edits on either side never cross. The starter library's licence terms are a billing item, not a technical link.

**Leak tests in CI**: fixtures create two organisations, a client in each, a staff member in each, a pending account, a client account; a script attempts every read and write path (tables, views, RPCs, storage, Edge Functions) across the boundary and fails on any success. Re-run on every push forever.

**Migration of today's data**: one organisation row for Grams of Health; every existing row stamped in one migration with a snapshot first; policies swapped in the same migration so there is never a moment with org_id present and policies absent.

## Public API, Zapier and bulk import

**API (T7, read first)**

- Keys per organisation, shown once, revocable, scoped (read, write-drafts); every call logged with key id, endpoint, rows, latency.
- Read endpoints: clients (identity and goals only, no clinical), published plan versions, recipes and foods with verification state, check-ins, forms and responses.
- Write endpoints follow the draft rules: create client (lead state), send a form, create a recipe (Needs review), create a food (unverified), submit a check-in on behalf. No endpoint sets verified, targets, requirements or publishes a plan.
- Rate limits per key; OpenAPI document generated from the Edge Functions.

**Zapier app**: triggers for new client, form completed, plan published, check-in submitted; actions for create client, send form, add note (draft). Built on the API above, so it inherits the rules.

**Bulk import at onboarding (T4)**

| Import | Format | Lands as | Checks |
| --- | --- | --- | --- |
| Clients | CSV with name, email, DOB, sex, height, weight, dietitian; or Cliniko | lead or active, no targets | Duplicate email, DOB sanity |
| Foods | CSV per 100 g with energy, protein, fat, carbs (available), fibre, optional nutrients, measures with grams, allergen tags | unverified, measures flagged estimated unless grams given | Energy-vs-macro check, density > 0, grams > 0 |
| Recipes | CSV or AI-2 paste; ingredient lines by food name and quantity and unit | Needs review; unmatched foods become "new food needed" | Line grams must resolve or the line is flagged |
| Documents | Zip per client | client-documents pending | Virus scan, size limit 100 MB per file |

Every import writes a change_log batch with the file name and row counts, and a report the admin downloads: imported, flagged, rejected with reasons.

## White-label app-store process and branding

**Branding (T3)**: organisation settings hold name, logo, two colours, support email and the web address; applied to the staff app header, the client web app, booklets, recipe cards, nutrition tables and every email. A preview page shows all five surfaces before saving. The client web app at a practice path (for example app.gramsofhealth.com.au or a subdomain per practice) picks branding from the address.

**Shared branded app (C6)**: one app-store listing for the platform; a client signs in and sees their practice's branding. This is the default for every tier and covers most practices.

**Own app-store listing (T7, paid add-on)**: a per-practice build of the same codebase with the practice's name, icon, splash and description, submitted under the practice's own developer accounts (Apple requires the practice to hold the account; Google allows ours). Process: collect assets and a signed authority, build, internal test, submit, review, publish; allow six to eight weeks, the market expectation Foodzilla set. Updates ship to every listing from one pipeline. The add-on covers the build and the annual re-submission effort.

**Email**: Resend with a verified sending domain per practice (DNS records the admin adds), practice branding, plain language, no unsubscribe link on transactional practice mail; marketing mail is not a feature.

## Compliance, consent and data-use statements

Kept to what the build needs; the legal review is outside this document.

- Hosting: confirm the Supabase project region is Sydney in project settings and state it on the privacy page; Edge Functions run in the same region.
- AI processing: a one-paragraph statement naming the provider, that client data is minimised (ids not names, no staff notes, clinical files only for the document reader), that outputs are drafts a dietitian confirms, and the retention of transcripts (decision 11). Consent flags per client (forms spec, template 2) gate each feature.
- Consent register: per client, per policy version, who, what, when, how (app, form, staff on behalf); exportable; tombstoned on deletion.
- Access log: every read of a clinical file and every support-grant use, kept for the retention period, visible to the practice owner.
- Retention: a per-practice setting with a default (to decide), applied by a scheduled purge after the deletion hold; plans, notes and check-ins kept for the period; clinical files purged first.
- Export: per client and per practice, on request, as a zip of PDFs and CSVs within 7 days.
- Two-factor for staff; leaked-password protection; key rotation on a calendar; a security page listing these in plain words.
- Data processing terms for practices on the SaaS tier, referencing the above.
