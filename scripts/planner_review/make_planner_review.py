"""Build the dietitian's planner set-up review page (HTML) from the review CSVs.

Usage: python3 -I scripts/planner_review/make_planner_review.py <out.html>

Three parts, each signed off on its own:
  1. Planner rules (tolerances, energy shares)   decisions/rule:<id>          {choice, note}
  2. Meal types (every base recipe; variants)    decisions/mt:<recipe_id>     {types, disc, note}   (only when changed)
                                                 decisions/mtv:<recipe_id>    {flagged, note}
  3. Swap groups (+ foods not in a group)        decisions/sw:<group>:<food>  {choice: keep|remove|move:<group>, note}
                                                 decisions/swu:<food>         {choice: leave|add:<group>, note}
Lists: sections/<id> {checked}. Sign-off: signoff/<part>.
A row with no decision doc = the suggestion stands (once its list is checked). Claude reads these back with
ArtifactData before loading meal types (0046) or swap groups.
"""
import csv, html, json, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
OUT = sys.argv[1]

AGREE = [{"v": "agree", "label": "Agree"}, {"v": "change", "label": "Use different numbers"}, {"v": "leave", "label": "Leave for later"}]
RULES = [
    ("energy", "Energy, each day", "Within ±10% of the day-type target is fine; within ±5% is shown as on target.",
     "Mifflin-St Jeor itself is only within about 10% of measured resting energy, so tighter plan precision buys nothing real."),
    ("protein", "Protein, each day", "Never under target; up to +15% over is fine.", "Protein is checked every day; the asymmetry is policy."),
    ("carb_fat", "Carbohydrate and fat, each day", "Within ±10% of target.", ""),
    ("fibre", "Fibre", "Judged on the weekly average against the client's fibre target (shown daily, not judged daily).",
     "Adequate intake 25 g women, 30 g men (NHMRC); 28 g and 38 g shown as a stretch."),
    ("amdr", "Energy split over the week", "Protein 15–25%, fat 20–35%, carbohydrate 45–65% of energy (NHMRC AMDR).",
     "Athletes or deliberate high-protein plans can sit above 25% protein as a recorded choice."),
    ("meal_protein", "Protein at main meals", "Flag (not fail) a lunch or dinner under 0.3 g/kg, or under 20 g for clients 65+.",
     "AND/DC/ACSM 0.3 g/kg per eating occasion; 20–25 g per main meal in older-adult trials."),
    ("treats", "Treats", "About one discretionary serve a day (600 kJ).", "Nutrition Australia convention. Uses the Treat tick in part 2."),
    ("serves", "Serving sizes", "Quarter-serve steps from 0.5 to 2 serves; anything outside 0.75–1.5 is flagged for a look.", ""),
    ("repeats", "Repeats", "No main on consecutive days unless it's a planned leftover; no recipe more than 3 times in 7 days. Each client's own settings override this.", ""),
    ("shares", "Slot energy shares", "Breakfast 25%, lunch 30%, dinner 30%, snacks 15% (split between snack slots). Each client's slots can override.",
     "The owner has agreed these defaults; tell us if you'd use different ones."),
]
OWNER = [
    "Lunch slots also take dinner recipes, so you don't need to tick Lunch on every dinner.",
    "Recipes with a food the client dislikes are left out completely.",
    "Protein rotation counts lunches and dinners; snacks top up the day's protein, carbs and fat.",
    "A plan looks set: one recipe per slot. Alternatives stay behind a Swap button until needed.",
]


def read(p):
    return list(csv.DictReader(open(os.path.join(REPO, p)))) if os.path.exists(os.path.join(REPO, p)) else []


parts, groups_meta = [], []

# ---- part 1: rules
parts.append({"id": "rules", "title": "Planner rules", "intro": "How close a plan has to be before the planner calls it on target. No professional body publishes these for written client plans, so they are practice policy. Agree, or say what you'd use.",
              "sections": [{"id": "rules", "kind": "decide", "title": "Tolerances and defaults", "intro": "", "open": True,
                            "items": [{"key": "rule:" + k, "title": t, "suggestion": s, "why": w, "options": AGREE} for k, t, s, w in RULES]}]})

# ---- part 2: meal types
mt = read("seed/meal_types/meal_types_for_review.csv")
BUCKETS = [("x", "Not a meal (sauces, sides, drinks)"), ("ld", "Lunch and dinner"), ("d", "Dinner"), ("l", "Lunch"),
           ("b", "Breakfast"), ("s", "Snacks and sweets"), ("none", "No suggestion")]
def bucket(r):
    t = {k for k, c in (("breakfast", "Breakfast"), ("lunch", "Lunch"), ("dinner", "Dinner"), ("snack", "Snack"), ("x", "Not a meal")) if r[c]}
    if "x" in t: return "x"
    if {"lunch", "dinner"} <= t: return "ld"
    if "dinner" in t: return "d"
    if "lunch" in t: return "l"
    if "breakfast" in t: return "b"
    if "snack" in t: return "s"
    return "none"
