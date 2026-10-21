"""AUSNUT revision 3 — Claude's decisions layered on top of the rev-2 package (21 Oct 2026).

Every entry was checked by hand against the live library (names, numbers, how recipes use the food)
and the AUSNUT 2023 master/measures. Owner's bar: apply only what is >= 95 % certain; everything else
is a PROPOSAL (not applied) for the owner/dietitian. build_changeset.py turns this into the changeset.
"""

# ---------------------------------------------------------------------------------------------
# 1. Unverified foods → write AUSNUT numbers and mark AI verified (confidence 'agreed_list').
#    (food_id: (ausnut_key, reason)).  Rule-based matches (exact key / High match) that pass the
#    gates are added by the builder; these are the ones decided by review.
LINK = {
    "light_mayonnaise": ("F005437", "light mayonnaise = AUSNUT reduced/low-fat mayonnaise (current numbers were a category estimate)"),
    "low_fat_mayo": ("F005437", "same food category; held only by the name rule ('Mayo' vs 'Mayonnaise')"),
    "malt_vinegar": ("F009498", "malt vinegar = AUSNUT vinegar (except balsamic)"),
    "microwavable_rice": ("F007678", "microwave rice = AUSNUT white rice, par-cooked/instant, as rice_pouch"),
    "microwaveable_basmati_rice_pouch": ("F007678", "microwave rice pouch = AUSNUT white rice, par-cooked/instant"),
    "packet_microwave_rice": ("F007678", "microwave rice packet = AUSNUT white rice, par-cooked/instant"),
    "mixed_colour_tomato": ("F009210", "fresh tomatoes (500 g) = AUSNUT tomato, raw, nfd"),
    "mixed_italian_herb": ("F004365", "dried Italian herbs (1 tsp) = AUSNUT herbs, dried, all types"),
    "mixed_spice": ("F008746", "mixed spice = AUSNUT spices, dried, all types"),
    "star_anise": ("F008746", "star anise = AUSNUT spices, dried, all types"),
    "sumac": ("F008746", "sumac = AUSNUT spices, dried, all types"),
    "szechuan_peppercorn": ("F008746", "Szechuan pepper = AUSNUT spices, dried, all types (current 35 kcal was a vegetable estimate)"),
    "ml_reduced_salt_vegetable_stock": ("F008937", "reduced-salt liquid stock = AUSNUT stock, liquid, reduced salt, prepared"),
    "mozzarella_ball": ("F002406", "a fresh mozzarella ball is the bocconcini type = AUSNUT cheese, bocconcini (not the firm pizza mozzarella); kept as its own food: recipes use '1 each' = 1 ball"),
    "packet_baking_milk_chocolate_melt": ("F002929", "milk chocolate melts = AUSNUT chocolate, milk"),
    "packet_prawn_dumpling": ("F010533", "= AUSNUT dumpling, savoury, prawn, purchased frozen"),
    "paprika": ("F006316", "ground paprika = AUSNUT paprika, dried, ground (gate: 282 → 313 kcal; blocks 13 recipes)"),
    "passionfruit_pulp": ("F006332", "its own key, canned pulp (gate miss is 116 vs 105 kcal)"),
    "pomegranate": ("F006842", "arils = AUSNUT pomegranate, peeled, raw; held only by the name rule"),
    "pre_sliced_mushroom": ("F005946", "sliced button mushrooms = AUSNUT mushroom, common, raw"),
    "radicchio": ("F002884", "radicchio is a red chicory = AUSNUT chicory, raw"),
    "sashimi_grade_salmon": ("F007863", "= AUSNUT salmon, sashimi style, raw"),
    "sashimi_grade_tuna": ("F009296", "= AUSNUT tuna, sashimi style, raw"),
    "snow_peas": ("F008373", "was keyed to boiled split peas; snow peas = AUSNUT snow pea, raw"),
    "sugar_white": ("F008976", "white sugar = AUSNUT sugar, white, granulated (the High match was icing sugar)"),
    "thai_basil": ("F000396", "Thai basil = AUSNUT basil, green, fresh"),
    "unsweetened_greek_yogurt": ("F009655", "= AUSNUT yoghurt, natural, greek style"),
    "white_and_pink_marshmallow": ("F005428", "= AUSNUT marshmallow, plain or flavoured"),
    "white_chocolate_button": ("F002946", "its own key; held only by the name rule ('button')"),
    "white_fish_fillet": ("F003956", "= AUSNUT fish, white flesh, raw, nfd"),
    "white_potato": ("F007356", "was keyed to white-flesh SWEET potato; potato = AUSNUT potato, peeled, raw"),
    "tzatziki": ("F003535", "tzatziki = AUSNUT dip, cucumber & yoghurt, commercial"),
    "sriracha": ("F007997", "sriracha = AUSNUT sauce, chilli, commercial"),
}

# B1 rows the plausibility gate would queue, but where the current numbers are known to be wrong
# (copied from a stand-in or the wrong food) and the B1 key is right: write AUSNUT numbers.
B1_OVERRIDE = {
    "tasty_cheese": "current numbers are a bocconcini stand-in; tasty = cheddar",
    "turkey_mince": "current numbers are a turkey-breast stand-in",
    "mixed_berries": "current numbers are goji berries; frozen mixed berries",
    "plain_rice_cake": "current numbers are a sponge-cake stand-in",
    "rosemary": "name says fresh; current numbers are dried rosemary",
    "thyme": "name says dried; current numbers are fresh thyme",
    "light_cream_cheese": "current numbers are full-fat cream cheese",
    "red_chili_flake": "flakes are dried; current numbers are fresh chilli",
    "tin_butter_bean": "current numbers are fresh butter beans; recipe uses a 400 g tin",
    "tomato_paste": "same food; AUSNUT tomato paste (blocks 9 recipes)",
    "mixed_herbs_dried": "same food; AUSNUT herbs, dried",
    "pepper": "same food; AUSNUT black pepper, ground (blocks 15 recipes)",
    "soy_sauce": "same food; AUSNUT soy sauce (blocks 14 recipes; live density 1.15 kept)",
    "oyster_mushroom": "current numbers are raw OYSTERS (seafood); oyster mushroom = AUSNUT mushroom, oriental",
    "olive_oil_kewpie_mayonnaise": "current numbers are olive oil (883 kcal); Kewpie = regular mayonnaise",
    "tomato_based_pizza_sauce": "current numbers are salsa; pizza sauce = AUSNUT tomato pasta sauce, commercial",
}

