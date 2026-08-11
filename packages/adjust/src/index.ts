/**
 * Grams of Health — target-adjustment solver.
 *
 * Pure and deterministic: same recipe + same target → same proposal. The
 * recalculation engine remains the only source of macro numbers; this module
 * only decides which grams to move, then asks the engine what that means.
 *
 * Rules implemented (see design doc):
 *  - Only adjustable roles move, each within ±30% of original grams.
 *  - Section rule: in sauce/dressing/marinade/… sections, adjustable_fat and
 *    adjustable_carb lines are treated as structural; proteins are exempt.
 *  - Tiered candidates: role matching the target macro first, other
 *    adjustables next, bulk_veg last. Pro-rata spread by current contribution.
 *  - Kitchen rounding: 5 g for gram lines, whole units otherwise.
 *  - Unreachable targets return reachable:false plus the closest achievable.
 *  - Lines that cannot resolve to grams are untouchable ("unpriceable").
 */
import {
  compute,
  toGrams,
  type FoodMap,
  type Line,
  type Macro,
  type Macros,
} from "@goh/engine";

export type Role =
  | "adjustable_protein"
  | "adjustable_carb"
  | "adjustable_fat"
  | "bulk_veg"
  | "flavour_base"
  | "structural";

export const SECTION_RE =
  /(sauce|dressing|marinade|glaze|caramel|cream layer|frosting|icing|crumble|dough|batter)/i;

export type AdjustLine = Line & { section?: string | null };

export type Target =
  | { kind: "macro"; macro: Macro; min: number; max: number } // per serve
  | { kind: "macro_delta"; macro: Macro; deltaG: number } // per serve
  | { kind: "energy_delta"; deltaKcal: number }; // per serve

export interface ProposalChange {
  index: number;
  food_id: string;
  beforeGrams: number;
  afterGrams: number;
  beforeQty: number;
  afterQty: number;
  unit: string;
}
export interface Proposal {
  reachable: boolean;
  message: string;
  before: Macros;
  after: Macros;
  changes: ProposalChange[];
  frozen: Array<{ index: number; food_id: string; reason: string }>;
  unpriceable: Array<{ index: number; food_id: string }>;
}

const ADJUSTABLE: ReadonlySet<string> = new Set([
  "adjustable_protein",
  "adjustable_carb",
  "adjustable_fat",
  "bulk_veg",
]);
const MATCH_ROLE: Partial<Record<Macro, Role>> = {
  protein: "adjustable_protein",
  carb_avail: "adjustable_carb",
  fat: "adjustable_fat",
};
const GRAMISH = new Set(["g", "gram", "grams", "kg"]);
const EPS = 1e-6;

interface LineInfo {
  index: number;
  line: AdjustLine;
  grams0: number | null;
  unitGrams: number; // grams of one unit of this line's unit (rounding step)
  role: Role | null;
  effRole: Role | null; // after section rule
  adjustable: boolean;
  bound: number; // max |grams delta|
}

function classify(
  lines: AdjustLine[],
  foods: FoodMap,
  roles: Record<string, Role | null | undefined>,
): LineInfo[] {
  return lines.map((line, index) => {
    const food = foods[line.food_id];
    let grams0: number | null = null;
    let unitGrams = 5;
    if (food) {
      try {
        grams0 = toGrams(food, line.quantity, line.unit);
        unitGrams = GRAMISH.has(line.unit) ? 5 : Math.max(toGrams(food, 1, line.unit), EPS);
      } catch {
        grams0 = null;
      }
    }
    const role = (roles[line.food_id] ?? null) as Role | null;
    let effRole = role;
    if (
      role &&
      (role === "adjustable_fat" || role === "adjustable_carb") &&
      line.section &&
      SECTION_RE.test(line.section)
    ) {
      effRole = "structural";
    }
    const adjustable = grams0 != null && grams0 > 0 && effRole != null && ADJUSTABLE.has(effRole);
    return {
      index,
      line,
      grams0,
      unitGrams,
      role,
      effRole,
      adjustable,
      bound: grams0 != null ? 0.3 * grams0 : 0,
    };
  });
}

