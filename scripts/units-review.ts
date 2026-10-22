/**
 * `npx tsx scripts/units-review.ts` — dietitian work list for recipe units (U1).
 * Read-only. Writes docs/units-review.csv with three sections:
 *   1 Estimated weight   — conversions marked `estimated` (never weighed)
 *   2 Can't be weighed   — recipe lines whose unit has no weight for that food
 *   3 Buy as             — foods with a shopping "Buy as" set (please check)
 * "What to do" suggests WHICH measure to use, never the grams — a person sets those.
 * Re-run any time to see what's left.
 */
import { writeFileSync } from "node:fs";
import { supabase } from "./supabase";

async function all<T>(table: string, columns: string): Promise<T[]> {
  const out: T[] = [];
  for (let from = 0; ; from += 1000) {
    const { data, error } = await supabase.from(table).select(columns).range(from, from + 999);
    if (error) throw error;
    out.push(...((data ?? []) as T[]));
    if (!data || data.length < 1000) return out;
  }
}

type Line = { id: string; recipe_id: string; food_id: string; quantity: number; unit: string; prep_note: string | null };
type Grams = { id: string; grams: number | null };
type Food = { food_id: string; display_name: string; density_g_ml: number | null; purchase_unit: string | null; default_size: string | null };
type Conv = { food_id: string; unit: string; grams: number; estimated: boolean };
type Recipe = { id: string; title: string };

const [lines, grams, foods, convs, recipes] = await Promise.all([
  all<Line>("ingredient_lines", "id,recipe_id,food_id,quantity,unit,prep_note"),
  all<Grams>("line_grams", "id,grams"),
  all<Food>("foods", "food_id,display_name,density_g_ml,purchase_unit,default_size"),
  all<Conv>("unit_conversions", "food_id,unit,grams,estimated"),
  all<Recipe>("recipes", "id,title"),
]);

const foodById = new Map(foods.map((f) => [f.food_id, f]));
const titleById = new Map(recipes.map((r) => [r.id, r.title]));
const gramsById = new Map(grams.map((g) => [g.id, g.grams]));
const convsByFood = new Map<string, Conv[]>();
for (const c of convs) convsByFood.set(c.food_id, [...(convsByFood.get(c.food_id) ?? []), c]);
const g = (n: number) => (n >= 10 ? String(Math.round(n)) : String(Math.round(n * 10) / 10));
const measures = (foodId: string, except?: string) =>
  (convsByFood.get(foodId) ?? [])
    .filter((c) => c.unit !== except)
    .sort((a, b) => a.grams - b.grams)
    .map((c) => `${c.unit} = ${g(Number(c.grams))} g${c.estimated ? " (estimate)" : ""}`)
    .join("; ");
const qty = (q: number) => String(Math.round(Number(q) * 1000) / 1000);
const VOLUME = ["tsp", "tbsp", "cup", "ml"];

// ---- suggestions (which measure — never the grams) ---------------------------------
const NOT_EACH = ["Oregano, dried", "Garam masala", "Light Brown Sugar", "Rolled oats", "Walnuts", "Self-raising flour",
  "Orange zest", "Sun-dried tomatoes", "Tasty cheese", "Beef stock"];
const ESTIMATE_ACTION: Record<string, string> = {
  "Watermelon|each": "100 g is far too low for a whole watermelon. Change the recipe line to g or 'cup (cubed)', or add a weighed 'quarter' measure.",
  "Water|each": "Give Water a density of 1 g/mL and use mL or cups in the recipe; then delete 'each'.",
  "Spinach, baby|each": "Unclear what 'each' means for spinach. Change these lines to handful (25 g), cup (30 g) or g, then delete this measure.",
  "Spinach, baby|small": "Unclear what 'small' means for spinach. Change these lines to handful, cup or g, then delete this measure.",
  "Garlic, fresh|large": "Probably a whole bulb. Add a weighed 'bulb' measure (or change the lines to cloves), then delete 'large'.",
  "Garlic, fresh|small": "Probably a whole bulb. Add a weighed 'bulb' measure (or change the lines to cloves), then delete 'small'.",
  "Protein powder|each": "Probably 1 scoop. Add 'scoop' (grams from the tub), change the lines to scoops, then delete 'each'.",
  "Pre-Cooked Bbq Chicken|each": "A whole BBQ chicken is far more than 100 g. Use grams of shredded meat, or weigh one.",
};
function estimateAction(food: string, unit: string, used: number): string {
  if (ESTIMATE_ACTION[`${food}|${unit}`]) return ESTIMATE_ACTION[`${food}|${unit}`];
  if (unit === "each" && NOT_EACH.includes(food))
    return "'each' doesn't suit this food. Change the recipe line to tsp/tbsp/cup/g, then delete 'each'.";
  if (used === 0) return "Not used in any recipe. Weigh and enter the grams, or delete this measure.";
  return "Weigh a typical one (or check the pack) and type the grams on the food page. If the current value is right, press Confirm.";
}

