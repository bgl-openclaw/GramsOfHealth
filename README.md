# Grams of Health — backend & engine (Phases 0–1)

The database and the recalculation engine for the Grams of Health recipe tool.
**No UI, no auth, no export** — those are later phases. Every macro is computed
from grams; nothing here stores a manually-overridden macro number.

## Layout

```
seed/                     The source CSVs/JSON (AFCD master, foods, conversions, recipes)
supabase/migrations/      SQL schema (six tables + afcd_master)
packages/engine/          The portable engine — pure functions, no framework/DB deps
scripts/                  Seed loader, Supabase import, verify command
tests/                    Engine tests mirroring validation_report.md
```

## Setup

```bash
npm install
```

## The engine (`@goh/engine`)

A standalone, dependency-free TypeScript package the front-end (Lovable) can
import. A faithful port of `seed/recalc_engine.py`.

- `toGrams(food, qty, unit)` — `g`/`kg` direct; `x95g` = qty × 95; volume units
  (tsp 5 mL / tbsp 20 mL / cup 250 mL) use density when present else the
  unit-conversion grams; descriptive/count units use the unit-conversion grams.
- `compute(lines, servings, foods)` → `{ totals, perServe, rows }`, each macro
  contribution = `grams / 100 × per-100g value`; `perServe = totals / servings`.
- `atwater(perServe)` = `4·protein + 4·carb + 9·fat + 2·fibre` kcal (consistency check).
- `createEngine(foods)` — convenience wrapper for `engine.compute(lines, servings)`.

"Carbs" = available carbohydrate, excluding fibre. Fibre is always separate.

```bash
npm run build:engine   # emits packages/engine/dist for consumers
```

## Verify & test

```bash
npm run verify   # prints per-serve macros + Atwater for both seed recipes
npm test         # asserts the seed numbers (vitest)
```

Expected (mirrors `seed/validation_report.md`):

| Recipe | Computed energy | Atwater |
| --- | --- | --- |
| Lentil Tuna Salad | 369 kcal/serve | 365 (1.0% drift) |
| Salmon Fish Cakes (listed) | 226 kcal/serve | 223 (1.4% drift) |

> Atwater lands "within about one percent" per the validation report. The seed's
> per-100g values carry rounding, so the real drift is 1.0% and 1.4%; the test
> tolerance is set accordingly (`ATWATER_TOLERANCE = 0.015`).

The Salmon recipe carries a known data issue: the salmon is named in the method
but missing from the printed ingredient list, so computed protein/energy
understate. `verify` flags it; a dietitian reconciles.

## Import into Supabase

```bash
cp .env.example .env        # fill SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY
supabase db push            # or apply supabase/migrations to a fresh project
npm run import              # idempotent — safe to re-run
```

`import` upserts `afcd_master`, `foods`, `unit_conversions` on their natural
keys and replaces recipes by title, so re-running yields exactly one copy of
each.

### Validation performed

- Migration applies cleanly to fresh Postgres 15 (Supabase's engine): six tables
  + `afcd_master`.
- Full seed loads under the schema with all FKs, the `food_source` enum, NOT
  NULLs and `unique(food_id, unit)` satisfied: 1,588 AFCD foods, 61 foods
  (19 AFCD / 42 custom), 20 conversions, 2 recipes, 27 ingredient lines.
