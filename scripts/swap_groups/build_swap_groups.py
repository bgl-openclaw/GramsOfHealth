"""Draft swap groups for dietitian approval (plans roadmap rev 2, P3 suggestions).

A swap group = foods that can replace each other gram for gram in the same recipe line
("beef mince → chicken mince, fat −9 g"). The generator's ingredient-swap suggestions only
ever pick inside a group, and every suggestion still goes through the client's screen.

Reads the live foods (role adjustable_*) plus the AUSNUT rev 3 new foods (not yet applied),
groups them by name rules, flags values that look wrong (Atwater check), and writes
seed/swap_groups/swap_groups_for_review.csv.  Re-run after AUSNUT is applied.

    python3 scripts/swap_groups/build_swap_groups.py
"""
import csv
import os
import re
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "ausnut"))
import _rest  # noqa: E402

REPO = _rest.REPO
OUT = os.path.join(REPO, "seed", "swap_groups")

# (key, title, note, role filter, include regex, exclude regex). First matching group wins unless the
# group is marked also=True (foods can sit in a second, cross-role group such as sour cream → yoghurt).
GROUPS = [
    # --- proteins ---
    ("mince", "Mince", "Any mince for any mince, same weight. Biggest fat lever (beef 10 g → extra lean 4 g per 100 g).",
     "adjustable_protein", r"\bmince\b", r"meatball"),
    ("quick_cuts", "Steak, fillet and stir-fry strips", "Quick-cook cuts: grill, pan-fry or stir-fry. Chicken, beef, lamb, pork, kangaroo and game swap here.",
     "adjustable_protein", r"steak|strip|backstrap|scotch fillet|loin|tenderloin|cutlet|\bchop\b|chicken, breast|chicken breast|chicken, thigh|turkey breast|duck breast|kangaroo fillet|venison|^pork$|raw chicken",
     r"salmon|tuna|fish"),
    ("roast_cuts", "Roasts and bone-in pieces", "Roasting joints, drumsticks and wings. Weigh raw, with bone where the food says so.",
     "adjustable_protein", r"roast,? |roast$|shoulder|belly|drumstick|wing|chicken, whole", r"deli"),
    ("slow_cuts", "Slow-cook cuts", "Braises and slow-cooker recipes.", "adjustable_protein", r"chuck|shank|osso|brisket", None),
    ("fish_fillet", "Fish fillets", "Fresh fish fillets and steaks (not sashimi, not tinned).", "adjustable_protein",
     r"barramundi|white fish|salmon, atlantic|^salmon|snapper|basa|\bcod\b|hake|\bling\b|flathead|whiting|trout|dory|tuna steak|grenadier|hoki|kingfish",
     r"smoked|sashimi|\btin\b|canned|dumpling"),
    ("tinned_fish", "Tinned fish", "Drained tinned fish.", "adjustable_protein",
     r"(tuna|sardine|salmon|mackerel|anchov).*(tin|can|drained|springwater|brine)|^tin (tuna|salmon|sardine)|plain tuna|sardine", r"sashimi|steak"),
    ("sashimi", "Sashimi-grade fish", "Raw use only.", "adjustable_protein", r"sashimi", None),
    ("seafood", "Prawns and seafood", "Shellfish allergy: never offered to a client with a shellfish block (the screen decides).",
     "adjustable_protein", r"prawn|shrimp|calamari|squid|scallop|mussel|crab|lobster|octopus|oyster", r"dumpling"),
    ("deli", "Deli meats, bacon and ham", "Small amounts for flavour; leaner swaps cut fat and salt.", "adjustable_protein",
     r"bacon|ham\b|prosciutto|chorizo|salami|pancetta|pastrami|deli-sliced|deli sliced", None),
    ("legumes", "Beans, lentils and chickpeas", "Drained weight for drained weight; dry legumes only swap with dry.", "adjustable_protein",
     r"bean|lentil|chickpea|four bean|split pea", r"paste"),
    ("tofu", "Firm and smoked tofu, tempeh", "Savoury mains. Silken tofu is for desserts and smoothies, not here.", "adjustable_protein",
     r"tofu, firm|firm tofu|tofu, smoked|tempeh", None),
    ("eggs", "Eggs and egg whites", "Swap some whole egg for whites to cut fat.", "adjustable_protein", r"^egg|egg white|egg, whole", r"yolk"),
    ("yoghurt_plain", "Plain yoghurt", "Plain and Greek-style; high-protein versions lift protein. Coconut yoghurt is the dairy-free swap.", None,
     r"yog", r"vanilla|lemon|berry|strawberry|mango|flavour|tzatziki"),
    ("yoghurt_flavoured", "Flavoured yoghurt", "Sweetened yoghurts.", "adjustable_protein", r"yog.*(vanilla|lemon|berry|strawberry|mango)|(vanilla|lemon|berry|strawberry|mango).*yog", None),
    ("soft_cheese", "Cottage cheese and ricotta", "Fresh cheeses for spreads, bakes and dips.", "adjustable_protein", r"cottage|ricotta|quark|skyr", None),
    ("melting_cheese", "Grated, sliced and melting cheese", "Cheddar, tasty, mozzarella, bocconcini, parmesan.", None,
     r"cheddar|tasty|taste cheese|mozzarella|bocconcini|parmesan|colby|\bedam\b|gouda|swiss", None),
    ("salty_cheese", "Feta, haloumi and goat's cheese", "Plant-based feta is the dairy-free swap.", "adjustable_protein", r"feta|haloumi|halloumi|goat", None),
    ("rich_cheese", "Brie, camembert and blue cheese", "", "adjustable_protein", r"brie|camembert|blue vein|gorgonzola", None),
    ("milk", "Milk and milk alternatives", "Owner rule: milk is not a protein family. Reduced-fat and skim cut fat; plant milks are the dairy-free swap (soy has the most protein).",
     "adjustable_protein", r"\bmilk\b|buttermilk", r"coconut|chocolate"),
    ("protein_powder", "Protein powders", "Collagen is an incomplete protein — check before swapping it for whey.", "adjustable_protein",
     r"protein powder|whey|collagen|protein electrolyte", None),
    ("dips", "Dips and spreads", "Hummus, tzatziki and labneh for wraps, bowls and snacks.", None, r"hummus|houmous|tzatziki|labneh|guacamole|baba", None),
    # --- carbohydrates ---
    ("rice_cooked", "Cooked rice and grains (ready to eat)", "Cooked weight for cooked weight. Never swap with dry rice gram for gram.",
     "adjustable_carb", r"(rice|quinoa|cou ?cou|couscous|freekeh|barley).*(\bcooked|pouch|packet|microwav)|(microwav|pouch).*(rice|quinoa)|^quinoa, cooked|^pearl? cou ?cou",
     r"noodle|paper|bubble|cake|uncooked"),
    ("rice_dry", "Dry rice, grains and pasta", "Dry weight for dry weight (about 1 : 3 cooked).", "adjustable_carb",
     r"rice, uncooked|aborio|arborio|buckwheat|^basmati$|uncooked|\bdry\b|risoni|semolina", r"noodle"),
    ("pasta_cooked", "Cooked pasta", "Cooked weight. Wholemeal and legume pastas add fibre or protein.", "adjustable_carb",
     r"pasta|ravioli", r"200g|\bdry\b"),
    ("noodles", "Noodles", "Ready-to-wok or cooked weight.", "adjustable_carb", r"noodle|udon|soba|vermicelli|ramen", None),
    ("bread", "Bread, rolls and buns", "Slice for slice by weight; thins and wholemeal cut energy or add fibre.", "adjustable_carb",
     r"bread\b|bread,|roll\b|bun\b|thins?\b|english muffin|bagel|crumpet", r"crumb|pita|naan|banana|crispbread"),
    ("wraps", "Wraps, pita and flatbread", "Low-GI and high-protein wraps change carbs and protein.", "adjustable_carb",
     r"wrap|tortilla$|^tortilla|pita|naan|flatbread|lavash|roti", r"chip"),
    ("crackers", "Crackers, crispbreads and rice cakes", "Snack bases.", "adjustable_carb", r"cracker|crispbread|rice cake|corn cake|vitawheat|ryvita", None),
    ("potato", "Potato and starchy vegetables", "Raw weight for raw weight.", "adjustable_carb", r"potato|cassava|taro", r"chip|crisp"),
    ("oats_cereal", "Oats and breakfast cereals", "Dry weight.", "adjustable_carb",
     r"oat|weet-?bix|wheat biscuit|granola|muesli|bubble|quinoa flake|bran|corn flakes|wheat germ", r"biscuit,|cookie"),
    ("crumbs", "Breadcrumbs and croutons", "Coatings and toppings.", "adjustable_carb", r"crumb|crouton", None),
    ("sweeteners", "Sugar, honey and syrups", "Not gram for gram in baking — check texture before suggesting.", "adjustable_carb",
     r"sugar\b|sugar,|honey|syrup|molasses", r"chocolate|jam"),
    ("jam", "Jam and marmalade", "No-added-sugar jam cuts sugar.", "adjustable_carb", r"\bjam\b|marmalade", None),
    ("chocolate", "Chocolate", "Dark chocolate >70% has less sugar.", "adjustable_carb", r"chocolate", r"cocoa powder|nesquik"),
    ("biscuits", "Biscuits", "", "adjustable_carb", r"biscuit|scotch finger|ladyfinger|biscoff", r"weet|wheat biscuit"),
    ("chips_popcorn", "Chips and popcorn", "Air-popped popcorn is the lighter swap for chips.", "adjustable_carb", r"chip|popcorn|crisps", r"chocolate"),
    ("cocoa", "Cocoa powder", "", "adjustable_carb", r"cocoa", None),
    # --- fats ---
    ("oils", "Cooking oils", "All about 100% fat: swaps change the type of fat, not the amount. Sesame oil is a flavour, not included.",
     "adjustable_fat", r"\boil\b", r"sesame|mayo|kewpie|burger"),
    ("butter", "Butter, ghee and spreads", "", "adjustable_fat", r"butter, (salted|unsalted)|margarine|spread|ghee", r"peanut|almond"),
    ("cream", "Cream and sour cream", "Light versions and Greek yoghurt cut fat.", "adjustable_fat", r"cream\b|cream$|sour cream", r"cheese|coconut|ice"),
    ("cream_cheese", "Cream cheese and mascarpone", "", None, r"cream cheese|mascarpone", None),
    ("mayo", "Mayonnaise", "Light mayo or Greek yoghurt cut fat.", "adjustable_fat", r"mayo", None),
    ("coconut_milk", "Coconut milk and cream", "Light coconut milk halves the fat.", "adjustable_fat", r"coconut (milk|cream)", None),
    ("nuts_seeds", "Nuts and seeds", "Tree-nut and peanut allergies: seeds are the usual swap (the screen decides).", "adjustable_fat",
     r"almond(s)?$|almonds|slivered|slithered|walnut|peanut(s)?$|natural peanut|pine nut|pepita|sunflower|sesame seed|cashew|pistachio|macadamia|hazelnut|pecan|brazil|mixed nuts|mixed seeds|chia|flax|linseed|poppy",
     r"butter|meal|oil|milk"),
    ("nut_butter", "Nut butters", "", "adjustable_fat", r"(peanut|almond|cashew) butter|tahini", None),
]
# Cross-role extras: a food added to a second group (key → regex on name). Shown with "also in".
ALSO = [
    ("cream", r"^(?!.*(vanilla|lemon|berry|mango)).*(greek|natural).*yog"),
    ("mayo", r"^(?!.*(vanilla|lemon|berry|mango)).*greek.*yog"),
]


