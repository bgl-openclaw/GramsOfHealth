# Dietitian review pack (22 October 2026)

Everything waiting on a dietitian, in the order it's needed. Nothing here changes the live app until it's reviewed and loaded.

| # | What | Where | Needed for |
|---|---|---|---|
| 1 | **AUSNUT food import**: urgent values, splits, measures, roles, protein families and aisles | Review page (share as Contributor): https://claude.ai/artifact/JNqBi3w2f8WE5MNpAog2Hn | Applying AUSNUT, which takes usable recipes from 26 to about 201 |
| 2–4 | **Planner set-up**: the rules (tolerances, slot energy shares), meal types for every recipe, and swap groups (with 40 foods whose values look wrong) | **Live review page** (share as Contributor): https://claude.ai/artifact/6KzWBgS79BtL1FueRJ9e5z. Three parts, each signed off separately | The meal planner and its report |
| 5 | **Clinical reference**: blood marker ranges (311), nutrient reference values (310), adult targets (energy split, fibre, saturated fat, sodium, treat allowance), optional plan rules and questions D1–D12 | In the app: Settings → Clinical reference (start with the Decisions tab) | The planner's nutrient checks and the results reader |

The CSVs in `seed/meal_types/` and `seed/swap_groups/` hold the same lists for reference. Answers are made on the live page, which Claude reads back before loading anything.

## Reference: the planner rules (answered on the live page, part 1)

No professional body publishes a tolerance for written client plans, so these are practice policy (from the research). The dietitian answers each one on the live page; this table is for reference. These rules are about the client's own targets only: population values (nutrient reference values, the protein/fat/carbohydrate energy split, saturated fat, sodium, the treat allowance) are decided once, under Settings → Clinical reference (item 5), so nothing is asked twice.

| Rule | Proposed | Agree? | Change to |
|---|---|---|---|
| Energy, each day | Within ±10% of the day-type target is fine; within ±5% is shown as on target | ☐ | |
| Protein, each day (the client's own target) | Never under target; up to +15% over is fine. The NRV protein floor is D11 in Clinical reference | ☐ | |
| Carbohydrate and fat, each day | Within ±10% of target | ☐ | |
| Fibre (the client's own target) | Judged on the weekly average against the client's own fibre target (shown daily, not judged daily) | ☐ | |
| Protein at main meals | Flag (not fail) a lunch or dinner under 0.3 g/kg, or under 20 g for clients 65+ | ☐ | |
| Serving sizes | Planner uses ¼-serve steps from 0.5 to 2 serves; anything outside 0.75–1.5 is flagged for a look | ☐ | |
| Repeats | Default: no main on consecutive days unless it's a planned leftover; no recipe more than 3 times in 7 days (each client's own settings override this) | ☐ | |
| Protein rotation | Counts lunches and dinners only; snacks are used to top up the day's protein, carbs and fat (owner decision) | — | |

Also decided by the owner (22 Oct): lunch slots also take dinner recipes; recipes containing a disliked food are always left out; the plan shows one recipe per slot, with alternatives behind Swap.

**Slot energy shares** (the owner has agreed these defaults; each client's slots can override them):

| Breakfast | Lunch | Dinner | Snacks (split between snack slots) |
|---|---|---|---|
| 25% | 30% | 30% | 15% |

