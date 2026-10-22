"""AUSNUT rev 3 — build the G3/G4 changeset from the package + decisions.py + the LIVE library (read-only).

Usage: python3 -I scripts/ausnut/build_changeset.py [--offline <live json dir>]
Writes seed/ausnut2023/changeset/<batch>.jsonl (what apply_changeset.py uploads) and review files in
seed/ausnut2023/changeset/review/ (what people read). Nothing is written to the database.

Batches (applied in this order, each in one transaction):
  g3a verified foods: link fixes (B2 + reviewed), decision 2a check, flags, urgent list
  g3b unverified foods: AUSNUT numbers + AI verification, everything else to the queue
  g3c measures: conversions for uncalculable lines, B1 measures, confirmed estimates, default sizes, line fixes
  g3d fills: aisle corrections, protein family
  g4a new foods (A + C): insert, measures, tags, default size, buy-as, then AI verification
  g4b merges and deletes: copy missing measures, re-point every reference, delete (zero references)
  g4c recipes: restore lost lines, fix notes, data_issue
"""
import csv
import importlib.util
import json
import os
import re
import sys
from collections import Counter, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
PKG = os.path.join(REPO, "seed", "ausnut2023")
OUT = os.path.join(PKG, "changeset")
REV = os.path.join(OUT, "review")
sys.path.insert(0, HERE)
from role_rules import suggest_with_note
spec = importlib.util.spec_from_file_location("decisions", os.path.join(HERE, "decisions.py"))
D = importlib.util.module_from_spec(spec); spec.loader.exec_module(D)

# ---------------------------------------------------------------------------------------- inputs
def C(rel):
    with open(os.path.join(PKG, rel), newline="", encoding="utf-8-sig") as fh:
        return list(csv.DictReader(fh))

if "--offline" in sys.argv:
    LIVE = sys.argv[sys.argv.index("--offline") + 1]
    L = lambda n: json.load(open(os.path.join(LIVE, n + ".json")))
else:
    sys.path.insert(0, HERE)
    from _rest import select_all
    _q = {"foods": "foods?select=*", "unit_conversions": "unit_conversions?select=food_id,unit,grams,estimated,basis",
          "ingredient_lines": "ingredient_lines?select=id,recipe_id,food_id,quantity,unit,prep_note,position",
          "food_tags": "food_tags?select=food_id,tag_id", "tags": "tags?select=id,label,kind,category",
          "afcd_master": "afcd_master?select=public_food_key", "recipes": "recipes?select=id,title,data_issue",
          "protein_families": "protein_families?select=key", "client_food_rules": "client_food_rules?select=food_id",
          "swap_suggestions": "swap_suggestions?select=*", "food_unit_exclusions": "food_unit_exclusions?select=*",
          "recipe_verification": "recipe_verification?select=recipe_id,status,has_title,has_image,step_count"}
    _cache = {}
    def L(n):
        if n not in _cache: _cache[n] = select_all(_q[n])
        return _cache[n]

def num(x):
    try: return float(x)
    except (TypeError, ValueError): return None

foods = {f["food_id"]: f for f in L("foods")}
convs = defaultdict(dict)
for u in L("unit_conversions"): convs[u["food_id"]][u["unit"]] = u
lines = L("ingredient_lines")
for l in lines: l["_orig"] = (l["food_id"], l["unit"], float(l["quantity"]))
lines_at_start = [dict(l) for l in lines]          # for the projection self-check
lines_by_food = defaultdict(list)
for l in lines: lines_by_food[l["food_id"]].append(l)
tag_label = {t["id"]: t["label"] for t in L("tags")}
tag_kind = {t["label"]: t["kind"] for t in L("tags")}
tags_by_food = defaultdict(set)
for x in L("food_tags"): tags_by_food[x["food_id"]].add(tag_label[x["tag_id"]])
afcd_keys = {a["public_food_key"] for a in L("afcd_master")}
recipes = {r["id"]: r for r in L("recipes")}
recipe_by_title = defaultdict(list)
for r in recipes.values(): recipe_by_title[r["title"].strip().upper()].append(r)
families = {p["key"] for p in L("protein_families")}
master = {m["public_food_key"]: m for m in C("reference/ausnut_master.csv")}
measures = defaultdict(list)
for m in C("reference/ausnut_measures.csv"): measures[m["public_food_key"]].append(m)
imp = C("import/import_foods.csv"); imp_by = {r["food_id"]: r for r in imp}
imp_conv = defaultdict(list)
for c in C("import/import_unit_conversions.csv"): imp_conv[c["food_id"]].append(c)
imp_tags = defaultdict(list)
for t in C("import/import_food_tags.csv"): imp_tags[t["food_id"]].append(t["tag_label"])
B1 = {r["food_id"]: r for r in C("lists/list_B1_repoint.csv")}
B2 = {r["food_id"]: r for r in C("lists/list_B2_relink_verified.csv")}
B3 = {r["duplicate_food_id"]: r["canonical_food_id"] for r in C("lists/list_B3_merge_delete.csv")}
SM = defaultdict(list)
for r in C("lists/suggested_matches_unlinked.csv"): SM[r["food_id"]].append(r)
for k in SM: SM[k].sort(key=lambda r: int(r["Rank"] or 9))

problems = []          # anything that would make a load fail → the build stops
def problem(msg): problems.append(msg)
def recipe(title):
    rs = recipe_by_title.get(title.strip().upper(), [])
    if len(rs) != 1: problem(f"recipe {title!r}: {len(rs)} matches"); return None
    return rs[0]
gone_ids = set(B3) | set(D.MERGE) | set(D.DELETE_UNUSED) | set(D.SPLITS)

# ---------------------------------------------------------------------------------------- rules
NUTR = [("energy_kcal_100g", "energy_kcal"), ("protein_100g", "protein_g"), ("fat_100g", "fat_g"),
        ("carb_avail_100g", "carb_avail_without_sa_g"), ("fibre_100g", "fibre_g"), ("sugars_100g", "sugars_g"),
        ("satfat_100g", "satfat_g"), ("sodium_100g", "sodium_mg"), ("potassium_100g", "potassium_mg"),
        ("calcium_100g", "calcium_mg"), ("iron_100g", "iron_mg"), ("zinc_100g", "zinc_mg"), ("magnesium_100g", "magnesium_mg"),
        ("folate_100g", "folate_total_ug"), ("vitamin_b12_100g", "vitamin_b12_ug")]
CORE = ["energy_kcal_100g", "protein_100g", "fat_100g", "carb_avail_100g", "fibre_100g"]

def gate(f, m):
    why = []
    o, x = num(f["energy_kcal_100g"]), num(m["energy_kcal"])
    if o is not None and x is not None and abs(x - o) > 10 and (o == 0 or abs(x - o) / o > 0.10): why.append(f"kcal {o:g}→{x:g}")
    for fc, mc, lab in (("protein_100g", "protein_g", "P"), ("fat_100g", "fat_g", "F"), ("carb_avail_100g", "carb_avail_without_sa_g", "C"), ("fibre_100g", "fibre_g", "fibre")):
        o, x = num(f[fc]), num(m[mc])
        if o is not None and x is not None and abs(x - o) > 1 and (o == 0 or abs(x - o) / o > 0.15): why.append(f"{lab} {o:g}→{x:g}")
    return why