def atwater_flag(kcal, p, f, c, fi):
    try:
        kcal, p, f, c, fi = (float(x or 0) for x in (kcal, p, f, c, fi))
    except ValueError:
        return "values missing"
    if c > 100 or p > 100 or f > 100:
        return "a value is over 100 g per 100 g"
    calc = 4 * p + 4 * c + 9 * f + 2 * fi
    if kcal <= 0:
        return "no energy value"
    if abs(calc - kcal) / max(kcal, calc) > 0.25:
        return f"energy {round(kcal)} kcal doesn't match its macros (~{round(calc)} kcal)"
    return ""


PLACEHOLDER_MIN = 3   # identical values on this many different foods = probably copied, not real
COOKED_GROUPS = {"rice_cooked", "pasta_cooked", "noodles"}
MEAT_GROUPS = {"mince", "quick_cuts", "slow_cuts", "fish_fillet"}


def plausibility(group, r, shared):
    try:
        kcal, f = float(r["kcal"] or 0), float(r["f"] or 0)
    except ValueError:
        return ""
    notes = []
    if shared >= PLACEHOLDER_MIN and r["status"] == "in the library (not verified)":
        notes.append(f"same values as {shared - 1} other foods — probably a placeholder")
    if group in COOKED_GROUPS and kcal > 250:
        notes.append("values look like the dry/uncooked food")
    if group == "legumes" and kcal > 200:
        notes.append("values look like dry weight, not drained")
    if group in MEAT_GROUPS and f > 25:
        notes.append("fat looks too high for this cut")
    if group == "mayo" and f > 80:
        notes.append("values look like oil, not mayonnaise")
    return "; ".join(notes)


