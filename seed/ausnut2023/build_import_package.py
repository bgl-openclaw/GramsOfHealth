"""Build the AUSNUT 2023 import package for Grams of Health.

Usage: python3 -I build_import_package.py <ausnut_dir> <work_dir> <out_dir>

Inputs (read only):
  <ausnut_dir>/AUSNUT 2023 - Food details.xlsx
  <ausnut_dir>/AUSNUT 2023 - Food nutrient profiles.xlsx
  <ausnut_dir>/AUSNUT 2023 - Food measures.xlsx
  <ausnut_dir>/AUSNUT 2023 - Food and dietary supplement classification system.xlsx
  <work_dir>/our_foods.json                 live foods table (517 rows)
  <out_dir>/foods_to_add_C.csv              the agreed C list (250 rows)

Outputs (all CSV, UTF-8):
  reference/ausnut_master.csv, ausnut_measures.csv, ausnut_classifications.csv
  rules/rule_aisle.csv, rule_tags.csv, rule_protein_family.csv, rule_purchase_unit.csv
  lists/list_A_create.csv, list_B1_repoint.csv, list_B2_relink_verified.csv,
        list_B3_merge_delete.csv, list_C_import.csv
  import/import_foods.csv, import_food_tags.csv, import_unit_conversions.csv,
         import_review_flags.csv
"""
import csv, json, os, re, sys
import openpyxl

AUS, WORK, OUT = sys.argv[1], sys.argv[2], sys.argv[3]
for d in ("reference", "rules", "lists", "import"):
    os.makedirs(os.path.join(OUT, d), exist_ok=True)

KJ_PER_KCAL = 4.184

def rows_of(path, sheet):
    wb = openpyxl.load_workbook(path, read_only=True)
    ws = wb[sheet]
    return list(ws.iter_rows(values_only=True))

def norm(s):
    return re.sub(r"\s+", " ", str(s or "")).strip().lower()

def slug(s):
    s = norm(s).replace("&", "and")
    s = re.sub(r"[^a-z0-9]+", "_", s).strip("_")
    return s

# ---------------------------------------------------------------- reference
det = rows_of(os.path.join(AUS, "AUSNUT 2023 - Food details.xlsx"), "Food details")
hdr = det[2]
details = {}
for r in det[4:]:
    if not r[0]:
        continue
    details[r[2]] = {
        "survey_id": r[0], "key": r[2], "derivation": r[3], "name": r[4],
        "description": r[5], "specific_gravity": r[9], "edible_portion": r[11],
        "cls_code": r[13], "cls_name": r[14], "adg_code": r[15], "discretionary": r[19],
    }

nut = rows_of(os.path.join(AUS, "AUSNUT 2023 - Food nutrient profiles.xlsx"), "Food nutrient profiles")
nh = {h: i for i, h in enumerate(nut[2])}
NCOLS = {
    "energy_kj": "Energy with dietary fibre (kJ)",
    "protein_g": "Protein (g)",
    "fat_g": "Total fat (g)",
    "carb_avail_with_sa_g": "Available carbohydrate, with sugar alcohols (g)",
    "carb_avail_without_sa_g": "Available carbohydrate, without sugar alcohols (g)",
    "sugars_g": "Total sugars (g)",
    "fibre_g": "Dietary fibre (g)",
    "satfat_g": "Total saturated fat (g)",
    "sodium_mg": "Sodium (Na) (mg)",
    "potassium_mg": "Potassium (K) (mg)",
    "calcium_mg": "Calcium (Ca) (mg)",
    "iron_mg": "Iron (Fe) (mg)",
    "zinc_mg": "Zinc (Zn) (mg)",
    "magnesium_mg": "Magnesium (Mg) (mg)",
    "folate_dfe_ug": "Dietary folate equivalents (ug)",
    "folate_total_ug": "Total folates (ug)",
    "vitamin_b12_ug": "Cobalamin (B12) (ug)",
}
for k, v in NCOLS.items():
    assert v in nh, v
nutr = {}
for r in nut[3:]:
    if not r[0]:
        continue
    d = {k: r[nh[v]] for k, v in NCOLS.items()}
    kj = d["energy_kj"] or 0
    d["energy_kcal"] = round(kj / KJ_PER_KCAL, 1)
    nutr[r[1]] = d

cls_rows = rows_of(os.path.join(AUS, "AUSNUT 2023 - Food and dietary supplement classification system.xlsx"), "Classifications")
cls = {str(r[0]): str(r[1]).strip() for r in cls_rows[3:] if r[0]}

meas = rows_of(os.path.join(AUS, "AUSNUT 2023 - Food measures.xlsx"), "AUSNUT 2023")
SIZE_WORDS = {"small", "medium", "large", "regular", "extra large"}
measures = []
for r in meas[3:]:
    if not r[0]:
        continue
    d1, d2, d3, d4 = (norm(r[5]), norm(r[6]), norm(r[7]), norm(r[8]))
    grams, vol = r[9], r[10]
    is_density = d1 == "density"
    is_brand = bool(d4)
    PACK_NOUNS = r"bottle|carton|tub|container|packet|pouch|box|bag|can\b|jar|sachet|cup|glass|bowl|serve|portion|bar\b|block"
    size_word = "" if re.search(PACK_NOUNS, d1) else next((w for w in (d1, d2, d3) if w in SIZE_WORDS), "")
    # suggested unit name for unit_conversions
    if is_density:
        unit = ""
    elif size_word:
        unit = size_word
    else:
        parts = [p for p in (d1, d2) if p]
        unit = parts[0] if len(parts) == 1 or parts[0] == parts[-1] else f"{parts[0]} ({parts[1]})"
    measures.append({
        "public_food_key": r[1], "food_name": r[2], "measure_id": r[3], "quantity": r[4],
        "descriptor_1": d1, "descriptor_2": d2, "descriptor_3": d3, "descriptor_4_brand": d4,
        "gram_amount": grams, "volume_ml": vol,
        "is_density": int(is_density), "is_brand_pack": int(is_brand), "size_word": size_word,
        "suggested_unit": unit,
    })

