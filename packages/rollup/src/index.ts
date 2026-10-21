/**
 * Grams of Health — plan roll-up (plans roadmap rev 2, P2a).
 *
 * Pure and deterministic: same plan + same library → same result. The engine
 * remains the only source of nutrition numbers; this module only decides which
 * lines and portions belong to each day, then asks the engine what they add up to.
 *
 *  - An item is a recipe (base, profile, then the item's own ingredient changes,
 *    times its serves) or a food (quantity + unit).
 *  - Totals per item, per slot, per day and per cycle; each day compared with its
 *    day-type targets (energy and protein daily, carbs and fat daily, fibre shown).
 *  - Free-choice slots: the day's targets shrink by the free-choice share, so a
 *    free-choice slot is never reported as a shortfall.
 *  - Leftovers count where they're eaten; the batch is cooked once (cook events,
 *    cooked serves = all serves in the group). Top-ups report what they add to
 *    the meal they boost.
 *  - Lines the engine can't resolve are left out and the result says so
 *    (confidence false, with the reason) — never treated as zero silently.
 *
 * Tolerances are policy, not a published standard (see research doc): energy
 * ±10% (±5% shown as on target), protein never under and at most +15%, carbs and
 * fat ±10%. Saturated fat, sodium and micronutrients come later (P2b).
 */
import { compute, toGrams, MACROS, type FoodMap, type Line, type Macros } from "@goh/engine";

export type DayType = "default" | "hard" | "moderate" | "rest";

export interface RecipeLine extends Line {
  /** ingredient_lines.id — what deltas point at. */
  id: string;
  section?: string | null;
}
export interface RecipeData {
  id: string;
  title?: string;
  servings: number;
  lines: RecipeLine[];
}
export interface Delta {
  kind: "quantity" | "swap" | "remove" | "add";
  line_ref?: string | null;
  new_food_id?: string | null;
  new_quantity?: number | null;
  new_unit?: string | null;
}
export interface ProfileData {
  id: string;
  recipe_id: string;
  deltas: Delta[];
}
export interface Library {
  foods: FoodMap;
  recipes: Record<string, RecipeData>;
  profiles?: Record<string, ProfileData>;
}

export interface Targets {
  kcal: number | null;
  protein_g: number | null;
  carb_g: number | null;
  fat_g: number | null;
  fibre_g: number | null;
}
export interface PlanDay {
  day: number;
  day_type: DayType;
  targets: Targets | null;
  /** Share of the day's targets left to free-choice slots (0–1). */
  free_choice_share?: number;
}
export interface PlanItem {
  id: string;
  day: number;
  slot: string;
  recipe_id?: string | null;
  profile_id?: string | null;
  /** Serves of the recipe (0.25 steps); default 1. */
  servings?: number | null;
  /** The item's own ingredient changes, applied after its profile. Quantities are for the whole
   *  recipe, like profile changes (to give one serve 60 g more, add 60 × recipe serves). */
  deltas?: Delta[];
  food_id?: string | null;
  quantity?: number | null;
  unit?: string | null;
  batch_group?: string | null;
  batch_role?: "cook" | "eat" | null;
  boosts_item_id?: string | null;
}
export interface PlanInput {
  days: PlanDay[];
  items: PlanItem[];
}

export interface Tolerances {
  energyAccept: number;
  energyStretch: number;
  proteinOver: number;
  proteinStretch: number;
  macroAccept: number;
  macroStretch: number;
}
export const DEFAULT_TOLERANCES: Tolerances = {
  energyAccept: 0.1,
  energyStretch: 0.05,
  proteinOver: 0.15,
  proteinStretch: 0.05,
  macroAccept: 0.1,
  macroStretch: 0.05,
};

