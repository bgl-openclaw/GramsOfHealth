"""Build the dietitian review page (HTML) from the changeset review lists.

Usage: python3 -I scripts/ausnut/make_review_page.py <out.html>
Run build_changeset.py first. The page stores each decision in the artifact's own `db`
(collection `decisions`, one document per item; `sections/<id>` for "checked" lists; `signoff/main`),
which Claude reads back and folds into scripts/ausnut/decisions.py before the import runs.
"""
import csv, hashlib, html, json, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
CS = os.path.join(REPO, "seed", "ausnut2023", "changeset")
R = os.path.join(CS, "review")
OUT = sys.argv[1]

def rows(n):
    p = os.path.join(R, n + ".csv")
    return list(csv.DictReader(open(p))) if os.path.exists(p) else []
def h(*parts): return hashlib.md5("|".join(map(str, parts)).encode()).hexdigest()[:10]
def num(x):
    try: return float(x)
    except (TypeError, ValueError): return None
def kcal(x):
    v = num(x)
    return "" if v is None else (f"{v:,.0f}" if v >= 100 else f"{v:g}")

S = json.load(open(os.path.join(CS, "summary.json")))
proj = S["_counts"]["recipes"]
ROLE_LABEL = {"adjustable_protein": "Adjustable protein", "adjustable_carb": "Adjustable carb", "adjustable_fat": "Adjustable fat",
              "bulk_veg": "Bulk veg", "flavour_base": "Flavour base", "structural": "Structural (fixed amount)"}
ROLES = [{"v": k, "label": v} for k, v in ROLE_LABEL.items()]
DEFAULT_OPTS = [{"v": "approve", "label": "Use the suggestion"}, {"v": "change", "label": "Something else"}, {"v": "leave", "label": "Leave for later"}]
sections = []

# ---------------------------------------------------------------- part 1: decide
urg = sorted(rows("urgent_verified"), key=lambda r: -int(r["uses"] or 0))
sections.append({"id": "urgent", "part": 1, "kind": "decide", "title": "Verified foods with wrong numbers",
    "intro": "These carry a dietitian's verified badge but their numbers are impossible or mistyped. The import removes the badge and leaves the numbers for you. Choose what to load instead.",
    "items": [{"key": "urgent:" + r["food_id"], "title": r["name"],
               "meta": f"Now {kcal(r['ours_kcal'])} kcal per 100 g · AUSNUT {kcal(r['ausnut_kcal'])} kcal ({r['ausnut_key']} {r['ausnut_name']}) · in {r['uses']} recipe{'s' if r['uses'] != '1' else ''}",
               "why": r["why"], "suggestion": f"Load the AUSNUT numbers ({r['ausnut_key']})", "options": DEFAULT_OPTS} for r in urg]})

sections.append({"id": "milk", "part": 1, "kind": "decide", "title": "Milk: protein or not?",
    "intro": "You said milk isn't a protein. It won't get a protein family (the label that marks a recipe's main protein). Separately, your library gives every milk the engine role \"adjustable protein\", which lets the adjust-to-targets engine scale milk to hit a protein target. Choose the role for all milks: the 4 in your library, 2 new ones (full cream, buttermilk) and 3 new plant milks.",
    "items": [{"key": "milk:role", "title": "Engine role for milk", "meta": "Milk (reduced fat), skim milk, lactose-free milk, Dairy Farmers protein milk; full cream, buttermilk; soy, almond and oat milk",
               "why": "Milk's nutrition numbers keep their real protein (about 3.4 g per 100 mL); this only changes how the engine treats it.",
               "suggestion": "", "options": [{"v": "adjustable_protein", "label": "Keep adjustable protein"},
                                             {"v": "structural", "label": "Structural (fixed amount)"},
                                             {"v": "adjustable_carb", "label": "Adjustable carb"},
                                             {"v": "change", "label": "Something else"}]}]})

spl = rows("splits")
sections.append({"id": "splits", "part": 1, "kind": "decide", "title": "Combined ingredients split into separate lines",
    "intro": "Salt and pepper (and four other pairs the import glued together) become separate lines. \"Salt & pepper\" was one amount, so it is split half and half. \"1 tbsp each paprika and cumin\" gives each the full amount, which also restores the missing second ingredient. Check the amounts, especially SPANNAKOPTIA's 2 tbsp.",
    "items": [{"key": "split:" + h(r["food_id"], r["recipe"], r["line"], r["becomes"]),
               "title": (r["recipe"].title() if r["recipe"] != "—" else f"{r['line']} (food id {r['food_id']})"),
               "meta": (f"{r['line']}  →  {r['becomes']}" if r["recipe"] != "—" else "Now unused. It's verified, so it is only deleted if you say so."),
               "why": r["why"],
               "suggestion": "",
               "options": ([{"v": "approve", "label": "Split as shown"}, {"v": "change", "label": "Different amounts"}, {"v": "leave", "label": "Leave combined"}]
                           if r["recipe"] != "—" else [{"v": "delete", "label": "Delete it"}, {"v": "keep", "label": "Keep it"}])}
              for r in spl]})

