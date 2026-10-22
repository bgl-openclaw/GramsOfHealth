"""Tiny Supabase REST helper for the AUSNUT scripts (stdlib only).

Reads SUPABASE_URL and a server key from the repo's .env: SUPABASE_SECRET_KEY (new sb_secret_… key)
if present, else SUPABASE_SERVICE_ROLE_KEY. Server-side only — never ship these keys to the app.
"""
import json
import os
import urllib.error
import urllib.request

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def _env():
    env = {}
    with open(os.path.join(REPO, ".env")) as fh:
        for line in fh:
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                env[k.strip()] = v.strip().strip('"').strip("'")
    url = env.get("SUPABASE_URL", "").rstrip("/")
    key = env.get("SUPABASE_SECRET_KEY") or env.get("SUPABASE_SERVICE_ROLE_KEY") or env.get("SUPABASE_SERVICE_KEY")
    if not url or not key:
        raise SystemExit("Missing SUPABASE_URL and a server key (SUPABASE_SECRET_KEY or SUPABASE_SERVICE_ROLE_KEY) in .env")
    return url, key


URL, KEY = _env()


def _headers(extra=None):
    h = {"apikey": KEY, "Content-Type": "application/json"}
    if KEY.startswith("eyJ"):  # legacy JWT service key; new sb_secret_ keys go in apikey only
        h["Authorization"] = f"Bearer {KEY}"
    h.update(extra or {})
    return h


def select_all(path, page=1000):
    """GET every row of a table/view path such as 'foods?select=*', paging with Range."""
    rows, start = [], 0
    while True:
        req = urllib.request.Request(f"{URL}/rest/v1/{path}", headers=_headers({"Range-Unit": "items", "Range": f"{start}-{start + page - 1}"}))
        with urllib.request.urlopen(req, timeout=120) as r:
            chunk = json.load(r)
        rows += chunk
        if len(chunk) < page:
            return rows
        start += page


def upsert(table, rows, on_conflict, batch=500):
    """POST rows in batches with merge-duplicates (idempotent re-runs)."""
    for i in range(0, len(rows), batch):
        body = json.dumps(rows[i:i + batch]).encode()
        req = urllib.request.Request(f"{URL}/rest/v1/{table}?on_conflict={on_conflict}", data=body, method="POST",
                                     headers=_headers({"Prefer": "resolution=merge-duplicates,return=minimal"}))
        try:
            urllib.request.urlopen(req, timeout=120).read()
        except urllib.error.HTTPError as e:
            raise SystemExit(f"{table} rows {i}-{i + len(rows[i:i + batch]) - 1}: HTTP {e.code} {e.read().decode()[:500]}")


def count(table):
    req = urllib.request.Request(f"{URL}/rest/v1/{table}?select=*", method="HEAD",
                                 headers=_headers({"Prefer": "count=exact", "Range": "0-0"}))
    with urllib.request.urlopen(req, timeout=60) as r:
        return int(r.headers.get("Content-Range", "*/0").split("/")[-1])


def delete(path):
    """DELETE rows matching a filter path such as 'ausnut_changeset?batch=eq.g3a&status=eq.pending'."""
    req = urllib.request.Request(f"{URL}/rest/v1/{path}", method="DELETE", headers=_headers({"Prefer": "return=minimal"}))
    try:
        urllib.request.urlopen(req, timeout=120).read()
    except urllib.error.HTTPError as e:
        raise SystemExit(f"DELETE {path}: HTTP {e.code} {e.read().decode()[:500]}")


def rpc(fn, args, timeout=330):
    """Call a database function through the REST API and return its JSON result."""
    req = urllib.request.Request(f"{URL}/rest/v1/rpc/{fn}", data=json.dumps(args).encode(), method="POST", headers=_headers())
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return json.load(r)
    except urllib.error.HTTPError as e:
        raise SystemExit(f"rpc {fn}: HTTP {e.code} {e.read().decode()[:800]}")
