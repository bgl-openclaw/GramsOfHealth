import { describe, it, expect } from "vitest";
import { compute, type FoodMap } from "@goh/engine";
import { rollupPlan, applyDeltas, type Library, type PlanInput, type RecipeLine } from "../packages/rollup/src";

const foods: FoodMap = {
  chicken: { name: "Chicken breast", energy_kcal: 120, protein: 31, fat: 2.6, carb_avail: 0, fibre: 0, density: null },
  rice: { name: "Rice cooked", energy_kcal: 130, protein: 2.6, fat: 0.3, carb_avail: 28, fibre: 0.4, density: null },
  olive_oil: { name: "Olive oil", energy_kcal: 883, protein: 0, fat: 99.9, carb_avail: 0, fibre: 0, density: 0.92 },
  yoghurt: { name: "Greek yoghurt", energy_kcal: 97, protein: 9, fat: 5, carb_avail: 3.6, fibre: 0, density: null },
  quinoa: { name: "Quinoa cooked", energy_kcal: 120, protein: 4.4, fat: 1.9, carb_avail: 19, fibre: 2.8, density: null },
  egg: { name: "Egg", energy_kcal: 127, protein: 12.6, fat: 8.5, carb_avail: 0.3, fibre: 0, density: null, conversions: { each: 50 } },
  mystery: { name: "Mystery", energy_kcal: 100, protein: 5, fat: 5, carb_avail: 5, fibre: 1, density: null },
};
const bowl: RecipeLine[] = [
  { id: "l1", food_id: "chicken", quantity: 300, unit: "g" },
  { id: "l2", food_id: "rice", quantity: 400, unit: "g" },
  { id: "l3", food_id: "olive_oil", quantity: 2, unit: "tbsp" },
];
const lib: Library = {
  foods,
  recipes: {
    bowl: { id: "bowl", title: "Chicken rice bowl", servings: 2, lines: bowl },
    muffins: {
      id: "muffins", title: "Egg muffins", servings: 4,
      lines: [{ id: "m1", food_id: "egg", quantity: 8, unit: "each" }, { id: "m2", food_id: "mystery", quantity: 1, unit: "handful" }],
    },
  },
  profiles: { hp: { id: "hp", recipe_id: "bowl", deltas: [{ kind: "quantity", line_ref: "l1", new_quantity: 400, new_unit: "g" }] } },
};
const T = { kcal: 2000, protein_g: 150, carb_g: 200, fat_g: 60, fibre_g: 30 };
const plan: PlanInput = {
  days: [
    { day: 1, day_type: "default", targets: T },
    { day: 2, day_type: "default", targets: T, free_choice_share: 0.3 },
    { day: 3, day_type: "hard", targets: { ...T, kcal: 2400 } },
  ],
  items: [
    { id: "cook", day: 1, slot: "Dinner", recipe_id: "bowl", servings: 1, batch_group: "g1", batch_role: "cook" },
    { id: "lunch", day: 1, slot: "Lunch", recipe_id: "bowl", profile_id: "hp", servings: 1.25 },
    { id: "topup", day: 1, slot: "Lunch", food_id: "chicken", quantity: 100, unit: "g", boosts_item_id: "lunch" },
    { id: "snack", day: 1, slot: "Snack", food_id: "yoghurt", quantity: 200, unit: "g" },
    { id: "eat", day: 2, slot: "Lunch", recipe_id: "bowl", servings: 1.5, batch_group: "g1", batch_role: "eat" },
    { id: "salad", day: 2, slot: "Snack", recipe_id: "bowl", servings: 1, deltas: [{ kind: "add", new_food_id: "quinoa", new_quantity: 60, new_unit: "g" }] },
    { id: "brekkie", day: 3, slot: "Breakfast", recipe_id: "muffins", servings: 2 },
  ],
};

describe("applyDeltas", () => {
  it("changes, swaps, removes and adds lines; ignores lines that are gone", () => {
    const out = applyDeltas(bowl, [
      { kind: "quantity", line_ref: "l1", new_quantity: 350, new_unit: "g" },
      { kind: "swap", line_ref: "l2", new_food_id: "quinoa", new_quantity: 300, new_unit: "g" },
      { kind: "remove", line_ref: "l3" },
      { kind: "add", new_food_id: "yoghurt", new_quantity: 50, new_unit: "g" },
      { kind: "remove", line_ref: "gone" },
    ]);
    expect(out.map((l) => `${l.food_id}:${l.quantity}${l.unit}`)).toEqual(["chicken:350g", "quinoa:300g", "yoghurt:50g"]);
    expect(bowl[0].quantity).toBe(300); // the recipe itself is untouched
  });
});

