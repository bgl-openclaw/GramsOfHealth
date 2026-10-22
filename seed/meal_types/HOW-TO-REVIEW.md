# Meal types: how to review `meal_types_for_review.csv`

The meal planner uses these to decide which recipes can go in which slot. Every one of the 374 recipes has a suggestion already filled in. Please check each row and change what's wrong.

- **Breakfast / Lunch / Dinner / Snack:** put an `x` in every slot the recipe suits. More than one is fine. Most mains suit lunch and dinner, and leftovers from dinner can still go to lunch.
- **Not a meal:** sauces, sides, condiments and drinks. The planner never places these on their own. Leave the other four columns empty when you tick this.
- **Discretionary:** treats and desserts (about one serve a day is the guide). An `x` is only a suggestion.
- **Variant of:** variants (e.g. the chicken version of a beef recipe) follow their base recipe. Only change a variant if it should differ.
- **Confidence / Why:** how the suggestion was made. "Old tag" is the meal tag from the old system, which has been kept.
- **Dietitian note:** anything we should know.
- Please don't edit the `recipe_id` column. It's how your answers are loaded back.

Nothing is loaded until you're done. Your answers are saved as dietitian-confirmed.
