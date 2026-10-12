#!/usr/bin/env python3
"""Write apps/<app>/assets/icon.svg for every app in APPS.

One template for the whole set: a rounded tile in the app's own colour,
lit from the top left, with a white Phosphor Bold glyph. Edit APPS and
re-run (needs fontTools); the SVGs are checked in.
"""
import re
import sys
from pathlib import Path

from fontTools.pens.boundsPen import BoundsPen
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont

# app: (glyph, light, dark)
APPS = {
    "phone": ("phone", "#4cd964", "#1a9b3c"),
    "messages": ("chat-circle-text", "#36c8f0", "#0a84c2"),
    "email": ("envelope-simple", "#5b9dff", "#1f5fd6"),
    "browser": ("globe-hemisphere-west", "#7b7ff7", "#4338ca"),
    "store": ("storefront", "#2ee6b8", "#0b917a"),
    "music": ("music-notes", "#ff5c7a", "#c21a4b"),
    "camera": ("camera", "#7d8a9c", "#3a4555"),
    "gallery": ("image", "#ffb340", "#e06d06"),
    "maps": ("map-trifold", "#34d399", "#0a7d5a"),
    "calendar": ("calendar-blank", "#ff7a45", "#d03a12"),
    "clock": ("clock", "#4a4f5c", "#15181e"),
    "calculator": ("calculator", "#b77cff", "#7a2fd6"),
    "notes": ("note-pencil", "#f5c400", "#b98500"),
    "settings": ("gear-six", "#9a9aa2", "#4a4a52"),
    "terminal": ("terminal-window", "#3a3f47", "#0b0d10"),
    "test": ("flask", "#9ad43c", "#4f8a12"),
    "template": ("squares-four", "#8a94a6", "#4b5563"),
}

SIZE = 64
RADIUS = 15
GLYPH = 34  # the glyph's longer side, in tile units

repo = Path(__file__).resolve().parent.parent
font = TTFont(repo / "shell/qml/ui/fonts/Phosphor-Bold.ttf")
glyphs_js = (repo / "shell/qml/ui/PhosphorGlyphs.js").read_text()
codepoints = {name: int(cp, 16) for name, cp in re.findall(r'"([a-z0-9-]+)": "\\u([0-9A-Fa-f]{4})"', glyphs_js)}
cmap = font.getBestCmap()
glyph_set = font.getGlyphSet()


def glyph_path(name):
    glyph = glyph_set[cmap[codepoints[name]]]
    bounds = BoundsPen(glyph_set)
    glyph.draw(bounds)
    x0, y0, x1, y1 = bounds.bounds
    scale = GLYPH / max(x1 - x0, y1 - y0)
    # Centre the outline in the tile; font units are y-up, SVG is y-down.
    dx = SIZE / 2 - (x0 + x1) / 2 * scale
    dy = SIZE / 2 + (y0 + y1) / 2 * scale
    pen = SVGPathPen(glyph_set, ntos=lambda v: f"{v:.2f}".rstrip("0").rstrip("."))
    glyph.draw(TransformPen(pen, (scale, 0, 0, -scale, dx, dy)))
    return pen.getCommands()


def icon(glyph, light, dark):
    return f"""<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {SIZE} {SIZE}">
    <defs>
        <linearGradient id="tile" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="{light}"/><stop offset="1" stop-color="{dark}"/></linearGradient>
        <linearGradient id="sheen" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#ffffff" stop-opacity="0.22"/><stop offset="0.5" stop-color="#ffffff" stop-opacity="0"/></linearGradient>
    </defs>
    <rect width="{SIZE}" height="{SIZE}" rx="{RADIUS}" fill="url(#tile)"/>
    <rect width="{SIZE}" height="{SIZE}" rx="{RADIUS}" fill="url(#sheen)"/>
    <path fill="#000000" fill-opacity="0.18" transform="translate(0 1.2)" d="{glyph}"/>
    <path fill="#ffffff" d="{glyph}"/>
</svg>
"""


for app, (glyph, light, dark) in APPS.items():
    target = repo / "apps" / app / "assets" / "icon.svg"
    if not target.parent.is_dir():
        print(f"skipping {app}: no {target.parent}", file=sys.stderr)
        continue
    target.write_text(icon(glyph_path(glyph), light, dark))
print(f"{len(APPS)} icons written", file=sys.stderr)