def write(path, rows, fields):
    with open(path, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=fields, extrasaction="ignore")
        w.writeheader()
        for r in rows:
            w.writerow(r)

master_fields = ["public_food_key", "survey_id", "food_name", "derivation", "classification_code",
                 "classification_name", "specific_gravity", "edible_portion", "discretionary",
                 "energy_kj", "energy_kcal", "protein_g", "fat_g", "carb_avail_with_sa_g",
                 "carb_avail_without_sa_g", "sugars_g", "fibre_g", "satfat_g", "sodium_mg",
                 "potassium_mg", "calcium_mg", "iron_mg", "zinc_mg", "magnesium_mg",
                 "folate_dfe_ug", "folate_total_ug", "vitamin_b12_ug", "description"]
master = []
for k, d in details.items():
    n = nutr.get(k, {})
    master.append({
        "public_food_key": k, "survey_id": d["survey_id"], "food_name": d["name"],
        "derivation": d["derivation"], "classification_code": d["cls_code"],
        "classification_name": d["cls_name"], "specific_gravity": d["specific_gravity"],
        "edible_portion": d["edible_portion"], "discretionary": d["discretionary"],
        "description": d["description"], **n,
    })
write(os.path.join(OUT, "reference", "ausnut_master.csv"), master, master_fields)
write(os.path.join(OUT, "reference", "ausnut_measures.csv"), measures, list(measures[0].keys()))
write(os.path.join(OUT, "reference", "ausnut_classifications.csv"),
      [{"code": c, "group_name": n, "level": len(c)} for c, n in cls.items()], ["code", "group_name", "level"])

# ---------------------------------------------------------------- rule tables
def g3(code):
    return str(code)[:3]

AISLE_BY_3 = {
    "111": "Drinks", "112": "Drinks", "118": "Drinks", "119": "Pantry",
    "121": "Pantry", "122": "Bakery", "123": "Bakery", "124": "Pantry", "125": "Pantry",
    "126": "Pantry", "132": "Pantry", "136": "Bakery",
    "141": "Dairy & eggs", "142": "Dairy & eggs", "144": "Pantry", "145": "Pantry",
    "151": "Meat & seafood", "152": "Meat & seafood", "153": "Meat & seafood",
    "154": "Pantry", "155": "Pantry", "157": "Meat & seafood",
    "161": "Produce", "162": "Produce", "163": "Produce", "164": "Produce", "165": "Produce",
    "166": "Produce", "168": "Pantry",
    "171": "Dairy & eggs",
    "181": "Meat & seafood", "182": "Meat & seafood", "183": "Meat & seafood", "186": "Meat & seafood",
    "191": "Dairy & eggs", "192": "Dairy & eggs", "193": "Dairy & eggs", "194": "Dairy & eggs",
    "195": "Frozen", "196": "Dairy & eggs",
    "201": "Dairy & eggs", "205": "Dairy & eggs", "206": "Dairy & eggs",
    "221": "Pantry", "222": "Pantry",
    "231": "Pantry", "232": "Pantry", "233": "Pantry", "235": "Dairy & eggs",
    "241": "Produce", "242": "Produce", "243": "Produce", "244": "Produce", "245": "Produce",
    "246": "Produce", "247": "Produce", "248": "Produce",
    "251": "Pantry", "252": "Pantry", "262": "Pantry",
    "271": "Pantry", "272": "Pantry", "281": "Pantry", "301": "Pantry",
    "311": "Pantry", "313": "Pantry", "315": "Pantry",
}
AISLE_5 = {"24602": "Pantry", "25102": "Pantry", "16402": "Pantry", "16503": "Pantry", "24803": "Frozen"}

def aisle_for(d):
    code = str(d["cls_code"]); name = norm(d["name"])
    if "frozen" in name:
        return "Frozen", "name contains frozen"
    if code in AISLE_5:
        return AISLE_5[code], f"5-digit {code}"
    if g3(code) in AISLE_BY_3:
        return AISLE_BY_3[g3(code)], f"group {g3(code)}"
    return "", "no rule"

ALLERGEN_LABELS = ["Dairy", "Egg", "Fish", "Gluten", "Honey", "Meat", "Peanuts", "Sesame", "Shellfish", "Soy", "Tree nuts"]
GLUTEN_GRAINS = r"wheat|spelt|rye|barley|bulgur|burghul|semolina|couscous|freekeh|triticale|kamut"
GF_GRAIN_WORDS = r"rice|corn|maize|polenta|cornmeal|arrowroot|millet|quinoa|buckwheat|amaranth|sorghum|tapioca|potato|chickpea|besan|konjac|gluten free|gluten-free|coconut|almond|lentil or pulse"