def load():
    foods = _rest.select_all("foods?select=food_id,display_name,role,verified,energy_kcal_100g,protein_100g,fat_100g,carb_avail_100g,fibre_100g&role=in.(adjustable_protein,adjustable_carb,adjustable_fat)")
    tags = _rest.select_all("food_tags?select=food_id,tags(label,kind)")
    allergens = {}
    for t in tags:
        tg = t.get("tags") or {}
        if tg.get("kind") == "allergen":
            allergens.setdefault(t["food_id"], []).append(tg["label"])
    used = {}
    for l in _rest.select_all("ingredient_lines?select=food_id,recipe_id"):
        if l.get("food_id"):
            used.setdefault(l["food_id"], set()).add(l["recipe_id"])
    rows = []
    for f in foods:
        rows.append({"id": f["food_id"], "name": f["display_name"] or f["food_id"], "role": f["role"],
                     "status": "in the library" if f["verified"] else "in the library (not verified)",
                     "kcal": f["energy_kcal_100g"], "p": f["protein_100g"], "f": f["fat_100g"], "c": f["carb_avail_100g"], "fi": f["fibre_100g"],
                     "allergens": ", ".join(sorted(set(allergens.get(f["food_id"], [])))), "uses": len(used.get(f["food_id"], ()))})
    nf = os.path.join(REPO, "seed", "ausnut2023", "changeset", "review", "new_foods.csv")
    if os.path.exists(nf):
        for r in csv.DictReader(open(nf)):
            if r.get("suggested_role") not in ("adjustable_protein", "adjustable_carb", "adjustable_fat"):
                continue
            rows.append({"id": r["food_id"], "name": r["name"], "role": r["suggested_role"], "status": "new from AUSNUT (after it is applied)",
                         "kcal": r["kcal"], "p": r["protein"], "f": r["fat"], "c": r["carbs"], "fi": r["fibre"],
                         "allergens": (r.get("allergens") or "").replace(";", ", "), "uses": 0})
    return rows


