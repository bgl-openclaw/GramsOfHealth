"""AUSNUT G3/G4 — upload the built changeset and run it one batch at a time (needs 0041–0043 applied).

  python3 -I scripts/ausnut/apply_changeset.py upload g3a        # replace the batch's PENDING rows with the jsonl
  python3 -I scripts/ausnut/apply_changeset.py dry-run g3a       # run it in a transaction that rolls back; report
  python3 -I scripts/ausnut/apply_changeset.py apply g3a         # the real run (one transaction; any error = nothing applied)

Order: g3a → g3b → g3c → g3d → g4a → g4b → g4c. Always dry-run first and read the skipped rows.
Rebuild (build_changeset.py) right before uploading so the preconditions match the live library.
Reports are saved to seed/ausnut2023/changeset/runs/.
"""
import datetime
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from _rest import delete, rpc, select_all, upsert  # noqa: E402

ORDER = ["g3a", "g3b", "g3c", "g3d", "g4a", "g4b", "g4c"]
CS = os.path.join(os.path.dirname(os.path.dirname(HERE)), "seed", "ausnut2023", "changeset")

if len(sys.argv) != 3 or sys.argv[1] not in ("upload", "dry-run", "apply") or sys.argv[2] not in ORDER:
    raise SystemExit(__doc__)
cmd, batch = sys.argv[1], sys.argv[2]
done = {r["batch"] for r in select_all("ausnut_changeset?select=batch&status=neq.pending")}

if cmd == "upload":
    if batch in done:
        raise SystemExit(f"{batch} has already been (partly) applied — not replacing it.")
    rows = [json.loads(l) for l in open(os.path.join(CS, f"{batch}.jsonl"))]
    delete(f"ausnut_changeset?batch=eq.{batch}&status=eq.pending")
    upsert("ausnut_changeset", [{k: r[k] for k in ("batch", "seq", "op", "food_id", "args", "note")} for r in rows], "batch,seq")
    n = len(select_all(f"ausnut_changeset?select=id&batch=eq.{batch}&status=eq.pending"))
    print(f"{batch}: {n} rows uploaded" + ("" if n == len(rows) else f" — EXPECTED {len(rows)}"))
else:
    if cmd == "apply":
        earlier = [b for b in ORDER[:ORDER.index(batch)] if b not in done]
        if earlier:
            raise SystemExit(f"apply the earlier batches first: {', '.join(earlier)}")
    res = rpc("ausnut_apply_batch", {"p_batch": batch, "p_dry_run": cmd == "dry-run"})
    os.makedirs(os.path.join(CS, "runs"), exist_ok=True)
    out = os.path.join(CS, "runs", f"{datetime.datetime.now():%Y%m%d-%H%M%S}-{batch}-{cmd}.json")
    json.dump(res, open(out, "w"), indent=1)
    skipped = [r for r in res.get("rows", res.get("skipped_rows", [])) if str(r.get("result", "")).startswith("skipped")]
    print(f"{batch} {cmd}: applied {res['applied']}, skipped {res['skipped']} (report: {os.path.relpath(out)})")
    for r in skipped[:60]:
        print(f"  #{r['seq']} {r['op']} {r['food_id']}: {r['result']}")