def tags_for(d):
    """Return (set_of_allergen_labels, set_of_review_notes)."""
    code = str(d["cls_code"]); g = g3(code); name = norm(d["name"])
    t, rev = set(), set()
    # dairy
    if g in {"141", "142", "191", "192", "193", "194", "195", "196"}:
        t.add("Dairy")
    if "whey" in name or "casein" in name:
        t.add("Dairy")
    # egg
    if g == "171" or re.search(r"\begg\b", name) and g not in {"124"}:
        t.add("Egg")
    if g == "124" and "egg" in name:
        t.add("Egg")
    if re.search(r"mayonnaise|dijonaise|tartare|aioli|custard", name):
        t.add("Egg"); rev.add("Egg: commercial product, confirm on label")
    # fish and shellfish
    if g in {"151", "153", "154"} or "fish roe" in name:
        t.add("Fish")
    if g in {"152", "157"} or re.search(r"prawn|shrimp|crab|lobster|oyster(?!.*sauce)|mussel|scallop|squid|calamari|octopus|abalone", name):
        t.add("Shellfish")
    if re.search(r"sauce, oyster|shrimp", name):
        t.add("Shellfish")
    if re.search(r"sauce, fish|worcestershire|anchovy", name):
        t.add("Fish")
    # meat (incl. gelatine)
    if g in {"181", "182", "183", "186"} or "gelatine" in name or "meat paste" in name:
        t.add("Meat")
    # soy
    if re.search(r"\bsoy|soya|tofu|tempeh|miso|edamame|teriyaki|hoi sin|hoisin|black bean, commercial", name):
        t.add("Soy")
    if g in {"231"} and re.search(r"sauce, (soy|teriyaki|honey soy|oyster|hoi sin|black bean)", name):
        t.add("Soy"); t.add("Gluten")
    # nuts and seeds
    if g == "222" and code != "22203":
        if "peanut" in name:
            t.add("Peanuts")
        else:
            t.add("Tree nuts")
    if re.search(r"\bnut, (?!peanut)|almond|cashew|macadamia|pistachio|pecan|hazelnut|brazil|walnut|pine nut", name) and "coconut" not in name:
        t.add("Tree nuts")
    if "peanut" in name or "satay" in name:
        t.add("Peanuts")
    if re.search(r"sesame|tahini|hummus|hommus", name):
        t.add("Sesame")
    # honey
    if re.search(r"\bhoney\b", name):
        t.add("Honey")
    # gluten
    if g in {"121", "122", "123", "124", "125", "126", "132", "136"}:
        if re.search(GLUTEN_GRAINS, name) or (not re.search(GF_GRAIN_WORDS, name) and not re.search(r"\boat", name)):
            t.add("Gluten")
        if re.search(r"\boat", name):
            t.add("Gluten"); rev.add("Oats: tagged Gluten to match the dietitians' rolled oats and quick oats; not sold as gluten free in Australia; dietitian decides")
        if "soba" in name or "buckwheat" in name and "noodle" in name:
            t.add("Gluten"); rev.add("Soba noodles usually contain wheat; confirm")
    if re.search(r"\boat", name) and g not in {"121", "122", "123", "124", "125", "126", "132", "136"}:
        t.add("Gluten"); rev.add("Oats: tagged Gluten to match the dietitians' rolled oats and quick oats; dietitian decides")
    if re.search(r"/wheat/|\bwheat\b", name) and "Gluten" not in t:
        t.add("Gluten")
    if re.search(r"vegemite|yeast extract|(?<!rice )malt\b|crumpet|croutons|falafel|stuffing", name):
        t.add("Gluten")
        if "falafel" in name:
            rev.add("Falafel: flour content varies, confirm")
    if re.search(r"stock, liquid, all flavours", name):
        rev.add("Stock: AUSNUT row covers all flavours incl. chicken and beef; vegan only if the product is vegetable stock")
    if re.search(r"stock, dry|stock cube|seasoning|taco|barbecue|hp \(brown\)|gravy|curry style|satay|plum, commercial|sauce, pasta|meat alternative", name):
        rev.add("Commercial seasoning or sauce: wheat and soy possible, confirm on label")
    if g == "281":
        rev.add("Chocolate: milk solids and soy lecithin possible, confirm on label")
    if g == "301":
        rev.add("Protein powder: reference row only, use the pack label")
    if g == "186":
        rev.add("Processed meat: dairy, gluten and soy possible, confirm on label")
    return t, rev

def dietary_for(allergens, review):
    dt = set()
    blocking = {n.split(":")[0] for n in review}
    if not (allergens & {"Dairy", "Egg", "Fish", "Shellfish", "Meat", "Honey"}) and not (blocking & {"Egg", "Chocolate", "Protein powder", "Processed meat", "Commercial seasoning or sauce", "Stock"}):
        dt.add("Vegan")
    if not (allergens & {"Fish", "Shellfish", "Meat"}) and not (blocking & {"Stock"}):
        dt.add("Vegetarian")
    if "Dairy" not in allergens and not (blocking & {"Chocolate", "Protein powder", "Processed meat"}):
        dt.add("Dairy-free")
    if not (allergens & {"Tree nuts", "Peanuts"}):
        dt.add("Nut-free")
    if "Gluten" not in allergens and not (blocking & {"Oats", "Soba noodles usually contain wheat; confirm".split(":")[0], "Commercial seasoning or sauce", "Falafel", "Chocolate", "Processed meat"}):
        dt.add("Gluten-free")
    return dt