def main():
    rows = load()
    out, unplaced = [], []
    for r in rows:
        name = r["name"].lower()
        placed = None
        for key, title, note, role, inc, exc in GROUPS:
            if role and r["role"] != role:
                continue
            if re.search(inc, name) and not (exc and re.search(exc, name)):
                placed = (key, title, note)
                break
        if placed:
            out.append((placed, r, ""))
        else:
            unplaced.append(r)
        for key, rx in ALSO:
            if re.search(rx, name):
                g = next(g for g in GROUPS if g[0] == key)
                out.append(((g[0], g[1], g[2]), r, "also in " + (placed[1] if placed else "no other group")))
    from collections import Counter as _C
    sig = lambda r: tuple(str(round(float(r[k] or 0), 1)) for k in ("kcal", "p", "f", "c"))
    shared = _C(sig(r) for r in rows)
    order = {g[0]: i for i, g in enumerate(GROUPS)}
    out.sort(key=lambda x: (order[x[0][0]], float(x[1]["f"] or 0), x[1]["name"].lower()))
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, "swap_groups_for_review.csv")
    with open(path, "w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(["Group", "Group note", "Food", "Keep in group", "Move to group", "kcal /100 g", "Protein", "Fat", "Carbs", "Fibre",
                    "Allergens", "Value check", "Status", "Used in recipes", "Cross-role", "Dietitian note", "food_id", "group_key"])
        for (key, title, note), r, cross in out:
            w.writerow([title, note, r["name"], "x", "", r["kcal"], r["p"], r["f"], r["c"], r["fi"], r["allergens"],
                        "; ".join(x for x in (atwater_flag(r["kcal"], r["p"], r["f"], r["c"], r["fi"]), plausibility(key, r, shared[sig(r)])) if x), r["status"], r["uses"], cross, "", r["id"], key])
    upath = os.path.join(OUT, "not_in_a_group.csv")
    with open(upath, "w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(["Food", "Role", "Status", "Used in recipes", "Suggested group (fill in if it should swap)", "food_id"])
        for r in sorted(unplaced, key=lambda r: (r["role"], r["name"].lower())):
            w.writerow([r["name"], r["role"], r["status"], r["uses"], "", r["id"]])
    from collections import Counter
    c = Counter(x[0][1] for x in out)
    print(f"{len(out)} rows in {len(c)} groups; {len(unplaced)} adjustable foods not in a group")
    for g in GROUPS:
        if c.get(g[1]):
            print(f"  {c[g[1]]:3}  {g[1]}")
    flagged = {r["id"] for (k, _, _), r, _ in out if atwater_flag(r["kcal"], r["p"], r["f"], r["c"], r["fi"]) or plausibility(k, r, shared[sig(r)])}
    print("foods with a value check:", len(flagged))


if __name__ == "__main__":
    main()
