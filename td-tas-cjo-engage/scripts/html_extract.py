#!/usr/bin/env python3
"""Analyze an Engage email HTML file as input for a plaintext version.

Usage:
    python3 html_extract.py <file.html> [--utm source=email,medium=plaintext,campaign=xxx]
                            [--domain example.com] [--optout-pattern /member/]

Prints JSON with:
  - text_blocks : visible text in document order (script/style removed, whitespace normalized)
  - images      : src, alt, width, height, needs_vision (alt missing / logo-only and large)
  - links       : anchor text, original href, href_with_utm (only when --utm is given)
  - liquid_tags : {{profile.xxx}} and other Liquid tags found (must be kept as-is in plaintext)
Standard library only. Does not fetch images; the agent reads images with vision.
"""
import argparse
import html
import json
import re
import sys
from html.parser import HTMLParser
from urllib.parse import parse_qsl, urlencode, urlparse, urlunparse

BLOCK_TAGS = {"p", "div", "br", "tr", "td", "th", "li", "h1", "h2", "h3", "h4", "h5", "h6", "table", "section"}


class Extractor(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.skip = 0
        self.blocks = []
        self.cur = []
        self.images = []
        self.links = []
        self._a = None

    def _flush(self):
        t = re.sub(r"\s+", " ", "".join(self.cur)).strip()
        if t:
            self.blocks.append(t)
        self.cur = []

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if tag in ("script", "style", "head", "title"):
            self.skip += 1
            return
        if tag in BLOCK_TAGS:
            self._flush()
        if tag == "img":
            self.images.append({
                "src": a.get("src"),
                "alt": (a.get("alt") or "").strip(),
                "width": a.get("width"),
                "height": a.get("height"),
                "in_link": self._a["href"] if self._a else None,
            })
        if tag == "a" and a.get("href"):
            self._a = {"href": a.get("href"), "text": []}

    def handle_endtag(self, tag):
        if tag in ("script", "style", "head", "title"):
            self.skip = max(0, self.skip - 1)
            return
        if tag == "a" and self._a:
            text = re.sub(r"\s+", " ", "".join(self._a["text"])).strip()
            self.links.append({"text": text, "href": self._a["href"]})
            self._a = None
        if tag in BLOCK_TAGS:
            self._flush()

    def handle_data(self, data):
        if self.skip:
            return
        self.cur.append(data)
        if self._a is not None:
            self._a["text"].append(data)


def needs_vision(img):
    alt = img["alt"]
    src = img["src"] or ""
    if src.startswith("cid:"):
        return False
    try:
        w = int(re.sub(r"\D", "", str(img["width"] or "0")) or 0)
    except ValueError:
        w = 0
    small = 0 < w < 120  # icons, arrows, spacer
    logo_like = bool(re.search(r"logo|ロゴ", alt, re.I))
    return (not alt or logo_like) and not small


def add_utm(url, utm, domain=None, optout_pattern=None):
    if not url or url.startswith(("mailto:", "tel:", "#")):
        return url
    # Liquid-generated links such as {{unsubscribe_url}} must stay untouched.
    if "{{" in url and not url.startswith("http"):
        return url
    if optout_pattern and optout_pattern in url:
        return url
    p = urlparse(url)
    if domain and domain not in p.netloc:
        return url
    q = dict(parse_qsl(p.query, keep_blank_values=True))
    for k, v in utm.items():
        if v:
            q[k] = v
    return urlunparse(p._replace(query=urlencode(q, safe="{}%")))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("html_file")
    ap.add_argument("--utm", help="comma-separated key=value; keys without utm_ prefix are prefixed")
    ap.add_argument("--domain", help="only add UTM to links on this domain")
    ap.add_argument("--optout-pattern", default=None, help="substring of opt-out URLs to leave untouched")
    args = ap.parse_args()

    with open(args.html_file, encoding="utf-8") as f:
        src = f.read()
    ex = Extractor()
    ex.feed(src)
    ex._flush()

    utm = {}
    if args.utm:
        for kv in args.utm.split(","):
            if "=" in kv:
                k, v = kv.split("=", 1)
                k = k.strip()
                utm[k if k.startswith("utm_") else f"utm_{k}"] = v.strip()

    images = []
    for img in ex.images:
        img["needs_vision"] = needs_vision(img)
        images.append(img)
    links = []
    seen = set()
    for ln in ex.links:
        key = (ln["text"], ln["href"])
        if key in seen:
            continue
        seen.add(key)
        if utm:
            ln["href_with_utm"] = add_utm(ln["href"], utm, args.domain, args.optout_pattern)
        links.append(ln)

    liquid = sorted(set(re.findall(r"\{\{\s*[^}]+\s*\}\}|\{%[^%]+%\}", src)))
    out = {
        "file": args.html_file,
        "text_blocks": [html.unescape(b) for b in ex.blocks],
        "images": images,
        "links": links,
        "liquid_tags": liquid,
        "summary": {
            "text_blocks": len(ex.blocks),
            "images": len(images),
            "images_with_alt": sum(1 for i in images if i["alt"]),
            "images_needing_vision": sum(1 for i in images if i["needs_vision"]),
            "links": len(links),
        },
    }
    json.dump(out, sys.stdout, ensure_ascii=False, indent=2)
    print()


if __name__ == "__main__":
    main()