STATE = {"raw": "raw", "fresh": "raw", "uncooked": "dry", "dried": "dry", "dry": "dry", "cooked": "cooked", "boiled": "cooked",
         "canned": "canned", "tinned": "canned", "drained": "canned", "frozen": "frozen"}
STOPW = {"in", "with", "and", "of", "the", "a", "extra", "lean", "light", "low", "fat", "reduced"}
def sing(w):
    if w.endswith("ies") and len(w) > 4: return w[:-3] + "y"
    if w.endswith("oes") and len(w) > 4: return w[:-2]
    if w.endswith("s") and not w.endswith("ss") and len(w) > 3: return w[:-1]
    return w
def head_ok(food_name, aus_name):
    seg = re.sub(r"\(.*?\)", "", food_name).split(",")[0]
    ws = [sing(w) for w in re.findall(r"[a-z]+", seg.lower()) if w not in STATE and w not in STOPW]
    return bool(ws) and ws[-1] in {sing(w) for w in re.findall(r"[a-z]+", aus_name.lower())}
def states(n): return {STATE[w] for w in re.findall(r"[a-z]+", (n or "").lower()) if w in STATE}
def state_ok(a, b):
    x, y = states(a), states(b)
    return not x or not y or bool(x & y) or (x == {"raw"} and "frozen" in y)

def evidence(k, why):
    m = master[k]
    e = (f"AUSNUT 2023 {k} {m['food_name'].strip()} ({m['derivation']}); {num(m['energy_kcal']):g} kcal, P {num(m['protein_g']):g}, "
         f"F {num(m['fat_g']):g}, C {num(m['carb_avail_without_sa_g']):g}, fibre {num(m['fibre_g']):g} per 100 g. {why}")
    return e[:400]

def numbers_set(k):
    m = master[k]
    return {fc: num(m[mc]) for fc, mc in NUTR}

def expect_numbers(f):
    return {c: num(f[c]) for c in CORE}

VOL_ML = {"tsp": 5, "tbsp": 20, "cup": 250, "ml": 1}
BRANDED = re.compile(r"protein_powder|whey|mini_wholemeal_wrap|maple_syrup_sf|sugar_free_maple|nesquik|red_bean_paste|mustard_seed", re.I)

# ---------------------------------------------------------------------------------------- batches
batches = defaultdict(list)
def op(batch, o, food_id, note=None, **args):
    batches[batch].append({"seq": len(batches[batch]) + 1, "op": o, "food_id": food_id, "args": args, "note": note})

review = defaultdict(list)   # sheet name → rows

# ===== g3a: verified foods ==========================================================================
checked = flagged = 0
for fid, f in sorted(foods.items()):
    if not f["verified"]: continue
    if fid in D.SPLITS: continue          # combined food: split in g4b, then unused
    if fid in D.URGENT_VERIFIED:          # numbers look wrong: the dietitian decides; nothing else is touched
        k, why = D.URGENT_VERIFIED[fid]
        op("g3a", "queue", fid, f"AUSNUT 2023 {k}", kind="urgent", reason=f"Numbers look wrong: {why}",
           suggestion={"ausnut_key": k, "ausnut_name": master[k]["food_name"].strip(), "ausnut": numbers_set(k), "ours": expect_numbers(f)})
        # a dietitian badge on numbers that are demonstrably wrong is misleading (and clients see "verified"):
        # remove the badge only — numbers untouched — until a dietitian fixes the food
        op("g3a", "set_food", fid, f"numbers look wrong — on the AUSNUT urgent list ({k})", set={"verified": False}, expect={"verified": True})
        review["urgent_verified"].append({"food_id": fid, "name": f["display_name"], "ours_kcal": f["energy_kcal_100g"], "uses": len(lines_by_food[fid]),
                                          "ausnut_key": k, "ausnut_name": master[k]["food_name"].strip(), "ausnut_kcal": master[k]["energy_kcal"], "why": why})
        flagged += 1; continue
    if fid in D.VERIFIED_HOLD:
        op("g3a", "queue", fid, None, kind="verified_check", reason=D.VERIFIED_HOLD[fid], suggestion=None)
        review["verified_flags"].append({"food_id": fid, "name": f["display_name"], "issue": D.VERIFIED_HOLD[fid], "ours_kcal": f["energy_kcal_100g"], "uses": len(lines_by_food[fid])})
        flagged += 1; continue
    src, k = None, None
    if fid in D.VERIFIED_KEY_FIX: k, src = D.VERIFIED_KEY_FIX[fid][0], "reviewed relink: " + D.VERIFIED_KEY_FIX[fid][1]
    elif fid in B2: k, src = B2[fid]["ausnut_key"], "B2 relink"
    elif f.get("afcd_key") in master: k, src = f["afcd_key"], "existing key"
    else:
        hi = [r for r in SM.get(fid, []) if r["Confidence"] == "High" and state_ok(f["display_name"], r["Candidate AUSNUT name"])
              and head_ok(f["display_name"], r["Candidate AUSNUT name"])]
        if hi: k, src = hi[0]["Candidate key"], "High match"
    if not k:
        op("g3a", "queue", fid, None, kind="verified_check", reason="Verified food with no AUSNUT key: no automatic check possible.", suggestion=None)
        review["verified_flags"].append({"food_id": fid, "name": f["display_name"], "issue": "no AUSNUT key", "ours_kcal": f["energy_kcal_100g"], "uses": len(lines_by_food[fid])})
        flagged += 1; continue
    if k not in master: problem(f"g3a {fid}: key {k} not in AUSNUT"); continue
    m = master[k]
    reviewed = src.startswith(("reviewed", "B2"))
    if reviewed:                          # agreed key correction: the link changes, the numbers never do
        op("g3a", "set_food", fid, f"AUSNUT 2023 {k}", expect={"verified": True},
           set={"ausnut_key": k, "afcd_key": k if k in afcd_keys else None,
                "match_note": f"AUSNUT 2023 {k} {m['food_name'].strip()} ({src}; numbers unchanged)"[:300]})
    why = gate(f, m); named = head_ok(f["display_name"], m["food_name"])
    if named and not why:                 # ai_verify also writes ausnut_key
        op("g3a", "ai_verify", fid, f"AUSNUT 2023 {k}", ausnut_key=k, confidence="checked_verified",
           evidence=evidence(k, f"Checked against the dietitian-verified values ({num(f['energy_kcal_100g']):g} kcal): agree within the gate; numbers unchanged."),
           expect={"verified": True, **expect_numbers(f)})
        checked += 1
        review["verified_checked"].append({"food_id": fid, "name": f["display_name"], "source": src, "ausnut_key": k, "ausnut_name": m["food_name"].strip(),
                                           "ours_kcal": f["energy_kcal_100g"], "ausnut_kcal": m["energy_kcal"]})
    else:
        if named and not reviewed:        # right food, numbers differ: the key is still the right link
            op("g3a", "set_food", fid, f"AUSNUT 2023 {k}", set={"ausnut_key": k}, expect={"verified": True})
        issue = "name doesn't match the key" if not named else "AUSNUT differs: " + "; ".join(why)
        op("g3a", "queue", fid, f"AUSNUT 2023 {k}", kind="verified_check", reason=f"{issue} ({k} {m['food_name'].strip()})",
           suggestion={"ausnut_key": k, "ausnut_name": m["food_name"].strip(), "ausnut": numbers_set(k), "ours": expect_numbers(f)})
        review["verified_flags"].append({"food_id": fid, "name": f["display_name"], "issue": issue, "ours_kcal": f["energy_kcal_100g"],
                                         "ausnut_key": k, "ausnut_name": m["food_name"].strip(), "ausnut_kcal": m["energy_kcal"], "uses": len(lines_by_food[fid]),
                                         "key_source": src, "key_written": named or reviewed})
        flagged += 1