by = {k: [] for k, _ in BUCKETS}
variants = []
for r in mt:
    types = [k for k, c in (("breakfast", "Breakfast"), ("lunch", "Lunch"), ("dinner", "Dinner"), ("snack", "Snack"), ("not_a_meal", "Not a meal")) if r[c]]
    item = {"key": "mt:" + r["recipe_id"], "title": r["Recipe"].title() if r["Recipe"].isupper() else r["Recipe"],
            "ing": r["Main ingredients"], "why": r["Why"], "old": r["Old tag"], "conf": r["Confidence"],
            "types": types, "disc": bool(r["Discretionary"]), "status": r["Recipe status"]}
    if r["Variant of"]:
        variants.append({"key": "mtv:" + r["recipe_id"], "cells": [item["title"], r["Variant of"].title() if r["Variant of"].isupper() else r["Variant of"],
                         ", ".join(t.replace("_", " ") for t in types) or "—"]})
    else:
        by[bucket(r)].append(item)
msecs = [{"id": "mt_" + k, "kind": "mealtypes", "title": f"{t}", "intro": "", "items": sorted(by[k], key=lambda i: i["title"].lower())}
         for k, t in BUCKETS if by[k]]
msecs.append({"id": "mt_variants", "kind": "skim", "title": "Variants (follow their base recipe)",
              "intro": "These are versions of another recipe (a different protein, or FODMAP-friendly). They take the base recipe's meal types. Flag one only if it should differ, and say how.",
              "cols": ["Variant", "Base recipe", "Meal types"], "items": sorted(variants, key=lambda i: i["cells"][0].lower())})
parts.append({"id": "meal_types", "title": "Meal types", "intro": "Which slots each recipe can fill. Every recipe is pre-filled. Change what's wrong, then press \"I've checked this list\" at the foot of each list. Treat marks discretionary foods (about one serve a day).",
              "owner": OWNER, "sections": msecs})

# ---- part 3: swap groups
sw = read("seed/swap_groups/swap_groups_for_review.csv")
order, gnote, rowsby = [], {}, {}
for r in sw:
    k = r["group_key"]
    if k not in rowsby:
        order.append(k); rowsby[k] = []; gnote[k] = (r["Group"], r["Group note"])
    rowsby[k].append(r)
groups_meta = [{"key": k, "title": gnote[k][0]} for k in order]
def fmt(x):
    try:
        v = float(x); return f"{v:,.0f}" if abs(v) >= 100 else f"{v:g}"
    except (TypeError, ValueError):
        return ""
ssecs = []
for k in order:
    items = []
    for r in rowsby[k]:
        items.append({"key": f"sw:{k}:{r['food_id']}", "food": r["Food"], "kcal": fmt(r["kcal /100 g"]), "p": fmt(r["Protein"]), "f": fmt(r["Fat"]),
                      "c": fmt(r["Carbs"]), "allergens": r["Allergens"], "check": r["Value check"], "status": r["Status"],
                      "cross": r["Cross-role"], "uses": r["Used in recipes"]})
    ssecs.append({"id": "sw_" + k, "group": k, "kind": "swaps", "title": gnote[k][0], "intro": gnote[k][1], "items": items})
un = read("seed/swap_groups/not_in_a_group.csv")
ssecs.append({"id": "sw_unplaced", "kind": "unplaced", "title": "Foods not in any group",
              "intro": "Adjustable foods the draft didn't place. Leave them out unless they should swap with a group.",
              "items": [{"key": "swu:" + r["food_id"], "food": r["Food"], "role": r["Role"].replace("adjustable_", ""), "status": r["Status"], "uses": r["Used in recipes"]} for r in un]})
nflag = len({i["key"].split(":", 2)[2] for s in ssecs if s["kind"] == "swaps" for i in s["items"] if i["check"]})
parts.append({"id": "swaps", "title": "Swap groups", "intro": f"Foods that can replace each other gram for gram in a recipe line, for suggestions like \"swap beef mince for chicken mince: fat −9 g\". The planner only suggests swaps inside a group, and every suggestion still goes through the client's allergy and dislike screen. {nflag} foods have values that look wrong (shaded): note what's wrong if you know.",
              "sections": ssecs})

data = {"parts": parts, "groups": groups_meta,
        "meta": {"recipes": len(mt), "base": len(mt) - len(variants), "variants": len(variants), "groups": len(order), "swap_rows": len(sw), "flagged": nflag}}
tpl = open(os.path.join(HERE, "planner_review_template.html")).read()
page = tpl.replace("/*DATA*/", json.dumps(data, ensure_ascii=False).replace("</", "<\\/"))
open(OUT, "w").write(page)
print(f"{sum(len(s['items']) for p in parts for s in p['sections'])} rows in {sum(len(p['sections']) for p in parts)} lists, {len(page):,} bytes → {OUT}")