# Combined ingredients → separate lines (owner, 21 Oct: "salt and pepper are different and should not be together").
# Each recipe line of the combined food becomes one line per part (quantity × factor, same unit, section and note),
# placed where the original line was. "each_…" foods came from lines like "1 tbsp each paprika and cumin", so each
# part gets the full amount; "salt & pepper" is one amount shared, so half each. If a recipe already lists every
# part separately, the combined line is a duplicate and is removed. Unverified combined foods are then deleted;
# verified ones are left unused for a dietitian to delete.
SPLITS = {
    "salt_and_pepper": {"parts": [("salt", 0.5), ("pepper", 0.5)], "why": "'salt & pepper': one amount, split half and half"},
    "each_paprika_and_cumin": {"parts": [("paprika", 1), ("cumin_powder", 1)], "why": "'1 tbsp each paprika and cumin': the cumin was missing"},
    "each_onion_garlic_powder": {"parts": [("onion_powder", 1), ("garlic_powder", 1)], "why": "'1 tsp each onion and garlic powder': the garlic powder was missing"},
    "each_onion_and_garlic_powder": {"parts": [("onion_powder", 1), ("garlic_powder", 1)], "why": "'½ tsp each onion and garlic powder': the garlic powder was missing"},
    "each_minced_ginger_and_minced_garlic": {"parts": [("ginger_fresh", 1), ("garlic", 1)], "why": "'1 tbsp each minced ginger and garlic': the ginger was missing"},
    "each_soy_sauce_sesame_oil": {"parts": [("soy_sauce", 1), ("sesame_oil", 1)], "why": "'2 tbsp each soy sauce and sesame oil': the sesame oil was missing"},
}

# B1 rows NOT to apply: the AUSNUT row is the wrong state for how recipes use the food.
B1_HOLD = {
    "vermicelli_noodles": "recipes use 200–250 g packets (dry); AUSNUT has only boiled rice noodles (≈3× too low). Label numbers needed.",
    "vermicelli_rice_noodle": "400 g in a ramen: dry or fresh? AUSNUT has only boiled rice noodles.",
    "pad_thai_rice_noodle": "400 g in pad see ew (fresh wide noodles?); AUSNUT has only boiled rice stick.",
    "red_curry_paste": "AUSNUT 'paste, curry style' (206 kcal) vs current green-curry-paste row (149); brands vary — label.",
    "tikka_curry_paste": "as red curry paste — label numbers needed.",
    "vegetable_stock_pot": "a stock pot is a concentrate (28 g each), not prepared liquid stock; its 'each' = 100 g is also wrong.",
}

# Unverified exact-key / High matches the rules would accept but that are wrong or uncertain.
RULE_HOLD = {
    "sardine_in": "'Sardine In' is canned sardines (in oil/springwater); key is raw sardine — state mismatch.",
    "protein_pita_bread": "branded high-protein pita; key is plain white pita. Label numbers.",
    "pulse_pasta": "High match is boiled pulse pasta; check whether the recipe weight is dry.",
    "soba_noodles": "keyed to BOILED soba, but the one recipe uses 250 g for 4 serves (62 g each) — almost certainly the dry packet weight.",
}

# Duplicates / garbled names → re-point every reference to the canonical food, then delete.
MERGE = {
    "mini_caper": ("capers", "capers"),
    "mixed_black_and_white_sesame_seed": ("sesame_seeds", "sesame seeds"),
    "nori_sheet": ("nori", "nori sheets"),
    "sushi_seaweed_sheet": ("nori", "sushi seaweed = nori sheets"),
    "overly_ripe_banana": ("banana", "banana"),
    "overripe_banana": ("banana", "banana"),
    "sized_ripe_banana": ("banana", "garbled 'medium-sized ripe banana'"),
    "unripe_banana": ("banana", "banana"),
    "taste_cheese": ("tasty_cheese", "typo of tasty cheese"),
    "sun_dried_tomato_strip": ("sundried_tomato", "sun-dried tomatoes"),
    "sake_small_pinch_salt_and_pepper": ("cooking_sake", "garbled 'sake' + 'small pinch salt and pepper' (lines are 1 tsp sake)"),
    "tenderloin_cut_raw_chicken": ("chicken_breast_tenderloin", "chicken tenderloins"),
    "tin_diced_tomato": ("diced_tomato_canned", "canned diced tomatoes"),
    "tinned_tomato": ("diced_tomato_canned", "canned tomatoes"),
    "turmeric_powder": ("turmeric", "ground turmeric"),
    "vine_tomato": ("tomato", "fresh tomato"),
    "slivered_almond": ("almond", "slivered almonds"),
    "soy": ("soy_sauce", "'2 tsp soy' in Spaghetti Bolognese; was keyed to soy LECITHIN (626 kcal)"),
}

# Unused (no recipe, no client rule, no swap) junk or test rows → delete.
DELETE_UNUSED = {
    "aaa": "test row 'aaa test'",
    "mcmuffin": "takeaway product, estimate numbers, unused",
    "mediterranean_orzo": "a dish name, estimate numbers, unused",
    "orange_peel_piece": "parse artefact, unused",
    "pepper_as_needed": "parse artefact, unused",
    "pinch_more_salt": "parse artefact, unused",
    "pinch_nutmeg": "parse artefact, unused",
    "pinch_salt_pepper": "parse artefact, unused",
    "pinch_sea_salt_flake": "parse artefact, unused",
    "sauce": "generic 'Sauce' keyed to BBQ sauce, unused",
    "spray_oil": "unused; olive_oil_spray is created in A",
    "vitawheat_9_seed_grain_biscuit": "branded, unused",
}

# Branded / no AUSNUT equivalent → label-entry queue (stays unverified; numbers from the pack).
LABEL = {
    "low_carb_bagel": "branded low-carb bagel", "low_gi_high_protein_wrap": "branded wrap", "low_gi_wrap": "branded wrap",
    "plant_based_feta": "branded plant-based cheese", "protein_electrolyte": "branded supplement", "sandwich_thin": "branded sandwich thins",
    "tub_chobani_greek_yoghurt": "Chobani (plain Greek, 0 % fat)", "tub_lemon_chobani_greek_yoghurt": "Chobani lemon",
    "vetta_smart_fibre_pasta": "Vetta Smart Fibre", "vetta_smart_protein_pasta": "Vetta Smart Protein", "wholemeal_wrap": "mini wholemeal wrap (brief: label)",
    "balsamic_glaze": "no AUSNUT glaze row", "nutritional_yeast": "no AUSNUT row; current numbers are wrong (fat 52 g)",
    "red_pesto": "no AUSNUT red pesto", "orange_zest": "no AUSNUT orange peel row (current values look like USDA orange peel)",
}