# ===== g3b: unverified foods ========================================================================
for fid, (tg, why) in D.ALLERGEN_ADD.items():               # first in g3b: before any AI write
    if fid not in foods or fid in gone_ids: problem(f"ALLERGEN_ADD {fid}: missing or being removed"); continue
    if any(o["op"] == "ai_verify" and o["food_id"] == fid for o in batches["g3a"]): problem(f"ALLERGEN_ADD {fid}: checked in g3a; the tag would undo it")
    for t in tg:
        if tag_kind.get(t) != "allergen": problem(f"ALLERGEN_ADD {fid}: {t} is not an allergen tag"); continue
        if t in tags_by_food[fid]: continue
        op("g3b", "add_tag", fid, "allergen: " + why, label=t); tags_by_food[fid].add(t)
        review["tags_added"].append({"food_id": fid, "name": foods[fid]["display_name"], "tag": t, "basis": why,
                                     "removes_dietitian_verification": foods[fid]["verified"]})
for fid, (tg, why) in D.TAG_REMOVE.items():
    if fid not in foods or fid in gone_ids: problem(f"TAG_REMOVE {fid}: missing or being removed"); continue
    for t in tg:
        if t not in tags_by_food[fid]: problem(f"TAG_REMOVE {fid}: has no {t}"); continue
        op("g3b", "remove_tag", fid, "wrong claim: " + why, label=t); tags_by_food[fid].discard(t)
        review["tags_removed"].append({"food_id": fid, "name": foods[fid]["display_name"], "tag": t, "why": why,
                                       "removes_dietitian_verification": foods[fid]["verified"]})
written = {}          # food_id → (key, confidence, density or None)
held_density = []
for fid, f in sorted(foods.items()):
    if f["verified"]: continue
    if fid in B3 or fid in D.MERGE or fid in D.DELETE_UNUSED or fid in D.SPLITS: continue          # handled in g4b
    est = "ESTIMATE" in (f.get("match_note") or "").upper()
    if fid in D.LABEL or BRANDED.search(fid):
        why = D.LABEL.get(fid, "branded product")
        op("g3b", "queue", fid, None, kind="label", reason=f"Label entry: {why}",
           suggestion={"candidates": [{"key": r["Candidate key"], "name": r["Candidate AUSNUT name"]} for r in SM.get(fid, [])[:3]]})
        review["queue"].append({"food_id": fid, "name": f["display_name"], "kind": "label", "reason": why, "uses": len(lines_by_food[fid]),
                                "now_kcal": f["energy_kcal_100g"]}); continue
    if fid in D.B1_HOLD or fid in D.RULE_HOLD or (fid in D.PROPOSE and fid not in D.LINK):
        why = D.B1_HOLD.get(fid) or D.RULE_HOLD.get(fid) or D.PROPOSE[fid][1]
        sugg = D.PROPOSE.get(fid, ("", ""))[0]
        op("g3b", "queue", fid, None, kind="proposal", reason=why, suggestion={"suggested": sugg})
        review["proposals"].append({"food_id": fid, "name": f["display_name"], "suggested": sugg, "why": why, "uses": len(lines_by_food[fid]),
                                    "now_kcal": f["energy_kcal_100g"]}); continue
    k = conf = why_note = None; density = None
    if fid in D.LINK:
        k, why_note = D.LINK[fid]; conf = "agreed_list"
    elif fid in B1:
        k = B1[fid]["ausnut_key"]; g = gate(f, master[k])
        if g and not est and fid not in D.B1_OVERRIDE:
            # R6: the agreed key is right but the numbers wait for a dietitian; fix the link and say so
            op("g3b", "set_food", fid, f"AUSNUT 2023 {k}", expect={"verified": False},
               set={"ausnut_key": k, "afcd_key": k if k in afcd_keys else None,
                    "match_note": f"AUSNUT 2023 {k} {master[k]['food_name'].strip()} (agreed re-point; current numbers are NOT AUSNUT's and fail the gate: {'; '.join(g)})"[:300]})
            op("g3b", "queue", fid, f"AUSNUT 2023 {k}", kind="match", reason="B1 re-point fails the plausibility gate (current numbers may be from another food): " + "; ".join(g),
               suggestion={"ausnut_key": k, "ausnut_name": master[k]["food_name"].strip(), "ausnut": numbers_set(k), "ours": expect_numbers(f)})
            review["queue"].append({"food_id": fid, "name": f["display_name"], "kind": "B1 gate", "reason": "; ".join(g), "uses": len(lines_by_food[fid])}); continue
        conf = "agreed_list"
        why_note = D.B1_OVERRIDE.get(fid) or ("ESTIMATE replaced: " + "; ".join(g) if g else "agreed re-point (B1)")
        # density: only where the food has none, and only if it agrees with any explicit spoon/cup measure
        r = imp_by.get(fid, {}); nd = num(r.get("density_g_ml"))
        if nd and not num(f["density_g_ml"]):
            clash = [(u, c["grams"], round(VOL_ML[u] * nd, 1)) for u, c in convs[fid].items() if u in VOL_ML and abs(VOL_ML[u] * nd - float(c["grams"])) > 0.10 * float(c["grams"])]
            if clash: held_density.append((fid, nd, clash))
            else: density = nd
    elif f.get("afcd_key") in master:
        k = f["afcd_key"]; m = master[k]
        if not head_ok(f["display_name"], m["food_name"]) or not state_ok(f["display_name"], m["food_name"]):
            op("g3b", "queue", fid, f"AUSNUT 2023 {k}", kind="match", reason=f"Exact key held: name/state doesn't match ({m['food_name'].strip()})",
               suggestion={"ausnut_key": k}); review["queue"].append({"food_id": fid, "name": f["display_name"], "kind": "exact key held", "reason": m["food_name"].strip(), "uses": len(lines_by_food[fid])}); continue
        g = gate(f, m)
        if g and not est:
            op("g3b", "queue", fid, f"AUSNUT 2023 {k}", kind="match", reason="Exact key fails the plausibility gate: " + "; ".join(g),
               suggestion={"ausnut_key": k, "ausnut": numbers_set(k), "ours": expect_numbers(f)})
            review["queue"].append({"food_id": fid, "name": f["display_name"], "kind": "exact key gate", "reason": "; ".join(g), "uses": len(lines_by_food[fid])}); continue
        conf = "exact_key"; why_note = "ESTIMATE replaced: " + "; ".join(g) if g else "same key as the food already carried"
    else:
        top = SM.get(fid, [None])[0]
        if top and top["Confidence"] == "High" and state_ok(f["display_name"], top["Candidate AUSNUT name"]) and head_ok(f["display_name"], top["Candidate AUSNUT name"]):
            k = top["Candidate key"]; g = gate(f, master[k])
            if g and not est:
                op("g3b", "queue", fid, f"AUSNUT 2023 {k}", kind="match", reason="High match fails the plausibility gate: " + "; ".join(g),
                   suggestion={"ausnut_key": k, "ausnut": numbers_set(k), "ours": expect_numbers(f)})
                review["queue"].append({"food_id": fid, "name": f["display_name"], "kind": "High gate", "reason": "; ".join(g), "uses": len(lines_by_food[fid])}); continue
            conf = "high_match"; why_note = "ESTIMATE replaced: " + "; ".join(g) if g else "High-confidence name match, same state"
        else:
            cands = [{"key": r["Candidate key"], "name": r["Candidate AUSNUT name"], "confidence": r["Confidence"]} for r in SM.get(fid, [])[:3]]
            op("g3b", "queue", fid, None, kind="match", reason=f"No confident match ({top['Confidence'] if top else 'no candidate'}).", suggestion={"candidates": cands})
            review["queue"].append({"food_id": fid, "name": f["display_name"], "kind": "no confident match", "reason": "; ".join(c["name"] for c in cands), "uses": len(lines_by_food[fid])}); continue
    if k not in master: problem(f"g3b {fid}: key {k} not in AUSNUT"); continue
    s = numbers_set(k)
    s.update({"ausnut_key": k, "match_note": f"AUSNUT 2023 {k} {master[k]['food_name'].strip()} ({conf})",
              "ai_verified": True, "ai_verified_at": "now", "ai_match_confidence": conf, "ai_evidence": evidence(k, why_note)})
    s["afcd_key"] = k if k in afcd_keys else None
    if density: s["density_g_ml"] = density
    # allergen tags the package derived for this food that it doesn't carry yet (added BEFORE the AI write:
    # a tag change clears AI verification). Never removes a tag; never adds a "-free" claim to an existing food.
    for t in imp_tags.get(fid, []):
        if t not in tags_by_food[fid] and tag_kind.get(t) == "allergen":
            op("g3b", "add_tag", fid, f"AUSNUT 2023 {k}", label=t); tags_by_food[fid].add(t)
            review["tags_added"].append({"food_id": fid, "name": f["display_name"], "tag": t, "basis": f"AUSNUT {k} {master[k]['food_name'].strip()}"})
    op("g3b", "set_food", fid, f"AUSNUT 2023 {k}", set=s, expect={"verified": False, **expect_numbers(f)})
    written[fid] = (k, conf, density)
    review["ai_verified"].append({"food_id": fid, "name": f["display_name"], "confidence": conf, "ausnut_key": k, "ausnut_name": master[k]["food_name"].strip(),
                                  "now_kcal": f["energy_kcal_100g"], "new_kcal": master[k]["energy_kcal"], "uses": len(lines_by_food[fid]), "why": why_note})
