#!/usr/bin/env python3
"""Recolour the designed app icons (docs/redesign app-icons.jsx) with one palette.

The marks stay as designed; each tile takes its app's colour, the teal mark
turns white, and dark cut-outs take a deep shade of the tile. Run on the
design-centre SVGs; it is not idempotent.
"""
import re
from pathlib import Path

# app: (tile top, tile bottom). One palette: similar depth and saturation.
PALETTE = {
    "phone": ("#2fb38a", "#1a7a5e"),
    "messages": ("#3a9fd0", "#1f6a96"),
    "email": ("#4f7fd6", "#2c4f9e"),
    "browser": ("#6a6fd6", "#3f4499"),
    "music": ("#d0587f", "#8f2f52"),
    "camera": ("#6a7280", "#3a404a"),
    "gallery": ("#e08a4a", "#a8552a"),
    "maps": ("#3aa0a8", "#1f6b74"),
    "calendar": ("#e05a4a", "#a3352b"),
    "clock": ("#4d5d78", "#283246"),
    "calculator": ("#9068cc", "#5b3a92"),
    "notes": ("#d4a83a", "#9a7420"),
    "settings": ("#7a8290", "#4a515e"),
}


def shade(hex_colour, factor):
    r, g, b = (int(hex_colour[i:i + 2], 16) for i in (1, 3, 5))
    return "#%02x%02x%02x" % tuple(round(c * factor) for c in (r, g, b))


repo = Path(__file__).resolve().parent.parent
for app, (top, bottom) in PALETTE.items():
    path = repo / "apps" / app / "assets" / "icon.svg"
    svg = path.read_text()
    deep = shade(bottom, 0.45)

    # The tile: the gradient the first full-size rect is filled with.
    tile_id = re.search(r'<rect[^>]*width="6[34]"[^>]*fill="url\(#([\w-]+)\)"', svg).group(1)
    grad = re.search(r'(<(linear|radial)Gradient id="%s"[^>]*>)(.*?)(</\2Gradient>)' % tile_id, svg, re.S)
    svg = svg.replace(grad.group(0), grad.group(1)
                      + f'<stop offset="0" stop-color="{top}"/><stop offset="1" stop-color="{bottom}"/>'
                      + grad.group(4))

    # The mark: Marathon teal becomes white, at the same opacities.
    svg = re.sub(r"#1de9b6", "#ffffff", svg, flags=re.I)
    svg = re.sub(r"rgba\((?:29,233,182|0,191,165|0,137,123),", "rgba(255,255,255,", svg)
    # Gallery's stacked prints: the back ones as fainter whites.
    svg = re.sub(r'fill="#006b5d"', 'fill="#ffffff" fill-opacity="0.45"', svg, flags=re.I)
    svg = re.sub(r'fill="#00bfa5"', 'fill="#ffffff" fill-opacity="0.7"', svg, flags=re.I)
    # Maps' inner map panel: the tile itself is the map.
    svg = svg.replace('<rect x="0" y="0" width="24" height="24" fill="#0a1814"/>', "")

    # Dark cut-outs, dials and inner panels: a deep shade of the tile.
    for dark in ("#040404", "#0a0a0b", "#0a1814", "#161718", "#1a1b1c", "#1c1c1d", "#000000", "#000"):
        svg = re.sub(r'(fill|stroke|stop-color)="%s"' % re.escape(dark), r'\1="%s"' % deep, svg, flags=re.I)

    path.write_text(svg)
print(f"{len(PALETTE)} icons recoloured")
