/**
 * Seed loader — reads the CSV/JSON files in `seed/` and shapes them for both
 * the database import and the engine. No database access here.
 */
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { parse } from "csv-parse/sync";
import type { FoodMap, Line } from "@goh/engine";

const HERE = dirname(fileURLToPath(import.meta.url));
export const SEED_DIR = join(HERE, "..", "seed");

const readCsv = (file: string): Record<string, string>[] =>
  parse(readFileSync(join(SEED_DIR, file), "utf8"), {
    columns: true,
    skip_empty_lines: true,
    trim: true,
  });

/** Parse a numeric cell; blank -> null. */
export const num = (v: string | undefined): number | null =>
  v === undefined || v.trim() === "" ? null : Number(v);

/** Parse a numeric cell, treating blank as 0 (matches the Python engine). */
export const num0 = (v: string | undefined): number => num(v) ?? 0;

export const str = (v: string | undefined): string | null =>
  v === undefined || v.trim() === "" ? null : v.trim();

// ---- Raw row types ---------------------------------------------------------

export interface AfcdRow {
  public_food_key: string;
  food_name: string;
  classification: string | null;
  specific_gravity: number | null;
  energy_kcal: number | null;
  protein: number | null;
  fat: number | null;
  satfat: number | null;
  carb_avail: number | null;
  sugars: number | null;
  fibre: number | null;
  sodium_mg: number | null;
}

export interface FoodRow {
  food_id: string;
  display_name: string;
  afcd_key: string | null;
  source: "afcd" | "custom";
  energy_kcal_100g: number | null;
  protein_100g: number | null;
  fat_100g: number | null;
  carb_avail_100g: number | null;
  fibre_100g: number | null;
  density_g_ml: number | null;
  verified: boolean;
  match_note: string | null;
}

export interface ConversionRow {
  food_id: string;
  unit: string;
  grams: number;
  basis: string | null;
}

export interface SeedRecipe {
  title: string;
  servings: number;
  time_minutes: number;
  printed_macros_per_serve?: Record<string, number>;
  data_issue?: string;
  ingredients: Array<{
    food_id: string;
    quantity: number;
    unit: string;
    size_text?: string;
    prep?: string;
    section?: string;
  }>;
}

// ---- Loaders ---------------------------------------------------------------

export function loadAfcd(): AfcdRow[] {
  // The core CSV uses the long AFCD header names; map them to snake_case.
  return readCsv("afcd_master_core.csv").map((r) => ({
    public_food_key: r["Public Food Key"],
    food_name: r["Food Name"],
    classification: str(r["Classification"]),
    specific_gravity: num(r["Specific Gravity"]),
    energy_kcal: num(r["Energy with dietary fibre (kcal)"]),
    protein: num(r["Protein (g)"]),
    fat: num(r["Fat, total (g)"]),
    satfat: num(r["Total saturated fatty acids, equated (g)"]),
    carb_avail: num(r["Available carbohydrate, without sugar alcohols (g)"]),
    sugars: num(r["Total sugars (g)"]),
    fibre: num(r["Total dietary fibre (g)"]),
    sodium_mg: num(r["Sodium (Na) (mg)"]),
  }));
}

export function loadFoods(): FoodRow[] {
  return readCsv("foods.csv").map((r) => ({
    food_id: r.food_id,
    display_name: r.display_name,
    afcd_key: str(r.afcd_key),
    source: (r.source as "afcd" | "custom") ?? "custom",
    energy_kcal_100g: num(r.energy_kcal_100g),
    protein_100g: num(r.protein_100g),
    fat_100g: num(r.fat_100g),
    carb_avail_100g: num(r.carb_avail_100g),
    fibre_100g: num(r.fibre_100g),
    density_g_ml: num(r.density_g_ml),
    verified: /^true$/i.test(r.verified ?? ""),
    match_note: str(r.match_note),
  }));
}

export function loadConversions(): ConversionRow[] {
  return readCsv("unit_conversions.csv").map((r) => ({
    food_id: r.food_id,
    unit: r.unit,
    grams: Number(r.grams),
    basis: str(r.basis),
  }));
}

export function loadRecipes(): SeedRecipe[] {
  return JSON.parse(readFileSync(join(SEED_DIR, "recipes_validation.json"), "utf8"));
}

/**
 * Build the engine's FoodMap from the food and conversion rows: per-100g
 * macros with each food's size-to-grams weights embedded.
 */
export function buildFoodMap(foods: FoodRow[], conversions: ConversionRow[]): FoodMap {
  const map: FoodMap = {};
  for (const f of foods) {
    map[f.food_id] = {
      name: f.display_name,
      energy_kcal: f.energy_kcal_100g ?? 0,
      protein: f.protein_100g ?? 0,
      fat: f.fat_100g ?? 0,
      carb_avail: f.carb_avail_100g ?? 0,
      fibre: f.fibre_100g ?? 0,
      density: f.density_g_ml,
      conversions: {},
    };
  }
  for (const c of conversions) {
    const food = map[c.food_id];
    if (food) (food.conversions ??= {})[c.unit] = c.grams;
  }
  return map;
}

/** The two validation recipes as engine-ready lines + servings. */
export function recipeToLines(recipe: SeedRecipe): { lines: Line[]; servings: number } {
  return {
    lines: recipe.ingredients.map((i) => ({
      food_id: i.food_id,
      quantity: i.quantity,
      unit: i.unit,
    })),
    servings: recipe.servings,
  };
}

/** One call to load everything the engine needs from the seed. */
export function loadSeed() {
  const foods = loadFoods();
  const conversions = loadConversions();
  const recipes = loadRecipes();
  return {
    foods,
    conversions,
    recipes,
    foodMap: buildFoodMap(foods, conversions),
  };
}