for fid, nd, clash in held_density:
    review["queue"].append({"food_id": fid, "name": foods[fid]["display_name"], "kind": "density held",
                            "reason": f"AUSNUT density {nd} disagrees with its own spoon/cup measures {clash}", "uses": len(lines_by_food[fid])})

# ===== g3c: measures ================================================================================
final_conv = {k: dict(v) for k, v in convs.items()}      # simulate
final_density = {fid: num(f["density_g_ml"]) for fid, f in foods.items()}
for fid, (k, conf, dens) in written.items():
    if dens: final_density[fid] = dens
def add_conv(batch, fid, unit, grams, estimated, basis, note):
    if unit in final_conv.get(fid, {}): return False
    if unit != re.sub(r"\s+", " ", unit.strip()).lower() or unit in ("g", "gram", "grams", "kg"): problem(f"{fid}: bad unit name {unit!r}"); return False
    if not grams or grams <= 0: problem(f"{fid}: grams {grams} for {unit}"); return False
    op(batch, "add_conversion", fid, note, unit=unit, grams=round(float(grams), 2), estimated=bool(estimated), basis=basis)
    final_conv.setdefault(fid, {})[unit] = {"grams": grams, "estimated": estimated}
    review["measures"].append({"food_id": fid, "unit": unit, "grams": grams, "estimated": estimated, "basis": basis})
    return True
for fid, unit, grams, estimated, basis in D.MEASURES:
    if fid not in foods: problem(f"MEASURES: {fid} missing"); continue
    add_conv("g3c", fid, unit, grams, estimated, basis, basis)
for fid in written:                                        # B1 package measures for re-points that were written
    if fid not in B1: continue
    for c in imp_conv.get(fid, []):
        if c["unit"] in VOL_ML and final_density.get(fid): continue
        add_conv("g3c", fid, c["unit"], num(c["grams"]), False, c["basis"], c["basis"])
# confirm estimated measures AUSNUT agrees with (within 10 %), on foods with a trusted key
for fid, cs in convs.items():
    f = foods.get(fid)
    if not f: continue
    k = (D.VERIFIED_KEY_FIX.get(fid) or (None,))[0] or (B2.get(fid) or {}).get("ausnut_key") or written.get(fid, (None,))[0] or (f.get("afcd_key") if f.get("afcd_key") in master and head_ok(f["display_name"], master[f["afcd_key"]]["food_name"]) else None)
    if not k: continue
    dens = [m for m in measures[k] if m["is_density"] == "1" and not m["descriptor_2"]]
    for unit, c in cs.items():
        if not c["estimated"]: continue
        target, how = None, None
        if unit in VOL_ML and len(dens) == 1:
            target, how = float(dens[0]["gram_amount"]) * VOL_ML[unit], f"density {float(dens[0]['gram_amount']):g} g/mL"
        elif unit in ("small", "medium", "large"):
            sz = [m for m in measures[k] if m["size_word"] == unit and m["is_brand_pack"] == "0"]
            if len(sz) == 1: target, how = float(sz[0]["gram_amount"]), f"measure {sz[0]['measure_id']} {sz[0]['descriptor_1']} {unit}"
        if target and abs(float(c["grams"]) - target) <= 0.10 * target:
            op("g3c", "confirm_conversion", fid, f"AUSNUT 2023 {k}", unit=unit, ausnut_grams=round(target, 2), basis=f"AUSNUT 2023 {k} {how}")
            final_conv[fid][unit] = {"grams": c["grams"], "estimated": False}
            review["confirmed_estimates"].append({"food_id": fid, "unit": unit, "grams": c["grams"], "ausnut_grams": round(target, 2), "basis": how})
for fid, unit in D.DEFAULT_SIZE.items():
    if unit not in final_conv.get(fid, {}): problem(f"DEFAULT_SIZE {fid}: no {unit!r} measure"); continue
    if "each" in final_conv.get(fid, {}): problem(f"DEFAULT_SIZE {fid}: already has each"); continue
    op("g3c", "set_default_size", fid, f"each = {unit}", unit=unit)
    final_conv[fid]["each"] = final_conv[fid][unit]