# Proposals for the owner/dietitian — NOT applied.  (food_id: (suggested action, reason))
PROPOSE = {
    "low_carb_potato": ("link F007356 potato, peeled, raw", "low-carb potato varieties have ~25 % fewer carbs than AUSNUT potato"),
    "milk_chocolate_chip_almond_flake": ("split the 2 lines into milk chocolate chips + flaked almonds", "two ingredients merged in the import"),
    "moroccan_seasoning": ("link F008746 spices (no salt) or label", "commercial blends usually contain salt"),
    "packet_ravioli": ("link F006428 (vegetable-filled) or F006425 (meat-filled)", "filling unknown"),
    "pad_thai_noodle": ("label: dry rice stick noodles", "200 g is a dry packet weight; AUSNUT has only boiled"),
    "peri_peri_sauce": ("link F007997 chilli sauce, commercial", "~90 % sure"),
    "pickle": ("link F004206 gherkin, pickled", "dill pickle vs sweet gherkin unclear"),
    "pork_scotch_fillet": ("label or AUSNUT pork forequarter (lean)", "no lean scotch-fillet row; current numbers are lean pork fillet"),
    "pre_cooked_bbq_chicken": ("link F002569 barbecued chicken, without skin (or F002568 with skin)", "skin on or off?"),
    "short_cut_bacon": ("link F000231 bacon, shortcut, cooked", "AUSNUT has only cooked; recipe weight is probably raw"),
    "slider_bun": ("link F001353 bread roll, white", "brioche sliders are richer"),
    "spiral_pasta": ("link F006458 pasta, white, dry", "450 g in a pasta salad is almost certainly the dry weight"),
    "pear_cou_cou": ("link F003239 couscous, uncooked", "0.5 cup, almost certainly dry"),
    "pearl_cou_cou": ("link F003239 couscous, uncooked", "250 g, almost certainly dry"),
    "thyme_oregano_mix": ("split into 1 tbsp thyme + 1 tbsp oregano (fresh or dried?)", "two herbs in one line; 2 tbsp: fresh or dried?"),
    "tub_cherry_bocconcini": ("merge into bocconcini and change the line to ~200 g", "'1 each' means one tub"),
    "vanilla_greek_yogurt": ("link F009922 flavoured, regular fat, high protein — or label", "no flavoured Greek row"),
    "vanilla_high_protein_yoghurt": ("link F009957 flavoured, low fat, high protein", "~90 % sure"),
    "wholegrain_wok_ready_noodle": ("link F006048 noodle, wheat, Asian style, cooked", "wok-ready noodles are pre-cooked; wholegrain variant"),
    "vermicelli_noodles": ("label: dry rice vermicelli (~360 kcal/100 g)", "B1 hold"),
    "vermicelli_rice_noodle": ("label: dry or fresh rice noodles", "B1 hold"),
    "pad_thai_rice_noodle": ("label: fresh wide rice noodles", "B1 hold"),
    "red_curry_paste": ("label from the brand used", "B1 hold"),
    "tikka_curry_paste": ("label from the brand used", "B1 hold"),
    "vegetable_stock_pot": ("link F008933 stock, dry powder or cube as proxy, and set each = 28 g", "B1 hold"),
    "sardine_in": ("link a canned sardine row", "rule hold"),
    "protein_pita_bread": ("label", "rule hold"),
    "pulse_pasta": ("check the recipe weight is cooked", "rule hold"),
    "soba_noodles": ("link F006043 soba, uncooked (359 kcal) if 250 g is the dry weight", "rule hold: state"),
}

# ---------------------------------------------------------------------------------------------
# 2. Dietitian-verified foods: link (key) corrections only — numbers are never touched.
VERIFIED_KEY_FIX = {
    "glace_cherry": ("F002521", "glacé cherries (was raw cherry)"),
    "cranberry_dried": ("F003248", "dried cranberries (was raw cranberry)"),
    "currants": ("F003331", "dried currants (was fresh currant)"),
    "fig": ("F003834", "fresh fig (was dried fig)"),
    "apple_sauce": ("F000104", "stewed apple (was dried apple)"),
    "wholemeal_pasta": ("F006464", "wholemeal pasta, boiled (was uncooked)"),
    "high_protein_yoghurt": ("F009809", "low-fat high-protein yoghurt (was high-fat flavoured)"),
    "almond": ("F006081", "almonds (was almond MILK)"),
    "balsamic_vinegar": ("F009499", "balsamic vinegar (was other vinegar)"),
    "200g_250g_pasta": ("F006458", "dry white pasta (was boiled pulse pasta)"),
    "greek_yoghurt": ("F009655", "Greek-style yoghurt (was regular natural)"),
    "capsicum": ("F002247", "red capsicum, matches its numbers (was green)"),
    "zucchini": ("F009775", "green zucchini, raw (was golden, cooked)"),
    "pear": ("F006609", "pear, raw (was canned)"),
    "beef_mince": ("F000655", "regular beef mince >10 % fat, matches its numbers (was <5 % fat)"),
    "bread": ("F001463", "white bread (was organic bread)"),
    "wholemeal_flour": ("F004014", "wholemeal WHEAT flour (was rye)"),
    "cabbage": ("F002015", "white cabbage (was mustard cabbage)"),
    "kale": ("F004781", "kale, raw (was cooked)"),
    "chocolate_dark": ("F002922", "dark chocolate >60 % (was dark with nuts)"),
    "adzuki_bean": ("F000448", "'Red Beans' = red kidney, canned, drained; matches its numbers"),
    "light_cottage_cheese": ("F002438", "reduced-fat cottage cheese (was regular)"),
    "beetroot": ("F001015", "beetroot, raw (was canned)"),
    "light_cream": ("F003261", "light thickened cream (was light SOUR cream)"),
    "lemon": ("F005174", "lemon, peeled, raw (the High match was PRESERVED lemon)"),
}

