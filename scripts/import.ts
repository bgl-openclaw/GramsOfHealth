/**
 * `npm run import` — load every seed file into Supabase. Idempotent: safe to
 * re-run. Reference tables upsert on their natural keys; recipes are replaced
 * by title so re-running yields exactly one copy of each.
 *
 * Order matters for foreign keys: afcd_master, then foods, then unit_conversions,
 * then recipes with their ingredient_lines and method_steps.
 */
import { supabase } from "./supabase";
import {
  loadAfcd,
  loadFoods,
  loadConversions,
  loadRecipes,
} from "./seed";

const CHUNK = 500;

async function upsertChunked(
  table: string,
  rows: object[],
  onConflict: string,
): Promise<void> {
  for (let i = 0; i < rows.length; i += CHUNK) {
    const slice = rows.slice(i, i + CHUNK);
    // The client has no generated Database types here, so row shapes are
    // validated by our loaders rather than by supabase-js's generics.
    const { error } = await supabase
      .from(table)
      .upsert(slice as never, { onConflict });
    if (error) throw new Error(`${table} upsert failed: ${error.message}`);
  }
  console.log(`  ${table}: upserted ${rows.length} row(s)`);
}

async function importAfcd(): Promise<void> {
  await upsertChunked("afcd_master", loadAfcd(), "public_food_key");
}

async function importFoods(): Promise<void> {
  await upsertChunked("foods", loadFoods(), "food_id");
}

async function importConversions(): Promise<void> {
  // unit_conversions has a surrogate id; dedupe on the natural (food_id, unit) key.
  await upsertChunked("unit_conversions", loadConversions(), "food_id,unit");
}

async function importRecipes(): Promise<void> {
  const recipes = loadRecipes();
  for (const recipe of recipes) {
    // Replace-by-title keeps re-runs idempotent (cascades delete child rows).
    const { error: delErr } = await supabase
      .from("recipes")
      .delete()
      .eq("title", recipe.title);
    if (delErr) throw new Error(`recipes delete failed: ${delErr.message}`);

    const { data: inserted, error: insErr } = await supabase
      .from("recipes")
      .insert({
        title: recipe.title,
        servings: recipe.servings,
        time_minutes: recipe.time_minutes,
      })
      .select("id")
      .single();
    if (insErr || !inserted) {
      throw new Error(`recipes insert failed: ${insErr?.message}`);
    }
    const recipeId = inserted.id;

    const lines = recipe.ingredients.map((ing, idx) => ({
      recipe_id: recipeId,
      food_id: ing.food_id,
      section: ing.section ?? null,
      position: idx,
      quantity: ing.quantity,
      unit: ing.unit,
      prep_note: ing.prep && ing.prep.trim() !== "" ? ing.prep : null,
    }));
    if (lines.length) {
      const { error } = await supabase.from("ingredient_lines").insert(lines);
      if (error) throw new Error(`ingredient_lines insert failed: ${error.message}`);
    }

    console.log(`  recipe "${recipe.title}": ${lines.length} ingredient line(s)`);
  }
}

async function main(): Promise<void> {
  console.log("Importing seed data into Supabase…");
  await importAfcd();
  await importFoods();
  await importConversions();
  await importRecipes();
  console.log("Done.");
}

main().catch((err) => {
  console.error(err instanceof Error ? err.message : err);
  process.exit(1);
});