def protein_family_for(d):
    code = str(d["cls_code"]); g = g3(code); name = norm(d["name"])
    if "turkey" in name:
        return "turkey"
    if re.search(r"duck|goose|quail|pigeon|emu|ostrich|guinea", name):
        return "other"
    if g == "183" or "chicken" in name and g in {"186"}:
        return "chicken"
    if re.search(r"\bbeef|\bveal", name) and g in {"181", "186"}:
        return "beef"
    if re.search(r"\blamb|mutton", name):
        return "lamb"
    if re.search(r"\bpork|bacon|\bham\b|prosciutto|salami|pastrami|speck|chorizo", name):
        return "pork"
    if "kangaroo" in name:
        return "kangaroo"
    if g in {"151", "153", "154"} or "fish" in name:
        return "fish"
    if g in {"152", "157"} or re.search(r"prawn|crab|lobster|oyster|mussel|scallop|squid|calamari|octopus", name):
        return "seafood"
    if g == "171":
        return "egg"
    if g in {"191", "192", "194", "196"} or re.search(r"cheese|yoghurt|milk, cow|quark", name):
        return "dairy"
    if re.search(r"tofu|tempeh", name):
        return "tofu_tempeh"
    if g in {"251", "252"} or re.search(r"\bbean|lentil|chickpea|pea, split|hummus|falafel|edamame", name):
        return "legumes"
    if g in {"181", "182", "186", "302"}:
        return "other"
    if g == "301" or "meat alternative" in name:
        return "other"
    return ""

def purchase_unit_for(d, has_can_measure):
    code = str(d["cls_code"]); g = g3(code); name = norm(d["name"])
    if "canned" in name or has_can_measure:
        return "can"
    if code == "24403":
        return "bunch"
    if g in {"162", "163", "164", "165", "166", "161"} and not re.search(r"berr|cherr|grape", name):
        return "each"
    if re.search(r"berr|cherr|cherry tomato|grape", name) and g in {"162", "166", "246"}:
        return "punnet"
    if g in {"241", "242", "243", "244", "245", "246", "247", "248"}:
        if re.search(r"packaged|mixed leafy|sprout|cauliflower rice|baby|snow pea|sugar snap|bean, green|bean, broad|herbs", name):
            return "packet"
        return "each"
    if g in {"191", "193", "201", "192", "205", "196", "195"}:
        return "each"
    if g in {"231", "232", "233", "235", "271", "272", "144", "141", "142", "311", "313", "281", "301", "111", "112", "118"}:
        return "each"
    if g in {"122", "123", "136"}:
        return "each"
    return "packet"

# write rule tables (one row per 3-digit group that appears in AUSNUT, plus the name rules in prose)
groups3 = sorted({g3(d["cls_code"]) for d in details.values()})
write(os.path.join(OUT, "rules", "rule_aisle.csv"),
      [{"group_code": g, "group_name": cls.get(g, ""), "aisle": AISLE_BY_3.get(g, ""), "override": "; ".join(f"{k}={v}" for k, v in AISLE_5.items() if k.startswith(g)), "name_rule": "name contains 'frozen' -> Frozen"} for g in groups3],
      ["group_code", "group_name", "aisle", "override", "name_rule"])

TAG_RULES = [
    ("Dairy", "groups 141, 142, 191-196 (butter, dairy blends, milk, yoghurt, cream, cheese, ice cream, custard); name has whey or casein"),
    ("Egg", "group 171; name has egg (pasta included); mayonnaise, dijonaise, tartare, aioli, custard (flag: confirm on label)"),
    ("Fish", "groups 151, 153, 154 (fin fish, roe, canned fin fish); fish sauce, Worcestershire, anchovy"),
    ("Shellfish", "groups 152, 157 (crustacea, molluscs); prawn, shrimp, crab, lobster, oyster, mussel, scallop, squid, octopus, abalone; oyster sauce, shrimp paste"),
    ("Meat", "groups 181, 182, 183, 186 (beef, lamb, pork, game, poultry, processed meat); gelatine; meat paste"),
    ("Soy", "soy, soya, tofu, tempeh, miso, edamame, teriyaki, hoisin, black bean sauce; soy-based sauces also get Gluten (wheat)"),
    ("Peanuts", "name has peanut or satay"),
    ("Tree nuts", "group 222 except 22203 coconut; almond, cashew, macadamia, pistachio, pecan, hazelnut, brazil, walnut, pine nut"),
    ("Sesame", "sesame, tahini, hummus"),
    ("Honey", "name has honey"),
    ("Gluten", "cereal groups 121-126, 132, 136 unless the grain is rice, corn, polenta, arrowroot, millet, quinoa, buckwheat, amaranth, konjac, chickpea or gluten free; vegemite, malt, crumpets, croutons, falafel, soba"),
    ("REVIEW (no tag written)", "oats (not gluten-free under FSANZ); commercial seasonings, stock cubes, barbecue and curry sauces; chocolate; protein powders; processed meats. These rows are listed in import_review_flags.csv for a dietitian."),
    ("Vegan", "derived: none of Dairy, Egg, Fish, Shellfish, Meat, Honey and no open review flag"),
    ("Vegetarian", "derived: none of Fish, Shellfish, Meat"),
    ("Dairy-free", "derived: no Dairy and no open dairy review flag"),
    ("Gluten-free", "derived: no Gluten, not oats, no open gluten review flag"),
    ("Nut-free", "derived: no Tree nuts and no Peanuts"),
    ("High-FODMAP", "never written by rule; dietitians only"),
]
write(os.path.join(OUT, "rules", "rule_tags.csv"), [{"tag": a, "rule": b} for a, b in TAG_RULES], ["tag", "rule"])

