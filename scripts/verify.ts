/**
 * `npm run verify` — prints, per recipe, the per-serve macros and the Atwater
 * consistency figure. Mirrors the bottom of the Python engine and the numbers
 * in seed/validation_report.md. Reads the seed CSVs directly; no database.
 */
import { compute, atwater } from "@goh/engine";
import { loadSeed, recipeToLines } from "./seed";

const { recipes, foodMap } = loadSeed();

console.log("Grams of Health — recipe verification (per serve)\n");

for (const recipe of recipes) {
  const { lines, servings } = recipeToLines(recipe);
  const { perServe } = compute(lines, servings, foodMap);
  const a = atwater(perServe);
  const drift = (Math.abs(a - perServe.energy_kcal) / perServe.energy_kcal) * 100;

  console.log(
    `${recipe.title.padEnd(24)} ` +
      `${perServe.energy_kcal.toFixed(0).padStart(4)} kcal/serve  |  ` +
      `C ${perServe.carb_avail.toFixed(0).padStart(3)}  ` +
      `P ${perServe.protein.toFixed(0).padStart(3)}  ` +
      `F ${perServe.fat.toFixed(0).padStart(3)}  ` +
      `fib ${perServe.fibre.toFixed(1).padStart(4)}  |  ` +
      `atwater ${a.toFixed(0).padStart(4)} (${drift.toFixed(1)}% drift)`,
  );

  if (recipe.data_issue) {
    console.log(`  ⚠ data issue: ${recipe.data_issue}`);
  }
}

console.log(
  "\nExpected from validation_report.md: " +
    "Lentil Tuna Salad ~369 kcal (atwater 365), Salmon Fish Cakes ~226 kcal (atwater 223).",
);
