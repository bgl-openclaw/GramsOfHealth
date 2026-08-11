/**
 * Batch profile preload: drafts the four standard profiles (High protein,
 * Low fat, Higher fibre, Lighter) for every ELIGIBLE recipe (all ingredients
 * verified + all lines priced) using the real solver, and emits idempotent SQL.
 *
 *  - Machine drafts only: origin='machine', verified=false. Never touches a
 *    verified or dietitian-owned profile; refreshes an untouched machine draft
 *    only when its base_fingerprint no longer matches.
 *  - Deterministic: recipes sorted, solver deterministic.
 *  - Unreachable target → nothing saved. Already meets → nothing saved.
 *
 * Usage: node dumps data to preload_data.json first (see bash driver), then
 *   npx tsx scripts/preload-profiles.ts <data.json> > preload.sql
 */
import { readFileSync } from "node:fs";
import type { FoodMap } from "@goh/engine";
import { compute, toGrams } from "@goh/engine";
import { proposeAdjustment, achievableRange, type Role, type AdjustLine, type Proposal } from "../packages/adjust/src";

type DumpLine = { id: string; food_id: string; quantity: number; unit: string; section: string | null; position: number };
type DumpRecipe = { id: string; title: string; servings: number; lines: DumpLine[] };
const dump = JSON.parse(readFileSync(process.argv[2], "utf8")) as {
  foods: Array<{ food_id: string; energy: number | null; protein: number | null; fat: number | null; carb: number | null; fibre: number | null; density: number | null; role: Role | null }>;
  conversions: Array<{ food_id: string; unit: string; grams: number }>;
  recipes: DumpRecipe[];
};

const foods: FoodMap = {};
for (const f of dump.foods) {
  foods[f.food_id] = {
    name: f.food_id,
    energy_kcal: f.energy ?? 0, protein: f.protein ?? 0, fat: f.fat ?? 0,
    carb_avail: f.carb ?? 0, fibre: f.fibre ?? 0, density: f.density,
    conversions: {},
  };
}
for (const c of dump.conversions) {
  const f = foods[c.food_id];
  if (f) (f.conversions ??= {})[c.unit] = Number(c.grams);
}
const roles: Record<string, Role | null> = {};
for (const f of dump.foods) roles[f.food_id] = f.role;

const fnv1a = (s: string) => {
  let h = 0x811c9dc5;
  for (let i = 0; i < s.length; i++) { h ^= s.charCodeAt(i); h = Math.imul(h, 0x01000193) >>> 0; }
  return h.toString(16).padStart(8, "0");
};
const fingerprint = (lines: DumpLine[]) =>
  fnv1a([...lines].sort((a, b) => a.position - b.position)
    .map((l) => `${l.food_id}|${Number(l.quantity)}|${l.unit}|${l.section ?? ""}`).join("\n"));