PF_RULES = [
    ("chicken", "group 183; chicken deli meats"), ("turkey", "name has turkey"), ("beef", "beef or veal in groups 181, 186"),
    ("lamb", "lamb or mutton"), ("pork", "pork, bacon, ham, prosciutto, salami, pastrami, speck, chorizo"), ("kangaroo", "kangaroo"),
    ("fish", "groups 151, 153, 154"), ("seafood", "groups 152, 157 and crustacea or mollusc names"), ("egg", "group 171"),
    ("dairy", "milk, yoghurt, cheese, quark (groups 191, 192, 194, 196)"), ("tofu_tempeh", "tofu, tempeh"),
    ("legumes", "groups 251, 252 and bean, lentil, chickpea, split pea, hummus, falafel, edamame"),
    ("other", "other game, duck, protein powders, meat alternatives"), ("(blank)", "everything else: not a protein source"),
]
write(os.path.join(OUT, "rules", "rule_protein_family.csv"), [{"protein_family": a, "rule": b} for a, b in PF_RULES], ["protein_family", "rule"])

PU_RULES = [
    ("can", "name has canned, or AUSNUT lists a can measure"), ("bunch", "fresh herbs (24403)"),
    ("each", "whole fruit; whole vegetables; milk, yoghurt, cream, custard, ice cream; sauces, oils, spreads, jars; bread, rolls, flat breads"),
    ("punnet", "berries, cherries, grapes, cherry tomatoes"),
    ("packet", "packaged salad and sprouts, snow peas, green beans; cheese; meat and fish; grains, flours, pasta, cereals, biscuits; nuts, seeds, dried fruit; spices; everything else"),
    ("pouch", "only where AUSNUT lists a pouch measure without brand (rice pouches)"),
]
write(os.path.join(OUT, "rules", "rule_purchase_unit.csv"), [{"purchase_unit": a, "rule": b} for a, b in PU_RULES], ["purchase_unit", "rule"])

# ---------------------------------------------------------------- lists
ours = json.load(open(os.path.join(WORK, "our_foods.json")))
live_conv = {}
for c in json.load(open(os.path.join(WORK, "our_conv_gaps.json")))["conv"]:
    live_conv.setdefault(c["food_id"], {})[c["unit"]] = c["grams"]
live_food = {f["food_id"]: f for f in ours}
our_ids = {f["food_id"] for f in ours}
our_names = {norm(f["display_name"]): f["food_id"] for f in ours}

C = list(csv.DictReader(open(os.path.join(OUT, "foods_to_add_C.csv"))))
list_C = []
DROP_C = {"Radish", "Brussels sprouts"}  # verified radish and brussel_sprout already exist with the same key and numbers
for r in C:
    if r["proposed_display_name"] in DROP_C:
        continue
    k = r["ausnut_key"]; d = details[k]
    fid = slug(r["proposed_display_name"].split(" (")[0])
    if fid in our_ids:
        fid = f"{fid}_ausnut"
    list_C.append({"action": "create", "food_id": fid, "display_name": r["proposed_display_name"].split(" (AUSNUT")[0],
                   "ausnut_key": k, "ausnut_name": d["name"], "category": r["category"], "note": ""})
write(os.path.join(OUT, "lists", "list_C_import.csv"), list_C, ["action", "food_id", "display_name", "ausnut_key", "ausnut_name", "category", "note"])

list_A = [
    {"action": "create", "food_id": "gelatine_powder", "display_name": "Gelatine powder", "ausnut_key": "F004196", "ausnut_name": details["F004196"]["name"], "recipes": "7 recipes with 'warm water + 3 tsp gelatine' in the method (data_issue)", "note": "add ingredient line; dietitian confirms quantity"},
    {"action": "reuse_existing", "food_id": "(existing Coconut, desiccated)", "display_name": "Coconut flakes", "ausnut_key": "F002987", "ausnut_name": details["F002987"]["name"], "recipes": "6 recipes (optional topping)", "note": "do not create; re-add the line using the existing coconut, desiccated food"},
    {"action": "create", "food_id": "olive_oil_spray", "display_name": "Olive oil spray", "ausnut_key": "F006177", "ausnut_name": details["F006177"]["name"], "recipes": "Savoury egg muffins", "note": "same nutrients as olive oil; AUSNUT spray measure 5 g loads as a conversion"},
    {"action": "none", "food_id": "", "display_name": "Quick pickled veg", "ausnut_key": "", "ausnut_name": "", "recipes": "5 recipes", "note": "sub-recipe, not a food; dietitian re-adds carrot, cucumber, vinegar, sugar lines"},
]
write(os.path.join(OUT, "lists", "list_A_create.csv"), list_A, ["action", "food_id", "display_name", "ausnut_key", "ausnut_name", "recipes", "note"])