# Verified foods the automatic check would pass but whose key is the wrong food: flagged, not checked.
VERIFIED_HOLD = {
    "fried_shallot": "'Fried Shallot' (the crispy garnish is ~550–600 kcal) carries cooked-shallot numbers (41 kcal). Unused.",
}

# Verified foods whose NUMBERS look wrong — proposals for the owner/dietitian (applying one
# replaces the numbers with AUSNUT's, which removes dietitian verification and sets AI verified).
URGENT_VERIFIED = {
    "milk_chocolate": ("F002929", "81 kcal with chocolate-MILK macros; milk chocolate is 521 kcal. A second food 'chocolate' (verified, 521 kcal) exists — merge into it."),
    "leek": ("F005164", "313 kcal but leek macros (P2.1 F0.4 C3.7) — a typo for ~31"),
    "lamb_leg_steak": ("F005095", "553 kcal, fat 57.6 g — separable-fat numbers; lean lamb steak is ~130 kcal"),
    "egg_white": ("F003706", "197 kcal with P11.2 — a typo for ~47"),
    "gf_pasta": ("F006429", "'Gluten-Free Pasta, cooked' carries dry-pasta numbers (361 kcal); cooked GF pasta is 153"),
    "haloumi": ("F002466", "1,050 kcal per 100 g is impossible (pure fat is 900); haloumi is 305"),
    "whiite_chocolate": ("F002946", "carbohydrate 546 g per 100 g — a typo for 54.6"),
    "yoghurt_farmer_union_greek": ("F009655", "513 kcal is impossible for yoghurt; Greek style is ~130. Unused."),
    "lentils_kidney_bean": ("F000448", "carries DRIED kidney-bean numbers (299 kcal) but all 4 recipes use it as '1 can, drained and rinsed' (105 kcal) — about 3× too high. Suggest: merge into 'Kidney beans, drained' (verified), or split into lentils + kidney beans if the recipe means both"),
}

# ---------------------------------------------------------------------------------------------
# 3. Measures that make uncalculable recipe lines calculable (conversions only — safe on verified
#    foods). (food_id, unit, grams, estimated, basis). estimated=True keeps the recipe in
#    "Needs review" ("uses an estimated weight") until a dietitian confirms.
MEASURES = [
    ("dijon_mustard", "tsp", 5.3, False, "AUSNUT 2023 F005973 density 1.05 g/mL × 5 mL"),
    ("dijon_mustard", "tbsp", 21, False, "AUSNUT 2023 F005973 measure tablespoon"),
    ("coriander_fresh", "cup", 62.5, False, "AUSNUT 2023 F003192 density 0.25 g/mL × 250 mL"),
    ("coriander_fresh", "tbsp", 5, False, "AUSNUT 2023 F003192 density 0.25 g/mL × 20 mL"),
    ("coriander_fresh", "tsp", 1.25, False, "AUSNUT 2023 F003192 density 0.25 g/mL × 5 mL"),
    ("coriander_fresh", "each", 2, True, "estimate: 1 sprig"),
    ("mint", "tbsp", 5, False, "AUSNUT 2023 mint, fresh: density 0.25 g/mL × 20 mL"),
    ("feta", "cup", 157.5, False, "AUSNUT 2023 F002452 measure cup crumbled"),
    ("beef_stock", "ml", 1.02, False, "AUSNUT 2023 F008936 stock: density 1.02 g/mL"),
    ("beef_stock", "cup", 255, False, "AUSNUT 2023 F008936 stock: measure cup"),
    ("chicken_stock", "ml", 1.02, False, "AUSNUT 2023 F008936 density 1.02 g/mL"),
    ("chicken_stock", "tbsp", 20.4, False, "AUSNUT 2023 F008936 density 1.02 g/mL × 20 mL"),
    ("coconut_milk_light", "ml", 1.02, False, "AUSNUT 2023 F002991 density 1.02 g/mL"),
    ("coconut_milk_light", "can", 408, True, "estimate: 400 mL can × 1.02 (270 mL cans exist)"),
    ("can_coconut_cream", "ml", 1.02, False, "AUSNUT 2023 coconut cream density 1.02 g/mL"),
    ("canned_coconut_milk", "ml", 1.02, False, "AUSNUT 2023 F002991 density 1.02 g/mL"),
    ("canola_oil", "cup", 230, False, "AUSNUT 2023 F006159 density 0.92 g/mL × 250 mL"),
    ("canola_oil", "ml", 0.92, False, "AUSNUT 2023 F006159 density 0.92 g/mL"),
    ("coconut_oil", "tbsp", 18.4, False, "AUSNUT 2023 F006163 density 0.92 g/mL × 20 mL"),
    ("cooking_sake", "tbsp", 19.2, False, "AUSNUT 2023 F010092 density 0.96 g/mL × 20 mL"),
    ("cooking_sake", "tsp", 4.8, False, "AUSNUT 2023 F010092 density 0.96 g/mL × 5 mL"),
    ("balsamic_vinegar", "tbsp", 20.2, False, "AUSNUT 2023 F009499 density 1.01 g/mL × 20 mL"),
    ("capers", "tbsp", 11.4, False, "AUSNUT 2023 F002220 density 0.57 g/mL × 20 mL"),
    ("cranberry_dried", "tbsp", 12.2, False, "the food's own cup (152.5 g) ÷ 12.5"),
    ("currants", "tbsp", 12, False, "AUSNUT 2023 F003331 density 0.6 g/mL × 20 mL"),
    ("currants", "cup", 150, False, "AUSNUT 2023 F003331 density 0.6 g/mL × 250 mL"),
    ("onion_brown", "tsp", 2.8, False, "AUSNUT 2023 F006225 density 0.56 g/mL × 5 mL"),
    ("onion_brown", "tbsp", 11.2, False, "AUSNUT 2023 F006225 density 0.56 g/mL × 20 mL"),
    ("onion_brown", "cup", 140, False, "AUSNUT 2023 F006225 density 0.56 g/mL × 250 mL"),
    ("celery", "cup", 127.5, False, "AUSNUT 2023 F002390 density 0.51 g/mL × 250 mL"),
    ("carrot", "cup", 115, False, "AUSNUT 2023 carrot density chopped 0.46 g/mL × 250 mL"),
    ("almond", "cup", 145, False, "AUSNUT 2023 F006081 density 0.58 g/mL × 250 mL"),
    ("apple_sauce", "cup", 265, False, "AUSNUT 2023 F000104 density 1.06 g/mL × 250 mL"),
    ("butter", "cup", 240, False, "the food's own tbsp (19.2 g) × 12.5"),
    ("cream_cheese", "cup", 252.5, False, "AUSNUT 2023 F002444 measure cup"),
    ("light_cream_cheese", "cup", 252.5, False, "AUSNUT 2023 F002444 measure cup"),
    ("lactose_free_milk", "cup", 257.5, False, "AUSNUT 2023 F005599 measure cup"),
    ("canned_pineapple_piece", "cup", 162.5, False, "AUSNUT 2023 pineapple pieces density 0.65 g/mL × 250 mL"),
    ("cherry_tomato", "cup", 157.5, False, "AUSNUT 2023 F009190 density 0.63 g/mL × 250 mL"),
    ("dates_dried", "cup", 160, False, "AUSNUT 2023 F003496 density 0.64 g/mL × 250 mL"),
    ("chocolate_chip_optional", "cup", 180, False, "the recipe's own note: ½ cup = 90 g"),
    ("broccolini", "bunch", 180, False, "AUSNUT 2023 broccolini measure bunch"),
    ("coleslaw_mix", "packet", 400, False, "AUSNUT 2023 F007742 measure bag pre-packaged"),
    ("barramundi_fillet", "small", 90, False, "AUSNUT 2023 barramundi measure fillet small"),
    ("red_cabbage", "each", 454, False, "AUSNUT 2023 F002006 measure cabbage (= the food's 'small cabbage')"),
    ("chicken_breast_tenderloin", "each", 51.25, False, "AUSNUT 2023 F002594 measure tenderloin"),
    ("diced_tomato_canned", "x400g", 400, False, "pack size in the unit name (= the food's 'can')"),
    ("crushed_tomato_canned", "x400g", 400, False, "pack size in the unit name (= the food's 'can')"),
    ("lentil_brown", "x400g", 240, False, "the food's own 'can' (240 g drained)"),
    ("cherry_tomato", "x250g", 250, False, "pack size in the unit name (= the food's 'punnet')"),
    ("beef_rump", "x120g", 120, False, "pack size in the unit name"),
    ("brown_rice_and_quinoa_microwave_packet", "x250g", 250, False, "pack size in the unit name"),
    ("gluten_free_arnott_scotch_finger", "x170g", 170, False, "pack size in the unit name"),
    ("plain_tuna", "x185g", 185, True, "pack size in the unit name; drained weight is ~140 g"),
    ("corn_chips", "round", 11, False, "same as the food's own 'chip' (tostada round)"),
    ("cinnamon", "each", 3, True, "estimate: 1 cinnamon stick"),
    ("cinnamon", "small", 2, True, "estimate: 1 small cinnamon stick"),
    ("butternut_pumpkin", "each", 1200, True, "estimate: 1 whole butternut pumpkin"),
    ("butternut_pumpkin", "large", 1800, True, "estimate: 1 large butternut pumpkin"),
    ("broccoli", "head", 350, True, "estimate: 1 head of broccoli"),
    ("broccoli", "each", 350, True, "estimate: 1 head of broccoli"),
    ("broccoli", "large", 450, True, "estimate: 1 large head of broccoli"),
    ("bok_choy", "bunch", 300, True, "estimate: 1 bunch of baby bok choy (2–3 heads)"),
    ("chia_seeds", "handful", 15, True, "estimate: 1 handful"),
    ("green_bean", "handful", 50, True, "estimate: 1 handful"),
    ("rocket", "each", 25, True, "estimate: 1 handful"),
    ("rocket", "large", 30, True, "estimate: 1 large handful"),
    ("baby_cos", "each", 150, True, "estimate: 1 baby cos lettuce"),
    ("collagen_powder", "each", 10, True, "estimate: 1 scoop"),
    ("earl_grey_tea_bag", "each", 2, True, "estimate: 1 tea bag (dry leaves)"),
    ("daikon", "cup", 112, True, "estimate: julienned daikon ~0.45 g/mL"),
    ("zucchini", "cup", 125, True, "estimate: grated zucchini ~0.5 g/mL"),
    ("chicken_breast", "cup", 140, True, "estimate: diced chicken breast"),
    ("red_curry_paste", "tbsp", 22, True, "estimate: curry paste ~1.1 g/mL × 20 mL"),
    ("nori", "each", 3, False, "same as the food's own 'sheet'"),
    ("pepper", "tbsp", 9.2, False, "the food's own tsp (2.3 g) × 4 (Australian 20 mL tablespoon)"),
]