lp = rows("line_proposals")
sections.append({"id": "lines", "part": 1, "kind": "decide", "title": "Recipe lines whose unit looks wrong",
    "intro": "Mostly \"each\" where the recipe means cups. Nothing here is changed unless you approve it.",
    "items": [{"key": "line:" + h(r["recipe"], r["food_id"], r["now"]), "title": r["recipe"].title(),
               "meta": f"{r['food_id'].replace('_', ' ')}: {r['now']}", "why": "", "suggestion": r["suggested"], "options": DEFAULT_OPTS} for r in lp]})

pr = sorted(rows("proposals"), key=lambda r: (-int(r["uses"] or 0), r["name"]))
sections.append({"id": "proposals", "part": 1, "kind": "decide", "title": "Foods I wasn't sure enough to change",
    "intro": "Each has a suggested action. Most are noodles, pasta and couscous whose recipe weight looks dry while AUSNUT only has the cooked food, and curry pastes or stock pots that need label numbers.",
    "items": [{"key": "prop:" + r["food_id"], "title": r["name"],
               "meta": f"Now {kcal(r['now_kcal'])} kcal per 100 g · {r['uses']} recipe line{'s' if r['uses'] != '1' else ''}",
               "why": r["why"], "suggestion": r["suggested"], "options": DEFAULT_OPTS} for r in pr]})

nf = rows("new_foods")
need = [r for r in nf if r["role_note"] and "milk" not in r["role_note"]]
sections.append({"id": "roles_decide", "part": 1, "kind": "role", "title": "Engine role for new foods that need your judgement",
    "intro": "The other new foods follow your team's existing conventions (part 3). These few don't fit neatly. Milks follow your answer above.",
    "items": [{"key": "role:" + r["food_id"], "title": r["name"], "meta": f"{kcal(r['kcal'])} kcal · P {r['protein']} · F {r['fat']} · C {r['carbs']}",
               "why": r["role_note"], "suggested_role": r["suggested_role"], "required": True} for r in need]})

# ---------------------------------------------------------------- part 2: label numbers
lab = sorted([r for r in rows("queue") if r["kind"] == "label"], key=lambda r: (-int(r["uses"] or 0), r["name"]))
sections.append({"id": "labels", "part": 2, "kind": "label", "title": "Label numbers for branded foods",
    "intro": "AUSNUT doesn't have these. If you have the pack, enter the per-100 g values; otherwise leave them for later. They stay unverified until entered.",
    "items": [{"key": "label:" + r["food_id"], "title": r["name"],
               "meta": f"{r['uses']} recipe line{'s' if r['uses'] != '1' else ''}" + (f" · now {kcal(r.get('now_kcal'))} kcal per 100 g" if r.get("now_kcal") else ""),
               "why": r["reason"]} for r in lab]})

# ---------------------------------------------------------------- part 3: check lists
ai = sorted(rows("ai_verified"), key=lambda r: (-int(r["uses"] or 0), r["name"]))
sections.append({"id": "ai_verified", "part": 3, "kind": "skim", "title": "Unverified foods that get AUSNUT numbers",
    "intro": "Each becomes \"AI verified\" with its AUSNUT key. Flag any row where the AUSNUT food isn't the same food.",
    "cols": ["Food", "AUSNUT food", "kcal now → AUSNUT", "Lines"],
    "items": [{"key": "ai:" + r["food_id"], "cells": [r["name"], f"{r['ausnut_key']} {r['ausnut_name']}", f"{kcal(r['now_kcal'])} → {kcal(r['new_kcal'])}", r["uses"]],
               "why": r["why"]} for r in ai]})

nf_rest = [r for r in nf if not r["role_note"]]
sections.append({"id": "new_foods", "part": 3, "kind": "role_skim", "title": "New foods from AUSNUT",
    "intro": "250 foods your recipes don't use yet. The role suggestion matches how your team set roles on 505 of your existing 510 foods. Change any role in the dropdown and flag anything that looks wrong.",
    "cols": ["Food", "kcal · P · F · C per 100 g", "Allergens", "Aisle · protein family", "Role"],
    "items": [{"key": "role:" + r["food_id"], "flag_key": "new:" + r["food_id"],
               "cells": [r["name"], f"{kcal(r['kcal'])} · {r['protein']} · {r['fat']} · {r['carbs']}", r["allergens"] or "none",
                         f"{r['aisle']}" + (f" · {r['protein_family']}" if r["protein_family"] else "")],
               "suggested_role": r["suggested_role"], "why": r["fixed"]} for r in nf_rest]})

