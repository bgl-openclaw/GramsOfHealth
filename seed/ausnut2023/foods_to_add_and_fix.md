# Foods to add, re-point and merge before the AI verification pass

Prepared 21 October 2026 from the live database (517 foods, 311 verified) and AUSNUT 2023 (FSANZ, 3,741 foods). Keys are AUSNUT 2023 Public Food Keys. kcal shown per 100 g from AUSNUT.

Tick, strike or edit each line. Nothing is applied until Claude Code runs the gated pass and reports back.

## A. Create: ingredients lost in the recipe ingest

The 21 `data_issue` recipes name these in the method but the ingredient line was dropped. Claude Code will create the food and add the line; the dietitian confirms quantities.

| New food | AUSNUT key | AUSNUT name | kcal | Recipes affected | Note |
| --- | --- | --- | --- | --- | --- |
| Gelatine powder | F004196 | Gelatine, all types | 346 | 7 cheesecake / crumble / sushi recipes | "3 tsp gelatine in warm water" |
| Coconut flakes | F002987 | Coconut, grated & desiccated | 664 | 6 (optional topping) | We already have "Coconut, desiccated" on this key. Recommend reusing it rather than adding a second food. |
| Olive oil spray | F006177 | Oil, olive | 883 | 1 (Savoury egg muffins) | AUSNUT has no spray row. Use the olive oil row with a "spray" measure of about 0.3 g per one-second spray, marked estimate. |
| Quick pickled veg | none | sub-recipe | | 5 | Not a food. Dietitian re-adds the components (carrot, cucumber, vinegar, sugar), all of which exist. |

## B1. Re-point: unverified foods sitting on a stand-in row

These keep their `food_id` (recipes untouched). The pass re-links to the AUSNUT row below and writes its numbers, then marks the food AI verified with the evidence sentence.

| Food (uses) | Currently linked to | Re-point to | kcal |
| --- | --- | --- | --- |
| Tasty cheese (17) | Cheese, bocconcini | F002414 Cheese, cheddar, natural, plain | 403 |
| Turkey mince (8) | Turkey breast, lean, raw | F010386 Turkey, mince, raw | 148 |
| Vermicelli noodles (11), Vermicelli rice noodle (1), Pad thai rice noodle (1) | Soba, boiled | F006038 Noodle, rice stick, boiled, drained | 119 |
| Red curry paste (4), Tikka curry paste (1) | Paste, green curry | F006471 Paste, curry style | 207 |
| Mixed berries (3) | Goji berry, dried | F009881 Mixed berry, frozen | 48 |
| Wholemeal bread roll (2) | Bread, wholemeal (loaf) | F001360 Bread roll, wholemeal, commercial | 262 |
| Plain rice cake (1) | Cake, sponge | F001147 Biscuit, savoury, rice cake, plain | 383 |
| Rosemary, fresh (1) | Rosemary, dried | F007716 Rosemary, fresh, raw | 95 |
| Thyme, dried (5) | Thyme, fresh | F009160 Thyme, dried | 283 |
| Light cream cheese (1) | Cheese, cream, plain | F002446 Cheese, cream, plain, reduced fat | 229 |
| Red chilli flakes (1) | Chilli, red, raw | F002893 Chilli, dried, ground | |
| Tin butter bean (1) | Bean, butter, raw | F000440 Bean, lima or butter, canned, drained | 85 |
| Powdered sugar (1) | Sugar, raw | F008980 Sugar, white, icing | 382 |
| Microwave rice pouch (18) | estimate | F007678 Rice, white, purchased par-cooked or instant, cooked | 154 |
| Microwave brown rice & quinoa pouch (5) | estimate | F007647 Rice, brown, par-cooked or instant, cooked | 173 |
| Tomato passata (14) | estimate | F009209 Tomato, puree, commercial | 23 |
| Tomato paste (27) | estimate | F009208 Tomato, paste, added salt | 66 |
| Pepitas (8) | estimate | F008212 Seed, pumpkin, hulled & dried, unsalted | 538 |
| Sun-dried tomatoes (6) | estimate | F009217 Tomato, sundried or semi-sundried | 263 |
| Taco seasoning (6) | estimate | F009072 Seasoning mix, chilli based, for tacos | 319 |
| Vegetable stock pot (5) | estimate | F008936 Stock, liquid, all flavours, prepared | 4 |
| Mixed herbs, dried (6) | estimate | F004365 Herbs, dried, all types | 293 |
| Salt (54), Salt & pepper (13) | custom | F007878 Salt, table, iodised | 0 |
| Water (41) | estimate | F009527 Water, tap | 0 |
| Pepper, black, ground (28) | custom | F006618 Pepper, black or white, ground | 276 |
| Soy sauce (46) | custom | F008065 Sauce, soy, commercial | 50 |

Accepted stand-ins (AUSNUT has nothing closer, keep and mark as such): rice wine, apple cider, white and sherry vinegar all on F009498 Vinegar (except balsamic); seeded mustard on F005973 Mustard, cream style; Swiss brown mushroom on F005946 Mushroom, common, raw.