for fid, unit, ag, basis in D.CONFIRM_MEASURES:
    c = convs.get(fid, {}).get(unit)
    if not c or not c["estimated"] or abs(float(c["grams"]) - ag) > 0.10 * ag: problem(f"CONFIRM {fid} {unit}: {c}"); continue
    op("g3c", "confirm_conversion", fid, basis, unit=unit, ausnut_grams=ag, basis=basis)
    final_conv[fid][unit] = {"grams": c["grams"], "estimated": False}
    review["confirmed_estimates"].append({"food_id": fid, "unit": unit, "grams": c["grams"], "ausnut_grams": ag, "basis": basis})
for fid, unit, old_g, new_g, estimated, basis in D.MEASURE_FIXES:
    c = convs.get(fid, {}).get(unit)
    if fid in gone_ids or not c: problem(f"MEASURE_FIX {fid} {unit}: food gone or no such measure"); continue
    if float(c["grams"]) != old_g or not c["estimated"]: problem(f"MEASURE_FIX {fid} {unit}: now {c['grams']} g estimated={c['estimated']}"); continue
    if unit == "each" and foods[fid]["default_size"]: problem(f"MEASURE_FIX {fid}: each follows the default size"); continue
    op("g3c", "fix_conversion", fid, basis, unit=unit, expect_grams=old_g, grams=new_g, estimated=estimated, basis=basis)
    final_conv[fid][unit] = {"grams": new_g, "estimated": estimated}
    review["measure_fixes"].append({"food_id": fid, "unit": unit, "was_g": old_g, "now_g": new_g, "estimated": estimated, "basis": basis,
                                    "lines": len([l for l in lines_by_food[fid] if l["unit"] == unit])})
for fx in D.LINE_FIXES:
    rid = recipe(fx["recipe_title"])["id"] if fx.get("recipe_title") else None
    hit = [l for l in lines if l["food_id"] == fx["food_id"] and float(l["quantity"]) == fx["match_quantity"] and l["unit"] == fx["match_unit"]
           and fx["match_prep"] in (l.get("prep_note") or "") and (rid is None or l["recipe_id"] == rid)]
    if len(hit) != 1: problem(f"LINE_FIX {fx['food_id']}: matched {len(hit)} lines"); continue
    l = hit[0]
    op("g3c", "update_line", fx["food_id"], fx["why"], line_id=l["id"], expect_food=l["food_id"], expect_quantity=l["quantity"], expect_unit=l["unit"], set=fx["set"])
    l["quantity"], l["unit"] = fx["set"]["quantity"], fx["set"]["unit"]
    review["recipes"].append({"recipe": recipes[l["recipe_id"]]["title"], "change": f"{fx['food_id']}: {fx['match_quantity']:g} {fx['match_unit']} → {fx['set']['quantity']:g} {fx['set']['unit']}", "why": fx["why"]})

# ===== g3d: fills ===================================================================================
for fid, aisle in D.AISLE_FIX.items():
    f = foods.get(fid)
    if not f or fid in D.DELETE_UNUSED: continue
    if f["aisle"] == aisle: continue
    op("g3d", "set_food", fid, "aisle correction", set={"aisle": aisle}, expect={"aisle": f["aisle"]})
    review["fills"].append({"food_id": fid, "name": f["display_name"], "field": "aisle", "old": f["aisle"], "new": aisle})
PF_RULES = [("kangaroo", r"\bkangaroo"), ("turkey", r"\bturkey"), ("chicken", r"\bchicken(?! stock| salt)"), ("lamb", r"\blamb\b"),
            ("pork", r"\bpork|\bham\b|prosciutto|bacon|chorizo|pancetta|salami"), ("beef", r"\bbeef|\bsteak|\bveal|\bbrisket|\bmince\b"),
            ("seafood", r"\bprawn|shrimp|scallop|calamari|squid|octopus|mussel|\boyster(?! sauce| mushroom)|\bcrab|lobster|\bclam"),
            ("fish", r"\bfish(?! sauce)|salmon|tuna|barramundi|snapper|\bcod\b|\bbasa\b|sardine|anchov|trout|mackerel|whiting|flathead|\bling\b|\bdory|\bhake|\bbream"),
            ("egg", r"\begg(s)?\b(?! noodle| wrap| pasta)"), ("tofu_tempeh", r"\btofu|tempeh"),
            ("legumes", r"\blentil|chickpea|\bbeans?\b|edamame|split pea|kidney|cannellini|borlotti|adzuki|hummus|falafel"),
            ("dairy", r"cheese|yoghurt|yogurt|\bmilk\b|ricotta|feta|halloumi|haloumi|cottage|bocconcini|mozzarella|parmesan|labneh|quark|skyr|kefir")]
PF_EXCL = re.compile(r"stock|sauce|powder|paste|seasoning|\boil\b|flavour|chocolate|\bbutter\b(?! bean)|cream(?! cheese)|ice cream|coconut milk|almond milk|oat milk|soy milk|rice milk|green bean|jelly bean|vanilla bean|broad bean|bean sprout|spray|stock cube", re.I)
gone = set(B3) | set(D.MERGE) | set(D.DELETE_UNUSED)
for fid, f in sorted(foods.items()):
    if fid in gone or f.get("protein_family"): continue
    if fid in D.PROTEIN_FAMILY_OVERRIDE: fam = D.PROTEIN_FAMILY_OVERRIDE[fid]
    else:
        name = (f["display_name"] + " " + fid.replace("_", " ")).lower(); fam = None
        for key, rx in PF_RULES:
            if re.search(rx, name): fam = key; break
        if fam and PF_EXCL.search(name) and not (fam == "legumes" and "butter bean" in name): fam = None
    if not fam: continue
    if fam not in families: problem(f"protein family {fam} unknown"); continue
    op("g3d", "set_food", fid, "protein family", set={"protein_family": fam}, expect={"protein_family": None})
    review["fills"].append({"food_id": fid, "name": f["display_name"], "field": "protein_family", "old": "", "new": fam})

# ===== g4a: new foods ===============================================================================
for fid in D.CREATE_FIXES:
    if fid not in imp_by or imp_by[fid]["action"] != "create": problem(f"CREATE_FIX {fid}: not a created food")
