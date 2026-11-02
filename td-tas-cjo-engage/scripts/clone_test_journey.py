#!/usr/bin/env python3
"""Turn a pulled production journey YAML into a new test journey YAML (test_v<N>_<name>).

Usage:
    python3 clone_test_journey.py <prod.yml> --version <N> [--out <path>]

What it does (server IDs must go, otherwise push may update the production journey):
  - top-level: name -> test_v<N>_<name>; drop id, bundle_id, bundle_name, version, version_number
    (folder_id is kept so the test journey lands in the same Console folder)
  - journeys: keep only the `latest: true` entry (or the last one); drop id, version,
    version_number, latest; force state: draft
  - stages[].id, steps[].uuid, ab_test variants[].id and with.unique_id are dropped
  - segments / activations are copied unchanged
The output is written next to the input (same folder => same server folder on push).
Requires PyYAML (`import yaml`). Without it, the script prints the manual checklist instead.
"""
import argparse
import os
import sys

TOP_DROP = ("id", "bundle_id", "bundle_name", "version", "version_number")
ENTRY_DROP = ("id", "version", "version_number", "latest")

CHECKLIST = """PyYAML is not available. Edit a copy of the YAML by hand:
  1. top-level name: test_v<N>_<name>
  2. delete top-level id / bundle_id / bundle_name / version / version_number (keep folder_id)
  3. journeys: keep only the entry with latest: true; in it delete id / version / version_number /
     latest and set state: draft
  4. delete every stages[].id, steps[].uuid, ab_test variants[].id and with.unique_id
  5. save in the SAME folder as the production YAML
"""


def clean_entry(entry):
    for k in ENTRY_DROP:
        entry.pop(k, None)
    entry["state"] = "draft"
    for st in entry.get("stages") or []:
        st.pop("id", None)
        for step in st.get("steps") or []:
            step.pop("uuid", None)
            w = step.get("with") or {}
            if step.get("type") == "ab_test":
                w.pop("unique_id", None)
                for v in w.get("variants") or []:
                    v.pop("id", None)
    return entry


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("prod_yaml")
    ap.add_argument("--version", type=int, required=True)
    ap.add_argument("--out")
    a = ap.parse_args()
    try:
        import yaml  # noqa: PLC0415
    except ImportError:
        print(CHECKLIST, file=sys.stderr)
        return 3

    with open(a.prod_yaml, encoding="utf-8") as f:
        doc = yaml.safe_load(f)
    if not isinstance(doc, dict) or doc.get("type") != "journey":
        sys.exit("not a journey YAML (type: journey)")

    prod_name = doc["name"]
    if prod_name.startswith("test_v"):
        sys.exit(f"input already looks like a test journey: {prod_name}")
    doc["name"] = f"test_v{a.version}_{prod_name}"
    for k in TOP_DROP:
        doc.pop(k, None)

    entries = doc.get("journeys") or []
    if not entries:
        sys.exit("no journeys: entries found")
    latest = [e for e in entries if e.get("latest")]
    chosen = latest[0] if latest else entries[-1]
    doc["journeys"] = [clean_entry(chosen)]
    doc.pop("versions", None)

    out = a.out or os.path.join(os.path.dirname(os.path.abspath(a.prod_yaml)), f"test_v{a.version}_{os.path.basename(a.prod_yaml)}")
    if os.path.exists(out):
        sys.exit(f"{out} already exists — choose a higher --version")
    with open(out, "w", encoding="utf-8") as f:
        yaml.safe_dump(doc, f, allow_unicode=True, sort_keys=False)
    print(f"written: {out}")
    print(f"journey name: {doc['name']}")
    print("next: edit the change, then `tdx journey validate` and `tdx journey push <file> --dry-run`;"
          " the dry-run must say the journey will be CREATED, not updated.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
