# Grams of Health — AI roadmap (v1, 15 Oct 2026)

Five AI updates, in build order, plus the shared groundwork they all use. Check-in summaries (beyond transcripts) and the client-app assistant come later.

## The rule every feature follows
**AI proposes · the dietitian decides · the engine does the maths.**
- AI output always lands as a **draft** tagged with the model, prompt version and time that produced it. A person accepts, edits or rejects it.
- AI never sets `verified = true`, never applies tags or client changes by itself (suggested tags/changes need a human tap — the "no auto-tagging" rule stands), and never produces nutrition numbers — every kcal still comes from grams × verified food data via the engine.
- Every accepted AI change goes through the normal save paths, so the change log records it like any other edit.

## Build order at a glance
| Phase | Update | Client data sent to AI? | Rough size | Depends on |
|---|---|---|---|---|
| **AI-0** | Shared groundwork | — | 2–3 days | — |
| **AI-1** | Food label reader | No | ~1 week | AI-0 |
| **AI-2** | Recipe import & clean-up | No | 1–2 weeks | AI-0 (AI-1 helps) |
| **AI-3** | Consult transcript → summary & key points | **Yes** | 1–2 weeks | AI-0 + privacy/consent update |
| **AI-4** | Clinical document reader (bloods, DEXA) | **Yes** | ~1 week | AI-0 + privacy/consent update |
| **AI-5** | Draft meal plans | Yes (profile, de-identified) | 2–3 weeks | **Plans build** (below) |
| Later | Check-in summaries · client-app assistant | Yes | — | AI-3, client app |

Each phase runs: plan → build → verify (my checks + a small accuracy test) → one-dietitian pilot → team rollout. Sizes assume the current pace (backend phase → Lovable prompt → verification round).

---