/** on_target = inside the stretch band; within = inside the accept band. */
export type Band = "on_target" | "within" | "under" | "over" | "no_target";
export interface Check {
  target: number | null;
  actual: number;
  delta: number | null;
  pct: number | null;
  band: Band;
}
export interface ItemResult {
  id: string;
  day: number;
  slot: string;
  kind: "recipe" | "food";
  servings: number;
  macros: Macros;
  complete: boolean;
  problems: string[];
}
export interface DayResult {
  day: number;
  day_type: DayType;
  totals: Macros;
  slots: Record<string, Macros>;
  /** Targets after taking out the free-choice share. */
  targets: Targets | null;
  free_choice_share: number;
  energy: Check;
  protein: Check;
  carb: Check;
  fat: Check;
  fibre: Check;
  complete: boolean;
}
export interface BatchResult {
  batch_group: string;
  recipe_id: string | null;
  cook_item_id: string | null;
  cook_day: number | null;
  cooked_servings: number;
  eaten: Array<{ item_id: string; day: number; servings: number }>;
}
export interface BoostResult {
  item_id: string;
  boosted_by: string[];
  added: Macros;
}
export interface CycleResult {
  days: number;
  average: Macros;
  /** % of average energy from protein / fat / carbs (AMDR check). */
  energy_split: { protein_pct: number; fat_pct: number; carb_pct: number };
  amdr: { protein: Band; fat: Band; carb: Band };
  fibre_average: Check;
  energy_sd_by_day_type: Partial<Record<DayType, { days: number; sd: number | null }>>;
  days_energy_within: number;
  days_protein_met: number;
  distinct_recipes: number;
  distinct_ingredients: number;
  cook_events: number;
}
export interface Rollup {
  items: ItemResult[];
  days: DayResult[];
  cycle: CycleResult;
  batches: BatchResult[];
  boosts: BoostResult[];
  confidence: boolean;
  problems: string[];
}

const ZERO = (): Macros => ({ energy_kcal: 0, protein: 0, fat: 0, carb_avail: 0, fibre: 0 });
const add = (a: Macros, b: Macros): Macros => {
  const r = ZERO();
  for (const m of MACROS) r[m] = a[m] + b[m];
  return r;
};
const scale = (a: Macros, k: number): Macros => {
  const r = ZERO();
  for (const m of MACROS) r[m] = a[m] * k;
  return r;
};
const r1 = (n: number): number => Math.round(n * 10) / 10;
const roundMacros = (a: Macros): Macros => {
  const r = ZERO();
  for (const m of MACROS) r[m] = r1(a[m]);
  return r;
};
// stable order for every sum, so results are identical run to run
const byKey = (a: string, b: string) => (a < b ? -1 : a > b ? 1 : 0);

/** Apply ingredient changes to a recipe's lines (profile deltas, then item deltas). */
export function applyDeltas(lines: RecipeLine[], deltas: Delta[] | undefined): RecipeLine[] {
  if (!deltas || deltas.length === 0) return lines;
  let out = lines.map((l) => ({ ...l }));
  let added = 0;
  for (const d of deltas) {
    if (d.kind === "add") {
      if (d.new_food_id && d.new_quantity != null && d.new_unit) {
        out.push({ id: `add:${added++}`, food_id: d.new_food_id, quantity: d.new_quantity, unit: d.new_unit });
      }
      continue;
    }
    const i = out.findIndex((l) => l.id === d.line_ref);
    if (i < 0) continue; // the line is gone (recipe edited since) — nothing to change
    if (d.kind === "remove") {
      out = out.filter((_, k) => k !== i);
    } else if (d.kind === "quantity" && d.new_quantity != null) {
      out[i] = { ...out[i], quantity: d.new_quantity, unit: d.new_unit || out[i].unit };
    } else if (d.kind === "swap" && d.new_food_id && d.new_quantity != null && d.new_unit) {
      out[i] = { ...out[i], food_id: d.new_food_id, quantity: d.new_quantity, unit: d.new_unit };
    }
  }
  return out;
}

/** Lines the engine can resolve, plus a reason for each it can't. */
function priceable(lines: Line[], foods: FoodMap): { ok: Line[]; problems: string[] } {
  const ok: Line[] = [];
  const problems: string[] = [];
  for (const l of lines) {
    const f = foods[l.food_id];
    if (!f) {
      problems.push(`unknown food ${l.food_id}`);
      continue;
    }
    try {
      toGrams(f, l.quantity, l.unit);
      ok.push(l);
    } catch {
      problems.push(`can't weigh ${f.name ?? l.food_id} (${l.unit})`);
    }
  }
  return { ok, problems };
}

function itemMacros(item: PlanItem, lib: Library): ItemResult {
  if (item.food_id) {
    const line: Line = { food_id: item.food_id, quantity: item.quantity ?? 0, unit: item.unit ?? "g" };
    const { ok, problems } = priceable([line], lib.foods);
    const macros = ok.length ? compute(ok, 1, lib.foods).totals : ZERO();
    return { id: item.id, day: item.day, slot: item.slot, kind: "food", servings: 1, macros, complete: problems.length === 0, problems };
  }
  const recipe = item.recipe_id ? lib.recipes[item.recipe_id] : undefined;
  const servings = item.servings ?? 1;
  if (!recipe) {
    return { id: item.id, day: item.day, slot: item.slot, kind: "recipe", servings, macros: ZERO(), complete: false, problems: [`recipe ${item.recipe_id ?? "?"} not loaded`] };
  }
  const profile = item.profile_id ? lib.profiles?.[item.profile_id] : undefined;
  const problems: string[] = [];
  if (item.profile_id && !profile) problems.push(`profile ${item.profile_id} not loaded`);
  const lines = applyDeltas(applyDeltas(recipe.lines, profile?.deltas), item.deltas);
  const p = priceable(lines, lib.foods);
  problems.push(...p.problems);
  const perServe = p.ok.length ? compute(p.ok, Math.max(1, recipe.servings), lib.foods).perServe : ZERO();
  return { id: item.id, day: item.day, slot: item.slot, kind: "recipe", servings, macros: scale(perServe, servings), complete: problems.length === 0, problems };
}

