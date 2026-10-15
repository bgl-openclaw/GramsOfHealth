/**
 * `npx tsx scripts/check-line-grams.ts` — parity check between the SQL
 * read-model `line_grams` (migration 0030) and the canonical engine toGrams,
 * over every live ingredient line. Read-only. Exit code 1 on any mismatch.
 */
import { toGrams, type FoodData } from "@goh/engine";
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

type Line = { id: string; food_id: string; quantity: number; unit: string };
type Food = { food_id: string; display_name: string; density_g_ml: number | null };
type Conv = { food_id: string; unit: string; grams: number };
type Sql = { id: string; grams: number | null };

const [lines, foods, convs, sql] = await Promise.all([
  all<Line>("ingredient_lines", "id,food_id,quantity,unit"),
  all<Food>("foods", "food_id,display_name,density_g_ml"),
  all<Conv>("unit_conversions", "food_id,unit,grams"),
  all<Sql>("line_grams", "id,grams"),
]);

const conversions = new Map<string, Record<string, number>>();
for (const c of convs) {
  const m = conversions.get(c.food_id) ?? {};
  m[c.unit] = Number(c.grams);
  conversions.set(c.food_id, m);
}
const foodData = new Map<string, FoodData>();
for (const f of foods) {
  foodData.set(f.food_id, {
    name: f.display_name, energy_kcal: 0, protein: 0, fat: 0, carb_avail: 0, fibre: 0,
    density: f.density_g_ml == null ? null : Number(f.density_g_ml),
    conversions: conversions.get(f.food_id) ?? {},
  });
}
const sqlById = new Map(sql.map((s) => [s.id, s.grams == null ? null : Number(s.grams)]));

let resolved = 0, unresolved = 0;
const mismatches: string[] = [];
for (const l of lines) {
  const food = foodData.get(l.food_id);
  let engine: number | null = null;
  try {
    if (food) engine = toGrams(food, Number(l.quantity), l.unit);
  } catch {
    engine = null;
  }
  const s = sqlById.has(l.id) ? sqlById.get(l.id)! : undefined;
  engine == null ? unresolved++ : resolved++;
  const same = s === undefined ? false : engine == null ? s == null : s != null && Math.abs(s - engine) < 1e-6;
  if (!same) mismatches.push(`${l.id} ${l.quantity} ${l.unit} ${l.food_id}: engine=${engine} sql=${s}`);
}

console.log(`lines ${lines.length} · engine resolved ${resolved} · unresolved ${unresolved} · mismatches ${mismatches.length}`);
for (const m of mismatches.slice(0, 20)) console.log("  " + m);
process.exit(mismatches.length ? 1 : 0);
