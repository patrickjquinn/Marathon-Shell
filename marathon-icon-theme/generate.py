#!/usr/bin/env python3
"""Write svg/<glyph>.svg for every Phosphor glyph icon-map.txt uses.

Run after editing icon-map.txt (needs fontTools):
  marathon-icon-theme/generate.py
The SVGs are checked in, so building the theme needs no Python.
"""
import re
import sys
from pathlib import Path

from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.ttLib import TTFont

here = Path(__file__).resolve().parent
repo = here.parent
font = TTFont(repo / "shell/qml/ui/fonts/Phosphor-Thin.ttf")
glyphs_js = (repo / "shell/qml/ui/PhosphorGlyphs.js").read_text()
codepoints = {name: int(cp, 16) for name, cp in re.findall(r'"([a-z0-9-]+)": "\\u([0-9A-Fa-f]{4})"', glyphs_js)}

upm = font["head"].unitsPerEm
ascent = font["hhea"].ascent
cmap = font.getBestCmap()
glyph_set = font.getGlyphSet()

wanted = set()
for line in (here / "icon-map.txt").read_text().splitlines():
    line = line.strip()
    if line and not line.startswith("#"):
        wanted.add(line.split()[1])

out = here / "svg"
out.mkdir(exist_ok=True)
for old in out.glob("*.svg"):
    if old.stem not in wanted:
        old.unlink()
for name in sorted(wanted):
    pen = SVGPathPen(glyph_set, ntos=lambda v: str(round(v)))
    glyph_set[cmap[codepoints[name]]].draw(pen)
    (out / f"{name}.svg").write_text(
        f'<svg xmlns="http://www.w3.org/2000/svg" width="@SIZE@" height="@SIZE@" viewBox="0 0 {upm} {upm}">'
        f'<path fill="#ffffff" transform="matrix(1 0 0 -1 0 {ascent})" d="{pen.getCommands()}"/></svg>\n')
print(f"{len(wanted)} glyphs written to {out}", file=sys.stderr)