B1 = [
    ("tasty_cheese", "F002414", ""), ("turkey_mince", "F010386", ""), ("vermicelli_noodles", "F006038", "cooked basis; confirm recipes mean cooked weight"),
    ("vermicelli_rice_noodle", "F006038", ""), ("pad_thai_rice_noodle", "F006038", ""), ("red_curry_paste", "F006471", ""), ("tikka_curry_paste", "F006471", ""),
    ("mixed_berries", "F009881", ""), ("plain_rice_cake", "F001147", ""), ("rosemary", "F007716", "fresh"),
    ("thyme", "F009160", "dried"), ("light_cream_cheese", "F002446", ""), ("red_chili_flake", "F002893", ""), ("tin_butter_bean", "F000440", ""),
    ("powdered_sugar", "F008980", ""), ("rice_pouch", "F007678", ""), ("microwave_brown_rice_quinoa_pouch", "F007647", "no quinoa blend row in AUSNUT; brown rice par-cooked used"),
    ("tomato_passata", "F009209", ""), ("tomato_paste", "F009208", ""), ("pepita", "F008212", ""), ("sundried_tomato", "F009217", ""),
    ("taco_seasoning", "F009072", ""), ("vegetable_stock_pot", "F008936", "concentrate pot; live numbers already on a prepared-stock basis; AUSNUT row is prepared stock, all flavours"), ("mixed_herbs_dried", "F004365", ""), ("salt", "F007878", ""),
    ("salt_and_pepper", "F007878", "salt and pepper to taste: salt row"), ("water", "F009527", ""), ("pepper", "F006618", ""), ("soy_sauce", "F008065", ""),
    ("light_soy_sauce", "F008065", "already on this key; load nutrients"), ("oregano", "F006281", "already on this key; load nutrients"),
    ("tomato", "F009193", "common tomato, not cherry"), ("rice_vinegar", "F009498", "accepted generic"), ("apple_cider_vinegar", "F009498", "accepted generic"),
    ("white_vinegar", "F009498", "accepted generic"), ("sherry_vinegar", "F009498", "accepted generic"), ("seeded_mustard", "F005973", "accepted stand-in"),
    ("swiss_brown_mushroom", "F005946", "accepted stand-in"),
    ("oyster_mushroom", "F005956", "live key points at Oyster, raw (seafood); numbers are seafood numbers, must be replaced"),
    ("olive_oil_kewpie_mayonnaise", "F005441", "live key points at Oil, olive (883 kcal); replace with mayonnaise"),
    ("tomato_based_pizza_sauce", "F008050", "live key points at salsa; tomato pasta sauce is the nearest row"),
]
write(os.path.join(OUT, "lists", "list_B1_repoint.csv"),
      [{"action": "repoint_and_load_numbers", "food_id": f, "ausnut_key": k, "ausnut_name": details[k]["name"], "note": n} for f, k, n in B1],
      ["action", "food_id", "ausnut_key", "ausnut_name", "note"])

B2 = [
    ("butter", "F001973"), ("chicken_stock", "F008936"), ("kalamata_olives", "F006198"), ("honey_olive_oil_labneh", "F009655"),
    ("hot_sauce", "F007997"), ("peas", "F006536"), ("pea_frozen", "F006536"), ("diced_tomato_canned", "F009222"), ("crushed_tomato_canned", "F009222"),
    ("chocolate", "F002929"), ("white_bread", "F001463"), ("grape_seed_oil", "F006167"), ("g_can_chickpea", "F002880"), ("can_kidney_bean", "F000448"),
    ("lentil_brown", "F010192"), ("microwave_brown_rice", "F007647"), ("beef_steak", "F000739"), ("tofu_silken", "F009183"),
    ("caster_sugar", "F008976"), ("gf_pasta", "F006429"), ("cottage_cheese_lf", "F002438"), ("dark_soy_sauce", "F008065"),
    ("wholemeal_roll", "F001360"),
]
write(os.path.join(OUT, "lists", "list_B2_relink_verified.csv"),
      [{"action": "relink_key_only_numbers_untouched", "food_id": f, "ausnut_key": k, "ausnut_name": details[k]["name"], "note": ("labneh has no AUSNUT row; Greek yoghurt is the nearest reference only. " if f == "honey_olive_oil_labneh" else "") + "verified row: change ausnut_key, source and match_note only; flag any nutrient difference >10% kcal or >15% macro for the dietitian"} for f, k in B2],
      ["action", "food_id", "ausnut_key", "ausnut_name", "note"])

B3 = [
    ("olive_oil_burger", "olive_oil"), ("olive_oil_coating", "olive_oil"), ("sesame_seed_tomato", "sesame_seeds"),
    ("salt_and_black_pepper", "salt"), ("salt_black_pepper", "salt"), ("lime_juice_to_assemble", "lime_juice"), ("juice_from_1_lime", "lime_juice"),
    ("stalk_celery", "celery"), ("powder", "curry_powder"), ("dried_oregano", "oregano"), ("tin_tuna_in_spring_water", "tuna_springwater"),
    ("old_fashioned_rolled_oat", "rolled_oats"), ("unsweetened_cocoa_powder", "cocoa_powder"), ("pesto_sauce", "pesto"),
    ("raspberry_tonic_water", "tonic_water"), ("red_long_chilli", "chilli_red"), ("spring_onion_green", "spring_onion"),
    ("egg_quick_pickled_veg", "egg"), ("lemongrass_stalk", "lemongrass"),
]
B3V = [
    ("egg_mayo", "light_mayonnaise", "verified, 0 uses after the ingest repair; 428 kcal vs 150 kcal for light mayonnaise, so not a true duplicate. Dietitian decides: keep as a separate food, or delete."),
    ("zest_lemon_juice", "freshly_squeezed_lemon_juice", "verified, 0 uses; same food as freshly squeezed lemon juice. Dietitian confirms delete."),
    ("juice_orange", "orange_juice", "verified, 0 uses; duplicate of orange juice. Dietitian confirms delete."),
]
write(os.path.join(OUT, "lists", "list_B3b_verified_duplicates_dietitian.csv"),
      [{"action": "dietitian_decision_required", "duplicate_food_id": a, "canonical_food_id": b, "note": n} for a, b, n in B3V],
      ["action", "duplicate_food_id", "canonical_food_id", "note"])
