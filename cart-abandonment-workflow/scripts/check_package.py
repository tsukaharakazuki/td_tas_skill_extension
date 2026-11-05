#!/usr/bin/env python3
"""Check distribution hygiene offline. This is not a complete secret scanner."""

import argparse
import json
from pathlib import Path
import re
import sys


EMAIL = re.compile(r"[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}")
UUID = re.compile(r"\b[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\b", re.I)
TEXT_SUFFIXES = {".md", ".dig", ".sql", ".yml", ".yaml", ".json", ".txt", ".py"}
EXAMPLE_DOMAINS = {"example.com", "example.org", "example.net", "example.invalid"}


def check(root, forbidden):
    errors = []
    outer = root / "SKILL.md"
    inner = root / "cart-abandonment/SKILL.md"
    if not outer.is_file() or not inner.is_file() or outer.read_bytes() != inner.read_bytes():
        errors.append("The two packaged SKILL.md copies must exist and match.")

    for path in sorted(root.rglob("*")):
        relative = path.relative_to(root)
        if any(part in {"__pycache__", ".git"} for part in relative.parts):
            continue
        if path.is_symlink():
            errors.append(f"{relative}: do not distribute symlinks")
            continue
        if not path.is_file():
            continue
        if path.name == ".env" or path.name.startswith(".env."):
            errors.append(f"{relative}: do not distribute environment secrets")
            continue
        if path.suffix not in TEXT_SUFFIXES:
            continue
        text = path.read_text(encoding="utf-8")
        for number, line in enumerate(text.splitlines(), 1):
            if any(value.casefold() in line.casefold() for value in forbidden):
                errors.append(f"{relative}:{number}: forbidden customer-specific text")
            for match in EMAIL.finditer(line):
                domain = match.group().rsplit("@", 1)[1].lower().rstrip(".")
                if domain not in EXAMPLE_DOMAINS and not domain.endswith((".invalid", ".example")):
                    errors.append(f"{relative}:{number}: non-example email address")
            if UUID.search(line):
                errors.append(f"{relative}:{number}: fixed UUID requires removal or review")

    metadata_path = root / "cart-abandonment/tdx.json"
    if metadata_path.exists():
        metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
        for key in ("profile", "workflow_project_id", "last_pulled_revision", "last_pulled_at"):
            if key in metadata:
                errors.append(f"cart-abandonment/tdx.json: remove account-specific field {key}")
    return errors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", nargs="?", type=Path, default=Path(__file__).resolve().parent.parent)
    parser.add_argument("--forbid", action="append", default=[], help="Customer-specific text to reject (repeatable)")
    args = parser.parse_args()
    errors = check(args.root.resolve(), args.forbid)
    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    print("Distribution hygiene checks passed (not a complete secret or SQL scanner).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