/** Deterministic pro-rata distribution with per-line clipping. */
function distribute(
  tier: LineInfo[],
  density: (i: LineInfo) => number,
  deltas: number[],
  need: number,
): number {
  let active = tier.filter((i) => density(i) > EPS);
  for (let pass = 0; pass < 24 && Math.abs(need) > EPS && active.length > 0; pass++) {
    const wSum = active.reduce((s, i) => s + (i.grams0 as number) * density(i), 0);
    if (wSum <= EPS) break;
    let progressed = false;
    for (const i of active) {
      const share = (need * ((i.grams0 as number) * density(i))) / wSum;
      const wantGrams = share / density(i);
      const prev = deltas[i.index];
      const next = Math.max(-i.bound, Math.min(i.bound, prev + wantGrams));
      if (Math.abs(next - prev) > EPS) progressed = true;
      need -= (next - prev) * density(i);
      deltas[i.index] = next;
    }
    active = active.filter((i) => Math.abs(Math.abs(deltas[i.index]) - i.bound) > EPS);
    if (!progressed) break;
  }
  return need;
}

function roundDelta(info: LineInfo, delta: number): number {
  const step = info.unitGrams;
  const snapped = Math.round(delta / step) * step;
  return Math.max(-info.bound - EPS, Math.min(info.bound + EPS, snapped));
}

export function proposeAdjustment(
  recipe: { lines: AdjustLine[]; servings: number },
  foods: FoodMap,
  roles: Record<string, Role | null | undefined>,
  target: Target,
): Proposal {
  const servings = Math.max(1, recipe.servings);
  const infos = classify(recipe.lines, foods, roles);
  // Rule 6: unpriceable lines are tolerated — excluded from totals, never moved.
  const priceable = (ls: AdjustLine[]) => ls.filter((_, idx) => infos[idx].grams0 != null);
  const before = compute(priceable(recipe.lines), servings, foods).perServe;

  const unpriceable = infos
    .filter((i) => i.grams0 == null)
    .map((i) => ({ index: i.index, food_id: i.line.food_id }));
  const frozen = infos
    .filter((i) => i.grams0 != null && !i.adjustable)
    .map((i) => ({
      index: i.index,
      food_id: i.line.food_id,
      reason:
        i.role && ADJUSTABLE.has(i.role) && i.effRole === "structural"
          ? "ratio-bound to its section"
          : "protected ingredient",
    }));

  // Resolve to a total macro delta.
  let macro: Macro;
  let lo: number, hi: number; // per-serve acceptance window
  if (target.kind === "macro") {
    macro = target.macro;
    lo = Math.min(target.min, target.max);
    hi = Math.max(target.min, target.max);
    if (hi - lo < EPS) {
      // Point target: allow kitchen-rounding slack.
      const tol = macro === "energy_kcal" ? 5 : 0.5;
      lo -= tol;
      hi += tol;
    }
  } else if (target.kind === "macro_delta") {
    macro = target.macro;
    const t = before[macro] + target.deltaG;
    lo = t - 0.5;
    hi = t + 0.5;
  } else {
    macro = "energy_kcal";
    const t = before.energy_kcal + target.deltaKcal;
    lo = t - 5;
    hi = t + 5;
  }

  const deltas = new Array(recipe.lines.length).fill(0);
  const density = (i: LineInfo) => (foods[i.line.food_id]?.[macro] ?? 0) / 100;

  const current = before[macro];
  if (current >= lo - EPS && current <= hi + EPS) {
    return {
      reachable: true,
      message: "Already within the requested range — no changes needed.",
      before,
      after: before,
      changes: [],
      frozen,
      unpriceable,
    };
  }
  const targetPoint = current < lo ? lo : hi;
  let need = (targetPoint - current) * servings; // total macro units to add/remove

  const adjustables = infos.filter((i) => i.adjustable);
  const tiers: LineInfo[][] = [];
  const match = MATCH_ROLE[macro];
  const sortT = (a: LineInfo, b: LineInfo) => {
    const ca = (a.grams0 as number) * density(a);
    const cb = (b.grams0 as number) * density(b);
    return cb - ca || a.line.food_id.localeCompare(b.line.food_id);
  };
  if (macro === "energy_kcal") {
    tiers.push(adjustables.filter((i) => i.effRole !== "bulk_veg").sort(sortT));
    tiers.push(adjustables.filter((i) => i.effRole === "bulk_veg").sort(sortT));
  } else {
    if (match) tiers.push(adjustables.filter((i) => i.effRole === match).sort(sortT));
    tiers.push(
      adjustables.filter((i) => i.effRole !== match && i.effRole !== "bulk_veg").sort(sortT),
    );
    tiers.push(adjustables.filter((i) => i.effRole === "bulk_veg").sort(sortT));
  }
  for (const tier of tiers) {
    need = distribute(tier, density, deltas, need);
    if (Math.abs(need) <= EPS) break;
  }

  // Kitchen rounding, then rebuild + measure with the engine.
  for (const i of infos) if (deltas[i.index] !== 0) deltas[i.index] = roundDelta(i, deltas[i.index]);
  const build = () =>
    recipe.lines.map((l, idx) => {
      const i = infos[idx];
      if (deltas[idx] === 0 || i.grams0 == null) return l;
      const newGrams = i.grams0 + deltas[idx];
      const perUnit = GRAMISH.has(l.unit)
        ? l.unit === "kg"
          ? 1000
          : 1
        : i.unitGrams;
      return { ...l, quantity: Math.max(0, newGrams / perUnit) };
    });
  let after = compute(priceable(build()), servings, foods).perServe;

  // One-step nudge if rounding left us outside a reachable window.
  if (after[macro] < lo - EPS || after[macro] > hi + EPS) {
    const movers = infos
      .filter((i) => deltas[i.index] !== 0)
      .sort((a, b) => Math.abs(deltas[b.index]) - Math.abs(deltas[a.index]) || a.line.food_id.localeCompare(b.line.food_id));
    for (const i of movers) {
      const dir = after[macro] < lo ? 1 : -1;
      const stepped = deltas[i.index] + dir * i.unitGrams;
      if (Math.abs(stepped) <= i.bound + EPS) {
        const prev = deltas[i.index];
        deltas[i.index] = stepped;
        const trial = compute(priceable(build()), servings, foods).perServe;
        if (Math.abs(trial[macro] - (lo + hi) / 2) < Math.abs(after[macro] - (lo + hi) / 2)) {
          after = trial;
          break;
        }
        deltas[i.index] = prev;
      }
    }
  }

  const changes: ProposalChange[] = infos
    .filter((i) => deltas[i.index] !== 0)
    .map((i) => {
      const perUnit = GRAMISH.has(i.line.unit) ? (i.line.unit === "kg" ? 1000 : 1) : i.unitGrams;
      const afterGrams = (i.grams0 as number) + deltas[i.index];
      return {
        index: i.index,
        food_id: i.line.food_id,
        beforeGrams: round1(i.grams0 as number),
        afterGrams: round1(afterGrams),
        beforeQty: i.line.quantity,
        afterQty: round2(afterGrams / perUnit),
        unit: i.line.unit,
      };
    })
    .sort((a, b) => a.index - b.index);

  const reachable = after[macro] >= lo - EPS && after[macro] <= hi + EPS;
  return {
    reachable,
    message: reachable
      ? "Target met within kitchen rounding."
      : `Target unreachable within ±30% bounds — closest achievable is ${round1(after[macro])} per serve.`,
    before,
    after,
    changes,
    frozen,
    unpriceable,
  };
}

