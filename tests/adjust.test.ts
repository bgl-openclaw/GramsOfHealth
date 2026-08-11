import { describe, it, expect } from "vitest";
import type { FoodMap } from "@goh/engine";
import { proposeAdjustment, parseTargetRequest, SECTION_RE, type Role } from "../packages/adjust/src";

const F: FoodMap = {
  chicken: { name: "Chicken breast", energy_kcal: 120, protein: 31, fat: 2.6, carb_avail: 0, fibre: 0, density: null },
  tofu: { name: "Tofu firm", energy_kcal: 120, protein: 12, fat: 7, carb_avail: 2, fibre: 1, density: null },
  rice: { name: "Rice cooked", energy_kcal: 130, protein: 2.6, fat: 0.3, carb_avail: 28, fibre: 0.4, density: null },
  olive_oil: { name: "Olive oil", energy_kcal: 883, protein: 0, fat: 99.9, carb_avail: 0, fibre: 0, density: 0.92 },
  butter: { name: "Butter", energy_kcal: 720, protein: 0.6, fat: 81, carb_avail: 0.6, fibre: 0, density: null },
  soy_sauce: { name: "Soy sauce", energy_kcal: 60, protein: 6, fat: 0, carb_avail: 8, fibre: 0.8, density: 1.15 },
  egg: { name: "Egg", energy_kcal: 127, protein: 12.6, fat: 8.5, carb_avail: 0.3, fibre: 0, density: null, conversions: { each: 50 } },
  mystery: { name: "Mystery", energy_kcal: 100, protein: 5, fat: 5, carb_avail: 5, fibre: 1, density: null }, // no conversion for its unit
};
const R: Record<string, Role | null> = {
  chicken: "adjustable_protein",
  tofu: "adjustable_protein",
  rice: "adjustable_carb",
  olive_oil: "adjustable_fat",
  butter: "adjustable_fat",
  soy_sauce: "flavour_base",
  egg: "adjustable_protein",
  mystery: "adjustable_protein",
};

const base = {
  servings: 2,
  lines: [
    { food_id: "chicken", quantity: 200, unit: "g" },
    { food_id: "tofu", quantity: 100, unit: "g" },
    { food_id: "rice", quantity: 300, unit: "g" },
    { food_id: "soy_sauce", quantity: 1, unit: "tbsp" },
  ],
};

describe("worked example 1 — protein increase hits bounds and spreads", () => {
  const p = proposeAdjustment(base, F, R, { kind: "macro", macro: "protein", min: 53, max: 54 });
  it("clips both protein sources at +30% and spills the residual to the carb line", () => {
    const chicken = p.changes.find((c) => c.food_id === "chicken")!;
    const tofu = p.changes.find((c) => c.food_id === "tofu")!;
    const rice = p.changes.find((c) => c.food_id === "rice");
    expect(chicken.afterGrams).toBe(260); // exactly +30%
    expect(tofu.afterGrams).toBe(130); // exactly +30%
    expect(rice).toBeDefined(); // pro-rata spillover to the next tier
    expect(rice!.afterGrams).toBeGreaterThan(300);
  });
  it("never touches flavour_base and reports it frozen", () => {
    expect(p.changes.find((c) => c.food_id === "soy_sauce")).toBeUndefined();
    expect(p.frozen.some((f) => f.food_id === "soy_sauce")).toBe(true);
  });
  it("lands inside the window", () => {
    expect(p.reachable).toBe(true);
    expect(p.after.protein).toBeGreaterThanOrEqual(53);
    expect(p.after.protein).toBeLessThanOrEqual(54);
  });
});

describe("worked example 2 — unreachable target refused with closest achievable", () => {
  const p = proposeAdjustment(base, F, R, { kind: "macro", macro: "protein", min: 100, max: 100 });
  it("refuses plainly and returns the closest figure", () => {
    expect(p.reachable).toBe(false);
    expect(p.message).toMatch(/unreachable/i);
    expect(p.after.protein).toBeLessThan(100);
    expect(p.after.protein).toBeGreaterThan(p.before.protein);
  });
  it("still respects every ±30% bound", () => {
    for (const c of p.changes) {
      expect(Math.abs(c.afterGrams - c.beforeGrams)).toBeLessThanOrEqual(0.3 * c.beforeGrams + 1e-6);
    }
  });
});

