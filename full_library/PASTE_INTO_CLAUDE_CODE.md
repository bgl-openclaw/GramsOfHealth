# Paste this into Claude Code (run from the Grams of Health repo root)

Import the full recipe library in `full_library/` into the Grams of Health Supabase
project. Read `full_library/HANDOFF_claude_code.md` first — it has the schema mapping
and integrity guarantees.

IMPORTANT: use the dedicated Grams of Health Supabase project, NOT the "MyTenure"
lease project. If a GoH project does not exist yet, create a new Supabase project for
it, then proceed.

Do this:

1. Confirm `.env` points at the GoH project: `SUPABASE_URL` + `SUPABASE_SERVICE_ROLE_KEY`.
2. Apply the schema: `supabase db push` (migrations in `supabase/migrations/`). No new
   migration is needed — `recipes` already has `show_macros_export` and `image_url_1/2`,
   and `method_steps` exists.
3. Copy the importer: `cp full_library/import_full_library.ts scripts/`
4. Run it: `npx tsx scripts/import_full_library.ts`
   It is idempotent (foods/conversions upsert on natural keys; recipes replace-by-title),
   skips the 751 ingredient lines with no resolvable food/quantity/unit, and inserts
   method steps. Expect 701 foods, 559 unit conversions, 326 recipes.
5. Upload images: in the Supabase dashboard, Storage -> `recipe-images` (public bucket),
   drag-drop the contents of `full_library/media/` (640 files). The importer already set
   `image_url_1/2` to `<bucket public base>/<slug>-N.<ext>`, so no further wiring is needed.

Then verify: `select count(*) from foods;` (701), `select count(*) from recipes;` (326),
and spot-check that `lentil-tuna-salad` computes ~369 kcal/serve via the engine.