# 'each' that should follow an existing size measure (the database copies it via default_size).
DEFAULT_SIZE = {
    "iceberg_lettuce": "medium head", "celery": "medium stalk", "broccolini": "stalk",
    "g_can_chickpea": "can", "chicken_stock_cube": "cube", "biscuit_digestive": "biscuit", "gyoza_wrappers_dumpling_wrapper": "sheet",
    "burger_thin": "serving", "corn_chips": "chip",
}

# Placeholder measures: the import set 'each'/size = 100 g ("default-estimate") on foods where 100 g is far off,
# and recipes use them (e.g. 16 sun-dried tomatoes = 1.6 kg, 2 star anise = 200 g, 5 large garlic = 900 g).
# Only rows still at the placeholder and still marked estimated are changed. estimated=False only where AUSNUT
# gives the measure for this exact food; everything else stays an estimate (recipe stays in "Needs review").
# (food_id, unit, placeholder grams, new grams, estimated, basis)
MEASURE_FIXES = [
    ("naan_bread", "each", 100, 89, False, "AUSNUT 2023 F001647 measure naan, regular"),
    ("pancake", "each", 100, 68, False, "AUSNUT 2023 F006298 measure pancake, regular"),
    ("pikelet", "each", 100, 25, False, "AUSNUT 2023 F006701 measure pikelet"),
    ("waffle", "each", 100, 70, False, "AUSNUT 2023 F010475 measure waffle"),
    ("mushroom", "each", 100, 35, False, "AUSNUT 2023 F005946 measure mushroom, medium"),
    ("swiss_brown_mushroom", "each", 100, 35, False, "AUSNUT 2023 F005946 measure mushroom, medium"),
    ("oyster_mushroom", "each", 100, 12, False, "AUSNUT 2023 F005956 measure mushroom (oriental)"),
    ("rice_paper_sheet", "each", 100, 8, False, "AUSNUT 2023 F007639 measure wrapper"),
    ("sundried_tomato", "each", 100, 4.8, False, "AUSNUT 2023 F009217 measure tomato (one sun-dried piece)"),
    ("white_fish_fillet", "each", 100, 150, False, "AUSNUT 2023 F003956 measure fillet, medium"),
    ("watermelon", "each", 100, 1345, False, "AUSNUT 2023 F005520 measure whole melon, medium"),
    ("weet_bix", "each", 100, 17, False, "AUSNUT 2023 F001844 measure whole wheat biscuit"),
    ("wholemeal_english_muffin", "each", 100, 76, False, "AUSNUT 2023 F010990 measure muffin (English, wholemeal)"),
    ("wholemeal_pita_pocket", "each", 100, 66, False, "AUSNUT 2023 F001404 measure pita bread, regular (wholemeal)"),
    ("granny_smith_apple", "each", 100, 165.6, False, "AUSNUT 2023 F000098 measure apple, medium (green skin, unpeeled)"),
    ("red_apple_cored", "each", 100, 155, True, "estimate: AUSNUT F000110 medium apple 165.6 g less the core"),
    ("gf_pita_bread", "each", 100, 66, True, "estimate: AUSNUT regular pita 66 g; gluten-free pitas vary"),
    ("slider_bun", "each", 100, 34, True, "estimate: AUSNUT small/dinner bread roll 34 g"),
    ("gluten_free_mini_wrap", "each", 100, 35, True, "estimate: 1 mini wrap"),
    ("individual_serve_instant_noodle", "each", 100, 145, True, "estimate: AUSNUT F006053 single serve, boiled & drained = 145 g (larger packs 195 g); the food's numbers are boiled"),
    ("lemongrass", "each", 100, 20, True, "estimate: 1 stalk"),
    ("mozzarella_ball", "each", 100, 125, True, "estimate: 1 fresh mozzarella ball (usually 125 g)"),
    ("star_anise", "each", 100, 1, True, "estimate: 1 whole star anise"),
    ("beef_steak", "each", 100, 200, True, "estimate: 1 steak"),
    ("pork_loin_steak", "each", 100, 160, True, "estimate: 1 loin steak"),
    ("low_carb_potato", "each", 100, 150, True, "estimate: same as potato 'each' (150 g)"),
    ("protein_powder", "each", 100, 30, True, "estimate: 1 scoop (brands 25–40 g)"),
    ("vegetable_stock_pot", "each", 100, 28, True, "estimate: 1 stock pot (Knorr Stock Pot is 28 g)"),
    ("packet_microwave_rice", "each", 100, 250, True, "estimate: 1 microwave rice packet (usually 250 g)"),
    ("plain_rice_cake", "each", 100, 10, True, "estimate: 1 rice cake (AUSNUT thin 7 g, thick 12.5 g)"),
    ("orange_zest", "each", 100, 6, True, "estimate: zest of 1 orange"),
    ("tortilla", "small", 80, 30, False, "AUSNUT 2023 F001669 measure tortilla, small (taco recipes use 6–8; 80 g was a placeholder, larger than the food's own 'each' 45 g)"),
    ("garlic", "large", 180, 5, True, "estimate: 1 large clove (AUSNUT clove = 3 g); 180 g was a whole-bulb placeholder"),
    ("garlic", "small", 80, 2, True, "estimate: 1 small clove (AUSNUT clove = 3 g)"),
]