const q = (v: unknown): string =>
  v == null ? "NULL" : typeof v === "number" ? String(v) : "'" + String(v).replace(/'/g, "''") + "'";

const dishWeight = (lines: AdjustLine[]) => {
  let w = 0;
  for (const l of lines) { const f = foods[l.food_id]; if (!f) continue; try { w += toGrams(f, l.quantity, l.unit); } catch { /* unpriceable */ } }
  return w;
};
const applyProposal = (lines: DumpLine[], p: Proposal): DumpLine[] =>
  lines.map((l, idx) => {
    const c = p.changes.find((x) => x.index === idx);
    return c ? { ...l, quantity: c.afterQty } : l;
  });

const stats: Record<string, { saved: number; skipped: Record<string, number> }> = {};
const note = (name: string, key: "saved" | string) => {
  stats[name] ??= { saved: 0, skipped: {} };
  if (key === "saved") stats[name].saved++;
  else stats[name].skipped[key] = (stats[name].skipped[key] ?? 0) + 1;
};
let widenedUsed = false;
const out: string[] = ["begin;"];

const emitProfile = (r: DumpRecipe, name: string, pos: number, p: Proposal, fp: string) => {
  if (p.changes.length === 0) { note(name, "no changes produced"); return; }
  const R = q(r.id), N = q(name), FP = q(fp);
  out.push(`-- ${r.title} :: ${name}`);
  out.push(`delete from recipe_profile_deltas d using recipe_profiles p where d.profile_id=p.id and p.recipe_id=${R} and p.name=${N} and p.origin='machine' and p.verified=false and p.base_fingerprint is distinct from ${FP};`);
  out.push(`delete from recipe_profiles where recipe_id=${R} and name=${N} and origin='machine' and verified=false and base_fingerprint is distinct from ${FP};`);
  out.push(`insert into recipe_profiles (recipe_id,name,position,origin,base_fingerprint) select ${R},${N},${pos},'machine',${FP} where not exists (select 1 from recipe_profiles where recipe_id=${R} and name=${N});`);
  const rows = p.changes.map((c, i) => {
    const l = r.lines[c.index];
    return `(${q(l.id)},${q(l.food_id)},${q(Number(l.quantity))},${q(l.unit)},${q(l.section)},'quantity',${q(c.afterQty)},${q(l.unit)},${i})`;
  });
  out.push(`insert into recipe_profile_deltas (profile_id,line_ref,base_food_id,base_quantity,base_unit,base_section,kind,new_quantity,new_unit,position)
select p.id, v.line_ref::uuid, v.base_food_id, v.base_quantity::numeric, v.base_unit, v.base_section, v.kind, v.new_quantity::numeric, v.new_unit, v.position::int from recipe_profiles p, (values ${rows.join(",")}) as v(line_ref,base_food_id,base_quantity,base_unit,base_section,kind,new_quantity,new_unit,position)
where p.recipe_id=${R} and p.name=${N} and p.origin='machine' and p.verified=false
  and not exists (select 1 from recipe_profile_deltas d where d.profile_id=p.id);`);
  note(name, "saved");
};

for (const r of [...dump.recipes].sort((a, b) => a.title.localeCompare(b.title) || a.id.localeCompare(b.id))) {
  const fp = fingerprint(r.lines);
  const base = compute(r.lines, r.servings, foods).perServe;
  const W = dishWeight(r.lines);
  const F = base.fat * r.servings;

  // 1. High protein — the achievable max, saved only if ≥ base +15%.
  {
    const range = achievableRange(r, foods, roles, "protein");
    if (range.max < base.protein * 1.15) note("High protein", "max gain <15%");
    else {
      const p = proposeAdjustment(r, foods, roles, { kind: "macro", macro: "protein", min: range.max, max: range.max });
      if (p.after.protein >= base.protein * 1.15) emitProfile(r, "High protein", 0, p, fp);
      else note("High protein", "rounding left gain <15%");
    }
  }
  // 2. Low fat — FSANZ ≤3 g / 100 g dish, closed form x=(F−0.03W)/0.97 + one verify pass.
  {
    if (W > 0 && F / W <= 0.03) note("Low fat", "already ≤3g/100g");
    else {
      const x = (F - 0.03 * W) / 0.97;
      let target = (F - x) / r.servings;
      let p = proposeAdjustment(r, foods, roles, { kind: "macro", macro: "fat", min: target, max: target });
      let after = applyProposal(r.lines, p);
      let ratio = (p.after.fat * r.servings) / Math.max(1, dishWeight(after));
      if (ratio > 0.0305 && p.changes.length > 0) {
        const F2 = p.after.fat * r.servings, W2 = dishWeight(after);
        const x2 = (F2 - 0.03 * W2) / 0.97;
        target = (F - (x + Math.max(0, x2))) / r.servings; // deeper cut from base
        p = proposeAdjustment(r, foods, roles, { kind: "macro", macro: "fat", min: target, max: target });
        after = applyProposal(r.lines, p);
        ratio = (p.after.fat * r.servings) / Math.max(1, dishWeight(after));
      }
      if (ratio <= 0.0305 && p.changes.length > 0) emitProfile(r, "Low fat", 1, p, fp);
      else note("Low fat", ratio > 0.0305 ? "unreachable within bounds" : "no movable fat");
    }
  }
  // 3. Higher fibre — base <4 g/serve → reach ≥4.
  {
    if (base.fibre >= 4) note("Higher fibre", "already ≥4g/serve");
    else {
      const p = proposeAdjustment(r, foods, roles, { kind: "macro", macro: "fibre", min: 4, max: 999 });
      if (p.reachable) emitProfile(r, "Higher fibre", 2, p, fp);
      else note("Higher fibre", "unreachable within bounds");
    }
  }
  // 4. Lighter — energy at base −20% (±5 kcal; widened to ±2% only if needed).
  {
    const t = base.energy_kcal * 0.8;
    const p = proposeAdjustment(r, foods, roles, { kind: "macro", macro: "energy_kcal", min: t, max: t });
    if (p.reachable) emitProfile(r, "Lighter", 3, p, fp);
    else if (Math.abs(p.after.energy_kcal - t) <= 0.02 * t && p.changes.length > 0) {
      widenedUsed = true;
      emitProfile(r, "Lighter", 3, p, fp);
    } else note("Lighter", "unreachable within bounds");
  }
}
out.push("commit;");
process.stdout.write(out.join("\n") + "\n");
process.stderr.write(`eligible recipes: ${dump.recipes.length}\n`);
for (const [name, s] of Object.entries(stats)) {
  process.stderr.write(`${name}: saved=${s.saved}` + (Object.keys(s.skipped).length ? ` skipped={${Object.entries(s.skipped).map(([k, v]) => `${k}:${v}`).join(", ")}}` : "") + "\n");
}
process.stderr.write(`lighter tolerance widened to ±2%: ${widenedUsed}\n`);
