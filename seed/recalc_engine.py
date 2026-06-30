"""
Grams of Health - recipe macro recalculation engine (seed).
Single source of truth: every macro is computed from grams.
Australian measures: tsp=5 mL, tbsp=20 mL, cup=250 mL.

Reads:  foods.csv, unit_conversions.csv  (same folder)
Usage:  from recalc_engine import Engine
        eng = Engine()
        totals, per_serve, rows = eng.compute(lines, servings)
        # lines = [(food_id, quantity, unit), ...]
"""
import csv, os

AU_VOLUME_ML = {"tsp": 5, "tbsp": 20, "cup": 250, "ml": 1}
MACROS = ("energy_kcal", "protein", "fat", "carb_avail", "fibre")
HERE = os.path.dirname(os.path.abspath(__file__))


class Engine:
    def __init__(self, foods="foods.csv", conv="unit_conversions.csv"):
        self.foods = {}
        with open(os.path.join(HERE, foods)) as fh:
            for r in csv.DictReader(fh):
                self.foods[r["food_id"]] = {
                    "name": r["display_name"],
                    "energy_kcal": float(r["energy_kcal_100g"] or 0),
                    "protein": float(r["protein_100g"] or 0),
                    "fat": float(r["fat_100g"] or 0),
                    "carb_avail": float(r["carb_avail_100g"] or 0),
                    "fibre": float(r["fibre_100g"] or 0),
                    "density": float(r["density_g_ml"]) if r["density_g_ml"] else None,
                }
        self.conv = {}
        with open(os.path.join(HERE, conv)) as fh:
            for r in csv.DictReader(fh):
                self.conv[(r["food_id"], r["unit"])] = float(r["grams"])

    def to_grams(self, food_id, qty, unit):
        """Resolve any quantity+unit to grams for a given food."""
        food = self.foods[food_id]
        if unit in ("g", "gram", "grams"):
            return qty
        if unit == "kg":
            return qty * 1000
        if unit == "x95g":            # fixed-weight pack count
            return qty * 95
        if unit in AU_VOLUME_ML:
            if food["density"]:        # liquids -> via density
                return qty * AU_VOLUME_ML[unit] * food["density"]
            if (food_id, unit) in self.conv:   # solids by volume -> stored grams
                return qty * self.conv[(food_id, unit)]
            raise KeyError(f"need density or unit_conversion for {food_id}/{unit}")
        if (food_id, unit) in self.conv:        # descriptive/count units
            return qty * self.conv[(food_id, unit)]
        raise KeyError(f"no conversion for {food_id}/{unit}")

    def compute(self, lines, servings):
        totals = {m: 0.0 for m in MACROS}
        rows = []
        for food_id, qty, unit in lines:
            g = self.to_grams(food_id, qty, unit)
            food = self.foods[food_id]
            contrib = {m: g / 100 * food[m] for m in MACROS}
            for m in MACROS:
                totals[m] += contrib[m]
            rows.append({"name": food["name"], "qty": qty, "unit": unit,
                         "grams": round(g, 1), **{m: round(contrib[m], 1) for m in MACROS}})
        per_serve = {m: totals[m] / servings for m in MACROS}
        return totals, per_serve, rows

    @staticmethod
    def atwater(per_serve):
        """Internal consistency check: 4/4/9/2 kcal per g of protein/carb/fat/fibre."""
        return (4 * per_serve["protein"] + 4 * per_serve["carb_avail"]
                + 9 * per_serve["fat"] + 2 * per_serve["fibre"])


if __name__ == "__main__":
    import json
    eng = Engine()
    data = json.load(open(os.path.join(HERE, "recipes_validation.json")))
    for rec in data:
        lines = [(l["food_id"], l["quantity"], l["unit"]) for l in rec["ingredients"]]
        _, per, _ = eng.compute(lines, rec["servings"])
        print(f"{rec['title']:42} {per['energy_kcal']:.0f} kcal/serve "
              f"| C {per['carb_avail']:.0f} P {per['protein']:.0f} F {per['fat']:.0f} "
              f"fib {per['fibre']:.1f} | atwater {eng.atwater(per):.0f}")
