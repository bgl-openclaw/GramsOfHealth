# Swap groups: how to review `swap_groups_for_review.csv`

A swap group is a set of foods that can replace each other **gram for gram in the same recipe line**. The meal planner uses these groups for suggestions like "swap the beef mince for chicken mince: fat −9 g". It never suggests a swap outside a group, and every suggestion still goes through the client's allergy and dislike screen. Nothing is applied without the dietitian approving it.

- **Keep in group:** leave the `x` if the food belongs. Delete it if it doesn't.
- **Move to group:** if it belongs in a different group, write that group's name here.
- **Value check:** foods whose numbers look wrong. Some have energy that doesn't match their macros, some share identical values with several other foods (probably a placeholder), and some "cooked" foods carry dry values. These need fixing in the food list before the planner can use them. A note is enough.
- **Status:** "new from AUSNUT" foods arrive when the AUSNUT import is applied.
- **Cross-role:** a food that also appears in a second group, e.g. Greek yoghurt as a swap for sour cream and mayonnaise.
- **Group note:** how the group swaps (cooked for cooked, dry for dry, drained for drained). Change the wording if it's wrong.
- `not_in_a_group.csv` lists adjustable foods that aren't in any group. Fill in a group only if they should swap.
- Please don't edit the `food_id` or `group_key` columns.