const CANT_WEIGH: Record<string, string> = {
  "Iceberg lettuce|each": "'½ lettuce' = 0.5 'medium head' (570 g exists). For shredded or chopped amounts, add 'handful' and 'cup (shredded)' and use those. Check '2 each' in CHOPPED CHICKEN WRAP (2 heads = 1.1 kg).",
  "Red cabbage|each": "0.25 each = 1 'quarter cabbage' (113 g exists). Change the lines.",
  "Cos lettuce |each": "Add a weighed 'head' measure (leaf = 12.5 g exists).",
  "Rocket|large": "Probably handfuls. Add 'handful' with grams and change the lines.",
  "Rocket|each": "Probably handfuls. Add 'handful' with grams and change the line.",
  "Coriander|cup": "Add 'cup (chopped)' or 'cup (leaves)' with grams and pick it on these lines.",
  "Coriander|tbsp": "Add 'tbsp (chopped)' with grams. Check it isn't ground coriander (a different food).",
  "Coriander|tsp": "Probably ground coriander, which is a different food. Switch the food on these lines.",
  "Coriander|each": "'3 each' coriander: probably sprigs or bunches. Add the right measure.",
  "Feta cheese|cup": "Change to 'cup (crumbled)' (157.5 g exists).",
  "Mint, fresh|tbsp": "Change to 'tbsp (chopped)' (1.5 g exists).",
  "Diced tomatoes, canned|x400g": "Change to 'can' (400 g exists). Same weight.",
  "Crushed tomatoes, canned|x400g": "Change to 'can' (400 g exists). Same weight.",
  "Brown lentils, drained|x400g": "Change to 'can' (240 g drained per can exists).",
  "Cherry tomatoes|x250g": "Change to 'punnet' (250 g exists). Same weight.",
  "Brown rice and quinoa, microwaveable pouch|x250g": "Change to 'pouch' (250 g exists). Same weight.",
  "Dates, pitted|each": "Change to 'date' (5 g exists).",
  "Digestive biscuit|each": "Change to 'biscuit' (15 g exists).",
  "Gyoza Wrappers/Dumpling Wrapper|each": "Change to 'sheet' (5 g exists).",
  "Chicken stock cube|each": "Change to 'cube' (5 g exists).",
  "Chickpeas, drained|each": "Change to 'can' (225 g exists).",
  "Celery|each": "Change to 'medium stalk' (40 g exists).",
  "Corn chips|each": "Change to 'chip' (11 g exists).",
  "Corn chips|round": "Change to 'chip' (11 g exists).",
  "Broccolini|each": "If 2 stalks were meant, change to 'stalk' (29 g exists). Otherwise add 'bunch'.",
  "Broccolini|bunch": "Add a weighed 'bunch' measure.",
  "Bok choy|bunch": "Add a weighed 'bunch' measure.",
  "Broccoli|each": "Add a weighed 'head' measure (sizes too if useful) and change the line.",
  "Broccoli|large": "Add a weighed 'large head' measure and change the line.",
  "Broccoli|head": "Add a weighed 'head' measure.",
  "Chia seeds|handful": "A handful of seeds isn't measurable. Change to tbsp (14.2 g exists).",
  "Cinnamon|small": "Probably a cinnamon stick. Add a weighed 'stick' measure (or use a separate cinnamon-stick food).",
  "Cinnamon|each": "Probably a cinnamon stick. Add a weighed 'stick' measure (or use a separate cinnamon-stick food).",
  "Collagen powder|each": "Probably 1 scoop. Add 'scoop' with grams.",
  "Brown onion|tsp": "Probably onion powder or flakes. Check the recipe and switch the food.",
  "Brown onion|tbsp": "Probably onion powder or flakes. Check the recipe and switch the food.",
  "Barramundi|small": "Change to a fillet size. The prep note says ~150–200 g, so 'large fillet' (175 g) may fit better than 'small fillet' (90 g).",
  "Beef rump steak, untrimmed|x120g": "Change the line to 480 g, or add 'x120g' = 120 g.",
  "Burger thins, white|each": "If 1 thin = 1 serving, change to 'serving' (34 g). Otherwise add a weighed 'each'.",
  "Butter, salted|each": "'10 each' butter is probably 10 g. Change the unit to g.",
  "Chocolate chips|cup": "The prep note says 90 g. Change the line to 90 g, or add 'cup'.",
  "Green beans|each": "The prep note says ~200 g. Change the line to g, or add 'handful'.",
  "Earl Grey Tea Bag|each": "Change to 'tea bag', but check 'tea bag = 220 g' first (a tea bag is about 2 g).",
  "Gluten-Free Arnott Scotch Finger|x170g": "Add 'packet' = 170 g, or change the line to 170 g.",
  "Plain Tuna|x185g": "Add 'x185g' with the drained weight of a 185 g can.",
  "Cream cheese|cup": "Add a density or a 'cup' measure. The prep note mentions protein powder, so check the food is right.",
  "Slaw mix|packet": "Add 'packet' with the pack weight.",
  "Coconut milk, light|can": "Add 'can' with grams (or give it a density).",
  "Butternut pumpkin|each": "Add weighed whole-pumpkin sizes, or change the line to 'cup (diced)' or g.",
  "Butternut pumpkin|large": "Add weighed whole-pumpkin sizes, or change the line to 'cup (diced)' or g.",
};
const LIQUIDS = ["Dijon mustard", "Apple cider vinegar", "Balsamic vinegar", "Red curry paste", "Cooking sake", "Coconut milk",
  "Coconut milk, light", "Coconut cream", "Beef stock", "Chicken stock", "Canola oil", "Coconut oil", "Apple sauce",
  "Lactose Free Milk", "Light Cream Cheese", "Butter, salted", "Capers"];
function cantWeighAction(food: string, unit: string): string {
  if (CANT_WEIGH[`${food}|${unit}`]) return CANT_WEIGH[`${food}|${unit}`];
  if (VOLUME.includes(unit) && LIQUIDS.includes(food))
    return "Give this food a density (g/mL). Then tsp, tbsp, cup and mL all work.";
  if (VOLUME.includes(unit)) return `Add a '${unit} (chopped/grated/…)' measure with grams and pick it on these lines.`;
  return `Add a weighed '${unit}' measure, or change these lines to a measure the food already has.`;
}

// ---- build rows ---------------------------------------------------------------------
type Row = { section: string; food: string; measure: string; grams: string; lines: number; quantities: string; recipes: string; has: string; action: string };
const rows: Row[] = [];

// 1 Estimated weights
for (const c of convs.filter((c) => c.estimated)) {
  const f = foodById.get(c.food_id);
  if (!f) continue;
  const used = lines.filter((l) => l.food_id === c.food_id && l.unit === c.unit);
  rows.push({
    section: "1 Estimated weight",
    food: f.display_name,
    measure: c.unit + (c.unit === "each" && f.default_size ? ` (= ${f.default_size})` : ""),
    grams: g(Number(c.grams)),
    lines: used.length,
    quantities: [...new Set(used.map((l) => qty(l.quantity)))].join(", "),
    recipes: [...new Set(used.map((l) => titleById.get(l.recipe_id) ?? "?"))].join("; "),
    has: measures(c.food_id, c.unit),
    action: estimateAction(f.display_name, c.unit, used.length),
  });
}

// 2 Can't be weighed
const groups = new Map<string, Line[]>();
for (const l of lines) {
  if (gramsById.get(l.id) != null) continue;
  const k = `${l.food_id}|${l.unit}`;
  groups.set(k, [...(groups.get(k) ?? []), l]);
}
for (const [k, ls] of groups) {
  const [foodId, unit] = k.split("|");
  const f = foodById.get(foodId);
  const name = f?.display_name ?? foodId;
  rows.push({
    section: "2 Can't be weighed",
    food: name,
    measure: unit,
    grams: "",
    lines: ls.length,
    quantities: [...new Set(ls.map((l) => qty(l.quantity) + (l.prep_note ? ` (${l.prep_note})` : "")))].join(", "),
    recipes: [...new Set(ls.map((l) => titleById.get(l.recipe_id) ?? "?"))].join("; "),
    has: measures(foodId) + (f?.density_g_ml ? `; density ${f.density_g_ml} g/mL` : ""),
    action: cantWeighAction(name, unit),
  });
}

// 3 Buy as
for (const f of foods.filter((f) => f.purchase_unit)) {
  const c = (convsByFood.get(f.food_id) ?? []).find((c) => c.unit === f.purchase_unit);
  rows.push({
    section: "3 Buy as (please check)",
    food: f.display_name,
    measure: f.purchase_unit!,
    grams: c ? g(Number(c.grams)) : "",
    lines: lines.filter((l) => l.food_id === f.food_id).length,
    quantities: "",
    recipes: "",
    has: measures(f.food_id, f.purchase_unit!),
    action: "Shopping list counts this food in this measure (rounded up). Change it on the food page if it's wrong.",
  });
}

rows.sort((a, b) => a.section.localeCompare(b.section) || b.lines - a.lines || a.food.localeCompare(b.food));
const esc = (v: string | number) => {
  const s = String(v);
  return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
};
const header = ["Section", "Food", "Measure / unit", "Grams now", "Recipe lines", "Quantities (prep note)", "Recipes", "Measures this food already has", "What to do"];
const csv = [header, ...rows.map((r) => [r.section, r.food, r.measure, r.grams, r.lines, r.quantities, r.recipes, r.has, r.action])]
  .map((r) => r.map(esc).join(","))
  .join("\n");
writeFileSync("docs/units-review.csv", "﻿" + csv + "\n");

const count = (s: string) => rows.filter((r) => r.section === s);
console.log(
  `1 estimated weights: ${count("1 Estimated weight").length} measures (${count("1 Estimated weight").filter((r) => r.lines > 0).length} used in recipes)` +
    ` · 2 can't be weighed: ${count("2 Can't be weighed").length} food/unit pairs, ${count("2 Can't be weighed").reduce((n, r) => n + r.lines, 0)} lines` +
    ` · 3 buy as: ${count("3 Buy as (please check)").length} foods → docs/units-review.csv`,
);
