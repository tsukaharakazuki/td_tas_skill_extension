#!/usr/bin/env python3
"""Extract IDs from Treasure Data console URLs (Engage Studio / CDP Journey / Segment).

Usage:
    python3 parse_console_url.py "<URL>" [<URL> ...]

Prints one JSON object per URL. Unknown parts are returned as null so the caller
can ask the user instead of guessing. Standard library only.
"""
import json
import re
import sys
from urllib.parse import urlparse

UUID = r"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"

# Engage Studio resource codes seen in console-next URLs.
ENGAGE_KINDS = {
    "em": "email_template",
    "ooc": "one_off_campaign",
    "aoc": "always_on_campaign",
}


def site_from_host(host: str):
    m = re.search(r"\.(us01|jp01|eu01|ap02|ap03)\.", host)
    if m:
        return m.group(1)
    if host.endswith("treasuredata.co.jp"):
        return "jp01"
    if host.endswith("treasuredata.com"):
        return "us01"
    return None


def parse(url: str) -> dict:
    p = urlparse(url.strip())
    path = p.path
    out = {
        "url": url,
        "host": p.netloc,
        "site": site_from_host(p.netloc),
        "engage_workspace_id": None,
        "engage_kind": None,
        "engage_resource_id": None,
        "parent_segment_id": None,
        "segment_id": None,
        "journey_id": None,
        "notes": [],
    }

    m = re.search(rf"/app/es/({UUID})(?:/([a-z]+)/({UUID}))?", path)
    if m:
        out["engage_workspace_id"] = m.group(1)
        if m.group(2):
            out["engage_kind"] = ENGAGE_KINDS.get(m.group(2), m.group(2))
            out["engage_resource_id"] = m.group(3)
            if m.group(2) not in ENGAGE_KINDS:
                out["notes"].append(f"unknown Engage resource code '{m.group(2)}'")

    # CDP: /app/audiences/<ps_id>/... or /app/ps/<ps_id>/...
    m = re.search(r"/app/(?:audiences|ps)/(\d+)", path)
    if m:
        out["parent_segment_id"] = m.group(1)
    m = re.search(r"/segments/(\d+)", path)
    if m:
        out["segment_id"] = m.group(1)
    m = re.search(r"/journeys?/(\d+)", path)
    if m:
        out["journey_id"] = m.group(1)
    # Journey console URLs printed by `tdx journey push` look like .../e/<id>
    m = re.search(r"/e/(\d+)(?:/|$)", path)
    if m and not out["journey_id"]:
        out["journey_id"] = m.group(1)
        out["notes"].append("journey id taken from '/e/<id>' — compare with the console URL the user is looking at")

    if out["parent_segment_id"]:
        out["notes"].append(
            "parent segment ID is not shown by `tdx ps list`; ask the user for the parent segment NAME"
        )
    return out


def main(argv):
    if len(argv) < 2:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    for u in argv[1:]:
        print(json.dumps(parse(u), ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
