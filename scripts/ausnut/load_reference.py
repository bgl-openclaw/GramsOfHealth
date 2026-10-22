"""AUSNUT G1 — load the read-only AUSNUT 2023 reference tables (after migrations 0041 + 0042).

Usage: python3 -I scripts/ausnut/load_reference.py [--check]
  --check   parse and validate the CSVs only; write nothing.
Source: seed/ausnut2023/reference/{ausnut_classifications,ausnut_master,ausnut_measures}.csv
Idempotent (upsert on the primary key). Measures whose food key isn't in the master file are skipped
and listed (AUSNUT ships 14 such rows).
"""
import csv
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
REF = os.path.join(REPO, "seed", "ausnut2023", "reference")
CHECK = "--check" in sys.argv

NUMERIC_MASTER = ["specific_gravity", "energy_kj", "energy_kcal", "protein_g", "fat_g", "carb_avail_with_sa_g",
                  "carb_avail_without_sa_g", "sugars_g", "fibre_g", "satfat_g", "sodium_mg", "potassium_mg", "calcium_mg",
                  "iron_mg", "zinc_mg", "magnesium_mg", "folate_dfe_ug", "folate_total_ug", "vitamin_b12_ug"]


def read(name):
    with open(os.path.join(REF, name + ".csv"), newline="", encoding="utf-8-sig") as fh:
        return list(csv.DictReader(fh))


def num(v, field, key):
    if v is None or v.strip() == "":
        return None
    try:
        return float(v)
    except ValueError:
        raise SystemExit(f"{key}: {field} is not a number: {v!r}")


def text(v):
    v = (v or "").strip()
    return v or None


classes = [{"code": r["code"].strip(), "group_name": r["group_name"].strip(), "level": int(r["level"])}
           for r in read("ausnut_classifications")]

master = []
for r in read("ausnut_master"):
    k = r["public_food_key"].strip()
    row = {"public_food_key": k, "survey_id": r["survey_id"].strip(), "food_name": r["food_name"].strip(),
           "derivation": text(r["derivation"]), "classification_code": text(r["classification_code"]),
           "classification_name": text(r["classification_name"]), "edible_portion": text(r["edible_portion"]),
           "discretionary": {"Discretionary": True, "Non-Discretionary": False}.get(r["discretionary"].strip()),
           "description": text(r["description"])}
    for f in NUMERIC_MASTER:
        row[f] = num(r[f], f, k)
    master.append(row)
keys = {m["public_food_key"] for m in master}

measures, orphans = [], []
for r in read("ausnut_measures"):
    k = r["public_food_key"].strip()
    if k not in keys:
        orphans.append((k, r["measure_id"]))
        continue
    measures.append({"measure_id": int(r["measure_id"]), "public_food_key": k, "quantity": num(r["quantity"], "quantity", k),
                     "descriptor_1": text(r["descriptor_1"]), "descriptor_2": text(r["descriptor_2"]),
                     "descriptor_3": text(r["descriptor_3"]), "descriptor_4_brand": text(r["descriptor_4_brand"]),
                     "gram_amount": num(r["gram_amount"], "gram_amount", k), "volume_ml": num(r["volume_ml"], "volume_ml", k),
                     "is_density": r["is_density"].strip() == "1", "is_brand_pack": r["is_brand_pack"].strip() == "1",
                     "size_word": text(r["size_word"]), "suggested_unit": text(r["suggested_unit"])})

bad = [m for m in master if m["discretionary"] is None] + [m for m in measures if not m["gram_amount"] or m["gram_amount"] <= 0]
print(f"classifications {len(classes)} | master {len(master)} | measures {len(measures)} (skipped {len(orphans)} with no master row)")
if bad:
    raise SystemExit(f"{len(bad)} rows failed validation, e.g. {bad[:2]}")
if orphans:
    print("  skipped measures:", ", ".join(f"{k}/{m}" for k, m in orphans))
if CHECK:
    print("check only — nothing written")
    sys.exit(0)

from _rest import count, upsert  # noqa: E402  (imported late so --check needs no key)

upsert("ausnut_classifications", classes, "code")
upsert("ausnut_master", master, "public_food_key")
upsert("ausnut_measures", measures, "measure_id")
for t, n in (("ausnut_classifications", len(classes)), ("ausnut_master", len(master)), ("ausnut_measures", len(measures))):
    got = count(t)
    print(f"{t:<24} expected {n:>5}  in database {got:>5}  {'OK' if got == n else 'MISMATCH'}")