const round1 = (n: number) => Math.round(n * 10) / 10;
const round2 = (n: number) => Math.round(n * 100) / 100;

// ---------------------------------------------------------------------------
// Typed-request parser — a small deterministic grammar, no AI.
// ---------------------------------------------------------------------------
const MACRO_WORD: Record<string, Macro> = {
  protein: "protein",
  carb: "carb_avail",
  carbs: "carb_avail",
  carbohydrate: "carb_avail",
  carbohydrates: "carb_avail",
  fat: "fat",
  fibre: "fibre",
  fiber: "fibre",
  calorie: "energy_kcal",
  calories: "energy_kcal",
  kcal: "energy_kcal",
  energy: "energy_kcal",
};

export function parseTargetRequest(text: string): Target | null {
  const s = text.trim().toLowerCase();
  const mw = "(protein|carbs?|carbohydrates?|fat|fibre|fiber|calories?|kcal|energy)";
  let m = s.match(new RegExp(`${mw}\\s+(?:to\\s+be\\s+)?between\\s+(\\d+(?:\\.\\d+)?)\\s+and\\s+(\\d+(?:\\.\\d+)?)`));
  if (m) return { kind: "macro", macro: MACRO_WORD[m[1]], min: Number(m[2]), max: Number(m[3]) };
  m = s.match(new RegExp(`${mw}\\s+(?:to|at|=)\\s+(\\d+(?:\\.\\d+)?)`));
  if (m) return { kind: "macro", macro: MACRO_WORD[m[1]], min: Number(m[2]), max: Number(m[2]) };
  m = s.match(new RegExp(`(add|increase(?:\\s+by)?|remove|cut|reduce(?:\\s+by)?)\\s+(\\d+(?:\\.\\d+)?)\\s*(?:g\\s+(?:of\\s+)?)?${mw}`));
  if (m) {
    const sign = /add|increase/.test(m[1]) ? 1 : -1;
    const macro = MACRO_WORD[m[3]];
    const val = sign * Number(m[2]);
    return macro === "energy_kcal"
      ? { kind: "energy_delta", deltaKcal: val }
      : { kind: "macro_delta", macro, deltaG: val };
  }
  return null;
}