function check(actual: number, target: number | null, kind: "energy" | "protein" | "macro" | "fibre", tol: Tolerances): Check {
  if (target == null || target <= 0) return { target, actual: r1(actual), delta: null, pct: null, band: "no_target" };
  const delta = actual - target;
  const pct = delta / target;
  let band: Band;
  if (kind === "protein") {
    band = pct < -1e-9 ? "under" : pct <= tol.proteinStretch ? "on_target" : pct <= tol.proteinOver ? "within" : "over";
  } else if (kind === "fibre") {
    band = pct < -1e-9 ? "under" : "on_target";
  } else {
    const accept = kind === "energy" ? tol.energyAccept : tol.macroAccept;
    const stretch = kind === "energy" ? tol.energyStretch : tol.macroStretch;
    band = Math.abs(pct) <= stretch ? "on_target" : Math.abs(pct) <= accept ? "within" : pct < 0 ? "under" : "over";
  }
  return { target: r1(target), actual: r1(actual), delta: r1(delta), pct: Math.round(pct * 1000) / 1000, band };
}

function sd(values: number[]): number | null {
  if (values.length < 2) return null;
  const mean = values.reduce((a, b) => a + b, 0) / values.length;
  return Math.sqrt(values.reduce((a, v) => a + (v - mean) ** 2, 0) / values.length);
}

/** AMDR (NHMRC): protein 15–25%, fat 20–35%, carbohydrate 45–65% of energy. */
function amdrBand(pct: number, lo: number, hi: number): Band {
  return pct < lo ? "under" : pct > hi ? "over" : "within";
}

