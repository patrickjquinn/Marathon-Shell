#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Patrick Quinn
# SPDX-License-Identifier: MIT
#
# Generates Keel's default ambience wallpapers and the glass dither (Keel's
# own artwork; no third-party image is used):
#
#   harbour-dark.jpg   "Harbour": a night harbour in deep blues and teal,
#                      for the default dark (light-on-dark) ambience
#   harbour-light.jpg  "Harbour light": the same scene by day, for the light
#                      (dark-on-light) ambience
#   glass-dither.png   8x8 tile of faint white specks that ApplicationWindow
#                      lays over the blurred wallpaper, like the fine pattern
#                      Sailfish OS 4/5 shows on application backgrounds
#
# The wallpapers are soft on purpose: ApplicationWindow blurs them further
# (image://keelambience). Requires Pillow.
#   python3 keel/silica/ambience/make-ambience.py [outdir]
import math
import os
import sys

from PIL import Image, ImageDraw, ImageFilter

SIZE = 1440


def lerp(a, b, t):
    return tuple(round(x + (y - x) * t) for x, y in zip(a, b))


def gradient(stops):
    """A vertical gradient through (position, colour) stops."""
    im = Image.new("RGB", (1, SIZE))
    for y in range(SIZE):
        t = y / (SIZE - 1)
        for (p0, c0), (p1, c1) in zip(stops, stops[1:]):
            if p0 <= t <= p1:
                im.putpixel((0, y), lerp(c0, c1, (t - p0) / (p1 - p0)))
                break
    return im.resize((SIZE, SIZE))


def glow(base, cx, cy, rx, ry, colour, strength, blur):
    """Adds a soft elliptical glow of `colour` (screen-like blend)."""
    mask = Image.new("L", base.size, 0)
    ImageDraw.Draw(mask).ellipse(
        [(cx - rx) * SIZE, (cy - ry) * SIZE, (cx + rx) * SIZE, (cy + ry) * SIZE],
        fill=round(255 * strength))
    mask = mask.filter(ImageFilter.GaussianBlur(blur * SIZE))
    return Image.composite(Image.new("RGB", base.size, colour), base, mask)


def shapes(base, colour, items, blur):
    """Solid soft-edged ellipses (rocks, a hull) in `colour`."""
    mask = Image.new("L", base.size, 0)
    d = ImageDraw.Draw(mask)
    for cx, cy, rx, ry in items:
        d.ellipse([(cx - rx) * SIZE, (cy - ry) * SIZE, (cx + rx) * SIZE, (cy + ry) * SIZE], fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(blur * SIZE))
    return Image.composite(Image.new("RGB", base.size, colour), base, mask)


ROCKS = [(0.18, 0.80, 0.16, 0.035), (0.46, 0.86, 0.12, 0.03), (0.80, 0.78, 0.18, 0.04),
         (0.62, 0.94, 0.22, 0.04), (0.08, 0.95, 0.12, 0.03)]


def dark():
    im = gradient([(0.0, (4, 9, 18)), (0.42, (10, 28, 52)), (0.58, (12, 44, 66)), (1.0, (5, 14, 24))])
    im = glow(im, 0.24, 0.22, 0.30, 0.20, (28, 58, 112), 0.55, 0.06)
    im = glow(im, 0.50, 0.56, 0.60, 0.07, (24, 104, 128), 0.65, 0.04)
    im = glow(im, 0.64, 0.40, 0.13, 0.13, (120, 196, 220), 0.70, 0.03)
    im = glow(im, 0.64, 0.66, 0.05, 0.16, (60, 150, 175), 0.35, 0.04)
    im = shapes(im, (3, 9, 17), ROCKS, 0.012)
    return im.filter(ImageFilter.GaussianBlur(4))


def light():
    im = gradient([(0.0, (196, 222, 238)), (0.5, (226, 238, 242)), (1.0, (238, 240, 236))])
    im = glow(im, 0.28, 0.24, 0.30, 0.18, (170, 198, 236), 0.6, 0.06)
    im = glow(im, 0.50, 0.56, 0.60, 0.07, (150, 210, 222), 0.6, 0.04)
    im = glow(im, 0.64, 0.40, 0.13, 0.13, (255, 246, 222), 0.8, 0.03)
    im = glow(im, 0.72, 0.80, 0.30, 0.10, (236, 214, 184), 0.5, 0.05)
    im = shapes(im, (120, 150, 160), ROCKS, 0.012)
    return im.filter(ImageFilter.GaussianBlur(4))


def dither():
    """Two staggered specks per 8x8 tile, each a point fading downwards."""
    tile = Image.new("RGBA", (8, 8), (255, 255, 255, 0))
    rows = [24, 15, 8, 4]
    for ox, oy in ((0, 0), (4, 4)):
        for dy, alpha in enumerate(rows):
            for dx in range(-dy, dy + 1):
                tile.putpixel(((ox + dx) % 8, (oy + dy) % 8), (255, 255, 255, alpha))
    return tile


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(os.path.abspath(__file__))
    dark().save(os.path.join(out, "harbour-dark.jpg"), quality=88, optimize=True, progressive=True)
    light().save(os.path.join(out, "harbour-light.jpg"), quality=88, optimize=True, progressive=True)
    dither().save(os.path.join(out, "glass-dither.png"), optimize=True)


if __name__ == "__main__":
    main()