describe("worked example 3 — section rule freezes a dressing's oil", () => {
  const recipe = {
    servings: 2,
    lines: [
      { food_id: "olive_oil", quantity: 40, unit: "g", section: "Orange Mustard Dressing" },
      { food_id: "butter", quantity: 50, unit: "g", section: null },
      { food_id: "chicken", quantity: 200, unit: "g", section: "Marinade" },
    ],
  };
  const p = proposeAdjustment(recipe, F, R, { kind: "macro_delta", macro: "fat", deltaG: 5 });
  it("freezes the dressing oil (ratio-bound) but moves the free fat", () => {
    expect(p.changes.find((c) => c.food_id === "olive_oil")).toBeUndefined();
    expect(p.frozen.find((f) => f.food_id === "olive_oil")?.reason).toMatch(/section/);
    expect(p.changes.find((c) => c.food_id === "butter")).toBeDefined();
  });
  it("protein in a Marinade section stays adjustable (exempt from the rule)", () => {
    const q = proposeAdjustment(recipe, F, R, { kind: "macro_delta", macro: "protein", deltaG: 4 });
    expect(q.changes.find((c) => c.food_id === "chicken")).toBeDefined();
  });
});

describe("rounding, determinism, unpriceable", () => {
  it("gram lines snap to 5 g; each-lines snap to whole units", () => {
    const recipe = {
      servings: 1,
      lines: [
        { food_id: "chicken", quantity: 200, unit: "g" },
        { food_id: "egg", quantity: 2, unit: "each" },
      ],
    };
    const p = proposeAdjustment(recipe, F, R, { kind: "macro_delta", macro: "protein", deltaG: 10 });
    for (const c of p.changes) {
      if (c.unit === "g") expect((c.afterGrams - c.beforeGrams) % 5).toBeCloseTo(0, 6);
      if (c.unit === "each") expect(Number.isInteger(c.afterQty)).toBe(true);
    }
  });
  it("is deterministic", () => {
    const a = proposeAdjustment(base, F, R, { kind: "macro", macro: "protein", min: 53, max: 54 });
    const b = proposeAdjustment(base, F, R, { kind: "macro", macro: "protein", min: 53, max: 54 });
    expect(JSON.stringify(a)).toBe(JSON.stringify(b));
  });
  it("lists lines that cannot resolve to grams as unpriceable and never moves them", () => {
    const recipe = { servings: 1, lines: [{ food_id: "mystery", quantity: 1, unit: "handful" }, { food_id: "chicken", quantity: 100, unit: "g" }] };
    const p = proposeAdjustment(recipe, F, R, { kind: "macro_delta", macro: "protein", deltaG: 3 });
    expect(p.unpriceable).toEqual([{ index: 0, food_id: "mystery" }]);
    expect(p.changes.find((c) => c.food_id === "mystery")).toBeUndefined();
  });
  it("no-op when already inside the range", () => {
    const p = proposeAdjustment(base, F, R, { kind: "macro", macro: "protein", min: 0, max: 999 });
    expect(p.reachable).toBe(true);
    expect(p.changes).toHaveLength(0);
  });
});

describe("typed-request parser", () => {
  it('parses "get fibre between 5 and 6"', () => {
    expect(parseTargetRequest("get fibre between 5 and 6")).toEqual({ kind: "macro", macro: "fibre", min: 5, max: 6 });
  });
  it('parses "add 400 calories"', () => {
    expect(parseTargetRequest("add 400 calories")).toEqual({ kind: "energy_delta", deltaKcal: 400 });
  });
  it('parses "protein to 42" and "cut 10 g fat"', () => {
    expect(parseTargetRequest("protein to 42")).toEqual({ kind: "macro", macro: "protein", min: 42, max: 42 });
    expect(parseTargetRequest("cut 10 g fat")).toEqual({ kind: "macro_delta", macro: "fat", deltaG: -10 });
  });
  it("section regex matches the agreed vocabulary", () => {
    for (const s of ["Orange Mustard Dressing", "Caramel sauce", "Cream layer", "dough"]) expect(SECTION_RE.test(s)).toBe(true);
    expect(SECTION_RE.test("To serve")).toBe(false);
  });
});