## AI-0 · Shared groundwork
**What:** the plumbing every feature reuses.
- **Anthropic account + API key** (owner's account; monthly spend limit set in the Anthropic Console). Key stored as a Supabase secret — never in the Lovable app.
- **Supabase Edge Function** scaffold (TypeScript, official Anthropic SDK): checks the caller is signed-in staff (and clinician where needed), calls Claude with **structured outputs** (results always match our fields), records the call.
- **`ai_runs` table:** feature, model, tokens in/out/cached, estimated cost, status, error, who ran it, when. Every AI draft links back to its run.
- **In-app spend guard:** monthly budget per feature; requests stop with a clear message when reached.
- **Feature switches** in Settings so each feature can be turned on per pilot.
- **Accuracy tests:** each feature gets a small real-world test set before rollout (e.g. 20 real labels) and is re-run whenever prompts or models change.
- **Model:** Claude Opus 5.5 by default ($4 / $20 per million tokens in/out; cached input ~$0.20). Cheaper models (Sonnet 5.5 $2/$10, Haiku 5.5 $0.10/$0.50) only if the accuracy test shows quality holds — owner's call per feature. **Prompt caching** for repeated instructions; **Batch API** (50% off) for overnight bulk jobs.

**Done when:** a test call from the app returns structured data, is logged in `ai_runs`, and is refused for a pending account.

---

## AI-1 · Food label reader
**Why first:** no client data, low risk, and it attacks the main bottleneck — 206 unverified foods are what keep recipes out of AI Verified.

**Flow:** Foods → "Add from label" (new food) or "Check against label" (existing food). Upload 1–3 photos (nutrition panel, ingredients/allergen statement, front) or a supplier spec PDF.

**AI extracts (structured):** product name and brand; serving size; **per-100 g** energy, protein, fat, saturated fat, carbohydrate, sugars, dietary fibre, sodium; ingredient list; allergen statement ("Contains: milk, soy").

**Code (not AI) then:**
- Converts kJ → kcal (Australian labels list kJ; kcal = kJ ÷ 4.184).
- Sanity checks: per-100 g vs per-serve mix-ups, components ≤ 100 g, energy vs Atwater (17P + 37F + 17C + 8 fibre kJ) within ~10% — failures flagged, never silently fixed.
- New food → **draft, unverified** food prefilled. Existing food → side-by-side "label vs current" with differences highlighted.
- Allergen statement → **suggested** tags shown as untapped chips; a person taps to apply.

**Stored:** label photos in a private staff-only bucket, linked to the food, for audit.

**Cost:** ~2–3 cents per label (≈ $5 to work through the backlog).
**Accuracy test:** 20 real labels from the pantry, compared field by field with what a dietitian enters.
**Decision needed:** keep label photos permanently (recommended, for audit) or delete after verification.

---

## AI-2 · Recipe import & clean-up
**Import:** paste text, upload a PDF or photo of a recipe card, or give a web link → AI returns title, servings, time, sections, ingredient lines and method steps; code normalises units to Australian measures (tsp 5 mL, tbsp 20 mL, cup 250 mL) and **matches each ingredient to your foods library** through a database search (best matches shown, dietitian confirms). Unmatched ingredients become "new food needed" with a link to the label reader. Saved as a **draft recipe**; the AI Verified badge shows exactly what's left.

**Clean-up:** for existing recipes in Needs review, AI proposes fixes as a review list — e.g. "Sake Small Pinch Salt And Pepper" → cooking sake + salt + pepper (3 lines); "2 large rocket" → "2 handfuls rocket"; missing method steps drafted from the ingredient list. Each proposal is accepted or rejected one by one; accepted ones save normally (logged).

**Backend:** a food-name search function (fuzzy matching) the AI and the app both use.
**Cost:** ~5–10 cents per recipe.
**Accuracy test:** 15 recipes of mixed formats; measure line-level match accuracy and unit correctness.

---

## AI-3 · Consult transcripts → summary & key points
**Start here for #3** (full check-in summaries later).

**Flow:** Client → Consults → "Upload transcript": a text transcript from Fireflies, Zoom, Teams or Otter (.txt, .docx, .vtt/.srt, PDF) or pasted notes. Claude doesn't transcribe audio — the recording tool does that. (Later: pull transcripts straight from Fireflies.)

**AI returns (structured), every point with the transcript quote it came from:**
- **Consult summary** in your practice's template (e.g. presenting concerns · progress since last visit · eating pattern · activity · sleep/stress · goals discussed · agreed actions).
- **Proposed client-record updates**, each a separate accept/reject item: new dislikes or foods to avoid, new requirements (e.g. "diagnosed coeliac" → Gluten), supplements started/stopped, a weight mentioned, goals, preferences, structure changes ("prefers batch cooking on Sundays").
- **Follow-ups** (tasks, referrals, next appointment).
- **Flags** shown prominently for clinical judgement (e.g. possible disordered-eating language, symptoms needing referral). The AI flags; it never decides.
- **Targets are never changed by AI** — discussion about energy/protein is summarised for the dietitian to act on.

**Backend:** `consult_notes` (client, date, transcript file, summary, status draft/approved, run) and `consult_note_items` (kind, proposed change, quote, status pending/accepted/rejected). Transcripts in the private clinical bucket.

**Access:** clinicians only by default (same as clinical records) — decision below.
**Cost:** ~10 cents per 45-minute consult.
**Before go-live (privacy):** update the privacy policy and client consent to cover recording and AI processing by an overseas provider; replace the client's name with "Client" in what's sent where practical; decide transcript retention.
**Decisions needed:** interns access consult notes? keep transcripts after the summary is approved or delete them? the summary template headings.

---

## AI-4 · Clinical document reader
**Flow:** Client → Clinical → "Read document": blood-test PDF/photo or DEXA report → AI returns test date, lab, and each result `{analyte, value, unit, reference range, flag as printed}` plus a short summary → dietitian reviews the table, edits, saves into the client's clinical record (existing private storage, clinician-only).

**Backend:** a small `clinical_analytes` list (Ferritin, Haemoglobin, HbA1c, Vitamin D, B12, Folate, TSH, LDL, HDL, Triglycerides, Glucose, eGFR, ALT, …; DEXA: body fat %, lean mass, VAT, BMD) so names are consistent and results can be **trended over time**. Units are kept as reported; only known pairs (e.g. mmol/L ↔ mg/dL) are converted, in code.
**Cost:** ~3–8 cents per document.
**Accuracy test:** 10 real (de-identified) reports.
**Same privacy prerequisite as AI-3.**

---

## Before AI-5 · Plans build (non-AI)
Draft plans need the planner to understand clients properly first:
- Plans get a **start date** so each day knows its weekday and therefore its **day type** (hard/moderate/rest targets).
- The planner uses the **client's own meal slots** (not the fixed four).
- **Publishing / versioning** of plans (also needed for the client app).
- Day-type-aware balance bars and gap-fill.

## AI-5 · Draft meal plans
**Approach: hybrid — code enforces the rules, AI uses judgement.**
- Code supplies candidates: only recipes the client's screen marks **ok** (never blocked; unconfirmed only when nothing else fits, and flagged), matched to slot kind, with per-serve macros from the engine.
- Claude assembles the plan using tools: get the client profile, search screened recipes, get day totals (engine), adjust portions (existing solver), check rules (repetition gap / max per cycle, protein spread, batch-cooking leftovers).
- Hard rules are checked in code after every step (blocked = rejected, targets within tolerance, repetition rules) — the AI can't break them.
- Output: a **draft plan** with a one-line reason per day ("batch-cooked chilli Mon → Tue lunch; fish twice to meet spread"), opened in the normal plan editor for the dietitian to change and approve.
- Runs in the background (1–3 minutes) with progress shown.

**Cost:** ~30–60 cents per plan.
**Accuracy test:** 10 representative client profiles; scored on rule violations (must be 0), macro accuracy per day type, variety, and a dietitian rating.
**Decision needed:** target tolerance (suggest ±10% energy, protein ≥ target −5%).

---

## Running cost (≈100 active clients, Opus 5.5 throughout)
| Feature | Volume | Approx. |
|---|---|---|
| Labels | backlog ~200, then a few a week | ~$5 once, then cents |
| Recipe import/clean-up | ~100 recipes | ~$10 once |
| Consult transcripts | ~150 consults/month | ~$15/month |
| Clinical documents | ~50/month | ~$3/month |
| Draft plans | ~100/month | ~$30–60/month |
| **Total** | | **~$50–80/month** after the one-off backlog |

Estimates — real usage is measured in `ai_runs` from AI-0 onward.

## Later
- **Check-in summaries:** weekly brief per client from structured check-ins, weights and consult notes (overnight batch).
- **Client-app assistant:** answers only from the client's own plan and your library; escalates to the dietitian.
- **Fireflies integration:** pull transcripts automatically after a consult.
