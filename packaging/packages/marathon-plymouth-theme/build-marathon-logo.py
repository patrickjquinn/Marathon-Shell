#!/usr/bin/env python3
# Generate marathon-logo.png for the Plymouth boot splash. Produces a
# 200x200 RGBA PNG with:
#   • subtle teal halo (radial fade) behind the disc
#   • teal-gradient disc, ~96 px diameter
#   • black "M" path centred inside the disc, sized to 58 % of disc
# All per docs/redesign/marathonos/project/design-system/ds-foundations.jsx.
#
# Run from this directory: ./build-marathon-logo.py
# Output: marathon-logo.png

import cairo
import math
import os

SIZE = 200
DISC_R = 48          # disc radius (matches the 96 px diameter spec)
HALO_R = DISC_R + 22 # halo outer radius
M_HEIGHT_FRAC = 0.58 # M = 58 % of disc per the DS spec
CX = CY = SIZE / 2

# M path in its own 56x56 viewBox per the JSX spec. Translated to render
# centred on (0,0) — we Cairo-translate to disc centre before drawing.
M_PATH_VIEWBOX = 56
M_PATH = [
    ("M", 10, 44),
    ("V", 14),
    ("h", 6),
    ("l", 12, 18),
    ("l", 12, -18),
    ("h", 6),
    ("v", 30),
    ("h", -6),
    ("V", 24),
    ("L", 28, 40),
    ("L", 16, 24),
    ("v", 20),
    ("Z",),
]


def draw_path(ctx, cmds):
    """Replay an SVG-style path on a Cairo context.

    The path d-string is parsed into absolute/relative segments in M_PATH
    above; this dispatcher walks each segment. M / L are absolute moves /
    lines; m / l are relative; H/V/h/v are horizontal / vertical lines.
    Z closes the subpath.
    """
    x = y = 0
    for cmd in cmds:
        op = cmd[0]
        if op == "M":
            x, y = cmd[1], cmd[2]
            ctx.move_to(x, y)
        elif op == "m":
            x, y = x + cmd[1], y + cmd[2]
            ctx.move_to(x, y)
        elif op == "L":
            x, y = cmd[1], cmd[2]
            ctx.line_to(x, y)
        elif op == "l":
            x, y = x + cmd[1], y + cmd[2]
            ctx.line_to(x, y)
        elif op == "H":
            x = cmd[1]
            ctx.line_to(x, y)
        elif op == "h":
            x += cmd[1]
            ctx.line_to(x, y)
        elif op == "V":
            y = cmd[1]
            ctx.line_to(x, y)
        elif op == "v":
            y += cmd[1]
            ctx.line_to(x, y)
        elif op in ("Z", "z"):
            ctx.close_path()


def render():
    surface = cairo.ImageSurface(cairo.FORMAT_ARGB32, SIZE, SIZE)
    ctx = cairo.Context(surface)

    # ─ Halo: radial gradient teal → transparent. Soft outer glow that
    #   matches the JSX `boxShadow: 0 0 24px var(--teal-halo)` plus the
    #   broader ambient fade in the BootSplash mockup.
    halo = cairo.RadialGradient(CX, CY, DISC_R - 4, CX, CY, HALO_R)
    halo.add_color_stop_rgba(0.0, 0.11, 0.91, 0.71, 0.55)
    halo.add_color_stop_rgba(0.5, 0.11, 0.91, 0.71, 0.18)
    halo.add_color_stop_rgba(1.0, 0.11, 0.91, 0.71, 0.0)
    ctx.set_source(halo)
    ctx.arc(CX, CY, HALO_R, 0, 2 * math.pi)
    ctx.fill()

    # ─ Disc: vertical teal gradient #1de9b6 → #00bfa5
    disc = cairo.LinearGradient(CX, CY - DISC_R, CX, CY + DISC_R)
    disc.add_color_stop_rgba(0.0, 0x1d / 255, 0xe9 / 255, 0xb6 / 255, 1.0)
    disc.add_color_stop_rgba(1.0, 0x00 / 255, 0xbf / 255, 0xa5 / 255, 1.0)
    ctx.set_source(disc)
    ctx.arc(CX, CY, DISC_R, 0, 2 * math.pi)
    ctx.fill_preserve()
    # Subtle 1 px white border for the JSX "inset 0 1px 0 rgba(255,255,255,0.3)"
    # glassy lift; render as a thin stroke INSIDE the disc.
    ctx.set_source_rgba(1, 1, 1, 0.18)
    ctx.set_line_width(1)
    ctx.stroke()

    # ─ Black M, centred in the disc and sized to M_HEIGHT_FRAC of disc.
    m_target = DISC_R * 2 * M_HEIGHT_FRAC
    scale = m_target / M_PATH_VIEWBOX
    ctx.save()
    # Translate to disc centre, then move back by half-scaled-viewbox so
    # the (0..56, 0..56) path renders centred on (CX, CY).
    ctx.translate(CX - (M_PATH_VIEWBOX * scale) / 2, CY - (M_PATH_VIEWBOX * scale) / 2)
    ctx.scale(scale, scale)
    draw_path(ctx, M_PATH)
    ctx.set_source_rgb(0, 0, 0)
    ctx.fill()
    ctx.restore()

    # Bake ordered dither into the PNG. HyperPixel 4.0 Square drives the
    # panel over an 18-bpp DPI bus and quantises the smooth disc gradient
    # to 6 bpc per channel WITHOUT dithering, producing the visible Mach
    # bands the user reported. We add ±1-LSB random noise per pixel
    # *inside the disc + halo region* — invisible on higher-bit panels,
    # breaks the banding on 18-bit ones. Plymouth doesn't have a runtime
    # dither shader so it has to be baked into the asset.
    from PIL import Image
    import random
    import io
    buf = io.BytesIO()
    surface.write_to_png(buf)
    buf.seek(0)
    im = Image.open(buf).convert("RGBA")
    px = im.load()
    rand = random.Random(42)  # deterministic — same output every build
    for y in range(SIZE):
        for x in range(SIZE):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            # ±1 jitter on each colour channel. ~1 LSB on 6-bpc; invisible
            # on 8-bpc, breaks the banding on 6-bpc panels.
            jr = max(0, min(255, r + rand.randint(-2, 2)))
            jg = max(0, min(255, g + rand.randint(-2, 2)))
            jb = max(0, min(255, b + rand.randint(-2, 2)))
            px[x, y] = (jr, jg, jb, a)
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "marathon-logo.png")
    im.save(out, "PNG")
    print(f"wrote {out} ({SIZE}x{SIZE}) with ordered dither")


if __name__ == "__main__":
    render()
