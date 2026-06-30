# Full library → Supabase: handoff for Claude Code

Everything needed to import the full recipe library into the existing Grams of Health
Supabase project. The data fits the **current schema with no migration** — `recipes`
already has `show_macros_export`, `image_url_1`, `image_url_2`, and the `method_steps`
table already exists.

## Files (in `full_library/`)

| File | Goes to | Key / dedup |
| --- | --- | --- |
| `foods.csv` | `foods` | upsert on `food_id` |
| `unit_conversions.csv` | `unit_conversions` | upsert on `(food_id, unit)` |
| `recipes.json` | `recipes` + `ingredient_lines` + `method_steps` | recipe replaced by `title` |
| `image_manifest.csv` | builds `recipes.image_url_1/2` | joined to recipes by `slug` |
| `media/` | Storage bucket `recipe-images` | drag-drop (public) |
| `import_full_library.ts` | the importer | — |

## Integrity already guaranteed (no double-ups, no FK breaks)

- **Foods**: 701 rows, every `food_id` unique. Every `unit_conversions.food_id` and every
  recipe ingredient `food_id` exists in `foods.csv` (verified — 0 orphans).
- **Recipes**: 326 unique, de-duplicated by slug (male/female portion variants and
  repeated titles already collapsed).
- **Ingredient lines**: 2,984 importable. The remaining 751 lines have a null
  `food_id`/`quantity`/`unit` (garnishes, "to taste", dropped un-parseable text) and are
  **skipped by the importer** so they never violate the NOT NULL FK columns.
- `verified = FALSE` on every food (dietitian sign-off pending).

## Steps

1. **Copy the importer** into the repo: `cp full_library/import_full_library.ts scripts/`
   (it reuses `scripts/supabase.ts` and the `csv-parse` dep already in the project).
2. **Env**: `.env` needs `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` (same as `npm run import`).
3. **Schema**: apply existing migrations to the project if not already (`supabase db push`).
   No new migration required.
4. **Images**: in the Supabase dashboard, Storage → `recipe-images` (public bucket, already
   created by migration `0003_storage.sql`), drag-drop the contents of `full_library/media/`.
   No service-role key needed for drag-drop. Public URLs become
   `…/storage/v1/object/public/recipe-images/<slug>-N.<ext>`.
5. **Import**: `npx tsx scripts/import_full_library.ts`
   (set `GOH_DATA_DIR` if `full_library/` is not at the repo root).
   Idempotent — safe to re-run; foods/conversions upsert, recipes replace-by-title.

## Notes

- The importer builds `image_url_1/2` from the manifest (`<bucket public base>/<filename>`),
  so import order vs. image upload doesn't matter — re-run the import after uploading images
  if you imported first.
- `recipes.json` carries extra fields (`slug`, `servings_source`, `printed_macros_per_serve`,
  `raw_text`, `needs_review`) for traceability; the importer ignores them.
- 38 recipes had no printed servings and were defaulted to 4 (`servings_source:
  "default-assumed"` in `recipes.json`) — listed in `coverage_report.md` for review.
- Macro confidence tiers are in each food's `match_note` (AFCD direct / AFCD proxy /
  curated estimate / category estimate). Have the dietitian verify category estimates first;
  `coverage_report.md` lists the recipes that depend on them.
