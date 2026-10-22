"""AUSNUT G1 step 0 — snapshot everything G3/G4 can touch, before anything changes (read-only).

Usage: python3 -I scripts/ausnut/snapshot.py [label]
Writes seed/archive/<YYYY-MM-DD>-<label>/<table>.json plus manifest.json (row counts).
"""
import datetime
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _rest import REPO, select_all  # noqa: E402

TABLES = ["foods", "food_tags", "unit_conversions", "ingredient_lines", "client_food_rules",
          "swap_suggestions", "food_unit_exclusions", "recipes"]

label = sys.argv[1] if len(sys.argv) > 1 else "pre-ausnut"
out = os.path.join(REPO, "seed", "archive", f"{datetime.date.today().isoformat()}-{label}")
os.makedirs(out, exist_ok=True)
manifest = {"taken_at": datetime.datetime.now(datetime.timezone.utc).isoformat(), "tables": {}}
for t in TABLES:
    rows = select_all(f"{t}?select=*")
    with open(os.path.join(out, f"{t}.json"), "w") as fh:
        json.dump(rows, fh, ensure_ascii=False, indent=0)
    manifest["tables"][t] = len(rows)
    print(f"{t:<22} {len(rows):>6}")
with open(os.path.join(out, "manifest.json"), "w") as fh:
    json.dump(manifest, fh, indent=2)
print("snapshot:", os.path.relpath(out, REPO))
