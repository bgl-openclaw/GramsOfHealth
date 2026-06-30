/**
 * Grams of Health — recipe macro recalculation engine.
 *
 * Single source of truth: every macro is computed from grams. There is no
 * manual override of a final macro number anywhere. Corrections happen only by
 * editing a food, its unit weight, the quantity or the size.
 *
 * Australian measures: tsp = 5 mL, tbsp = 20 mL, cup = 250 mL.
 * "Carbs" means available carbohydrate, excluding fibre. Fibre is always
 * computed and carried separately.
 *
 * This module is a faithful TypeScript port of `seed/recalc_engine.py`. It is
 * pure: no framework and no database access. Callers pass plain food and
 * conversion data in, so the same code runs in the import scripts, the tests,
 * and the Lovable front-end for instant live totals.
 */

/** Australian volume standards, in millilitres per unit. */
export const AU_VOLUME_ML: Record<string, number> = {
  tsp: 5,
  tbsp: 20,
  cup: 250,
  ml: 1,
};

/** The five macros the engine tracks, in order. */
export const MACROS = [
  "energy_kcal",
  "protein",
  "fat",
  "carb_avail",
  "fibre",
] as const;

export type Macro = (typeof MACROS)[number];

/** A per-100g nutrient bundle for one food, with its size-to-grams weights. */
export interface FoodData {
  /** Optional human-readable name, surfaced on computed rows. */
  name?: string;
  /** Per-100g energy in kcal (energy with dietary fibre). */
  energy_kcal: number;
  /** Per-100g protein in grams. */
  protein: number;
  /** Per-100g total fat in grams. */
  fat: number;
  /** Per-100g available carbohydrate in grams (excludes fibre). */
  carb_avail: number;
  /** Per-100g dietary fibre in grams. */
  fibre: number;
  /** Density in g/mL for liquids; null for solids. */
  density: number | null;
  /**
   * Size-to-grams weights for this food, keyed by unit
   * (e.g. { clove: 3, x95g: 95 }). Liquids resolve volume via `density`
   * instead and need no entries here.
   */
  conversions?: Record<string, number>;
}

/** A map of food_id -> food data. */
export type FoodMap = Record<string, FoodData>;

/** One ingredient line: a food, a quantity and the unit it was measured in. */
export interface Line {
  food_id: string;
  quantity: number;
  unit: string;
}

/** A per-macro number bundle (totals, per-serve, or a single contribution). */
export type Macros = Record<Macro, number>;

/** One computed ingredient row: resolved grams plus each macro contribution. */
export interface ComputedRow extends Macros {
  name: string;
  qty: number;
  unit: string;
  grams: number;
}

/** The result of `compute`: recipe totals, per-serve figures and per-line rows. */
export interface ComputeResult {
  totals: Macros;
  perServe: Macros;
  rows: ComputedRow[];
}

const round1 = (n: number): number => Math.round(n * 10) / 10;

/**
 * Resolve any quantity + unit to grams for a given food.
 *
 *  - `g` / `gram` / `grams` and `kg` are direct.
 *  - `x95g` is a fixed-weight pack count: qty × 95.
 *  - Volume units (tsp/tbsp/cup/ml) use the food's density when present,
 *    otherwise the stored unit-conversion grams.
 *  - Descriptive and count units (clove, slice, medium, handful, …) use the
 *    stored unit-conversion grams.
 *
 * Throws if a unit cannot be resolved (missing density or conversion weight).
 */
export function toGrams(food: FoodData, qty: number, unit: string): number {
  if (unit === "g" || unit === "gram" || unit === "grams") {
    return qty;
  }
  if (unit === "kg") {
    return qty * 1000;
  }
  if (unit === "x95g") {
    // fixed-weight pack count
    return qty * 95;
  }

  const conv = food.conversions ?? {};

  if (unit in AU_VOLUME_ML) {
    if (food.density) {
      // liquids -> via density
      return qty * AU_VOLUME_ML[unit] * food.density;
    }
    if (unit in conv) {
      // solids measured by volume -> stored grams
      return qty * conv[unit];
    }
    throw new Error(`need density or unit_conversion for ${food.name ?? "food"}/${unit}`);
  }

  if (unit in conv) {
    // descriptive / count units
    return qty * conv[unit];
  }

  throw new Error(`no conversion for ${food.name ?? "food"}/${unit}`);
}

/**
 * Compute a recipe. Each macro contribution is `grams / 100 × per-100g value`;
 * totals are summed across lines and `perServe = totals / servings`.
 */
export function compute(lines: Line[], servings: number, foods: FoodMap): ComputeResult {
  const totals: Macros = { energy_kcal: 0, protein: 0, fat: 0, carb_avail: 0, fibre: 0 };
  const rows: ComputedRow[] = [];

  for (const line of lines) {
    const food = foods[line.food_id];
    if (!food) {
      throw new Error(`unknown food_id: ${line.food_id}`);
    }
    const g = toGrams(food, line.quantity, line.unit);
    const contrib = {} as Macros;
    for (const m of MACROS) {
      contrib[m] = (g / 100) * food[m];
      totals[m] += contrib[m];
    }
    rows.push({
      name: food.name ?? line.food_id,
      qty: line.quantity,
      unit: line.unit,
      grams: round1(g),
      energy_kcal: round1(contrib.energy_kcal),
      protein: round1(contrib.protein),
      fat: round1(contrib.fat),
      carb_avail: round1(contrib.carb_avail),
      fibre: round1(contrib.fibre),
    });
  }

  const perServe = {} as Macros;
  for (const m of MACROS) {
    perServe[m] = totals[m] / servings;
  }

  return { totals, perServe, rows };
}

/**
 * Internal consistency check: 4/4/9/2 kcal per gram of
 * protein / carbohydrate / fat / fibre. Should land within ~1% of the
 * grams-computed energy for a self-consistent recipe.
 */
export function atwater(perServe: Macros): number {
  return (
    4 * perServe.protein +
    4 * perServe.carb_avail +
    9 * perServe.fat +
    2 * perServe.fibre
  );
}

/**
 * Convenience factory that closes over a foods map, mirroring the Python
 * `Engine` class so callers can write `engine.compute(lines, servings)`.
 */
export function createEngine(foods: FoodMap) {
  return {
    foods,
    toGrams: (foodId: string, qty: number, unit: string): number => {
      const food = foods[foodId];
      if (!food) throw new Error(`unknown food_id: ${foodId}`);
      return toGrams(food, qty, unit);
    },
    compute: (lines: Line[], servings: number): ComputeResult =>
      compute(lines, servings, foods),
    atwater,
  };
}

export type Engine = ReturnType<typeof createEngine>;
