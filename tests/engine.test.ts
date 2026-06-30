import { describe, it, expect } from "vitest";
import { compute, atwater, toGrams, type FoodData } from "@goh/engine";
import { loadSeed, recipeToLines } from "../scripts/seed";

const { recipes, foodMap } = loadSeed();

// validation_report.md: computed energy matches the 4/4/9/2 Atwater sum
// "within about one percent". The seed's per-100g values carry rounding, so the
// real drift lands at 1.04% (Lentil) and 1.37% (Salmon) — this band covers both.
const ATWATER_TOLERANCE = 0.015;
const byTitle = (t: string) => {
  const r = recipes.find((x) => x.title === t);
  if (!r) throw new Error(`recipe not found: ${t}`);
  return r;
};

describe("toGrams — unit resolution rules", () => {
  const oil: FoodData = { name: "oil", energy_kcal: 0, protein: 0, fat: 0, carb_avail: 0, fibre: 0, density: 0.92 };
  const solid: FoodData = {
    name: "garlic", energy_kcal: 0, protein: 0, fat: 0, carb_avail: 0, fibre: 0, density: null,
    conversions: { clove: 3, medium: 150 },
  };

  it("g / grams / kg are direct", () => {
    expect(toGrams(solid, 420, "g")).toBe(420);
    expect(toGrams(solid, 50, "grams")).toBe(50);
    expect(toGrams(solid, 1.5, "kg")).toBe(1500);
  });

  it("x95g is qty x 95", () => {
    expect(toGrams(solid, 4, "x95g")).toBe(380);
  });

  it("Australian volumes use density for liquids (tbsp = 20 mL)", () => {
    expect(toGrams(oil, 2, "tbsp")).toBeCloseTo(2 * 20 * 0.92, 6);
    expect(toGrams(oil, 1, "cup")).toBeCloseTo(250 * 0.92, 6);
  });

  it("volume on a solid falls back to the unit-conversion grams", () => {
    const withCupWeight: FoodData = { ...solid, conversions: { cup: 40 } };
    expect(toGrams(withCupWeight, 1, "cup")).toBe(40);
  });

  it("descriptive / count units use the unit-conversion grams", () => {
    expect(toGrams(solid, 2, "clove")).toBe(6);
    expect(toGrams(solid, 1, "medium")).toBe(150);
  });

  it("throws when a unit cannot be resolved", () => {
    expect(() => toGrams(solid, 1, "handful")).toThrow();
  });
});

describe("seed validation recipes (mirrors validation_report.md)", () => {
  it("Lentil Tuna Salad is ~369 kcal/serve and Atwater-consistent", () => {
    const recipe = byTitle("Lentil Tuna Salad");
    const { lines, servings } = recipeToLines(recipe);
    const { perServe } = compute(lines, servings, foodMap);

    expect(perServe.energy_kcal).toBeCloseTo(369, 0);
    expect(Math.abs(perServe.energy_kcal - 369)).toBeLessThanOrEqual(2);

    const a = atwater(perServe);
    expect(Math.abs(a - perServe.energy_kcal) / perServe.energy_kcal).toBeLessThan(ATWATER_TOLERANCE);
  });

  it("Salmon Fish Cakes (listed) is ~226 kcal/serve and Atwater-consistent", () => {
    const recipe = byTitle("Salmon Fish Cakes");
    const { lines, servings } = recipeToLines(recipe);
    const { perServe } = compute(lines, servings, foodMap);

    expect(perServe.energy_kcal).toBeCloseTo(226, 0);
    expect(Math.abs(perServe.energy_kcal - 226)).toBeLessThanOrEqual(2);

    const a = atwater(perServe);
    expect(Math.abs(a - perServe.energy_kcal) / perServe.energy_kcal).toBeLessThan(ATWATER_TOLERANCE);
  });
});

describe("engine invariants", () => {
  it("perServe = totals / servings for every macro", () => {
    const recipe = byTitle("Lentil Tuna Salad");
    const { lines, servings } = recipeToLines(recipe);
    const { totals, perServe } = compute(lines, servings, foodMap);
    for (const m of Object.keys(totals) as (keyof typeof totals)[]) {
      expect(perServe[m]).toBeCloseTo(totals[m] / servings, 9);
    }
  });

  it("every validation line resolves to grams", () => {
    for (const recipe of recipes) {
      const { lines, servings } = recipeToLines(recipe);
      expect(() => compute(lines, servings, foodMap)).not.toThrow();
    }
  });
});