write(os.path.join(OUT, "lists", "list_B3_merge_delete.csv"),
      [{"action": "repoint_lines_then_delete", "duplicate_food_id": a, "canonical_food_id": b, "note": "check 'powder' recipe line before merging" if a == "powder" else ""} for a, b in B3],
      ["action", "duplicate_food_id", "canonical_food_id", "note"])

# ---------------------------------------------------------------- import package (C + A creates + B1 repoints)
targets = []
for r in list_C:
    targets.append((r["food_id"], r["display_name"], r["ausnut_key"], "create"))
targets.append(("gelatine_powder", "Gelatine powder", "F004196", "create"))
targets.append(("olive_oil_spray", "Olive oil spray", "F006177", "create"))
for f, k, n in B1:
    targets.append((f, next((x["display_name"] for x in ours if x["food_id"] == f), f), k, "repoint"))

meas_by_key = {}
for m in measures:
    meas_by_key.setdefault(m["public_food_key"], []).append(m)

tag_rows, conv_rows, flag_rows, food_rows = [], [], [], []
for fid, name, k, action in targets:
    d = details[k]; n = nutr[k]; ms = meas_by_key.get(k, [])
    dens = [m for m in ms if m["is_density"]]
    others = [m for m in ms if not m["is_density"] and not m["is_brand_pack"]]
    brand = [m for m in ms if m["is_brand_pack"]]
    g = g3(d["cls_code"]); code = str(d["cls_code"])
    DRY_CUP_GROUPS = {"121", "124", "125", "126", "168", "221", "222", "251", "271", "311", "313", "315", "301"}
    density = ""
    LIQUID_GROUPS = {"111", "112", "118", "119", "144", "145", "191", "192", "193", "196", "201", "205", "231", "232", "233", "235", "271", "272", "313", "118"}
    plain = [m for m in dens if not m["descriptor_2"]]
    if len(dens) == 1 and (g in LIQUID_GROUPS or g in DRY_CUP_GROUPS):
        density = dens[0]["gram_amount"]
    elif len(plain) == 1 and g in LIQUID_GROUPS:
        density = plain[0]["gram_amount"]
    if len(dens) > 1 or (len(dens) == 1 and dens[0]["descriptor_2"]):
        for m in dens:
            if re.search(r"grated|shredded|chopped|diced|sliced|crumbled|mashed|flaked|torn|segments", m["descriptor_2"]):
                d2 = m['descriptor_2'].split('/')[0].strip()
                unit = "cup" if d2 == "cup" else f"cup ({d2})"
                conv_rows.append({"food_id": fid, "unit": unit, "grams": round(250 * float(m["gram_amount"]), 1), "basis": f"AUSNUT 2023 measure {m['measure_id']} density {m['gram_amount']} g/mL x 250 mL", "estimated": 0})
    SKIP_PACK = r"millilitres|single serve|snack size|king|twin|fun size|\bmini\b|foot long|individual serve|\bbox\b|container|\btub\b|bottle|carton|sachet|dinner sized|serve\b|portion|bar \(|family size|family pack|dixie|glass|bowl|microwavable cup|microwave bag|babybel|\bjar\b|packet \(small\)|packet \(large\)"
    UNIT_MAP = {"tablespoon": "tbsp", "teaspoon": "tsp", "cup": "cup"}
    sizes = {}
    for m in others:
        unit = m["suggested_unit"]
        if not unit or re.search(SKIP_PACK, unit):
            continue
        unit = UNIT_MAP.get(unit, unit)
        unit = re.sub(r"^(.+) \((\1)\)$", r"\1", unit)
        if "microwavable bag" in unit or "pouch" in unit:
            unit = "pouch"
        if float(m["gram_amount"] or 0) < 0.5:
            continue
        if unit in ("tbsp", "tsp", "cup") and density:
            continue  # engine derives spoons and cups from density
        if unit in sizes:
            continue
        sizes[unit] = m
        conv_rows.append({"food_id": fid, "unit": unit, "grams": m["gram_amount"], "basis": f"AUSNUT 2023 measure {m['measure_id']} {m['descriptor_1']} {m['descriptor_2']}".strip(), "estimated": 0})
    PIECE_GROUPS = {"161", "162", "163", "164", "165", "166", "171", "181", "182", "183", "151", "241", "242", "243", "244", "245", "246", "247", "248"}
    default_size = ""
    if "medium" in sizes:
        default_size = "medium"
    elif "regular" in sizes:
        default_size = "regular"
    elif g in PIECE_GROUPS:
        piece = [u for u, m in sizes.items() if u not in SIZE_WORDS and float(m["gram_amount"]) >= 5 and not re.search(r"cup|tbsp|tsp|can|jar|slice|handful|scoop|piece|wedge|cube|punnet|bunch|packet|leaf|floret|sprig|stalk|clove|segment|wheel|ring|berry|nut\b|seed|grape|sultana|raisin|anchovy|olive|caper|kernel|strip|row|square", u)]
        if len(piece) == 1:
            m = sizes[piece[0]]
            conv_rows.append({"food_id": fid, "unit": "regular", "grams": m["gram_amount"], "basis": f"AUSNUT 2023 measure {m['measure_id']} one {piece[0]}", "estimated": 0})
            default_size = "regular"
    if fid == "olive_oil_spray" and "spray" not in sizes:
        conv_rows.append({"food_id": fid, "unit": "spray", "grams": 0.3, "basis": "estimate: one-second spray", "estimated": 1})
    has_can = any(m["descriptor_1"] == "can" for m in others)
    density_note = ""
    if action == "repoint":
        lf = live_food[fid]; lc = live_conv.get(fid, {})
        live_d = lf.get("density_g_ml")
        if live_d:
            if not density:
                density = live_d; density_note = "live density kept (AUSNUT gives none)"
            elif abs(float(density) - float(live_d)) / float(live_d) > 0.10:
                flag_rows.append({"food_id": fid, "ausnut_key": k, "flag": f"density change > 10%: live {live_d} vs AUSNUT {density}; every spoon and cup line of this food moves. Queue, do not write"})
                density = live_d; density_note = "live density kept pending dietitian (AUSNUT differs > 10%)"
        if default_size and ("each" in lc or any(u in lc for u in SIZE_WORDS)):
            flag_rows.append({"food_id": fid, "ausnut_key": k, "flag": f"default size not set: food already has each/size measures ({', '.join(sorted(lc))}); setting it would rewrite 'each'"})
            default_size = ""
        conv_rows[:] = [c for c in conv_rows if not (c["food_id"] == fid and c["unit"] in lc)]
    allergens, review = tags_for(d)
    dietary = dietary_for(allergens, review)
    aisle, aisle_why = aisle_for(d)
    pf = protein_family_for(d)
    pu_suggested = purchase_unit_for(d, has_can)
    units_here = {c["unit"] for c in conv_rows if c["food_id"] == fid} | set(live_conv.get(fid, {}) if action == "repoint" else [])
    pu = pu_suggested if pu_suggested in units_here else ""
    if action == "repoint":
        aisle_live = live_food[fid].get("aisle") or ""
        if aisle_live and aisle_live != aisle:
            flag_rows.append({"food_id": fid, "ausnut_key": k, "flag": f"aisle not changed: live '{aisle_live}', rule suggests '{aisle}'"})
        aisle = aisle_live or aisle
    for t in sorted(allergens):
        tag_rows.append({"food_id": fid, "tag_label": t, "kind": "allergen"})
    for t in sorted(dietary):
        tag_rows.append({"food_id": fid, "tag_label": t, "kind": "dietary"})
    for rv in sorted(review):
        flag_rows.append({"food_id": fid, "ausnut_key": k, "flag": rv})
    if fid == "olive_oil_spray":
        flag_rows.append({"food_id": fid, "ausnut_key": k, "flag": "AUSNUT spray measure is 5 g (44 kcal); a one-second spray is closer to 0.3 g. Loaded as AUSNUT gives it; dietitian may override"})
    if brand:
        flag_rows.append({"food_id": fid, "ausnut_key": k, "flag": f"{len(brand)} brand pack measures skipped"})
    if not aisle:
        flag_rows.append({"food_id": fid, "ausnut_key": k, "flag": "no aisle rule"})
    food_rows.append({
        "action": action, "food_id": fid, "display_name": name, "source": "ausnut", "ausnut_key": k, "ausnut_name": d["name"],
        "derivation": d["derivation"], "classification_code": d["cls_code"], "classification_name": d["cls_name"],
        "energy_kcal_100g": n["energy_kcal"], "protein_100g": n["protein_g"], "fat_100g": n["fat_g"],
        "carb_avail_100g": n["carb_avail_without_sa_g"], "carb_avail_with_sa_100g": n["carb_avail_with_sa_g"], "fibre_100g": n["fibre_g"],
        "sugars_100g": n["sugars_g"], "satfat_100g": n["satfat_g"], "sodium_100g": n["sodium_mg"], "potassium_100g": n["potassium_mg"],
        "calcium_100g": n["calcium_mg"], "iron_100g": n["iron_mg"], "zinc_100g": n["zinc_mg"], "magnesium_100g": n["magnesium_mg"],
        "folate_100g": n["folate_total_ug"], "folate_dfe_ug_reference": n["folate_dfe_ug"], "vitamin_b12_100g": n["vitamin_b12_ug"],
        "density_g_ml": density, "density_note": density_note, "specific_gravity_ausnut": d["specific_gravity"], "default_size": default_size,
        "aisle": aisle, "aisle_rule": aisle_why, "protein_family": pf, "purchase_unit": pu, "purchase_unit_suggested": pu_suggested,
        "allergen_tags": "; ".join(sorted(allergens)), "dietary_tags": "; ".join(sorted(dietary)),
        "review_flags": "; ".join(sorted(review)),
        "ai_evidence": f"AUSNUT 2023 {k} {d['name']} ({d['derivation']}); {n['energy_kcal']} kcal, P {n['protein_g']}, F {n['fat_g']}, C {n['carb_avail_without_sa_g']}, fibre {n['fibre_g']} per 100 g",
        "verified": 0, "ai_verified": 1,
    })

write(os.path.join(OUT, "import", "import_foods.csv"), food_rows, list(food_rows[0].keys()))
write(os.path.join(OUT, "import", "import_food_tags.csv"), tag_rows, ["food_id", "tag_label", "kind"])
write(os.path.join(OUT, "import", "import_unit_conversions.csv"), conv_rows, ["food_id", "unit", "grams", "basis", "estimated"])
write(os.path.join(OUT, "import", "import_review_flags.csv"), flag_rows, ["food_id", "ausnut_key", "flag"])

print("master", len(master), "measures", len(measures), "classes", len(cls))
print("C", len(list_C), "A", len(list_A), "B1", len(B1), "B2", len(B2), "B3", len(B3))
print("import foods", len(food_rows), "tags", len(tag_rows), "conversions", len(conv_rows), "flags", len(flag_rows))
