#!/usr/bin/env python3
"""Compare an Engage email's HTML, plaintext and subject for stale or missing content.

Usage:
    python3 check_mail_consistency.py <file.html> <file.txt> [--subject "件名"]

Prints JSON: key elements (dates, times, prices, discounts, URLs, member tiers) found in
each source, and the differences. The agent turns this into the user-facing report;
differences can be intentional (image-only text), so never auto-fix from this output.
"""
import argparse
import json
import re
import sys
from html.parser import HTMLParser

PATTERNS = {
    "date": r"\d{4}[/.-]\d{1,2}[/.-]\d{1,2}|\d{1,2}月\d{1,2}日|\d{1,2}/\d{1,2}(?:\s*[\(（][月火水木金土日][\)）])?",
    "time": r"\d{1,2}:\d{2}",
    "price": r"[￥¥]\s?[\d,]+|[\d,]+\s?円",
    "discount": r"\d+\s?%\s?(?:OFF|off|オフ)|[\d,]+円\s?(?:OFF|off|引き)",
    "tier": r"VIP|GOLD|SILVER|PLATINUM|ゴールド|シルバー|プラチナ|ブロンズ",
    "liquid": r"\{\{\s*[^}]+\s*\}\}",
}
URL_RE = r"https?://[^\s\"'<>）)]+"


class Text(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.skip = 0
        self.parts = []
        self.hrefs = []

    def handle_starttag(self, tag, attrs):
        if tag in ("script", "style", "head"):
            self.skip += 1
        if tag == "a":
            h = dict(attrs).get("href")
            if h:
                self.hrefs.append(h)

    def handle_endtag(self, tag):
        if tag in ("script", "style", "head"):
            self.skip = max(0, self.skip - 1)

    def handle_data(self, d):
        if not self.skip:
            self.parts.append(d)


def norm_url(u):
    u = u.split("#")[0]
    return re.sub(r"[?&]utm_[a-z_]+=[^&]*", "", u).rstrip("?&/")


def elements(text):
    return {k: sorted(set(m.strip() for m in re.findall(p, text))) for k, p in PATTERNS.items()}


def sentences(text):
    parts = re.split(r"[。\n！!？?]+", text)
    return {re.sub(r"\s+", "", s) for s in parts if len(re.sub(r"\s+", "", s)) >= 8}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("html_file")
    ap.add_argument("txt_file")
    ap.add_argument("--subject", default="")
    a = ap.parse_args()

    t = Text()
    with open(a.html_file, encoding="utf-8") as f:
        t.feed(f.read())
    html_text = re.sub(r"[ \t\r\f\v]+", " ", "\n".join(t.parts))
    with open(a.txt_file, encoding="utf-8") as f:
        txt = f.read()

    he, te, se = elements(html_text), elements(txt), elements(a.subject)
    diff = {}
    for k in PATTERNS:
        h, x = set(he[k]), set(te[k])
        if h != x:
            diff[k] = {"only_in_html": sorted(h - x), "only_in_txt": sorted(x - h)}
    # Substring match so that "11/10" in the subject matches "2026/11/10" in the body.
    subj_missing = {k: [v for v in se[k] if v not in html_text and v not in txt] for k in PATTERNS}
    subj_missing = {k: v for k, v in subj_missing.items() if v}

    hu = {norm_url(u) for u in t.hrefs if u.startswith("http")}
    tu = {norm_url(u) for u in re.findall(URL_RE, txt)}
    hs, ts = sentences(html_text), sentences(txt)
    out = {
        "elements": {"html": he, "txt": te, "subject": se},
        "element_differences": diff,
        "subject_values_missing_from_body": subj_missing,
        "urls": {"only_in_html": sorted(hu - tu), "only_in_txt": sorted(tu - hu)},
        "sentences_only_in_txt": sorted(ts - hs)[:50],
        "sentences_only_in_html": sorted(hs - ts)[:50],
        "note": "URL comparison ignores utm_* params and fragments. Image-only text appears as 'only_in_txt'.",
    }
    json.dump(out, sys.stdout, ensure_ascii=False, indent=2)
    print()


if __name__ == "__main__":
    sys.exit(main())
