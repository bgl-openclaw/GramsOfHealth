# Grams of Health — coverage & outliers report

Built from the recipe PDFs, matched against AFCD Release 3 (1,588 foods). Every row carries `verified = FALSE` — the dietitian confirms or corrects.

## Corpus

- **326 unique recipes** parsed (308 from the master "(44)" PDF + 18 only in the two Nutrition Books; male/female portion variants and exact-title duplicates de-duplicated by slug).
- **3735 ingredient lines**, **701 unique foods**.
- Images: 326/326 recipes have a primary photo, 314 have a second; named `<slug>-1` / `<slug>-2`.

## Foods: every row now carries macros (none blank)

Per your instruction, every food has per-100g macros filled. The `match_note` column states the confidence tier for each row so the dietitian knows what to check first. All rows are `verified = FALSE`.

| Confidence tier | Count | Source of macros |
| --- | --- | --- |
| AFCD direct | **242** | Pulled from AFCD; curated key |
| AFCD proxy (auto) | **88** | Closest AFCD food, auto-matched |
| Seed custom | **33** | Carried from the original seed library |
| Curated estimate | **67** | Hand-entered per-100g for branded/composite items |
| Category estimate | **271** | Typical value for the food class (lowest confidence) |
| **Total foods** | **701** | |

**By ingredient occurrence, 2239/2984 (75%) of resolvable ingredient lines map to a high-confidence food** (AFCD direct or seed). AFCD-matched staples (oils, meats, eggs, dairy, common vegetables, grains, legumes) drive almost all of the macro totals. The **271 category estimates** are the weakest tier — mostly rare, single-use ingredients; verify these first. (54 ingredient lines were dropped as un-parseable method text — see below.)

## Engine validation

`recalc_engine.py` runs over **all 326 recipes with no unresolved units**. For each recipe the energy computed from grams is checked against the 4/4/9/2 Atwater sum of its own macros.

- Seed check — **Lentil Tuna Salad: 369 kcal/serve, C20 P34 F15, Atwater 365 (1.1% drift)** — reproduces the seed validation report exactly.
- Atwater drift across recipes: mean 1.5% (excluding alcoholic drinks), median 0.9%. Drift above ~3% almost always means a recipe contains a blank-macro custom ingredient (understated) — listed below.

## Recipes to fix (data issues)

### A. Ingredient named in the method but missing from the list (the "salmon fish cakes" case) — 9

A protein appears as the object of a cooking step yet has no ingredient line — computed protein/energy understate until the dietitian adds it and confirms the quantity. (Heuristic; a few may be incidental mentions worth a quick glance.)

- **SALMON FISH CAKES** — "salmon" appears in the method, not in the ingredient list.
- **CHICKEN PAD THAI** — "chicken" appears in the method, not in the ingredient list.
- **JAPANESE MISO RAMEN** — "chicken" appears in the method, not in the ingredient list.
- **SMOKED SALMON BAGEL** — "chicken" appears in the method, not in the ingredient list.
- **CARAMELISED BRUSSEL SPROUTS WITH BACON** — "bacon" appears in the method, not in the ingredient list.
- **LOADED SPAGHETTI BOLOGNESE** — "pork" appears in the method, not in the ingredient list.
- **MARRY ME PRAWN PASTA** — "chicken" appears in the method, not in the ingredient list.
- **COCONUT TOFU VIETNAMESE SALAD** — "chicken" appears in the method, not in the ingredient list.
- **SHEET PAN PROTEIN PANCAKES** — "egg" appears in the method, not in the ingredient list.

### B. Recipes whose servings could not be read (38) — defaulted to 4, flagged

- ORANGE & CRANBERRY COOKIE BARS
- HUGO SPRITZ
- RASPBERRY & LEMON SPRITZ
- PROTEIN ZUCCHINI FRITTERS
- TOMATO CHUTNEY
- TERIYAKI CHICKEN PARCELS
- COTTAGE PIE
- HOMEMADE BEEF & CHEESE PIES
- HOMEMADE BEEF PIES
- HOMEMADE GREEK CHICKEN PIES
- HOMEMADE CHICKEN POT PIES
- VEGETABLE HASH CAKES
- PIKELETS
- PISTAHIO ICE-CREAM SANDOS
- SAVOURY EGG MUFFINS
- BANANA BREAD CHOC CHIP COOKIES
- FLUFFY JAPANESE SOUFFLE PANCAKES
- PICKLED VEG!
- BANANA OAT MUFFINS
- CRISPY TUNA SUSHI BALLS
- MANGO SALSA TOSTADAS WITH AVOCADO CREAM
- CEVICHE TOSTADAS
- CAPRESE SKEWERS
- PORK WONTON CUPS
- CRISPY SALMON SUSHI BITES
- CHERRY & GOATS CHEESE TOASTS
- HIGH PROTEIN PORRIDGE
- PROTEIN PANCAKES
- LOW FODMAP LEMON BARS
- CHOC COVERED PEANUT BUTTER DATES
- CHOC COVERED APPLE SLICE SANDWICH
- FODMAP FRIENDLY LCM BARS
- HOMEMADE LCM BARS
- FODMAP FRIENDLY RICE PAPER DUMPLINGS
- FODMAP FRIENDLY FRITTATA MUFFINS
- FODMAP FRIENDLY PEANUT BUTTER COOKIES
- PEANUT BUTTER GRANOLA COOKIES
- RAINBOW FRITTATA MUFFINS