created = set()
for r in imp:
    if r["action"] != "create": continue
    fid = r["food_id"]
    if fid in foods: problem(f"create {fid}: already exists"); continue
    k = r["ausnut_key"]
    if k not in master: problem(f"create {fid}: key {k} not in AUSNUT"); continue
    fx = D.CREATE_FIXES.get(fid, {})
    row = {"display_name": r["display_name"], "source": "custom", "verified": False, "aisle": r["aisle"] or None,
           "protein_family": fx["protein_family"] if "protein_family" in fx else (r["protein_family"] or None), "density_g_ml": num(r["density_g_ml"]),
           "match_note": f"AUSNUT 2023 {k} {master[k]['food_name'].strip()} (created from AUSNUT; agreed list)",
           "afcd_key": k if k in afcd_keys else None, "ausnut_key": k}
    row.update(numbers_set(k))
    if row["protein_family"] and row["protein_family"] not in families: problem(f"create {fid}: family {row['protein_family']}")
    role, role_note = suggest_with_note(r["display_name"])
    role = D.NEW_FOOD_ROLE_OVERRIDES.get(fid, role)
    review["roles_new_foods"].append({"food_id": fid, "name": r["display_name"], "suggested_role": role, "needs_decision": role_note or ""})
    if D.NEW_FOOD_ROLES_APPROVED: row["role"] = role
    op("g4a", "insert_food", fid, f"AUSNUT 2023 {k}", row=row)
    created.add(fid); final_conv.setdefault(fid, {}); final_density[fid] = row["density_g_ml"]
    seen = set()
    for c in imp_conv.get(fid, []):
        if c["unit"] in seen: continue                      # rev 3: duplicate rows dropped (feta 'cup')
        if c["unit"] in VOL_ML and row["density_g_ml"]: continue   # density already gives spoons/cups
        seen.add(c["unit"]); add_conv("g4a", fid, c["unit"], num(c["grams"]), False, c["basis"], c["basis"])
    want = [t for t in imp_tags.get(fid, []) if t not in fx.get("drop_tags", [])] + [t for t in fx.get("add_tags", []) if t not in imp_tags.get(fid, [])]
    for t in fx.get("drop_tags", []):
        if t not in imp_tags.get(fid, []): problem(f"CREATE_FIX {fid}: {t} not in the package tags")
    for t in want:
        if t not in tag_kind: problem(f"create {fid}: unknown tag {t!r}")
        op("g4a", "add_tag", fid, f"AUSNUT 2023 {k}", label=t)
    review["new_foods"].append({"food_id": fid, "name": r["display_name"], "ausnut_key": k, "ausnut_name": master[k]["food_name"].strip(),
        "kcal": row["energy_kcal_100g"], "protein": row["protein_100g"], "fat": row["fat_100g"], "carbs": row["carb_avail_100g"], "fibre": row["fibre_100g"],
        "aisle": row["aisle"], "protein_family": row["protein_family"] or "",
        "allergens": "; ".join(t for t in want if tag_kind.get(t) == "allergen"), "diet": "; ".join(t for t in want if tag_kind.get(t) != "allergen"),
        "default_size": r["default_size"] or "", "suggested_role": role, "role_note": role_note or "", "fixed": fx.get("why", "")})
    if fx: review["create_fixes"].append({"food_id": fid, "name": r["display_name"], "change": json.dumps({x: y for x, y in fx.items() if x != "why"}), "why": fx["why"]})
    if r["default_size"]:
        if r["default_size"] not in final_conv[fid]: problem(f"create {fid}: default size {r['default_size']} has no measure")
        else:
            op("g4a", "set_default_size", fid, f"AUSNUT 2023 {k}", unit=r["default_size"]); final_conv[fid]["each"] = final_conv[fid][r["default_size"]]
    if r["purchase_unit"]:
        if r["purchase_unit"] not in final_conv[fid]: problem(f"create {fid}: buy-as {r['purchase_unit']} has no measure")
        else: op("g4a", "set_purchase_unit", fid, f"AUSNUT 2023 {k}", unit=r["purchase_unit"])
    op("g4a", "ai_verify", fid, f"AUSNUT 2023 {k}", ausnut_key=k, confidence="agreed_list",
       evidence=evidence(k, "Created from the agreed AUSNUT import list (21 Oct 2026)."))

# ===== g4b: merges and deletes ======================================================================
def resolvable(fid, unit):
    if unit in ("g", "gram", "grams", "kg", "x95g"): return True
    if unit in VOL_ML and final_density.get(fid): return True
    return unit in final_conv.get(fid, {})
for combo, sp in D.SPLITS.items():
    if combo not in foods: problem(f"SPLIT {combo}: missing"); continue
    parts = sp["parts"]
    for p_fid, _ in parts:
        if p_fid not in foods and p_fid not in created: problem(f"SPLIT {combo}: part {p_fid} missing")
    for l in sorted(lines_by_food.get(combo, []), key=lambda l: (l["recipe_id"], l["position"])):
        rc = recipes[l["recipe_id"]]
        others = {x["food_id"] for x in lines if x["recipe_id"] == l["recipe_id"] and x is not l}
        if all(p in others for p, _ in parts):
            op("g4b", "delete_line", combo, f"split {combo}: recipe already lists each part", line_id=l["id"], expect_food=combo,
               expect_quantity=l["quantity"], expect_unit=l["unit"])
            lines.remove(l)
            review["splits"].append({"food_id": combo, "recipe": rc["title"], "line": f"{float(l['quantity']):g} {l['unit']} {foods[combo]['display_name']}",
                                     "becomes": "removed: the recipe already lists " + " and ".join(p for p, _ in parts), "why": sp["why"]})
            continue
        q = float(l["quantity"])
        for p_fid, fac in parts:
            if not resolvable(p_fid, l["unit"]): problem(f"SPLIT {combo} → {p_fid}: unit {l['unit']!r} won't resolve")
        op("g4b", "split_line", combo, sp["why"], line_id=l["id"], expect_food=combo, expect_quantity=l["quantity"], expect_unit=l["unit"],
           parts=[{"food_id": p_fid, "quantity": round(q * fac, 4)} for p_fid, fac in parts])
        review["splits"].append({"food_id": combo, "recipe": rc["title"], "line": f"{q:g} {l['unit']} {foods[combo]['display_name']}",
                                 "becomes": " + ".join(f"{q * fac:g} {l['unit']} {p_fid}" for p_fid, fac in parts), "why": sp["why"]})
        # simulate: the original line becomes part 1, the others are new lines
        l["food_id"], l["quantity"] = parts[0][0], q * parts[0][1]
        for p_fid, fac in parts[1:]:
            lines.append({**l, "id": None, "food_id": p_fid, "quantity": q * fac, "_orig": None})
    lines_by_food = defaultdict(list)
    for l in lines: lines_by_food[l["food_id"]].append(l)
    if foods[combo]["verified"]:
        review["splits"].append({"food_id": combo, "recipe": "—", "line": foods[combo]["display_name"], "becomes": "food left in the library, now unused (verified: a dietitian deletes it)", "why": ""})
    else:
        op("g4b", "delete_food", combo, "split into separate foods; now unused")
merges = {**B3, **{k: v[0] for k, v in D.MERGE.items()}}
for dup, canon in sorted(merges.items()):
    if dup not in foods: problem(f"merge {dup}: missing"); continue
    if canon not in foods and canon not in created: problem(f"merge {dup}: canonical {canon} missing"); continue
    if foods[dup]["verified"]: problem(f"merge {dup}: verified — dietitian decides"); continue
    for l in lines_by_food[dup]:
        if not resolvable(canon, l["unit"]):
            if l["unit"] in final_conv.get(dup, {}):
                op("g4b", "copy_conversion", dup, f"merge into {canon}", to=canon, unit=l["unit"])
                final_conv.setdefault(canon, {})[l["unit"]] = final_conv[dup][l["unit"]]
            else: problem(f"merge {dup}→{canon}: line unit {l['unit']!r} won't resolve on {canon}")
    why = (D.MERGE.get(dup) or (None, "B3 duplicate"))[1]
    op("g4b", "repoint", dup, f"merged into {canon}", to=canon)
    op("g4b", "delete_food", dup, f"merged into {canon}")
    review["merges_deletes"].append({"food_id": dup, "name": foods[dup]["display_name"], "action": f"merge into {canon}", "why": why, "lines_moved": len(lines_by_food[dup])})
    for l in lines_by_food.get(dup, []): l["food_id"] = canon      # simulate: later ops see the merged state
    lines_by_food[canon].extend(lines_by_food.pop(dup, []))