# Estimated measures that AUSNUT confirms (same food, same size, within 10 %): estimate flag cleared.
# (food_id, unit, AUSNUT grams, basis)
CONFIRM_MEASURES = [
    ("button_mushroom", "each", 35, "AUSNUT 2023 F005946 measure mushroom, medium = 35 g"),
    ("fig", "each", 50, "AUSNUT 2023 F003834 measure fig = 50 g"),
    ("apple", "medium", 165.6, "AUSNUT 2023 F000110 measure apple (red skin, unpeeled), medium = 165.6 g"),
]

# Recipe line corrections where the line's own note, or the method, gives the amount.
LINE_FIXES = [
    {"food_id": "green_bean", "match_quantity": 2, "match_unit": "each", "match_prep": "~200g", "set": {"quantity": 200, "unit": "g"},
     "why": "prep note says ~200 g"},
    {"food_id": "self_raising_flour", "match_quantity": 1.25, "match_unit": "each", "match_prep": "", "recipe_title": "PIKELETS",
     "set": {"quantity": 1.25, "unit": "cup"}, "why": "'1¼ each self-raising flour' is 1¼ cups (the batter for 4)"},
    {"food_id": "iceberg_lettuce", "match_quantity": 2, "match_unit": "each", "match_prep": "roughly chopped", "recipe_title": "CHOPPED CHICKEN WRAP",
     "set": {"quantity": 2, "unit": "large leaf"}, "why": "2 wraps: 2 leaves, not 2 whole lettuces (which would now count as 1.14 kg)"},
]

# Lines that are the recipe's YIELD, parsed as an ingredient ("makes 6 pancakes" → 6 × pancake). Removed.
DELETE_LINES = [
    {"recipe_title": "WAFFLES", "food_id": "waffle", "quantity": 68, "unit": "each", "why": "yield line ('6–8 waffles') parsed as 68 waffles = 6.8 kg"},
    {"recipe_title": "FLUFFY JAPANESE SOUFFLE PANCAKES", "food_id": "pancake", "quantity": 6, "unit": "each", "why": "yield line: the recipe makes the pancakes"},
    {"recipe_title": "PROTEIN PANCAKES", "food_id": "pancake", "quantity": 6, "unit": "each", "why": "yield line: the recipe makes the pancakes"},
    {"recipe_title": "PIKELETS", "food_id": "pikelet", "quantity": 12, "unit": "each", "why": "yield line: the recipe makes the pikelets"},
]