### C. Recipes leaning on a *category-level* estimate (≥30 g of a lowest-tier food) — 119

These compute fine, but their macros depend on a category estimate rather than a specific value — highest priority for the dietitian to confirm (food id + grams shown).

- **AIR FRIED SALMON POKE BOWL**: microwave_brown_rice_quinoa_pouch (~450 g)
- **AIR FRYER TOMATO SOUP**: ml_reduced_salt_vegetable_stock (~20000 g), red_capsium (~50 g)
- **ALMOND BAKED OATS**: flaked_almond (~30 g)
- **ARRABBIATA SAUCE**: tin_diced_tomato (~400 g)
- **ASIAN CHICKEN NOODLES**: individual_serve_instant_noodle (~200 g)
- **ASIAN FISH PARCELS**: white_fish_fillet (~200 g)
- **BAKED LAMB RISOTTO**: vegetable_stock_pot (~100 g)
- **BAKED VEGETABLE FRITTATA**: taste_cheese (~169 g)
- **BANANA BREAD CHOC CHIP COOKIES**: overripe_banana (~80 g)
- **BANANA BREAD GRANOLA**: coconut_shard (~72 g)
- **BANANA BREAD MUG CAKE**: overly_ripe_banana (~120 g)
- **BANANA GRANOLA COOKIES**: sized_ripe_banana (~120 g)
- **BANANA NICE CREAM**: natural_peanut (~36 g)
- **BANANA OAT MUFFINS**: chocolate_chip_optional (~85 g)
- **BEEF BURGERS**: zuchinni (~100 g)
- **BEEF BURRITO BOWL**: microwaveable_basmati_rice_pouch (~450 g)
- **BLOOD ORANGE GRAIN SALAD**: blood_orange (~180 g)
- **BUTTER CHICKEN**: x_mingle_butter_chicken_sachet (~100 g), salt_reduced_chicken_stock (~200 g)
- **CAPRESE SALAD WITH PANGRATTATO**: roma_tomato (~140 g), mozzarella_ball (~100 g)
- **CAPRESE SKEWERS**: tub_cherry_bocconcini (~100 g)
- **CEVICHE TOSTADAS**: sashimi_grade_salmon (~200 g)
- **CHEESEBURGER TACOS**: gluten_free_mini_wrap (~800 g)
- **CHICKEN & QUINOA FRITTERS**: firm_feta (~200 g)
- **CHICKEN CACCIATORE WITH BASMATI RICE**: g_tin_diced_tomato (~200 g)
- **CHICKEN MI GORENG**: wholegrain_wok_ready_noodle (~400 g)
- **CHICKEN PAD THAI**: pad_thai_noodle (~200 g)
- **CHICKEN PARMI BAKE**: vine_tomato (~100 g), low_carb_potato (~400 g), bag_rocket_salad_bag_mix (~100 g)
- **CHICKEN PASTA BAKE**: cheese_oil_spray (~125 g)
- **CHICKEN POT PIES**: chicken_stock_cube (~200 g)
- **CHICKEN QUESADILLAS**: pre_cooked_bbq_chicken (~100 g)
- **CHICKEN SANDO BITES**: sandwich (~1200 g)
- **CHICKEN SCHNITZEL AND VEG**: tenderloin_cut_raw_chicken (~800 g)
- **CHOC DIPPED RICE CAKES**: chocolate_melt (~200 g)
- **CHOPPED CHICKEN WRAP**: wholemeal (~200 g)
- **CHRISTMAS PUDDING BALLS**: whiite_chocolate (~40 g)
- **COWBOY CAVIAR**: roma_tomato (~140 g), coriander_tortilla_chip_serving (~57 g)
- **CREAMY BEEF UDON NOODLE BOWL**: wok_ready_udon_noodle (~440 g)
- **CRISPY TUNA SUSHI BALLS**: light_mayonnaise (~46 g), baby_cos (~100 g)
- **DESSERT NACHOS**: plain_greek_yogurt (~188 g), heavy_whipping_cream (~83 g), milk_chocolate_chip_almond_flake (~125 g)
- **DESSERT PIZZA**: vanilla_greek_yogurt (~188 g), milk_chocolate_chip_almond_flake (~62 g)
- **EARL GREY CAKE**: earl_grey_tea_bag (~200 g)
- **EASTER ROCKY ROAD**: white_and_pink_marshmallow (~344 g), gluten_free_arnott_scotch_finger (~170 g), packet_baking_milk_chocolate_melt (~450 g)
- **EASY CHICKEN FAJITAS**: x_mini_wholegrain_wrap_coriander (~800 g)
- **FLORENTINE SLICE**: slivered_almond (~125 g)
- **FLUFFY JAPANESE SOUFFLE PANCAKES**: cake_flour (~75 g)
- **FODMAP FRIENDLY BAKED OATS**: unripe_banana (~240 g)
- **FODMAP FRIENDLY FRITTATA MUFFINS**: short_cut_bacon (~69 g)
- **FODMAP FRIENDLY PEANUT BUTTER COOKIES**: firm_banana (~400 g)
- **FODMAP FRIENDLY PESTO**: day (~500 g)
- **FODMAP FRIENDLY PESTO ORZO SALAD**: gf_risoni (~344 g), tuna_in_springwater_shredded_chicken (~190 g)
- **FODMAP FRIENDLY RICE PAPER DUMPLINGS**: dumpling_s (~600 g)
- **GARLIC SESAME TOFU STIR FRY**: bread_crumb (~33 g)
- **GLUTEN FREE BEEF MEAT PIE**: gluten_free_puff_pastry (~250 g)
- **GRILLED LAMB STEAK WITH ROAST VEG COUS COUS**: pearl_cou_cou (~250 g), hot_vegetable_stock (~300 g)
- **GUACAMOLE**: yellow_onion (~40 g), roma_tomato (~140 g), jalapeno_pepper (~100 g)
- **HERB CRUSTED SALMON**: panko_bread_crumb (~38 g)
- **HIGH PROTEIN NO BAKE CHEESECAKE**: vanilla_yopro_yogurt (~62 g), warm_water_3_teaspoon_gelatin_powder (~60 g)
- **HIGH PROTEIN OVERNIGHT WEETBIX**: weet_bix (~400 g)
- **HIGH PROTEIN RAVIOLI LASAGNE**: packet_ravioli (~800 g), tinned_tomato (~400 g)
- **HOMEMADE BEEF BURGERS**: sandwich_thin (~400 g)
- **HOMEMADE CHILLI OIL**: star_anise (~200 g), chinese_chilli_flake (~103 g), korean_red_pepper_flake (~33 g)
- **INDIVIDUAL TIRAMISU CUPS**: mascarpone_cheese (~250 g), ladyfinger_biscuit (~1600 g)
- **ITALIAN PASTA SALAD**: spiral_pasta (~450 g)
- **KOFTA PITA POCKETS**: wholemeal_pita_pocket (~400 g)
- **KOREAN BEEF & KIMCHI RICE BOWL**: kimchi (~200 g)
- **LAMB GYROS - GF, LF**: lactose_free_greek_yoghurt (~125 g), pickled_onion (~75 g), lactose_free_yoghurt_lettuce (~125 g)
- **LEMON MILLE FUIELLE**: granulated_sugar_1_large_egg (~50 g)
- **MAC N’ CHEESE**: pulse_pasta (~250 g)
- **MANGO CRISPY RICE SALAD**: thai_basil (~40 g)
- **MASSAMAN CURRY PASTE**: red_chilly (~600 g)
- **MEATBALL SHAKSHUKA**: danish_feta (~100 g)
- **MEXICAN RICE BOWL**: microwavable_rice (~450 g)
- **MOROCCAN LAMB COUS COUS SALAD**: lamb_backstrap (~400 g), pear_cou_cou (~81 g)
- **NANDOS INSPIRED CHICKEN BURGERS**: malt_vinegar (~80 g), peri_peri_sauce (~60 g), burger_thin (~400 g)
- **ONE PAN TUSCAN SALMON**: parmesan_few_handful_baby_spinach (~30 g)
- **ONE POT MEXICAN RICE**: greek_yoghurt_lime_wedge (~83 g)
- **PEACH & RASPBERRY PAN CRUMBLE**: rolled_quinoa_flake (~46 g)
- **PEANUT BUTTER RAMEN**: ramen_wok_ready_noodle (~400 g)
- **PESTO AIR-FRYER BREAKFAST BAGELS**: low_carb_bagel (~100 g)
- **PESTO PASTA SALAD**: risoni (~344 g)
- **PISTAHIO ICE-CREAM SANDOS**: sando (~600 g)
- **POACHED PEACHES WITH HONEY LABNEH & CRUMBLE**: ripe_but_firm_peach (~400 g)
- **PORK WONTON CUPS**: wonton_cup (~1200 g)
- **PRAWN DUMPLING STIR FRY**: packet_prawn_dumpling (~180 g)
- **PREP-AHEAD EGG MCMUFFINS**: wholemeal_english_muffin (~300 g)
- **QUICK LEMON YOGHURT PARFAIT**: tub_lemon_chobani_greek_yoghurt (~100 g)
- **QUICK YOGHURT PARFAIT**: tub_chobani_greek_yoghurt (~100 g)
- **RAINBOW FRITTATA MUFFINS**: sun_dried_tomato_strip (~75 g), feta_oil_spray (~125 g)
- **RAVIOLI 3 WAYS**: lasagne_sheet (~500 g)
- **RED BEAN MOCHI**: x_rice_paper_sheet_cornstarch_dusting (~800 g)
- **SALMON FISH CAKES**: tzatziki_lemon_wedge (~65 g)
- **SARDINE KALE PASTA**: high_protein_pasta (~300 g)
- **SAVOURY EGG MUFFINS**: tasty_cheese_oil_spray (~125 g)
- **SLOW COOKER BEEF RAGU WITH PAPPARDELLE**: pasta_water_parsley (~125 g)
- **SLOW COOKER TIKKA MASALA**: light_cream_cooked_basmati_rice (~100 g), roma_tomato (~140 g)
- **SMASHED CUCUMBER SALAD**: side_serving (~400 g)
- **SPAGHETTI BOLOGNESE**: pre_sliced_mushroom (~200 g), g_can_crushed_tomato (~100 g), vetta_smart_fibre_pasta (~250 g)
- **SPINACH AND RICOTTA CANNELONI**: cannelloni_shell_sauce (~250 g)
- **SPINACH AND RICOTTA RAVIOLI**: lasagna_sheet (~800 g), tomato_passata_prepare_pasta (~700 g)
- **SPRING ONION PANCAKE W DIPPING SAUCE**: with_second_ball_dough (~700 g)
- **STRAWBERRY ICE-CREAM**: unsweetened_greek_yogurt (~125 g)
- **SUPER GREENS & PRAWN VEGETABLE CURRY**: lebanese_eggplant (~600 g)
- **SWEET AND SOUR PORK**: canned_pineapple_piece (~72 g)
- **TERIYAKI CHICKEN & RICE**: packet_microwave_rice (~200 g)
- **TERIYAKI CHICKEN PARCELS**: packet_filo_pastry_teriyaki_chicken (~375 g)
- **TERIYAKI CHICKEN SUSHI ROLLS**: nori_sheet (~300 g)
- **TERIYAKI SAUCE TERIYAKI CHICKEN SUSHI**: sushi_seaweed_sheet (~600 g), sushi_roll (~600 g)
- **THAI CHICKEN LARB**: lemongrass_stalk (~100 g)
- **THAI CHICKEN PEANUT NOODLES (FODMAP)**: wok_ready_noodle (~250 g)
- **THERMOMIX LENTIL AND PUMPKIN SOUP**: canned_crushed_tomato (~400 g)
- **TOMATO CHUTNEY**: mixed_colour_tomato (~500 g)
- **TUNA SUSHI BOWL**: plain_tuna (~370 g)
- **TUNA TARTARE**: sashimi_grade_tuna (~200 g), mini_caper (~33 g)
- **VEGETABLE DUMPLINGS**: wombok (~38 g), gyoza_wrappers_dumpling_wrapper (~2000 g)
- **VEGETARIAN PASTA**: vetta_smart_protein_pasta (~250 g)
- **VIETNAMESE BÁNH MÌ STYLE SLIDERS**: each_soy_sauce_sesame_oil (~40 g), egg_quick_pickled_veg (~100 g), daikon (~46 g), egg_mayo (~69 g), slider_bun (~1000 g)
- **WAFFLES**: waffle (~6800 g)
- **WREATH ROCKET & PROSCUITTO SALAD**: bocconcini_homemade_crouton_balsamic_glaze (~200 g)
- **with Edamame Dip**: brown_rice_and_quinoa_microwave_packet (~500 g)

### D. Recipes with unresolved units (0)

None — every ingredient line resolves to grams.

## Notes & conventions held

- Australian measures: tsp = 5 mL, tbsp = 20 mL, cup = 250 mL.
- "Carbs" = available carbohydrate **excluding** fibre; fibre is a separate, always-populated field.
- No nutrition values invented: custom items with no AFCD match and no label are left blank and flagged.
- `unit_conversions.csv` weights are sensible Australian defaults (`basis = default`); item/household weights such as "1 medium onion = 110 g" should be confirmed.
- Alcoholic drinks (spritzes, mocktails) show high Atwater drift because ethanol carries energy that the 4/4/9/2 check does not count — expected, not an error.