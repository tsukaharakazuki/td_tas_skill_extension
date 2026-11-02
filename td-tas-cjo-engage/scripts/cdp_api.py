#!/usr/bin/env python3
"""Minimal, guarded CDP REST helper for the cases tdx cannot cover (activation PATCH etc.).

Usage:
    python3 cdp_api.py get   <path>                       [--site us01] [--out file.json]
    python3 cdp_api.py patch <path> --body body.json      [--site us01] [--backup-of <path>] [--execute]
    python3 cdp_api.py put   <path> --body body.json      [--site us01] [--backup-of <path>] [--execute]

Token: $TDX_ACCESS_TOKEN, else the file in $TDX_ACCESS_TOKEN_FILE, else $TD_API_KEY
(sent as "TD1 <key>"). Writes are DRY-RUN unless --execute is given: the script prints
the method, URL and body, saves a GET backup of --backup-of (default: same path) to
./backups/, and exits. Only pass --execute after the user approved the printed request.
Standard library only.
"""
import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.request

HOSTS = {
    "us01": "https://api-cdp.treasuredata.com",
    "jp01": "https://api-cdp.treasuredata.co.jp",
    "eu01": "https://api-cdp.eu01.treasuredata.com",
    "ap02": "https://api-cdp.ap02.treasuredata.com",
    "ap03": "https://api-cdp.ap03.treasuredata.com",
}
CT = "application/vnd.treasuredata.v1+json"


def auth_header():
    tok = os.environ.get("TDX_ACCESS_TOKEN")
    if not tok and os.environ.get("TDX_ACCESS_TOKEN_FILE"):
        with open(os.environ["TDX_ACCESS_TOKEN_FILE"], encoding="utf-8") as f:
            tok = f.read().strip()
    if tok:
        return f"Bearer {tok}"
    key = os.environ.get("TD_API_KEY")
    if key:
        return f"TD1 {key}"
    sys.exit("No credential: set TDX_ACCESS_TOKEN / TDX_ACCESS_TOKEN_FILE / TD_API_KEY")


def call(method, url, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method, headers={
        "Authorization": auth_header(),
        "Content-Type": CT,
        "Accept": CT + ", application/json",
    })
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            raw = r.read()
            return r.status, json.loads(raw) if raw else None
    except urllib.error.HTTPError as e:
        txt = e.read().decode("utf-8", "replace")
        try:
            return e.code, json.loads(txt)
        except ValueError:
            return e.code, {"error": txt[:2000]}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("method", choices=["get", "patch", "put"])
    ap.add_argument("path")
    ap.add_argument("--site", default=os.environ.get("TDX_SITE", "us01"))
    ap.add_argument("--body")
    ap.add_argument("--out")
    ap.add_argument("--backup-of")
    ap.add_argument("--execute", action="store_true")
    a = ap.parse_args()
    base = HOSTS.get(a.site)
    if not base:
        sys.exit(f"unknown site {a.site}; known: {', '.join(HOSTS)}")
    url = base + (a.path if a.path.startswith("/") else "/" + a.path)

    if a.method == "get":
        st, js = call("GET", url)
        text = json.dumps(js, ensure_ascii=False, indent=2)
        if a.out:
            with open(a.out, "w", encoding="utf-8") as f:
                f.write(text)
            print(f"HTTP {st} -> {a.out}")
        else:
            print(f"HTTP {st}")
            print(text)
        return 0 if st < 400 else 1

    if not a.body:
        sys.exit("--body is required for writes")
    with open(a.body, encoding="utf-8") as f:
        body = json.load(f)

    os.makedirs("backups", exist_ok=True)
    bpath = a.backup_of or a.path
    st, js = call("GET", base + bpath)
    bfile = os.path.join("backups", f"{int(time.time())}_{bpath.strip('/').replace('/', '_')}.json")
    with open(bfile, "w", encoding="utf-8") as f:
        json.dump(js, f, ensure_ascii=False, indent=2)
    print(f"backup GET {bpath}: HTTP {st} -> {bfile}")
    if st >= 400:
        sys.exit("backup GET failed; stop and report to the user")

    print(f"\n{a.method.upper()} {url}")
    print(json.dumps(body, ensure_ascii=False, indent=2))
    if not a.execute:
        print("\nDRY-RUN: not sent. Show this request and the backup diff to the user; re-run with --execute after approval.")
        return 0
    st, js = call(a.method.upper(), url, body)
    print(f"\nHTTP {st}")
    print(json.dumps(js, ensure_ascii=False, indent=2)[:4000])
    return 0 if st < 400 else 1


if __name__ == "__main__":
    sys.exit(main())