# Recipes where the method needs ingredients the import lost (or other import errors): a data_issue note keeps
# them in "Needs review" until someone fixes them. (Appended if a note already exists.)
RECIPE_NOTES = {
    "WAFFLES": "Import check 21 Oct: the method whisks FLOUR with the sugar, but there is no flour line. Add it from the original recipe.",
    "FLUFFY JAPANESE SOUFFLE PANCAKES": "Import check 21 Oct: the method uses cake flour, cream and powdered sugar, but those lines are missing. Add them from the original recipe.",
    "PROTEIN PANCAKES": "Import check 21 Oct: the method describes two versions (banana-oat, and yoghurt + self-raising flour); the yoghurt and vanilla lines are missing.",
    "CAPRICCIOSA PIZZA": "Import check 21 Oct: the method makes the dough from flour + Greek yoghurt and adds cheese, but those lines are missing; '2 each pizza' is probably the yield. Add the dough and cheese lines, remove the pizza line.",
    "BANANA OAT MUFFINS": "Import check 21 Oct: 5½ cups oats and 5½ cups self-raising flour for 12 muffins looks like a parse error (1½ cups?). Check the original.",
    "THERMOMIX LENTIL AND PUMPKIN SOUP": "Import check 21 Oct: servings = 41 (typo?), and water appears twice at 900 mL while the method adds 250 mL. Check the original.",
}

# Lines whose unit looks wrong ('each' where the recipe clearly means cups, cloves, handfuls…). NOT changed —
# listed for the owner with a suggested fix.  (recipe title, food_id, current, suggested)
LINE_PROPOSALS = [
    ("HOMEMADE LCM BARS", "rice_bubble", "1.5 each", "1.5 cup (puffed rice)"),
    ("FODMAP FRIENDLY LCM BARS", "gf_rice_bubble", "1.5 each", "1.5 cup"),
    ("BANANA BREAD CHOC CHIP COOKIES", "light_brown_sugar", "0.5 each", "0.5 cup"),
    ("CHOC-PEANUT PROTEIN BALLS", "rolled_oats", "0.25 each", "0.25 cup"),
    ("CHOC-PEANUT PROTEIN BALLS", "walnut", "0.33 each", "0.33 cup"),
    ("CHEESEBURGER SAUSAGE ROLLS", "tasty_cheese", "1.5 each", "1.5 cup, shredded"),
    ("LAMB GYROS - GF, LF", "oregano", "2 each", "2 tsp (dried)"),
    ("SLOW COOKER TIKKA MASALA", "garam_masala", "5 each", "5 tsp? (check the original)"),
    ("HOMEMADE CHILLI OIL", "garam_masala", "1 each", "1 tbsp? (check the original)"),
    ("SLOW COOKER BEEF RAGU WITH PAPPARDELLE", "beef_stock", "1 each (crumbled)", "a beef stock CUBE, not liquid stock"),
    ("GREEN GODDESS ANCIENT GRAIN SALAD", "water", "15 each (to thin)", "15 mL"),
    ("TOFU PEANUT NOODLES", "spinach", "4 each", "4 handfuls (~120 g)?"),
    ("THAI CHICKEN PEANUT NOODLES", "spinach", "4 each", "4 handfuls (~120 g)?"),
    ("THAI CHICKEN PEANUT NOODLES (FODMAP)", "spinach", "4 each", "4 handfuls (~120 g)?"),
    ("CHICKEN PARMI BAKE", "spinach", "2 each", "2 handfuls (~60 g)?"),
    ("TOFU PEANUT NOODLES", "vermicelli_noodles", "2 each", "2 noodle cakes — weight from the pack"),
    ("THAI CHICKEN PEANUT NOODLES", "vermicelli_noodles", "2 each", "2 noodle cakes — weight from the pack"),
    ("CHICKEN QUESADILLAS", "pre_cooked_bbq_chicken", "1 each (shredded)", "1 BBQ chicken: AUSNUT whole chicken 967 g without skin / 1,075 g with"),
    ("HOMEMADE BEEF BURGERS", "pickle", "4 each (sliced)", "weight per pickle from the jar"),
    ("LEMON CHEESECAKE MILLE FEUILLE", "cream_cheese", "0.5 cup (note: 'True Protein Vanilla or Natural Protein Powder')", "the note says protein powder: check which ingredient this line is"),
    ("CHRISTMAS PUDDING BALLS", "dates_dried", "4 each", "grams: Medjool ~20 g each, dried 5 g (AUSNUT) — which?"),
    ("CHOC COCONUT BLISS BALL", "dates_dried", "12 each", "grams: Medjool ~20 g each, dried 5 g (AUSNUT) — which?"),
    ("CHOC-PEANUT PROTEIN BALLS", "dates_dried", "12 each (soaked)", "grams: Medjool ~20 g each, dried 5 g (AUSNUT) — which?"),
    ("CHOC COVERED PEANUT BUTTER DATES", "dates_dried", "12 each (×2 lines)", "almost certainly Medjool (~20 g each); also two identical lines"),
]

# ---------------------------------------------------------------------------------------------
# 4. Aisles (only where the current aisle is clearly wrong)
AISLE_FIX = {
    "beef_stock": "Pantry", "chicken_stock": "Pantry", "chicken_stock_cube": "Pantry", "salt_reduced_chicken_stock": "Pantry",
    "oyster_mushroom": "Produce", "wholemeal_english_muffin": "Bakery", "goat_cheese": "Dairy & eggs", "haloumi": "Dairy & eggs",
    "plant_based_feta": "Dairy & eggs", "green_bean": "Produce", "mixed_berries": "Frozen", "radicchio": "Produce", "rosemary": "Produce",
    "tub_cherry_bocconcini": "Dairy & eggs", "each_onion_and_garlic_powder": "Pantry", "each_onion_garlic_powder": "Pantry",
    "feta_oil_spray": "Pantry", "fish_sauce": "Pantry", "garlic_infused_oil": "Pantry", "garlic_powder": "Pantry", "garlic_sauce": "Pantry",
    "grape_seed_oil": "Pantry", "italian_dried_herb_blend": "Pantry", "pear_cou_cou": "Pantry", "pepita": "Pantry",
    "sweet_chilli_sauce": "Pantry", "tomato_based_pizza_sauce": "Pantry", "tomato_passata": "Pantry", "tomato_paste": "Pantry",
    "tomato_sauce": "Pantry", "tin_butter_bean": "Pantry", "packet_baking_milk_chocolate_melt": "Pantry", "milk_chocolate": "Pantry",
    "mixed_italian_herb": "Pantry", "aaa": None,
}
AISLE_FIX = {k: v for k, v in AISLE_FIX.items() if v}

