#!/usr/bin/env python3
"""Summarize `tdx journey activations ... --json` output, keeping the newest ID per name.

Usage:
    tdx journey activations "<journey>" --json > /tmp/acts.json
    python3 latest_activations.py /tmp/acts.json

Why: after `tdx journey push`, old activation records with the same name can remain.
The newest (largest numeric) ID per name is the current one; duplicates are listed so
the agent can tell the user which records are stale. Standard library only.
"""
import json
import sys


def rows(data):
    if isinstance(data, dict):
        data = data.get("data", data.get("activations", []))
    for a in data or []:
        attrs = a.get("attributes", a) if isinstance(a, dict) else {}
        params = attrs.get("activationParams", attrs)
        cc = params.get("connectorConfig") or attrs.get("connectorConfig") or {}
        try:
            aid = int(str(a.get("id") or attrs.get("id") or "0"))
        except ValueError:
            aid = 0
        yield {
            "id": aid,
            "name": params.get("name") or attrs.get("name") or "",
            "connectionId": params.get("connectionId") or attrs.get("connectionId"),
            "allColumns": params.get("allColumns", attrs.get("allColumns")),
            "columns": len(params.get("columns") or attrs.get("columns") or []),
            "scheduleType": params.get("scheduleType") or attrs.get("scheduleType"),
            "workspaceId": cc.get("workspaceId"),
            "alwaysOnCampaignId": cc.get("alwaysOnCampaignId"),
            "campaignType": cc.get("campaignType"),
        }


def main():
    if len(sys.argv) != 2:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    with open(sys.argv[1], encoding="utf-8") as f:
        data = json.load(f)
    by_name = {}
    for r in rows(data):
        by_name.setdefault(r["name"], []).append(r)
    result = []
    for name, rs in sorted(by_name.items()):
        rs.sort(key=lambda r: r["id"], reverse=True)
        latest = dict(rs[0])
        latest["stale_ids"] = [r["id"] for r in rs[1:]]
        result.append(latest)
    json.dump(result, sys.stdout, ensure_ascii=False, indent=2)
    print()
    dup = [r for r in result if r["stale_ids"]]
    if dup:
        print(f"# {len(dup)} activation name(s) have stale duplicates — use the newest id", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