tg = [{"key": "tag:" + h("add", r["food_id"], r["tag"]), "cells": [r["name"], f"+ {r['tag']}", r["basis"] + (" (removes the verified badge)" if r.get("removes_dietitian_verification") == "True" else "")]} for r in rows("tags_added")]
tg += [{"key": "tag:" + h("rm", r["food_id"], r["tag"]), "cells": [r["name"], f"− {r['tag']}", r["why"] + (" (removes the verified badge)" if r.get("removes_dietitian_verification") == "True" else "")]} for r in rows("tags_removed")]
tg += [{"key": "tag:" + h("cf", r["food_id"]), "cells": [r["name"] + " (new)", r["change"].replace('"', "").replace("{", "").replace("}", ""), r["why"]]} for r in rows("create_fixes")]
sections.append({"id": "tags", "part": 3, "kind": "skim", "title": "Allergen and diet tag changes",
    "intro": "Missing allergens added, two wrong \"Vegan\" tags removed, and package errors fixed on new foods.", "cols": ["Food", "Change", "Why"], "items": tg})

new_ids = {r["food_id"] for r in nf}
ms = [{"key": "meas:" + h("fix", r["food_id"], r["unit"]), "cells": [r["food_id"].replace("_", " "), f"{r['unit']}: {kcal(r['was_g'])} g → {r['now_g']} g", ("estimate · " if r["estimated"] == "True" else "") + r["basis"]]} for r in rows("measure_fixes")]
ms += [{"key": "meas:" + h("conf", r["food_id"], r["unit"]), "cells": [r["food_id"].replace("_", " "), f"{r['unit']}: {r['grams']} g confirmed", r["basis"]]} for r in rows("confirmed_estimates")]
ms += [{"key": "meas:" + h("add", r["food_id"], r["unit"]), "cells": [r["food_id"].replace("_", " "), f"+ {r['unit']} = {r['grams']} g", ("estimate · " if r["estimated"] == "True" else "") + r["basis"]]}
       for r in rows("measures") if r["food_id"] not in new_ids]
sections.append({"id": "measures", "part": 3, "kind": "skim", "title": "Measures corrected, confirmed or added",
    "intro": "Placeholder weights fixed first (the 100 g \"each\" problem), then estimates AUSNUT confirms, then new measures that make recipe lines calculable. Rows marked \"estimate\" keep their recipes in review until confirmed.",
    "cols": ["Food", "Measure", "Basis"], "items": ms})

fl = rows("fills")
sections.append({"id": "fills", "part": 3, "kind": "skim", "title": "Protein family and shopping aisle",
    "intro": "Protein family marks a recipe's main protein (used for variety and client protein preferences). Milk and mixed products are left without one.",
    "cols": ["Food", "Field", "Change"],
    "items": [{"key": "fill:" + r["food_id"] + "-" + r["field"], "cells": [r["name"], r["field"].replace("_", " "), (f"{r['old']} → " if r["old"] else "") + r["new"].replace("_", " ")]} for r in fl]})

rc = rows("recipes")
sections.append({"id": "recipes", "part": 3, "kind": "skim", "title": "Recipe repairs",
    "intro": "Yield lines removed (the recipe counted as its own ingredient), lost lines restored, and notes that keep incomplete recipes in review.",
    "cols": ["Recipe", "Change", "Why"],
    "items": [{"key": "rec:" + h(r["recipe"], r["change"]), "cells": [r["recipe"].title(), r["change"], r["why"]]} for r in rc]})

# ---------------------------------------------------------------- part 4: after the import (info only)
vf = sorted(rows("verified_flags"), key=lambda r: -int(r.get("uses") or 0))
info = {"verified_flags": len(vf), "verified_flags_used": sum(1 for r in vf if int(r.get("uses") or 0) > 0),
        "top_flags": [{"name": r["name"], "issue": r["issue"], "uses": r.get("uses") or "0"} for r in vf[:12]],
        "checked": len(rows("verified_checked"))}

data = {"meta": {"ready_before": proj["before"]["ai_verified"], "ready_after": proj["after"]["ready (AI verified)"],
                 "total": proj["before"]["ai_verified"] + proj["before"]["needs_review"],
                 "ai_verified": S["_counts"]["unverified_ai_verified"], "created": S["_counts"]["created"]},
        "roles": ROLES, "role_label": ROLE_LABEL, "sections": sections, "info": info}
tpl = open(os.path.join(HERE, "review_page_template.html")).read()
blob = json.dumps(data, ensure_ascii=False).replace("</", "<\\/")
page = tpl.replace("/*DATA*/", blob)
open(OUT, "w").write(page)
n = sum(len(s["items"]) for s in sections)
print(f"{len(sections)} sections, {n} items, {len(page):,} bytes → {OUT}")