for fid, why in sorted(D.DELETE_UNUSED.items()):
    if fid not in foods: continue
    if lines_by_food[fid]: problem(f"delete {fid}: still used by {len(lines_by_food[fid])} lines"); continue
    if foods[fid]["verified"]: problem(f"delete {fid}: verified"); continue
    if any(x["food_id"] == fid for x in L("client_food_rules")) or any(fid in (x.get("trigger_food_id"), x.get("suggestion_food_id")) for x in L("swap_suggestions")):
        problem(f"delete {fid}: client rule or swap"); continue
    op("g4b", "delete_food", fid, "unused: " + why)
    review["merges_deletes"].append({"food_id": fid, "name": foods[fid]["display_name"], "action": "delete (unused)", "why": why, "lines_moved": 0})

# ===== g4c: recipes =================================================================================
for x in D.DELETE_LINES:
    rc = recipe(x["recipe_title"])
    hit = [l for l in lines if rc and l["recipe_id"] == rc["id"] and l["food_id"] == x["food_id"] and float(l["quantity"]) == x["quantity"] and l["unit"] == x["unit"]]
    if len(hit) != 1: problem(f"DELETE_LINE {x}: matched {len(hit)} lines"); continue
    l = hit[0]
    op("g4c", "delete_line", x["food_id"], x["why"], line_id=l["id"], expect_food=l["food_id"], expect_quantity=l["quantity"], expect_unit=l["unit"])
    lines.remove(l); lines_by_food[l["food_id"]].remove(l)
    review["recipes"].append({"recipe": rc["title"], "change": f"remove {x['quantity']:g} {x['unit']} {x['food_id']}", "why": x["why"]})
for x in D.RESTORE_LINES:
    rc = recipe(x["recipe_title"])
    if not rc: continue
    if not resolvable(x["food_id"], x["unit"]): problem(f"restore {x['food_id']} {x['unit']}: unit won't resolve")
    op("g4c", "insert_line", x["food_id"], x["why"], recipe_id=rc["id"], quantity=x["quantity"], unit=x["unit"], prep_note=x["prep_note"])
    review["recipes"].append({"recipe": rc["title"], "change": f"add {x['quantity']} {x['unit']} {x['food_id']}", "why": x["why"]})
for x in D.CLEAR_PREP_NOTE:
    rc = recipe(x["recipe_title"])
    hit = [l for l in lines if rc and l["recipe_id"] == rc["id"] and l["food_id"] == x["food_id"] and x["old"] in (l.get("prep_note") or "")]
    if len(hit) != 1: problem(f"prep note {x}: {len(hit)} lines"); continue
    l = hit[0]
    op("g4c", "update_line", x["food_id"], x["why"], line_id=l["id"], expect_food=l["food_id"], expect_quantity=l["quantity"], expect_unit=l["unit"],
       set={"prep_note": (l["prep_note"] or "").replace(x["old"], "").strip(" ,;") or None})
    review["recipes"].append({"recipe": rc["title"], "change": f"{x['food_id']} note: remove '{x['old']}'", "why": x["why"]})
notes = {t.upper(): n for t, n in D.RECIPE_NOTES.items()}
for t in notes: recipe(t)                                     # each title must match exactly one recipe
clear = {t.upper() for t in D.CLEAR_DATA_ISSUE}
for rc in sorted(recipes.values(), key=lambda r: r["title"]):
    di = (rc.get("data_issue") or "").strip(); T = rc["title"].strip().upper(); parts, why = [], []
    if di and T in clear: why.append("old note was informational only (every component present)")
    elif di and "AUSNUT check" not in di: parts.append(di + " | " + D.DATA_ISSUE_APPEND); why.append("old note kept, precise check added (notes were copied across recipes by the import)")
    elif di: parts.append(di)
    if T in notes: parts.append(notes[T]); why.append("method needs ingredients the import lost / import error")
    new = " | ".join(parts) or None
    if new == (di or None): continue
    op("g4c", "set_recipe_issue", None, "data issue: " + "; ".join(why), recipe_id=rc["id"], expect_issue=rc["data_issue"], data_issue=new)
    review["recipes"].append({"recipe": rc["title"], "change": "data issue cleared" if new is None else "data issue set/updated", "why": "; ".join(why)})
for t, fid, cur, sugg in D.LINE_PROPOSALS:
    rc = recipe(t)
    if rc and not any(l["recipe_id"] == rc["id"] and l["food_id"] == fid for l in lines): problem(f"LINE_PROPOSAL {t} / {fid}: no such line")
    review["line_proposals"].append({"recipe": t, "food_id": fid, "now": cur, "suggested": sugg})

# ===== simulate: what stays uncalculable after everything ===========================================
residual = Counter()
for fid, ls in lines_by_food.items():
    for l in ls:
        if not resolvable(fid, l["unit"]): residual[(fid, l["unit"])] += 1
for (fid, unit), n in residual.most_common():
    review["still_uncalculable"].append({"food_id": fid, "unit": unit, "lines": n})
# grams per line after everything (the engine's rules: g/kg, x95g, density for spoons/cups/ml, else an exact measure)
UNIT_G = {"g": 1, "gram": 1, "grams": 1, "kg": 1000, "x95g": 95}
def line_g(l):
    fid, u, q = l["food_id"], l["unit"], float(l["quantity"])
    if u in UNIT_G: return q * UNIT_G[u]
    if u in VOL_ML and final_density.get(fid): return q * VOL_ML[u] * final_density[fid]
    c = final_conv.get(fid, {}).get(u)
    return q * float(c["grams"]) if c else None
orig_density = {fid: num(f["density_g_ml"]) for fid, f in foods.items()}
def line_g_before(l):
    if l["_orig"] is None: return None                # a line the split adds
    fid, u, q = l["_orig"]
    if u in UNIT_G: return q * UNIT_G[u]
    if u in VOL_ML and orig_density.get(fid): return q * VOL_ML[u] * orig_density[fid]
    c = convs.get(fid, {}).get(u)
    return q * float(c["grams"]) if c else None
tot = Counter()
for l in lines:
    b, a = line_g_before(l), line_g(l)
    if b is None and a is not None:
        review["newly_calculable"].append({"recipe": recipes[l["recipe_id"]]["title"], "line": f"{float(l['quantity']):g} {l['unit']} {l['food_id']}",
                                           "prep_note": l.get("prep_note") or "", "grams": round(a, 1)})
    elif b is not None and a is not None and abs(a - b) > max(5, 0.10 * b):
        review["grams_changed"].append({"recipe": recipes[l["recipe_id"]]["title"], "line": f"{float(l['quantity']):g} {l['unit']} {l['food_id']}",
                                        "before_g": round(b, 1), "after_g": round(a, 1)})
    g = line_g(l)
    if g is None: continue
    tot[l["recipe_id"]] += g
    if g >= 500: review["big_lines_after"].append({"recipe": recipes[l["recipe_id"]]["title"], "line": f"{float(l['quantity']):g} {l['unit']} {l['food_id']}", "grams": round(g)})