# 5. Protein family: keyword rule (builder) plus these overrides (None = no family).
PROTEIN_FAMILY_OVERRIDE = {
    "gyoza_wrappers_dumpling_wrapper": None, "egg_mayo": None, "egg_quick_pickled_veg": None, "plant_based_feta": None,
    "beef_stock": None, "canned_coconut_milk": None, "chocolate": None, "coconut_milk_light": None, "feta_oil_spray": None,
    "milk_chocolate": None, "milk_chocolate_chip_almond_flake": None, "packet_baking_milk_chocolate_melt": None,
    "bean_sprout": None, "green_bean": None, "red_bean_paste": None, "honey_olive_oil_labneh": "dairy",
    "protein_powder": "other", "collagen_powder": "other",
    # recipe_protein_families picks a recipe's MAIN protein by grams, so milk (e.g. 400 mL in a curry) would
    # outrank the chicken; composite products likewise. No family for these.
    "milk": None, "skim_milk": None, "lactose_free_milk": None, "farmer_high_protein_milk": None, "packet_prawn_dumpling": None,
}

# Allergen tags missing on EXISTING foods (name makes it certain). Added at the start of g3b, before any AI
# verification is written. On a dietitian-verified food a tag change removes verification (by design) — only
# haloumi (already on the urgent list), labneh and furikake (both unused) are affected.
ALLERGEN_ADD = {
    "haloumi": (["Dairy"], "haloumi is a cheese"),
    "honey_olive_oil_labneh": (["Dairy"], "labneh is strained yoghurt"),
    "furikake": (["Sesame"], "furikake is sesame-based"),
    "tub_cherry_bocconcini": (["Dairy"], "bocconcini is a cheese"),
    "pancake": (["Gluten", "Egg", "Dairy"], "AUSNUT plain homemade pancake: flour, egg, milk"),
    "waffle": (["Gluten", "Egg", "Dairy"], "AUSNUT plain waffle: flour, egg, milk"),
    "pikelet": (["Gluten", "Egg"], "AUSNUT plain homemade pikelet: flour, egg, milk"),
    "pear_cou_cou": (["Gluten"], "couscous is wheat"),
    "pearl_cou_cou": (["Gluten"], "couscous is wheat"),
    "pesto": (["Tree nuts"], "basil pesto contains pine nuts (often cashews)"),
    "red_pesto": (["Tree nuts"], "pesto contains nuts"),
}

# Wrong "free-from" claims on existing foods (a vegan client could be served these). Removing the claim is the
# safe direction; on a verified food it removes verification (by design).
TAG_REMOVE = {
    "danish_feta": (["Vegan"], "feta is a dairy cheese"),
    "butter_unsalted": (["Vegan"], "butter is dairy"),
}

# Adjustment-engine role for the 250 new foods (role tells the "adjust to the client's targets" engine what it may
# scale; NULL = frozen, never adjusted). Suggestions come from scripts/ausnut/role_rules.py, which reproduces the
# team's existing roles for 505 of 510 foods. Written ONLY once a dietitian has approved them:
NEW_FOOD_ROLES_APPROVED = False
NEW_FOOD_ROLE_OVERRIDES = {}     # food_id: role — the dietitian's changes to individual suggestions

# Package fixes for created foods (list A + C): wrong tags / families from the name rules.
# Allergen rule: when unsure, keep the allergen tag (over-warning is safe) and drop the "-free" claim.
CREATE_FIXES = {
    "squash_button": {"protein_family": None, "drop_tags": ["Shellfish"], "add_tags": ["Vegan", "Vegetarian"],
                      "why": "'scallopini' squash matched the scallop rule — it's a vegetable"},
    "honeydew_melon": {"drop_tags": ["Honey"], "add_tags": ["Vegan"], "why": "'honey dew' matched the honey rule"},
    "mixed_nuts_unsalted": {"add_tags": ["Tree nuts"], "why": "mixed nuts are tree nuts (Peanuts kept: real mixes often contain them)"},
    "corn_flakes": {"drop_tags": ["Gluten-free"], "add_tags": ["Gluten"], "why": "standard corn flakes contain barley malt"},
    "mixed_seeds": {"add_tags": ["Sesame"], "why": "seed mixes usually contain sesame"},
    "muesli_natural_untoasted": {"drop_tags": ["Nut-free"], "why": "natural muesli usually contains nuts"},
    "lobster_raw": {"protein_family": "seafood", "why": "lobster is a crustacean (seafood), not fish"},
    "coconut_yoghurt_natural": {"protein_family": None, "why": "coconut yoghurt is not dairy and not a protein source"},
    "custard_vanilla_reduced_fat": {"protein_family": None, "why": "a dessert, not a protein source"},
    "milk_full_cream": {"protein_family": None, "why": "milk would become a recipe's 'main protein' by weight (see protein family note)"},
    "buttermilk": {"protein_family": None, "why": "as milk"},
    "black_bean_sauce": {"protein_family": None, "why": "a sauce, not a legume serve"},
}

# 6. data_issue recipes: lines to restore and notes to clear.
RESTORE_LINES = [
    {"recipe_title": "HIGH PROTEIN NO BAKE CHEESECAKE", "food_id": "gelatine_powder", "quantity": 3, "unit": "tsp",
     "prep_note": "sprinkled over the water to bloom", "why": "method step 2 uses gelatin; the import note says '3 teaspoon gelatin powder'"},
    {"recipe_title": "SAVOURY EGG MUFFINS", "food_id": "olive_oil_spray", "quantity": 1, "unit": "spray",
     "prep_note": "for greasing the muffin tin", "why": "method step 1 sprays the tin; the spray line was merged into tasty cheese"},
]
CLEAR_PREP_NOTE = [
    {"recipe_title": "SAVOURY EGG MUFFINS", "food_id": "tasty_cheese", "old": "for greasing muffin tin", "why": "belonged to the oil-spray line"},
]
# data_issue notes that were informational only (every component present): clear
CLEAR_DATA_ISSUE = ["SALTED CARAMEL BLISS BALLS", "SPRING ONION PANCAKE W DIPPING SAUCE", "PORK WONTON CUPS", "SMASHED CUCUMBER SALAD",
                    "FODMAP FRIENDLY PESTO ORZO SALAD", "CHOPPED CHICKEN WRAP", "PISTAHIO ICE-CREAM SANDOS", "CHICKEN SANDO BITES"]
# everything else keeps its note, with this appended
DATA_ISSUE_APPEND = ("AUSNUT check 21 Oct: the 'coconut flake', 'gelatine' and 'pickled veg' notes were copied across recipes by the import; "
                     "the method of this recipe does not use them. Add a line only if the original recipe has it, then clear this note.")
