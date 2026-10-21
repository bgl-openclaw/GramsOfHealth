# Dietitian review pack (22 October 2026)

Everything waiting on a dietitian, in the order it's needed. Nothing here changes the live app until it's reviewed and loaded.

| # | What | Where | Needed for |
|---|---|---|---|
| 1 | **AUSNUT food import**: urgent values, splits, measures, roles, protein families and aisles | Review page (share as Contributor): https://claude.ai/artifact/JNqBi3w2f8WE5MNpAog2Hn | Applying AUSNUT, which takes usable recipes from 26 to about 201 |
| 2 | **Meal types**: which slots each of the 374 recipes can fill, and which are treats | `seed/meal_types/meal_types_for_review.csv` (how to: `seed/meal_types/HOW-TO-REVIEW.md`) | The meal planner (it uses whatever is in this list) |
| 3 | **Swap groups**: which foods can replace each other in suggestions, plus 40 foods whose values look wrong | `seed/swap_groups/swap_groups_for_review.csv` and `not_in_a_group.csv` (how to: `seed/swap_groups/HOW-TO-REVIEW.md`) | Ingredient-swap suggestions in the planner report |
| 4 | **Planner rules**: the tolerances and slot energy shares below | This page; tick or change | The planner report's "on target / within / under / over" |

## 4. Planner rules to confirm

No professional body publishes a tolerance for written client plans, so these are practice policy (from the research). Please tick **Agree** or write the number you'd use.

| Rule | Proposed | Agree? | Change to |
|---|---|---|---|
| Energy, each day | Within ±10% of the day-type target is fine; within ±5% is shown as on target | ☐ | |
| Protein, each day | Never under target; up to +15% over is fine | ☐ | |
| Carbohydrate and fat, each day | Within ±10% of target | ☐ | |
| Fibre | Judged on the weekly average against the client's fibre target (shown daily, not judged daily) | ☐ | |
| Energy split over the week | Protein 15–25%, fat 20–35%, carbohydrate 45–65% of energy (NHMRC AMDR). Athletes or deliberate high-protein plans can sit above 25% protein as a recorded choice | ☐ | |
| Protein at main meals | Flag (not fail) a lunch or dinner under 0.3 g/kg, or under 20 g for clients 65+ | ☐ | |
| Treats | About one discretionary serve a day | ☐ | |
| Serving sizes | Planner uses ¼-serve steps from 0.5 to 2 serves; anything outside 0.75–1.5 is flagged for a look | ☐ | |
| Repeats | Default: no main on consecutive days unless it's a planned leftover; no recipe more than 3 times in 7 days (each client's own settings override this) | ☐ | |
| Protein rotation | Counts lunches and dinners only; snacks are used to top up the day's protein, carbs and fat (owner decision) | ☐ | |

**Slot energy shares** (the owner has agreed these defaults; each client's slots can override them):

| Breakfast | Lunch | Dinner | Snacks (split between snack slots) |
|---|---|---|---|
| 25% | 30% | 30% | 15% |

Notes:
