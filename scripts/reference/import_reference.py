"""Load the dietitian reference workbooks into Supabase (migration 0051). Stdlib only.

    python3 scripts/reference/import_reference.py parse <workbook.xlsx> [...]   # read only, no database
    python3 scripts/reference/import_reference.py plan  <workbook.xlsx> [...]   # dry run: what would change
    python3 scripts/reference/import_reference.py apply <workbook.xlsx> [...]   # write it

Workbooks (detected by their tabs):
  marker_ranges_dietitian_decides.xlsx   → clinical_markers, marker_ranges, reference_sources
  meal_plan_logic_dietitian_decides.xlsx → nutrient_reference_values, nutrition_targets, plan_rules,
                                           reference_decisions, reference_sources

Only the reference (green) columns are loaded. Each row gets a row_key and a hash of its reference columns:
  new key            → inserted as 'proposed' (inactive until a dietitian decides)
  same key, same hash → left alone (keeps its decision)
  same key, new hash  → reference updated; previous values kept in previous_ref; a decided row becomes 'changed'
                        (inactive until re-decided), an undecided one stays 'proposed'
  key gone           → retired (kept for history)
Filled-in yellow (decision) cells in a workbook are reported, not imported: decisions are made in the app.
"""
import csv
import datetime
import hashlib
import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
import zipfile
import xml.etree.ElementTree as ET

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
OUT = os.path.join(REPO, "seed", "reference")

# ---------- xlsx (stdlib) ----------
NS = {"m": "http://schemas.openxmlformats.org/spreadsheetml/2006/main",
      "r": "http://schemas.openxmlformats.org/officeDocument/2006/relationships"}


def _col(ref):
    n = 0
    for ch in re.match(r"[A-Z]+", ref).group(0):
        n = n * 26 + ord(ch) - 64
    return n - 1


def read_xlsx(path):
    """{sheet name: [rows as lists of strings]}"""
    z = zipfile.ZipFile(path)
    shared = []
    if "xl/sharedStrings.xml" in z.namelist():
        for si in ET.fromstring(z.read("xl/sharedStrings.xml")).findall("m:si", NS):
            shared.append("".join(t.text or "" for t in si.iter("{%s}t" % NS["m"])))
    rels = {r.get("Id"): r.get("Target") for r in ET.fromstring(z.read("xl/_rels/workbook.xml.rels"))}
    sheets = {}
    for sh in ET.fromstring(z.read("xl/workbook.xml")).find("m:sheets", NS):
        target = rels[sh.get("{%s}id" % NS["r"])].lstrip("/")
        target = target if target.startswith("xl/") else "xl/" + target
        rows = []
        for row in ET.fromstring(z.read(target)).iter("{%s}row" % NS["m"]):
            cells = {}
            for c in row.findall("m:c", NS):
                t, v = c.get("t"), c.find("m:v", NS)
                if t == "s" and v is not None:
                    val = shared[int(v.text)]
                elif t == "inlineStr":
                    val = "".join(x.text or "" for x in c.iter("{%s}t" % NS["m"]))
                else:
                    val = v.text if v is not None and v.text is not None else ""
                cells[_col(c.get("r"))] = val.strip()
            if cells:
                rows.append([cells.get(i, "") for i in range(max(cells) + 1)])
        sheets[sh.get("name")] = rows
    return sheets


def table(rows, first_yellow):
    """Header + records; splits reference (green) columns from decision (yellow) columns."""
    hdr = rows[0]
    cut = hdr.index(first_yellow)
    out = []
    for r in rows[1:]:
        r = r + [""] * (len(hdr) - len(r))
        if not any(x.strip() for x in r[:cut]):
            continue
        rec = dict(zip(hdr, r))
        ref = {h: rec[h] for h in hdr[:cut]}
        yellow = {h: rec[h] for h in hdr[cut:] if rec[h].strip()}
        out.append((rec, ref, yellow))
    return out


# ---------- parsing ----------
UNIT_DAYS = {"d": 1, "wk": 7, "mo": 30.4375, "y": 365.25}


def age_days(text, is_upper):
    """'18 y' → days (inclusive from). Upper ages are exclusive: '<18 y' → 18 y, '69 y' → 70 y. '' → None."""
    s = (text or "").strip()
    if not s:
        return None
    below = s.startswith("<")
    m = re.fullmatch(r"(\d+(?:\.\d+)?)\s*(d|wk|mo|y)", s.lstrip("<").strip())
    if not m:
        raise ValueError(f"age {text!r}")
    n = float(m.group(1)) + (1 if is_upper and not below else 0)
    return round(n * UNIT_DAYS[m.group(2)])


NUM = re.compile(r"-?\d+(?:\.\d+)?")


def plain_number(text):
    s = (text or "").replace(",", "").strip()
    return float(s) if re.fullmatch(r"-?\d+(?:\.\d+)?", s) else None


def limit(text, side):
    """A low or high value: a plain number, or a simple limit (low: '>=7.0', high: '<4.0'); else None."""
    s = (text or "").replace(",", "").strip()
    if not s:
        return None
    if plain_number(s) is not None:
        return plain_number(s)
    m = re.match(r"^(<=|>=|≤|≥|<|>)\s*(-?\d+(?:\.\d+)?)", s)
    if m and ((side == "low" and m.group(1) in (">", ">=", "≥")) or (side == "high" and m.group(1) in ("<", "<=", "≤"))):
        return float(m.group(2))
    return None


SEX = {"any": "any", "male": "male", "female": "female"}


def sex(text):
    v = SEX.get((text or "").strip().lower())
    if not v:
        raise ValueError(f"sex {text!r}")
    return v


def h(ref):
    return hashlib.md5(json.dumps(ref, sort_keys=True, ensure_ascii=False).encode()).hexdigest()


def keyed(rows, base):
    """row_key = base(row); exact duplicates get #2, #3 … in sheet order."""
    seen, out = {}, []
    for item in rows:
        k = base(item)
        seen[k] = seen.get(k, 0) + 1
        out.append((k if seen[k] == 1 else f"{k}#{seen[k]}", item))
    return out


# ---------- workbook → table rows ----------
def marker_workbook(sheets, notes):
    t = {"clinical_markers": [], "marker_ranges": [], "reference_sources": []}
    filled = []
    md = table(sheets["Marker decisions"], "Track this marker? (Y/N)")
    for pos, (rec, ref, yellow) in enumerate(md):
        ref = {k: v for k, v in ref.items() if k != "Rows on Ranges by age"}   # a count, changes with the ranges
        code = rec["Marker code"].strip()
        t["clinical_markers"].append({"row_key": code, "code": code, "name": rec["Marker"], "unit": rec["Unit"] or None,
                                      "category": "bloods", "position": pos, "ref": ref, "content_hash": h(ref)})
        if yellow:
            filled.append(("Marker decisions", code, yellow))
    codes = {m["code"] for m in t["clinical_markers"]}
    rg = table(sheets["Ranges by age"], "Agree? (Y / N / Edit)")
    base = lambda it: "|".join([it[0]["Marker code"], it[0]["Population"], it[0]["Sex"], it[0]["Age from"],
                                it[0]["Age to"], it[0]["Pregnancy"], it[0]["Range type"], it[0]["Source"]])
    for pos, (key, (rec, ref, yellow)) in enumerate(keyed(rg, base)):
        if rec["Marker code"] not in codes:
            raise SystemExit(f"Ranges by age row {pos + 2}: marker {rec['Marker code']!r} isn't on Marker decisions")
        lo, hi = limit(rec["Low"], "low"), limit(rec["High"], "high")
        for side, txt, val in (("Low", rec["Low"], lo), ("High", rec["High"], hi)):
            if txt and (val is None or plain_number(txt) is None):
                notes.append(["marker_ranges", key, side, txt, "" if val is None else val,
                              "not a plain number: kept as printed" + ("" if val is None else "; read as a limit")])
        t["marker_ranges"].append({
            "row_key": key, "marker_code": rec["Marker code"], "position": pos, "population": rec["Population"],
            "sex": sex(rec["Sex"]), "age_from_days": age_days(rec["Age from"], False), "age_to_days": age_days(rec["Age to"], True),
            "pregnancy": rec["Pregnancy"].strip().lower() == "yes", "unit": rec["Unit"] or None, "range_type": rec["Range type"],
            "low": lo, "high": hi, "low_text": rec["Low"] or None, "high_text": rec["High"] or None,
            "is_gap": rec["Range type"].lower().startswith("gap"), "is_comparator": rec["Range type"].lower().startswith("comparator"),
            "ref": ref, "content_hash": h(ref)})
        if yellow:
            filled.append(("Ranges by age", key, yellow))
    t["reference_sources"] = sources(sheets["Sources"], "marker_ranges")
    return t, filled


