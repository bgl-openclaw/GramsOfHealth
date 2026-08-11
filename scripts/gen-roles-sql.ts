/**
 * Emits idempotent SQL loading adjustment-engine roles from
 * seed/food_roles_v2.csv into foods.role.
 *  - Duplicate food_ids: prefer the row WITH a note, else the first.
 *  - 'JUNK_REVIE' typo normalised to JUNK_REVIEW.
 *  - Only the six engine roles are written; JUNK/delete-marked rows → NULL
 *    (frozen — the engine never moves an unclassified food).
 *   npx tsx scripts/gen-roles-sql.ts > roles_load.sql
 */
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { parse } from "csv-parse/sync";

const HERE = dirname(fileURLToPath(import.meta.url));
const ROLES = new Set(["adjustable_protein","adjustable_carb","adjustable_fat","bulk_veg","flavour_base","structural"]);
const rows = parse(readFileSync(join(HERE, "..", "seed", "food_roles_v2.csv"), "utf8"),
  { columns: true, skip_empty_lines: true, trim: true }) as Array<Record<string,string>>;

const byId = new Map<string, Record<string,string>>();
for (const r of rows) {
  const prev = byId.get(r.food_id);
  if (!prev || ((r.note ?? "").trim() && !(prev.note ?? "").trim())) byId.set(r.food_id, r);
}
const q = (s: string) => "'" + s.replace(/'/g, "''") + "'";
const sets: string[] = [];
let engineRoles = 0, frozen = 0;
for (const r of byId.values()) {
  const role = (r.role ?? "").trim().replace(/^JUNK_REVIE$/, "JUNK_REVIEW");
  if (ROLES.has(role)) { sets.push(`(${q(r.food_id)},${q(role)})`); engineRoles++; }
  else frozen++;
}
process.stdout.write(
`begin;
update foods set role = null;  -- full reload: CSV is the source of truth
update foods f set role = v.role
from (values\n${sets.join(",\n")}\n) as v(food_id, role)
where f.food_id = v.food_id;
commit;\n`);
process.stderr.write(`unique foods in CSV: ${byId.size} | engine roles: ${engineRoles} | junk/frozen (NULL): ${frozen}\n`);