review["big_lines_after"].sort(key=lambda r: -r["grams"])
for rid, g in tot.most_common(15):
    review["heaviest_recipes_after"].append({"recipe": recipes[rid]["title"], "servings": None, "total_g": round(g)})

# ===== projection: recipe status after every batch (same rules as recipe_verification) ===============
rv = {r["recipe_id"]: r for r in L("recipe_verification")}
ai_ok = {o["food_id"] for b in ("g3a", "g4a") for o in batches[b] if o["op"] == "ai_verify"} | set(written)
lost = {fid for fid, (tg, _) in D.ALLERGEN_ADD.items() if foods.get(fid, {}).get("verified")} | {fid for fid in D.TAG_REMOVE if foods[fid]["verified"]} \
     | {fid for fid in D.URGENT_VERIFIED if foods[fid]["verified"]}
def food_ok(fid):
    if fid in created: return True
    f = foods.get(fid)
    return bool(f) and ((f["verified"] and fid not in lost) or fid in ai_ok)
def estimated(l):
    fid, u = l["food_id"], l["unit"]
    if u in UNIT_G or (u in VOL_ML and final_density.get(fid)): return False
    c = final_conv.get(fid, {}).get(u)
    return bool(c and c["estimated"])
final_issue = {rc["id"]: (rc.get("data_issue") or "").strip() or None for rc in recipes.values()}
for o in batches["g4c"]:
    if o["op"] == "set_recipe_issue": final_issue[o["args"]["recipe_id"]] = o["args"]["data_issue"]
by_recipe = defaultdict(list)
for l in lines: by_recipe[l["recipe_id"]].append(l)
before = Counter(r["status"] for r in rv.values()); after = Counter(); blockers = Counter(); one_away = Counter()
for rid, rc in recipes.items():
    v = rv.get(rid, {}); ls = by_recipe[rid]
    unv = sorted({l["food_id"] for l in ls if not food_ok(l["food_id"])})
    unc = [l for l in ls if not resolvable(l["food_id"], l["unit"])]
    est = [l for l in ls if resolvable(l["food_id"], l["unit"]) and estimated(l)]
    other = [x for x in (not v.get("has_title", True) and "no title", not v.get("has_image") and "no image", not ls and "no ingredients",
                         not v.get("step_count") and "no method steps", final_issue[rid] and "data issue") if x]
    st = "ready (AI verified)" if not (unv or unc or est or other) else "needs review"
    after[st] += 1
    if not (unc or est or other):
        for fid in unv: blockers[fid] += 1
        if len(unv) == 1: one_away[unv[0]] += 1
    review["recipes_after"].append({"recipe": rc["title"], "before": v.get("status"), "after": st, "unverified_foods": "; ".join(unv),
                                    "uncalculable": "; ".join(f"{l['food_id']} ({l['unit']})" for l in unc),
                                    "estimated": "; ".join(f"{l['food_id']} ({l['unit']})" for l in est), "other": "; ".join(other)})
for fid, n in blockers.most_common(25):
    review["top_blockers_after"].append({"food_id": fid, "name": (foods.get(fid) or {}).get("display_name"), "recipes_blocked": n,
                                         "recipes_it_alone_blocks": one_away[fid], "verified_now": (foods.get(fid) or {}).get("verified")})
# self-check: the same rules on TODAY's data must reproduce the live view exactly
def ok_before(l):
    fid, u, q = l["_orig"]
    if u in UNIT_G: return True, False
    if u in VOL_ML and orig_density.get(fid): return True, False
    c = convs.get(fid, {}).get(u)
    return (bool(c), bool(c and c["estimated"]))
orig_lines = defaultdict(list)
for l in lines_at_start: orig_lines[l["recipe_id"]].append(l)
mismatch = []
for rid, rc in recipes.items():
    v = rv.get(rid, {}); ls = orig_lines[rid]
    bad = any(not foods.get(l["_orig"][0], {}).get("verified") for l in ls) or any(not ok_before(l)[0] or ok_before(l)[1] for l in ls) \
          or not v.get("has_title", True) or not v.get("has_image") or not ls or not v.get("step_count") or (rc.get("data_issue") or "").strip()
    if ("needs_review" if bad else "ai_verified") != v.get("status"): mismatch.append(rc["title"])
if mismatch: problem(f"projection self-check: {len(mismatch)} recipes disagree with the live view, e.g. {mismatch[:5]}")
projection = {"before": dict(before), "after": dict(after), "self_check_mismatches": len(mismatch)}

# ===== consistency: an allergen tag and its "-free" claim never on the same food ====================
CLASH = [("Dairy", "Dairy-free"), ("Gluten", "Gluten-free"), ("Tree nuts", "Nut-free"), ("Peanuts", "Nut-free"), ("Meat", "Vegetarian"),
         ("Fish", "Vegetarian"), ("Shellfish", "Vegetarian"), ("Dairy", "Vegan"), ("Egg", "Vegan"), ("Honey", "Vegan"), ("Meat", "Vegan")]
final_tags = defaultdict(set, {k: set(v) for k, v in tags_by_food.items()})
for b in ("g3b", "g4a"):
    for o in batches[b]:
        if o["op"] == "add_tag": final_tags[o["food_id"]].add(o["args"]["label"])
for fid, ts in final_tags.items():
    for a, c in CLASH:
        if a in ts and c in ts and fid not in gone_ids:
            review["tag_conflicts"].append({"food_id": fid, "name": (foods.get(fid) or imp_by.get(fid) or {}).get("display_name"), "has": f"{a} + {c}",
                                            "existing_food": fid in foods})

# ---------------------------------------------------------------------------------------- write
if problems:
    print("PROBLEMS — changeset not written:"); [print("  -", p) for p in problems]; sys.exit(1)
os.makedirs(REV, exist_ok=True)
for b, rows in sorted(batches.items()):
    with open(os.path.join(OUT, f"{b}.jsonl"), "w") as fh:
        for r in rows: fh.write(json.dumps({"batch": b, **r}, ensure_ascii=False, default=float) + "\n")
for name, rows in review.items():
    keys = list(dict.fromkeys(k for r in rows for k in r))
    with open(os.path.join(REV, f"{name}.csv"), "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=keys); w.writeheader(); w.writerows(rows)
summary = {b: dict(Counter(r["op"] for r in rows)) for b, rows in sorted(batches.items())}
summary["_counts"] = {"verified_checked": checked, "verified_flagged": flagged, "unverified_ai_verified": len(written),
                      "created": len(created), "merged": len(merges), "deleted_unused": len(D.DELETE_UNUSED),
                      "still_uncalculable_lines": sum(residual.values()), "density_held": len(held_density), "recipes": projection}
json.dump(summary, open(os.path.join(OUT, "summary.json"), "w"), indent=2)
print(json.dumps(summary, indent=2))