NRV_STATUS = {"general": "general", "pregnancy": "pregnancy", "lactation": "lactation"}


def plan_workbook(sheets, notes):
    t = {"nutrient_reference_values": [], "nutrition_targets": [], "plan_rules": [], "reference_decisions": [], "reference_sources": []}
    filled = []
    nr = table(sheets["NRVs"], "Agree? (Y / N / Edit)")
    base = lambda it: "|".join([it[0]["Nutrient code"], it[0]["Life stage"], it[0]["Sex"], it[0]["Status"]])
    for pos, (key, (rec, ref, yellow)) in enumerate(keyed(nr, base)):
        vals = {}
        for col, name in (("EAR", "ear"), ("RDI", "rdi"), ("AI", "ai"), ("UL", "ul"), ("SDT (adults)", "sdt")):
            vals[name] = plain_number(rec[col])
            if rec[col] and vals[name] is None:
                notes.append(["nutrient_reference_values", key, col, rec[col], "", "not a number: kept as printed"])
        food = rec["Food library column"].strip()
        t["nutrient_reference_values"].append({
            "row_key": key, "nutrient_code": rec["Nutrient code"], "nutrient": rec["Nutrient"], "position": pos, "unit": rec["Unit"] or None,
            "food_column": None if not food or food.startswith("(") else food, "life_stage": rec["Life stage"], "sex": sex(rec["Sex"]),
            "age_from_days": age_days(rec["Age from"], False), "age_to_days": age_days(rec["Age to"], True),
            "status": NRV_STATUS[rec["Status"].strip().lower()], **vals, "ul_applies_to": rec["UL applies to"] or None,
            "ref": ref, "content_hash": h(ref)})
        if yellow:
            filled.append(("NRVs", key, yellow))
    tg = table(sheets["Targets and ranges"], "Agree? (Y / N / Edit)")
    base = lambda it: "|".join([it[0]["Code"], it[0]["Life stage"], it[0]["Sex"]])
    for pos, (key, (rec, ref, yellow)) in enumerate(keyed(tg, base)):
        lo, hi = plain_number(rec["Lower"]), plain_number(rec["Upper"])
        for col, val in (("Lower", lo), ("Upper", hi)):
            if rec[col] and val is None:
                notes.append(["nutrition_targets", key, col, rec[col], "", "not a number: kept as printed"])
        t["nutrition_targets"].append({"row_key": key, "code": rec["Code"], "what": rec["What"], "position": pos, "unit": rec["Unit"] or None,
                                       "life_stage": rec["Life stage"] or None, "sex": sex(rec["Sex"]), "lower": lo, "upper": hi,
                                       "ref": ref, "content_hash": h(ref)})
        if yellow:
            filled.append(("Targets and ranges", key, yellow))
    pr = table(sheets["Plan rules"], "Use this rule? (Y/N)")
    for pos, (rec, ref, yellow) in enumerate(pr):
        code = rec["Rule code"].strip()
        t["plan_rules"].append({"row_key": code, "code": code, "rule": rec["Rule"], "position": pos, "ref": ref, "content_hash": h(ref)})
        if yellow:
            filled.append(("Plan rules", code, yellow))
    dc = table(sheets["Decisions"], "Decision")
    for pos, (rec, ref, yellow) in enumerate(dc):
        code = rec["#"].strip()
        t["reference_decisions"].append({"row_key": f"meal_plan_logic|{code}", "workbook": "meal_plan_logic", "code": code,
                                         "question": rec["Question"], "position": pos, "ref": ref, "content_hash": h(ref)})
        if yellow:
            filled.append(("Decisions", code, yellow))
    t["reference_sources"] = sources(sheets["Sources"], "meal_plan_logic")
    return t, filled


