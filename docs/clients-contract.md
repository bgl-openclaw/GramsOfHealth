# Clients module — backend contract (C3)

Source of truth for the C4 Lovable prompts. Backend migrations 0026–0031 (live 2026-10-15).
Types: `supabase/types.ts` (regenerated). Everything in the Client tab is entered by staff.

## Access (enforced by RLS — the UI only mirrors it)

| Role | Clients | Check-ins | Clinical | Targets |
|---|---|---|---|---|
| admin, dietitian ("clinician") | all | all | read/write | read/write |
| intern | only clients ticked for them in `client_staff_access` | only if `can_view_checkins` ticked for that client | never | read only |
| pending / anyone else | none | none | none | none |

- Allocation: clinicians insert/delete `client_staff_access(client_id, profile_id, can_view_checkins)`.
- Roles live in `profiles.role` (`admin | dietitian | intern | pending`); invitations accept `intern`.
- Plans linked to a client follow the client's access; unlinked plans (templates) are visible to all staff.
- RPC helpers callable from the app: `is_clinician()`, `is_staff()`, `current_staff_role()`.

## Client editor sections → storage

| Section | Tables / views / RPCs |
|---|---|
| Identity | `clients`: full_name, email, phone, date_of_birth, sex (`female|male|other|unspecified`), equation_sex (`male|female`, only when sex is other/unspecified), height_cm, activity_level (→ `activity_levels.key`), assigned_dietitian (→ profiles), status (`active|paused|finished`), protein_g_per_kg, notes (staff-only) · goals: `client_goals` (goal_type → `goal_types`, detail, target_date, is_primary — at most one active primary, ended_on) |
| Weights | `client_weights` (weight_kg, recorded_on, note, checkin_id?, source) |
| Targets | write: insert into `client_targets` (append-only history; clinician only). read: `client_current_targets` (latest per day_type). day_type `default|hard|moderate|rest`. |
| Calculator | `client_energy_inputs(p_client_id, p_as_of)` → `energyInputsFromRow()` → `estimateEnergy()` (src/lib/energy.ts = byte-identical copy of packages/energy/src/index.ts). Accept → insert `client_targets` with `source='calculator_accepted'` and `calc_inputs` = result.working + `bmr`, `tdee`, `factor`, `protein_g`, plus the suggested values. DB refuses calc_inputs without `as_of, weight_kg, height_cm, age_years, sex_constant, bmr`. Edited-before-accept values are still `calculator_accepted`; the working shows the suggestion. |
| Requirements | `client_requirements(client_id, tag_id)` — allergen tag = avoid it; dietary/diet tag = avoid its `tag_blockers`; tag with neither (Heart-healthy, Diabetes-friendly) = prefer. Read-outs: `client_blocked_tags`, `client_preferred_tags`. |
| Food rules | `client_food_rules(client_id, food_id, rule 'avoid'|'dislike', primary_only)` — avoid = never; dislike = soft; primary_only = only where the food is ≥10% of recipe weight. |
| Preferences | `client_protein_preferences(protein_family, 'like'|'dislike')`, `client_supplements(name, dose, timing, notes, started_on, ended_on, position)` |
| Variety & structure | save the whole section with `save_client_structure(p_client_id, p_settings, p_slots, p_protein_spread)` (one transaction; null argument = leave that part). Read `client_structure`, `client_meal_slots` (position, name, slot_kind `breakfast|lunch|dinner|snack`, time_of_day, free_choice), `client_protein_spread`. day_type_pattern = 7 entries, Monday→Sunday. |
| Clinical | `client_clinical_records(kind 'dexa'|'bloods'|'other', recorded_on, summary, measurements jsonb, file_path)`; files in private bucket `clinical-records` at `{client_id}/{filename}` (PDF/JPEG/PNG/HEIC, ≤20 MB); open with a signed URL. Hide the section entirely for interns. |
| Check-ins | `client_checkins(checkin_on, feeling/hunger/energy/sleep 1–5, bowels_bristol 1–7, bowels_notes, training, likes, dislikes, changes_wanted, notes, answers jsonb, source, entered_by)`. Scales: feeling/energy/sleep 1 = very poor … 5 = great; hunger 1 = never hungry … 5 = always hungry. A weight entered with a check-in → also insert `client_weights` with that `checkin_id`. |
| Plans | `meal_plans where client_id = …` |
| Clients list | `client_overview` (name, status, assigned dietitian, primary goal, latest weight + date, latest check-in, default kcal, plan count) |

## Recipe screening for a client

`client_recipe_screen(p_client_id)` → one row per recipe:
`status` = `blocked` (contains a blocked tag or an avoid-food) › `unconfirmed` (client has allergen/diet requirements and the recipe has unverified ingredients — its "contains" tags can't be trusted) › `disliked` › `ok`; `reasons text[]` (show verbatim); `preferred_tags`; `main_protein_families`; `liked_protein`.
Never treat `unconfirmed` as safe. Replaces `RESTRICTION_BLOCKERS` / `restrictionConflicts` in src/lib/planner.ts.

## Lookups (staff read, admin write)
`activity_levels(key, label, factor, position, active)` · `goal_types(key, label, category, position, active)` · `protein_families(key, label, position, active)` · `tag_blockers(tag_id, blocks_tag_id)`. `foods.protein_family` is set by dietitians on the food page.

## Read models
`line_grams` (grams per ingredient line; null = unresolvable) mirrors packages/engine `toGrams` exactly — `scripts/check-line-grams.ts` proves parity over every live line. `line_priceability` now derives from it. `recipe_protein_families` (family grams per recipe, `is_main`).

## Cutover (C4a → C5)
`clients.kcal_target / protein_target_g / carb_target_g / fat_target_g / fibre_target_g` and `clients.restrictions` stay until the app (client editor AND plan editor) reads `client_current_targets` and `client_recipe_screen`. C5 shows a before/after diff, then drops them on approval.