describe("rollupPlan", () => {
  const r = rollupPlan(plan, lib);
  const perServe = compute(bowl, 2, foods).perServe;

  it("uses the engine's numbers: serves × per-serve, profile then item changes", () => {
    const cook = r.items.find((i) => i.id === "cook")!;
    expect(cook.macros.energy_kcal).toBeCloseTo(perServe.energy_kcal, 1);
    const lunch = r.items.find((i) => i.id === "lunch")!;
    const hp = compute(applyDeltas(bowl, lib.profiles!.hp.deltas), 2, foods).perServe;
    expect(lunch.macros.protein).toBeCloseTo(hp.protein * 1.25, 1);
    const salad = r.items.find((i) => i.id === "salad")!;
    // item changes use whole-recipe quantities (like profiles): 60 g added to a 2-serve recipe = 30 g a serve
    expect(salad.macros.fibre).toBeCloseTo(perServe.fibre + ((60 / 100) * 2.8) / 2, 1);
  });

  it("a top-up reports what it adds to the meal it boosts", () => {
    expect(r.boosts).toEqual([{ item_id: "lunch", boosted_by: ["topup"], added: { energy_kcal: 120, protein: 31, fat: 2.6, carb_avail: 0, fibre: 0 } }]);
  });

  it("leftovers: eaten where they're eaten, cooked once", () => {
    expect(r.batches).toEqual([{
      batch_group: "g1", recipe_id: "bowl", cook_item_id: "cook", cook_day: 1, cooked_servings: 2.5,
      eaten: [{ item_id: "cook", day: 1, servings: 1 }, { item_id: "eat", day: 2, servings: 1.5 }],
    }]);
    expect(r.days[1].slots.Lunch.energy_kcal).toBeCloseTo(perServe.energy_kcal * 1.5, 1);
    expect(r.cycle.cook_events).toBe(4); // cook, lunch, salad, brekkie — the leftover isn't cooked again
    expect(r.cycle.distinct_recipes).toBe(2);
  });

  it("a free-choice slot shrinks the day's targets instead of showing a shortfall", () => {
    expect(r.days[1].free_choice_share).toBe(0.3);
    expect(r.days[1].targets).toEqual({ kcal: 1400, protein_g: 105, carb_g: 140, fat_g: 42, fibre_g: 21 });
    expect(r.days[1].energy.target).toBe(1400);
  });

  it("an ingredient that can't be weighed is left out and named, never silently zero", () => {
    expect(r.confidence).toBe(false);
    expect(r.days[2].complete).toBe(false);
    expect(r.days[0].complete).toBe(true);
    expect(r.problems).toEqual(["day 3 Breakfast: can't weigh Mystery (handful)"]);
    const brekkie = r.items.find((i) => i.id === "brekkie")!;
    expect(brekkie.macros.protein).toBeCloseTo((8 * 50 * 12.6) / 100 / 4 * 2, 1);
  });

  it("counts every ingredient once across the cycle", () => {
    // chicken, rice, olive_oil, yoghurt, quinoa, egg, mystery
    expect(r.cycle.distinct_ingredients).toBe(7);
  });

  it("leaves alternatives (behind Swap) out of every total", () => {
    const withOption = { ...plan, items: [...plan.items, { id: "alt", day: 1, slot: "Dinner", recipe_id: "muffins", servings: 2, option_of: "cook" }] };
    const r2 = rollupPlan(withOption, lib);
    expect(JSON.stringify(r2)).toBe(JSON.stringify(r));
  });

  it("is deterministic: item order doesn't change the result", () => {
    const shuffled = { ...plan, items: [...plan.items].reverse() };
    expect(JSON.stringify(rollupPlan(shuffled, lib))).toBe(JSON.stringify(r));
  });
});

describe("bands (policy tolerances)", () => {
  const day = (kcal: number, protein: number) => {
    // one food item sized so the day lands exactly on the given numbers
    const lib2: Library = { foods: { x: { name: "X", energy_kcal: kcal, protein, fat: 0, carb_avail: 0, fibre: 0, density: null } }, recipes: {} };
    return rollupPlan({ days: [{ day: 1, day_type: "default", targets: { kcal: 2000, protein_g: 100, carb_g: null, fat_g: null, fibre_g: null } }],
      items: [{ id: "a", day: 1, slot: "Lunch", food_id: "x", quantity: 100, unit: "g" }] }, lib2).days[0];
  };
  it("energy: ±5% on target, ±10% within, beyond that under/over", () => {
    expect(day(1920, 100).energy.band).toBe("on_target");
    expect(day(1840, 100).energy.band).toBe("within");
    expect(day(1760, 100).energy.band).toBe("under");
    expect(day(2240, 100).energy.band).toBe("over");
  });
  it("protein: never under; up to +15% is fine", () => {
    expect(day(2000, 99).protein.band).toBe("under");
    expect(day(2000, 100).protein.band).toBe("on_target");
    expect(day(2000, 110).protein.band).toBe("within");
    expect(day(2000, 120).protein.band).toBe("over");
  });
  it("no target → no judgement", () => {
    expect(day(2000, 100).carb.band).toBe("no_target");
  });
});
