/**
 * Import the FULL recipe library (full_library/) into Supabase.
 *
 * Idempotent and de-duplicating, matching scripts/import.ts conventions:
 *   - afcd_master, foods            : upsert on natural key (re-run safe)
 *   - unit_conversions              : upsert on (food_id, unit)
 *   - recipes                       : delete-by-title then insert (one copy each)
 *   - ingredient_lines, method_steps: inserted per recipe (cascade-deleted with it)
 *
 * Extends the seed importer with: method_steps, image_url_1/2 (built from the
 * image manifest slug + the public bucket base), show_macros_export, and a
 * SKIP rule for ingredient lines that have no resolvable food / quantity / unit
 * (garnish flourishes, "to taste", dropped un-parseable text) so the NOT NULL
 * FK columns on ingredient_lines never get a null.
 *
 * Usage:
 *   1. Place this file in scripts/ alongside import.ts (it reuses ./supabase).
 *   2. Ensure .env has SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY.
 *   3. Drag-drop full_library/media/* into Storage -> recipe-images (public).
 *   4. npx tsx scripts/import_full_library.ts
 */
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { parse } from "csv-parse/sync";
import { supabase } from "./supabase";

const HERE = dirname(fileURLToPath(import.meta.url));
// full_library/ lives at the repo root next to seed/
const DATA_DIR = process.env.GOH_DATA_DIR ?? join(HERE, "..", "full_library");
const PUBLIC_BASE =
  `${process.env.SUPABASE_URL}/storage/v1/object/public/recipe-images`;

const CHUNK = 500;

const num = (v?: string): number | null =>
  v === undefined || v.trim() === "" ? null : Number(v);

const readCsv = (file: string): Record<string, string>[] =>
  parse(readFileSync(join(DATA_DIR, file), "utf8"), {
    columns: true,
    skip_empty_lines: true,
    trim: true,
  });

async function upsertChunked(table: string, rows: object[], onConflict: string) {
  for (let i = 0; i < rows.length; i += CHUNK) {
    const { error } = await supabase
      .from(table)
      .upsert(rows.slice(i, i + CHUNK) as never, { onConflict });
    if (error) throw new Error(`${table} upsert failed: ${error.message}`);
  }
  console.log(`  ${table}: upserted ${rows.length} row(s)`);
}

async function importFoods() {
  const rows = readCsv("foods.csv").map((r) => ({
    food_id: r.food_id,
    display_name: r.display_name,
    afcd_key: r.afcd_key || null,
    source: r.source as "afcd" | "custom",
    energy_kcal_100g: num(r.energy_kcal_100g),
    protein_100g: num(r.protein_100g),
    fat_100g: num(r.fat_100g),
    carb_avail_100g: num(r.carb_avail_100g),
    fibre_100g: num(r.fibre_100g),
    density_g_ml: num(r.density_g_ml),
    verified: false,
    match_note: r.match_note || null,
  }));
  await upsertChunked("foods", rows, "food_id");
}

async function importConversions() {
  const rows = readCsv("unit_conversions.csv").map((r) => ({
    food_id: r.food_id,
    unit: r.unit,
    grams: Number(r.grams),
    basis: r.basis || null,
  }));
  await upsertChunked("unit_conversions", rows, "food_id,unit");
}

interface Ing {
  food_id: string | null;
  quantity: number | null;
  unit: string | null;
  prep: string;
  section?: string;
}
interface Recipe {
  title: string;
  slug: string;
  servings: number;
  time_minutes: number | null;
  ingredients: Ing[];
  method: string[];
  show_macros_export: boolean;
}

function imageUrls(slug: string, manifest: Map<string, Record<string, string>>) {
  const m = manifest.get(slug);
  const url = (f?: string) => (f && f.trim() !== "" ? `${PUBLIC_BASE}/${f}` : null);
  return { image_url_1: url(m?.image_1), image_url_2: url(m?.image_2) };
}

async function importRecipes() {
  const recipes: Recipe[] = JSON.parse(
    readFileSync(join(DATA_DIR, "recipes.json"), "utf8"),
  );
  const manifest = new Map<string, Record<string, string>>();
  for (const r of readCsv("image_manifest.csv")) manifest.set(r.slug, r);

  let skipped = 0;
  for (const recipe of recipes) {
    await supabase.from("recipes").delete().eq("title", recipe.title);

    const { image_url_1, image_url_2 } = imageUrls(recipe.slug, manifest);
    const { data: inserted, error: insErr } = await supabase
      .from("recipes")
      .insert({
        title: recipe.title,
        servings: recipe.servings,
        time_minutes: recipe.time_minutes,
        show_macros_export: recipe.show_macros_export ?? true,
        image_url_1,
        image_url_2,
      })
      .select("id")
      .single();
    if (insErr || !inserted) throw new Error(`recipes insert: ${insErr?.message}`);
    const recipeId = inserted.id;

    // Only lines with a real food + quantity + unit can satisfy the NOT NULL FK.
    const lines = recipe.ingredients
      .filter((i) => i.food_id && i.quantity != null && i.unit)
      .map((i, idx) => ({
        recipe_id: recipeId,
        food_id: i.food_id,
        section: i.section ?? null,
        position: idx,
        quantity: i.quantity,
        unit: i.unit,
        prep_note: i.prep && i.prep.trim() !== "" ? i.prep : null,
      }));
    skipped += recipe.ingredients.length - lines.length;
    if (lines.length) {
      const { error } = await supabase.from("ingredient_lines").insert(lines);
      if (error) throw new Error(`ingredient_lines: ${error.message}`);
    }

    const steps = recipe.method.map((text, idx) => ({
      recipe_id: recipeId,
      position: idx,
      text,
    }));
    if (steps.length) {
      const { error } = await supabase.from("method_steps").insert(steps);
      if (error) throw new Error(`method_steps: ${error.message}`);
    }
  }
  console.log(
    `  recipes: ${recipes.length} imported, ${skipped} non-resolvable ingredient line(s) skipped`,
  );
}

async function main() {
  console.log(`Importing full library from ${DATA_DIR} …`);
  await importFoods();
  await importConversions();
  await importRecipes();
  console.log("Done.");
}

main().catch((err) => {
  console.error(err instanceof Error ? err.message : err);
  process.exit(1);
});
