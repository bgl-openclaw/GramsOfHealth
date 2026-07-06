/**
 * Emits idempotent SQL that (1) loads the seven added nutrient columns into
 * afcd_master from seed/afcd_master_full.csv and (2) backfills the ten
 * per-100g nutrient fields on foods for source='afcd' rows via afcd_key —
 * coalesce-guarded, so a value a dietitian has already entered is NEVER
 * overwritten. Custom foods are untouched (null, for label entry).
 *
 * Requires migration 0015_food_nutrients.sql to be applied first.
 *
 *   npx tsx scripts/gen-nutrients-sql.ts > nutrients_load.sql
 */
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { parse } from "csv-parse/sync";

const HERE = dirname(fileURLToPath(import.meta.url));
const CSV = join(HERE, "..", "seed", "afcd_master_full.csv");

// afcd_master column -> exact source column in the full AFCD CSV
const NUTRIENTS: Array<[string, string]> = [
  ["potassium_mg", "Potassium (K) (mg)"],
  ["calcium_mg", "Calcium (Ca) (mg)"],
  ["iron_mg", "Iron (Fe) (mg)"],
  ["zinc_mg", "Zinc (Zn) (mg)"],
  ["magnesium_mg", "Magnesium (Mg) (mg)"],
  ["folate_ug", "Total folates (ug)"],
  ["vitamin_b12_ug", "Cobalamin (B12) (ug)"],
];

// foods column -> afcd_master column (backfill map, all ten)
const BACKFILL: Array<[string, string]> = [
  ["sugars_100g", "sugars"],
  ["satfat_100g", "satfat"],
  ["sodium_100g", "sodium_mg"],
  ["potassium_100g", "potassium_mg"],
  ["calcium_100g", "calcium_mg"],
  ["iron_100g", "iron_mg"],
  ["zinc_100g", "zinc_mg"],
  ["magnesium_100g", "magnesium_mg"],
  ["folate_100g", "folate_ug"],
  ["vitamin_b12_100g", "vitamin_b12_ug"],
];

const num = (v: string | undefined): string => {
  if (v === undefined) return "NULL";
  const t = v.trim();
  if (t === "") return "NULL";
  const n = Number(t);
  return Number.isFinite(n) ? String(n) : "NULL";
};

const rows = parse(readFileSync(CSV, "utf8"), {
  columns: true,
  skip_empty_lines: true,
  trim: true,
  bom: true,
}) as Record<string, string>[];

const out: string[] = ["begin;"];

// 1. Load the seven nutrients into afcd_master (plain overwrite — this is the
//    reference table; its values ARE the AFCD source).
const values = rows
  .filter((r) => r["Public Food Key"])
  .map((r) => {
    const key = "'" + r["Public Food Key"].replace(/'/g, "''") + "'";
    const nums = NUTRIENTS.map(([, src]) => num(r[src]));
    return `(${key},${nums.join(",")})`;
  });
out.push(
  `update afcd_master am set\n` +
    NUTRIENTS.map(([col], i) => `  ${col} = v.c${i}`).join(",\n") +
    `\nfrom (values\n${values.join(",\n")}\n) as v(key,${NUTRIENTS.map((_, i) => `c${i}`).join(",")})\nwhere am.public_food_key = v.key;`,
);

// 2. Backfill foods (AFCD rows only), never overwriting an entered value.
out.push(
  `update foods f set\n` +
    BACKFILL.map(([fc, ac]) => `  ${fc} = coalesce(f.${fc}, am.${ac})`).join(",\n") +
    `\nfrom afcd_master am\nwhere f.source = 'afcd' and f.afcd_key = am.public_food_key;`,
);

out.push("commit;");
process.stdout.write(out.join("\n") + "\n");
process.stderr.write(`afcd_master rows in CSV: ${values.length}\n`);