export function rollupPlan(plan: PlanInput, lib: Library, tolerances: Partial<Tolerances> = {}): Rollup {
  const tol = { ...DEFAULT_TOLERANCES, ...tolerances };
  const sorted = [...plan.items].sort((a, b) => a.day - b.day || byKey(a.slot, b.slot) || byKey(a.id, b.id));
  const items = sorted.map((it) => itemMacros(it, lib));
  const byId = new Map(items.map((r) => [r.id, r]));
  const problems: string[] = [];
  for (const r of items) for (const p of r.problems) problems.push(`day ${r.day} ${r.slot}: ${p}`);

  const days: DayResult[] = [...plan.days]
    .sort((a, b) => a.day - b.day)
    .map((d) => {
      const mine = items.filter((r) => r.day === d.day);
      let totals = ZERO();
      const slots: Record<string, Macros> = {};
      for (const r of mine) {
        totals = add(totals, r.macros);
        slots[r.slot] = add(slots[r.slot] ?? ZERO(), r.macros);
      }
      const share = Math.min(1, Math.max(0, d.free_choice_share ?? 0));
      const k = 1 - share;
      const t = d.targets
        ? {
            kcal: d.targets.kcal == null ? null : d.targets.kcal * k,
            protein_g: d.targets.protein_g == null ? null : d.targets.protein_g * k,
            carb_g: d.targets.carb_g == null ? null : d.targets.carb_g * k,
            fat_g: d.targets.fat_g == null ? null : d.targets.fat_g * k,
            fibre_g: d.targets.fibre_g == null ? null : d.targets.fibre_g * k,
          }
        : null;
      const slotsRounded: Record<string, Macros> = {};
      for (const s of Object.keys(slots).sort(byKey)) slotsRounded[s] = roundMacros(slots[s]);
      return {
        day: d.day,
        day_type: d.day_type,
        totals: roundMacros(totals),
        slots: slotsRounded,
        targets: t && {
          kcal: t.kcal == null ? null : r1(t.kcal),
          protein_g: t.protein_g == null ? null : r1(t.protein_g),
          carb_g: t.carb_g == null ? null : r1(t.carb_g),
          fat_g: t.fat_g == null ? null : r1(t.fat_g),
          fibre_g: t.fibre_g == null ? null : r1(t.fibre_g),
        },
        free_choice_share: share,
        energy: check(totals.energy_kcal, t?.kcal ?? null, "energy", tol),
        protein: check(totals.protein, t?.protein_g ?? null, "protein", tol),
        carb: check(totals.carb_avail, t?.carb_g ?? null, "macro", tol),
        fat: check(totals.fat, t?.fat_g ?? null, "macro", tol),
        fibre: check(totals.fibre, t?.fibre_g ?? null, "fibre", tol),
        complete: mine.every((r) => r.complete),
      };
    });

  // leftovers: cooked once, eaten where they're eaten
  const groups = new Map<string, PlanItem[]>();
  for (const it of sorted) if (it.batch_group) groups.set(it.batch_group, [...(groups.get(it.batch_group) ?? []), it]);
  const batches: BatchResult[] = [...groups.keys()].sort(byKey).map((g) => {
    const members = groups.get(g)!;
    const cook = members.find((m) => m.batch_role === "cook") ?? null;
    return {
      batch_group: g,
      recipe_id: cook?.recipe_id ?? members[0].recipe_id ?? null,
      cook_item_id: cook?.id ?? null,
      cook_day: cook?.day ?? null,
      cooked_servings: members.reduce((a, m) => a + (m.servings ?? 1), 0),
      eaten: members.map((m) => ({ item_id: m.id, day: m.day, servings: m.servings ?? 1 })),
    };
  });

  // top-ups: what each boosted meal gained
  const boostMap = new Map<string, string[]>();
  for (const it of sorted) if (it.boosts_item_id) boostMap.set(it.boosts_item_id, [...(boostMap.get(it.boosts_item_id) ?? []), it.id]);
  const boosts: BoostResult[] = [...boostMap.keys()].sort(byKey).map((target) => {
    const by = boostMap.get(target)!;
    return { item_id: target, boosted_by: by, added: roundMacros(by.reduce((a, id) => add(a, byId.get(id)?.macros ?? ZERO()), ZERO())) };
  });

  // cycle
  const n = days.length || 1;
  let sum = ZERO();
  for (const r of items) sum = add(sum, r.macros);
  const average = scale(sum, 1 / n);
  const e = average.energy_kcal || 1;
  const split = { protein_pct: r1((average.protein * 4 * 100) / e), fat_pct: r1((average.fat * 9 * 100) / e), carb_pct: r1((average.carb_avail * 4 * 100) / e) };
  const fibreTargets = days.map((d) => d.targets?.fibre_g).filter((x): x is number => x != null);
  const fibreTarget = fibreTargets.length ? fibreTargets.reduce((a, b) => a + b, 0) / fibreTargets.length : null;
  const sdByType: CycleResult["energy_sd_by_day_type"] = {};
  for (const type of ["default", "hard", "moderate", "rest"] as DayType[]) {
    const vals = days.filter((d) => d.day_type === type).map((d) => d.totals.energy_kcal);
    if (vals.length) {
      const s = sd(vals);
      sdByType[type] = { days: vals.length, sd: s == null ? null : r1(s) };
    }
  }
  const recipeItems = sorted.filter((it) => it.recipe_id);
  const ingredients = new Set<string>();
  for (const it of sorted) {
    if (it.food_id) ingredients.add(it.food_id);
    const rec = it.recipe_id ? lib.recipes[it.recipe_id] : undefined;
    if (rec) {
      const prof = it.profile_id ? lib.profiles?.[it.profile_id] : undefined;
      for (const l of applyDeltas(applyDeltas(rec.lines, prof?.deltas), it.deltas)) ingredients.add(l.food_id);
    }
  }

  const cycle: CycleResult = {
    days: days.length,
    average: roundMacros(average),
    energy_split: split,
    amdr: { protein: amdrBand(split.protein_pct, 15, 25), fat: amdrBand(split.fat_pct, 20, 35), carb: amdrBand(split.carb_pct, 45, 65) },
    fibre_average: check(average.fibre, fibreTarget, "fibre", tol),
    energy_sd_by_day_type: sdByType,
    days_energy_within: days.filter((d) => d.energy.band === "on_target" || d.energy.band === "within").length,
    days_protein_met: days.filter((d) => d.protein.band === "on_target" || d.protein.band === "within").length,
    distinct_recipes: new Set(recipeItems.map((it) => it.recipe_id)).size,
    distinct_ingredients: ingredients.size,
    cook_events: recipeItems.filter((it) => it.batch_role !== "eat").length,
  };

  return {
    items: items.map((r) => ({ ...r, macros: roundMacros(r.macros) })),
    days,
    cycle,
    batches,
    boosts,
    confidence: items.every((r) => r.complete),
    problems,
  };
}
