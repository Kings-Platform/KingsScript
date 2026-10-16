#!/usr/bin/env python3
# Reads a page's HTML on stdin and prints its tab-icon URLs, best first, one per line.
# Order follows what a browser tab shows (SVG, raster by size, ICO, /favicon.ico);
# apple-touch-icon comes last, since it is often a different artwork (filled, padded).
import sys
from html.parser import HTMLParser
from urllib.parse import urljoin


class IconLinks(HTMLParser):
    def __init__(self):
        super().__init__()
        self.base = None
        self.links = []

    def handle_starttag(self, tag, attrs):
        a = {k.lower(): (v or "") for k, v in attrs}
        if tag == "base" and a.get("href") and self.base is None:
            self.base = a["href"]
        if tag != "link":
            return
        rel = a.get("rel", "").lower().split()
        if "icon" in rel or "apple-touch-icon" in rel or "apple-touch-icon-precomposed" in rel:
            if a.get("href"):
                self.links.append((rel, a["href"], a.get("type", "").lower(), a.get("sizes", "").lower()))


def largest_size(sizes):
    if sizes == "any":
        return 10_000
    best = 0
    for s in sizes.split():
        w = s.split("x")[0]
        if w.isdigit():
            best = max(best, int(w))
    return best


def rank(rel, href, mime, sizes):
    path = href.split("?")[0].lower()
    is_svg = "svg" in mime or path.endswith(".svg") or href.startswith("data:image/svg")
    is_ico = "x-icon" in mime or "vnd.microsoft.icon" in mime or path.endswith(".ico")
    if "icon" not in rel:
        return (4, -largest_size(sizes))
    if is_svg:
        return (0, 0)
    if is_ico:
        return (2, -largest_size(sizes))
    return (1, -largest_size(sizes))


def main():
    page = sys.argv[1]
    parser = IconLinks()
    parser.feed(sys.stdin.read())
    base = urljoin(page, parser.base) if parser.base else page
    ranked = sorted(parser.links, key=lambda l: rank(*l))
    seen = []
    for _, href, _, _ in ranked:
        url = href if href.startswith("data:") else urljoin(base, href)
        if url not in seen:
            seen.append(url)
    fallback = urljoin(page, "/favicon.ico")
    if fallback not in seen:
        tab_count = sum(1 for l in ranked if "icon" in l[0])
        seen.insert(min(tab_count, len(seen)), fallback)
    print("\n".join(seen))


main()