def sources(rows, workbook):
    out = []
    hdr = rows[0]
    for pos, r in enumerate(rows[1:]):
        r = r + [""] * (len(hdr) - len(r))
        rec = dict(zip(hdr, r))
        short = (rec.get("Short name used") or rec.get("Short name") or "").strip()
        if not short:
            continue
        ref = {"short_name": short, "full_reference": rec.get("Full reference", ""), "link": rec.get("Link", "")}
        out.append({"row_key": f"{workbook}|{short}", "workbook": workbook, "short_name": short,
                    "full_reference": ref["full_reference"] or None, "link": ref["link"] or None, "position": pos,
                    "content_hash": h(ref)})
    return out


# ---------- REST ----------
def _env():
    env = {}
    with open(os.path.join(REPO, ".env")) as fh:
        for line in fh:
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                env[k.strip()] = v.strip().strip('"').strip("'")
    url = env.get("SUPABASE_URL", "").rstrip("/")
    key = env.get("SUPABASE_SECRET_KEY") or env.get("SUPABASE_SERVICE_ROLE_KEY")
    if not url or not key:
        raise SystemExit("Missing SUPABASE_URL and a server key in .env")
    return url, key


def call(method, path, body=None, prefer=None):
    url, key = _env()
    headers = {"apikey": key, "Content-Type": "application/json"}
    if key.startswith("eyJ"):
        headers["Authorization"] = f"Bearer {key}"
    if prefer:
        headers["Prefer"] = prefer
    req = urllib.request.Request(f"{url}/rest/v1/{path}", data=None if body is None else json.dumps(body).encode(),
                                 method=method, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            raw = r.read()
            return json.loads(raw) if raw else None
    except urllib.error.HTTPError as e:
        raise SystemExit(f"{method} {path.split('?')[0]}: HTTP {e.code} {e.read().decode()[:600]}")


def live(tab):
    cols = "row_key,content_hash,retired_at" + ("" if tab == "reference_sources" else ",review_state,ref")
    rows, start = [], 0
    while True:
        chunk = call("GET", f"{tab}?select={cols}&order=row_key&offset={start}&limit=1000")
        rows += chunk
        if len(chunk) < 1000:
            return {r["row_key"]: r for r in rows}
        start += 1000


ORDER = ["reference_sources", "clinical_markers", "marker_ranges", "nutrient_reference_values", "nutrition_targets",
         "plan_rules", "reference_decisions"]


def diff(tab, rows, current, workbook):
    scope = {k: v for k, v in current.items()
             if tab not in ("reference_sources", "reference_decisions") or k.startswith(workbook + "|")}
    new, changed, unchanged, unretire = [], [], [], []
    for r in rows:
        cur = scope.get(r["row_key"])
        if cur is None:
            new.append(r)
        elif cur["content_hash"] != r["content_hash"]:
            changed.append((r, cur))
        else:
            unchanged.append(r)
            if cur["retired_at"]:
                unretire.append(r)
    keys = {r["row_key"] for r in rows}
    retire = [k for k, v in scope.items() if k not in keys and not v["retired_at"]]
    return new, changed, unchanged, unretire, retire


def main():
    if len(sys.argv) < 3 or sys.argv[1] not in ("parse", "plan", "apply"):
        raise SystemExit(__doc__)
    mode, paths = sys.argv[1], sys.argv[2:]
    os.makedirs(OUT, exist_ok=True)
    for path in paths:
        sheets = read_xlsx(path)
        notes = []
        if "Ranges by age" in sheets:
            workbook, (tables, filled) = "marker_ranges", marker_workbook(sheets, notes)
        elif "NRVs" in sheets:
            workbook, (tables, filled) = "meal_plan_logic", plan_workbook(sheets, notes)
        else:
            raise SystemExit(f"{path}: not a reference workbook (no 'Ranges by age' or 'NRVs' tab)")
        with open(os.path.join(OUT, f"{workbook}_parse_notes.csv"), "w", newline="") as fh:
            w = csv.writer(fh)
            w.writerow(["table", "row_key", "column", "as printed", "read as", "note"])
            w.writerows(notes)
        summary = {"file": os.path.basename(path), "tables": {}, "values_kept_as_printed": len(notes),
                   "filled_decision_cells_not_imported": len(filled)}
        print(f"\n{os.path.basename(path)} → {workbook}")
        for tab in ORDER:
            if tab not in tables:
                continue
            rows = tables[tab]
            if mode == "parse":
                print(f"  {tab:28} {len(rows):4} rows")
                continue
            new, changed, unchanged, unretire, retire = diff(tab, rows, live(tab), workbook)
            summary["tables"][tab] = {"rows": len(rows), "new": len(new), "changed": len(changed),
                                      "unchanged": len(unchanged), "retired": len(retire), "unretired": len(unretire)}
            print(f"  {tab:28} {len(rows):4} rows: {len(new)} new, {len(changed)} changed, {len(unchanged)} unchanged, "
                  f"{len(retire)} to retire, {len(unretire)} back from retired")
            if mode != "apply":
                continue
            if new:
                for i in range(0, len(new), 200):
                    call("POST", tab, new[i:i + 200], prefer="return=minimal")
            for r, cur in changed:
                patch = dict(r)
                patch.pop("row_key")
                if tab != "reference_sources":
                    patch["previous_ref"] = cur.get("ref")
                    patch["review_state"] = "changed" if cur["review_state"] in ("decided", "changed") else "proposed"
                patch["retired_at"] = None
                call("PATCH", f"{tab}?row_key=eq.{urllib.parse.quote(r['row_key'], safe='')}", patch, prefer="return=minimal")
                call("POST", "reference_change_log", {"table_name": tab, "row_key": r["row_key"], "field": "reference",
                                                      "old_value": json.dumps(cur.get("ref"), ensure_ascii=False),
                                                      "new_value": json.dumps(r.get("ref"), ensure_ascii=False),
                                                      "reason": f"Workbook {os.path.basename(path)}", "kind": "import"},
                     prefer="return=minimal")
            for r in unretire:
                call("PATCH", f"{tab}?row_key=eq.{urllib.parse.quote(r['row_key'], safe='')}", {"retired_at": None}, prefer="return=minimal")
            for k in retire:
                call("PATCH", f"{tab}?row_key=eq.{urllib.parse.quote(k, safe='')}", {"retired_at": datetime.datetime.now(datetime.timezone.utc).isoformat()}, prefer="return=minimal")
                call("POST", "reference_change_log", {"table_name": tab, "row_key": k, "field": "retired", "new_value": "no longer in the workbook",
                                                      "reason": f"Workbook {os.path.basename(path)}", "kind": "import"}, prefer="return=minimal")
        print(f"  values kept as printed (see seed/reference/{workbook}_parse_notes.csv): {len(notes)}")
        if filled:
            print(f"  NOTE: {len(filled)} rows have filled-in decision (yellow) cells. They were NOT imported; decisions are made in the app.")
        if mode == "apply":
            call("POST", "reference_imports", {"workbook": workbook, "file_name": os.path.basename(path), "summary": summary},
                 prefer="return=minimal")
            print("  applied.")
        else:
            print(f"  ({mode} only: nothing written)")


if __name__ == "__main__":
    main()