No AUSNUT match, leave for label entry: protein powder (whey rows exist but brand matters; suggest F007493 whey >70% as a reference only), sugar-free maple syrup (suggest F009955 Syrup, maple flavoured, intense sweetened), mini wholemeal wrap (suggest F001411 Bread, flat wrap or tortilla, wholemeal), red bean paste, mustard seed, strawberry Nesquik.

## B2. Verified foods with the wrong reference link

Numbers are correct (a dietitian fixed them by hand), but the stored AFCD key points at the wrong food. The pass would change the reference key and note only, never the numbers, so `verified` is untouched. Please confirm this is acceptable.

| Food (uses) | Linked to now | Should link to |
| --- | --- | --- |
| Butter, salted (20) | Bean, butter, raw | F001973 Butter, plain, salted |
| Chicken stock (9) | Chicken, mince, raw | F008936 Stock, liquid, all flavours, prepared |
| Kalamata olives (4) | Oil, olive | F006198 Olive, green or black, drained |
| Labneh (0) | Oil, olive | none in AUSNUT; nearest F009655 Yoghurt, natural, greek style |
| Hot sauce (3) | Hot dog roll | F007997 Sauce, chilli, commercial |
| Peas, green (7) and Peas, frozen (0) | Pea, split, dried | F006536 Pea, green, raw |
| Diced tomatoes, canned (10) and Crushed tomatoes, canned (5) | Tomato, cherry, raw | F009222 Tomato, whole, canned in tomato juice |
| Chocolate, milk (1) | Chocolate, white | F002929 Chocolate, milk |
| White Bread (0) | Tortilla | F001463 Bread, white, commercial |
| Grapeseed oil (1) | Oil, mustard seed | F006167 Oil, grapeseed |
| Chickpeas, drained (1) | Chickpea, dried | F002880 Chickpea, canned, drained |
| Kidney beans, drained (1) | Bean, red kidney, dried | F000448 Bean, red kidney, canned, drained |
| Brown lentils, drained (9) | Lentil, dried, cooked | F010192 Lentil, canned (Green lentils, cooked stays on its correct cooked row) |
| Microwave brown rice (1) | Rice, brown, uncooked | F007647 Rice, brown, par-cooked or instant, cooked |
| Beef rump steak, trimmed (6) | Beef, diced, lean | F000739 Beef, rump steak, lean, raw |
| Tofu, silken (5) | Tofu, firm | F009183 Tofu, silken or soft |
| Caster sugar (16) | Sugar, white, icing | F008976 Sugar, white, granulated |
| Gluten-free pasta, cooked (5) | Pasta, white, boiled | F006429 Pasta, gluten free, plain, boiled |
| Cottage cheese, low fat (11) | Cheese, cottage | F002438 Cheese, cottage, reduced fat |
| Soy sauce, dark (4) | Soy, reduced salt | F008065 Sauce, soy, commercial |

## B3. Parse-artefact duplicates to merge into the real food

These were created by the PDF ingest from phrases, not foods. Each has 0 or 1 uses. Decision (Ben, 21 Oct): remove them. The pass re-points any ingredient line to the canonical food in the right-hand column, snapshots the row to seed/archive, then deletes it.

| Duplicate | Merge into |
| --- | --- |
| Olive Oil Burger, Olive Oil Coating | Extra virgin olive oil |
| Sesame Seed Tomato | Sesame seeds |
| Salt And Black Pepper, Salt & Black Pepper | Salt (and Pepper) |
| Lime Juice To Assemble, Lime Juice, freshly squeezed | Lime juice |
| Stalk Celery | Celery |
| Powder | Curry powder (check the recipe) |
| Dried Oregano (dried_oregano) | Oregano, dried (oregano) |
| Tin Tuna In Spring Water | Tuna, springwater, drained |
| Old Fashioned Rolled Oat | Rolled oats |
| Unsweetened Cocoa Powder | Cocoa powder |
| Pesto Sauce | Pesto |
| Tonic Water, Raspberry Tonic Water | one Tonic water food |
| Red Long Chilli | Red Chilli |
| Spring Onion Green | Spring onion |
| Soba noodles | keep (different food from vermicelli) |
| Egg quick pickled veg | re-point lines to Egg, then delete |
| Lemongrass Stalk | Lemongrass |

The machine-readable version is `lists/list_B3_merge_delete.csv` (19 rows, all unverified). Three verified look-alikes (Egg mayo, a second Lemon juice, a second Orange juice) are in `lists/list_B3b_verified_duplicates_dietitian.csv` for a dietitian to decide; Egg mayo is a full-fat mayonnaise, not the same food as light mayonnaise.

## C. New pantry foods

Superseded by `foods_to_add_C.md` / `foods_to_add_C.csv` (250 proposed, grouped by category, with a dietitian decision column).
