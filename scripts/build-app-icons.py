#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Patrick Quinn
# SPDX-License-Identifier: Apache-2.0
"""Draw apps/<app>/assets/icon.svg for every first-party Marathon app.

Jolla's Sailfish OS launcher icon system (sailfishos.org/design/icons,
Sailfish-Apps-icon-template.zip), with one base shape for the family. Spec:
docs/design/app-icon-spec.md.

    scripts/build-app-icons.py [apps-dir]

- Shape. 86 x 86, Sailfish's base shape with the bottom-left corner
  square, for every icon.
- Field. The shape is the colour: a two-stop gradient from the square
  corner (deep) to the top right (light), its hue turning toward the warm
  light (LIGHT) as it brightens, as Jolla's stock icons do.
- Object. One bold flat object inside Jolla's guide, the shape inset
  GUIDE: pale P at 0.9 opacity so the field shows through, at most one
  second plane Q, details in the shared ink K or dark N, and one accent A
  where the metaphor has one (the = key, the pin, the liquid).
- Paper. Objects that are paper (Calendar, Notes) take the whole shape as
  the page and carry the hue in a band across its top.
"""

import math
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
S, IN = 86.0, 0.3            # canvas, inset
ROUND, SQUARE = 42.7, 1.423  # corner radii
MARATHON = (True, True, True, False)  # (tl, tr, br, bl): bottom left square
C0 = 43.0                    # centre of every round corner's arc
GUIDE = 10.7                 # Jolla's template guide: r 32.0 corners
R = ROUND - GUIDE
LO, HI = IN + GUIDE, S - IN - GUIDE
LIGHT = 95.0                 # hue the field turns toward as it brightens
INK = 237.0                  # Jolla's ink blue; blue fields ink in their own deep tone
PAPER = ("#EFE8CF", "#FBF8EA")


def _srgb(x):
    x = max(0.0, min(1.0, x))
    return 12.92 * x if x <= 0.0031308 else 1.055 * x ** (1 / 2.4) - 0.055


def oklch(L, C, h):
    """OKLCH to #RRGGBB, giving up chroma until the colour is in gamut."""
    while True:
        a, b = C * math.cos(math.radians(h)), C * math.sin(math.radians(h))
        l = (L + 0.3963377774 * a + 0.2158037573 * b) ** 3
        m = (L - 0.1055613458 * a - 0.0638541728 * b) ** 3
        s = (L - 0.0894841775 * a - 1.2914855480 * b) ** 3
        rgb = (4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
               -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
               -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s)
        if all(-0.001 <= v <= 1.001 for v in rgb) or C <= 0:
            return "#" + "".join(f"{round(_srgb(v) * 255):02X}" for v in rgb)
        C -= 0.005


def turn(a, b):
    """Signed degrees from hue a to hue b."""
    return (b - a + 180) % 360 - 180


def palette(h, accent):
    """Field gradient F (deep, light); pale object P, its muted shade M,
    bright second plane Q, ink K, dark N, accent A."""
    t = turn(h, LIGHT)
    s = max(-22.0, min(22.0, t))
    y = max(0.0, 1 - abs(t) / 50)  # yellows stay bright when deep
    ink = (0.47, 0.11, INK) if abs(turn(h, INK)) > 50 else (0.42, 0.14, h)
    if accent is None:
        accent = (0.78, 0.16, h)
    elif not isinstance(accent, tuple):
        accent = (0.78, 0.16, accent)
    w = h + s / 2
    dk = LIGHT - 30 if abs(t) < 15 else h - s  # a yellow turns up from amber, not olive
    lt = 140.0 if h >= 140 > h + s else h + s  # a green's light end stays green, not lime
    return {"F": (oklch(0.57 + 0.09 * y, 0.17, dk), oklch(0.77 + 0.06 * y, 0.17, lt)),
            "P": oklch(0.96, 0.045, w),
            "M": oklch(0.87, 0.05, w),
            "Q": oklch(0.86, 0.15, w),
            "K": oklch(*ink),
            "N": oklch(0.27, 0.04, h),
            "A": oklch(*accent)}


def base(tl, tr, br, bl, d=0.0):
    """The base shape, each corner True (round) or False (square); `d`
    insets it, keeping round corners concentric."""
    r = [(ROUND - d) if c else SQUARE for c in (tl, tr, br, bl)]
    a, b = IN + d, S - IN - d
    return (f"M{a + r[0]:.3f},{a:.3f} H{b - r[1]:.3f} A{r[1]:.3f},{r[1]:.3f} 0 0 1 {b:.3f},{a + r[1]:.3f} "
            f"V{b - r[2]:.3f} A{r[2]:.3f},{r[2]:.3f} 0 0 1 {b - r[2]:.3f},{b:.3f} "
            f"H{a + r[3]:.3f} A{r[3]:.3f},{r[3]:.3f} 0 0 1 {a:.3f},{b - r[3]:.3f} "
            f"V{a + r[0]:.3f} A{r[0]:.3f},{r[0]:.3f} 0 0 1 {a + r[0]:.3f},{a:.3f} Z")


SHAPE = base(*MARATHON)


def inset(d=GUIDE):
    return base(*MARATHON, d=d)


def pt(r, a, c=(C0, C0)):
    """The point at radius r and angle a (degrees, clockwise from 3 o'clock)
    about c."""
    return c[0] + r * math.cos(math.radians(a)), c[1] + r * math.sin(math.radians(a))


def arc(r, a1, a2, c=(C0, C0)):
    """An arc of radius r about c from a1 to a2 degrees, clockwise."""
    (x1, y1), (x2, y2) = pt(r, a1, c), pt(r, a2, c)
    big = 1 if (a2 - a1) % 360 > 180 else 0
    return f"M{x1:.2f} {y1:.2f} A{r} {r} 0 {big} 1 {x2:.2f} {y2:.2f}"


def rect(x0, y0, x1, y1, r=0.0):
    return (f"M{x0 + r} {y0}H{x1 - r}A{r} {r} 0 0 1 {x1} {y0 + r}V{y1 - r}A{r} {r} 0 0 1 {x1 - r} {y1}"
            f"H{x0 + r}A{r} {r} 0 0 1 {x0} {y1 - r}V{y0 + r}A{r} {r} 0 0 1 {x0 + r} {y0}Z")


def stroke(d, colour, w, cap="round"):
    return (f'<path d="{d}" fill="none" stroke="{{{colour}}}" stroke-width="{w}" '
            f'stroke-linecap="{cap}" stroke-linejoin="round"/>')


def fill(d, colour, extra=""):
    return f'<path d="{d}" fill="{{{colour}}}"{extra}/>'


def rounded(pts, radii):
    """A closed polygon with each corner filleted to its radius in `radii`."""
    n, d = len(pts), ""
    for i, ((x, y), r) in enumerate(zip(pts, radii)):
        (px, py), (nx, ny) = pts[i - 1], pts[(i + 1) % n]
        lp, ln = math.hypot(px - x, py - y), math.hypot(nx - x, ny - y)
        r1, r2 = min(r, lp / 2) / lp, min(r, ln / 2) / ln
        d += (f"{'L' if d else 'M'}{x + (px - x) * r1:.2f} {y + (py - y) * r1:.2f}"
              f"Q{x:.2f} {y:.2f} {x + (nx - x) * r2:.2f} {y + (ny - y) * r2:.2f}")
    return d + "Z"


def gear(c, teeth, ro, ri, hole, w, rt, rv):
    """A gear about c: `teeth` teeth w wide from radius ri to ro, their tips
    rounded rt and the valleys rv, with a hole cut out (even-odd)."""
    pts, radii = [], []
    for i in range(teeth):
        m = i * 360 / teeth - 90
        for r, side, rad in ((ri, -1, rv), (ro, -1, rt), (ro, 1, rt), (ri, 1, rv)):
            pts.append(pt(r, m + side * math.degrees(math.asin(w / 2 / r)), c))
            radii.append(rad)
    return (rounded(pts, radii) + f"M{c[0] + hole} {c[1]}A{hole} {hole} 0 1 0 {c[0] - hole} {c[1]}"
            f"A{hole} {hole} 0 1 0 {c[0] + hole} {c[1]}Z")


class Art:
    """One icon's layers; `{name}` in a layer is a palette colour."""

    def __init__(self, colours):
        self.c, self.parts, self.n = colours, [], 0
        self.paper, self.field = False, SHAPE

    def add(self, *svg):
        self.parts.extend(s.format(**self.c) for s in svg)

    def pale(self, *svg):
        """Layers drawn as one surface at 0.9 opacity, the field showing
        through as on Jolla's stock icons."""
        self.parts.append('<g opacity="0.9">' + "".join(s.format(**self.c) for s in svg) + "</g>")

    def clip(self, shape_d, *svg):
        self.n += 1
        self.parts.append(f'<clipPath id="c{self.n}"><path d="{shape_d}"/></clipPath>'
                          f'<g clip-path="url(#c{self.n})">' + "".join(s.format(**self.c) for s in svg) + "</g>")


def render(title, hue, accent, draw):
    tones = palette(hue, accent)
    art = Art({k: (f"url(#g{k})" if k == "F" else v) for k, v in tones.items()})
    draw(art)
    field = "url(#gPaper)" if art.paper else "url(#gF)"
    diag, across = 'x1="0.717" y1="85.283" x2="73.194" y2="12.806"', 'x1="0" y1="0" x2="86" y2="0"'
    grads = [("F", diag, tones["F"])] + ([("Paper", diag, PAPER), ("Band", across, tones["F"])] if art.paper else [])
    defs = "\n".join(
        f'    <linearGradient id="g{k}" gradientUnits="userSpaceOnUse" {xy}>\n'
        f'      <stop offset="0" stop-color="{a}"/>\n      <stop offset="1" stop-color="{b}"/>\n'
        f'    </linearGradient>' for k, xy, (a, b) in grads)
    body = "\n".join("  " + p for p in art.parts)
    return f'''<?xml version="1.0" encoding="UTF-8"?>
<!-- {title}. Generated by scripts/build-app-icons.py; spec in docs/design/app-icon-spec.md. -->
<svg xmlns="http://www.w3.org/2000/svg" width="86" height="86" viewBox="0 0 86 86">
  <defs>
{defs}
  </defs>
  <path d="{art.field}" fill="{field}"/>
{body}
</svg>
'''


def phone(a):
    # One handset bowed into the square corner: a band about c whose inner
    # edge swells smoothly into the ear and mouth pieces at its rounded ends.
    k, ro, ri, rp, a1, a2, sp, tw, rr = 26.0, 58.0, 49.0, 40.0, 95.0, 175.0, 24.0, 12.0, 6.5
    c = (C0 + k, C0 - k)

    def r_in(t):
        e = min(t - a1, a2 - t)
        u = max(0.0, min(1.0, (e - sp) / tw))
        return rp + (ri - rp) * u * u * (3 - 2 * u)

    def p(r, t):
        x, y = pt(r, t, c)
        return f"{x:.2f} {y:.2f}"
    do, di = math.degrees(rr / ro), math.degrees(rr / rp)
    inner = [a2 - di - i * (a2 - a1 - 2 * di) / 90 for i in range(91)]
    a.pale(fill(f"M{p(ro, a1 + do)}A{ro} {ro} 0 0 1 {p(ro, a2 - do)}Q{p(ro, a2)} {p(ro - rr, a2)}"
                f"L{p(rp + rr, a2)}Q{p(rp, a2)} {p(rp, a2 - di)}"
                + "".join(f"L{p(r_in(t), t)}" for t in inner)
                + f"Q{p(rp, a1)} {p(rp + rr, a1)}L{p(ro - rr, a1)}Q{p(ro, a1)} {p(ro, a1 + do)}Z", "P"))


def messages(a):
    # The guide shape as the bubble, the square corner as its tail.
    t = 9.76
    bubble = (f"M{LO} {HI}c6.02 0 10.9 -4.285 10.9 -{t}H{C0}"
              f"A{R} {R - t} 0 0 0 {HI} {C0}A{R} {R} 0 0 0 {C0} {LO}A{R} {R} 0 0 0 {LO} {C0}Z")
    a.pale(fill(bubble, "P"))
    cy = (LO + HI - t) / 2
    a.add(*(f'<circle cx="{x}" cy="{cy:.2f}" r="5.4" fill="{{K}}"/>' for x in (C0 - 16, C0, C0 + 16)))


def email(a):
    # A paper envelope across the guide, cream as paper is; the flap and
    # the lower fold lighter.
    x0, y0, x1, y1 = LO, 22.0, HI, 64.0
    env = rect(x0, y0, x1, y1, 2.5)
    body, light = oklch(0.87, 0.05, LIGHT), oklch(0.97, 0.03, LIGHT)
    a.clip(env, f'<path d="{env}" fill="{body}"/>',
           f'<path d="M{x0} {y1}L{C0} 40L{x1} {y1}Z" fill="{light}" opacity="0.5"/>',
           f'<path d="M{x0} {y0}L{C0} 46L{x1} {y0}Z" fill="{light}" stroke="{body}" stroke-width="1.2"/>')


def browser(a):
    # The guide circle as the globe; meridian, equator and two parallels in
    # ink.
    disc = f"M{C0 + R} {C0}A{R} {R} 0 1 0 {C0 - R} {C0}A{R} {R} 0 1 0 {C0 + R} {C0}Z"
    a.pale(fill(disc, "P"))
    a.clip(disc, stroke(f"M{C0} {LO}A14 {R} 0 0 0 {C0} {HI}A14 {R} 0 0 0 {C0} {LO}"
                        f"M{LO} {C0}H{HI}M{C0 - 27} {C0 - 15}Q{C0} {C0 - 9} {C0 + 27} {C0 - 15}"
                        f"M{C0 - 27} {C0 + 15}Q{C0} {C0 + 21} {C0 + 27} {C0 + 15}", "K", 3.4))


def store(a):
    # A shopping bag: a handle about the bag's mouth, two rivets in ink.
    top = 32.0
    a.pale(stroke(arc(12, 180, 360, (C0, top)), "P", 5.4),
           fill(rect(15, top, 71, 71, 4), "P"),
           fill(rect(15, top, 71, top + 7, 0), "Q"))
    a.add(f'<circle cx="{C0 - 12}" cy="{top + 12}" r="2.8" fill="{{K}}"/>',
          f'<circle cx="{C0 + 12}" cy="{top + 12}" r="2.8" fill="{{K}}"/>')


def music(a):
    # Two beamed quavers.
    heads = "".join(f'<ellipse cx="{x}" cy="{y}" rx="9.5" ry="7.2" transform="rotate(-22 {x} {y})" fill="{{P}}"/>'
                    for x, y in ((26, 63), (58, 57)))
    a.pale(heads, fill("M31.5 63V24H37V63Z", "P"), fill("M63.5 57V16H69V57Z", "P"),
           fill("M31.5 22.5L69 14.5V25L31.5 33Z", "P"))


def camera(a):
    # A lens: the barrel in N fills the guide; deep glass, a highlight arc
    # and one accent glint.
    a.add(f'<circle cx="{C0}" cy="{C0}" r="{R}" fill="{{N}}"/>',
          f'<circle cx="{C0}" cy="{C0}" r="{R - 4.5}" fill="none" stroke="#FFFFFF" stroke-opacity="0.14" stroke-width="1.6"/>',
          '<radialGradient id="glass" cx="38" cy="38" r="26" gradientUnits="userSpaceOnUse">'
          f'<stop offset="0" stop-color="{oklch(0.52, 0.17, 262)}"/><stop offset="1" stop-color="{oklch(0.24, 0.10, 268)}"/>'
          '</radialGradient>',
          f'<circle cx="{C0}" cy="{C0}" r="21" fill="url(#glass)"/>',
          f'<circle cx="{C0}" cy="{C0}" r="8" fill="{oklch(0.20, 0.05, 40)}"/>',
          stroke(arc(14.5, 195, 245), "Q", 4.6),
          f'<circle cx="{pt(8.5, 45)[0]:.2f}" cy="{pt(8.5, 45)[1]:.2f}" r="4" fill="{{A}}"/>')


def gallery(a):
    # Two leaves from one stem, each the family shape drawn out along its
    # diagonal with the square corner at the stem; translucent where they
    # overlap.
    for rot, kx, ky, hh, op in ((-45, 0.76, 0.42, 88, 1), (-12, 0.6, 0.34, 150, 0.8)):
        a.add(f'<path d="{SHAPE}" fill="{oklch(0.82, 0.17, hh)}" opacity="{op}" transform="translate(15 73) '
              f'rotate({rot}) scale({kx} {ky}) rotate(45) translate({-IN} {IN - S})"/>')


def maps(a):
    # A folded map in three panels, the middle one Q, under a pin in the
    # accent: the family shape turned so its square corner points down.
    third = (HI - LO) / 3
    a.clip(inset(), fill(inset(), "P"), fill(rect(LO + third, 0, LO + 2 * third, S), "Q"),
           stroke(f"M{LO} 60C28 54 34 46 46 46S66 40 {HI} 30", "K", 3.6, "butt"))
    a.add(f'<g transform="translate(8 -9) rotate(-45 {C0} {C0})"><path d="{inset(23)}" fill="{{A}}"/>'
          f'<circle cx="{C0}" cy="{C0}" r="7" fill="{{P}}"/></g>')


def calendar(a):
    # The shape as the page, the hue a band across its top; the month's
    # days on it, today in ink.
    a.paper = True
    band = 27.0
    a.clip(SHAPE, f'<path d="{rect(0, 0, S, band)}" fill="url(#gBand)"/>')
    cells = []
    for row in range(3):
        for col in range(4):
            x, y = 19.25 + col * 12.5, 34.5 + row * 12.5
            cells.append((x, y))
    a.add(*(fill(rect(x, y, x + 10, y + 10, 1.5), "K" if (i == 5) else "Q") for i, (x, y) in enumerate(cells)))


def clock(a):
    # The guide circle as the dial; the hour hand points into the square
    # corner.
    a.pale(f'<circle cx="{C0}" cy="{C0}" r="{R}" fill="{{P}}"/>')
    hx, hy = pt(13, 135)
    a.add(stroke(f"M{C0} {C0 - 22}V{C0}L{hx:.2f} {hy:.2f}", "K", 6))


def calculator(a):
    # + ÷ × on the field; the square corner's quarter is the = key in the
    # accent.
    a.add(fill(rect(IN, C0 + 0.05, C0 - 0.05, S - IN, SQUARE), "A"))
    q, b, h = 16.2, 3.9, 8.8  # quarter offset, bar, half length
    tl, tr, br, bl = (C0 - q, C0 - q), (C0 + q, C0 - q), (C0 + q, C0 + q), (C0 - q, C0 + q)

    def bar(cx, cy, rot=0):
        return (f'<rect x="{cx - h}" y="{cy - b / 2}" width="{2 * h}" height="{b}" '
                f'transform="rotate({rot} {cx} {cy})" fill="{{P}}"/>')
    a.add(bar(*tl), bar(*tl, 90), bar(*tr),
          f'<circle cx="{tr[0]}" cy="{tr[1] - 6}" r="2.4" fill="{{P}}"/>',
          f'<circle cx="{tr[0]}" cy="{tr[1] + 6}" r="2.4" fill="{{P}}"/>',
          bar(*br, 45), bar(*br, -45),
          bar(bl[0] + 2, bl[1] + 2.2), bar(bl[0] + 2, bl[1] + 9))


def notes(a):
    # The shape as the page, the hue a band across its top, ruled; the
    # square corner folded over.
    a.paper = True
    f = 17.0
    a.field = SHAPE.replace(f"H{IN + SQUARE:.3f} A{SQUARE:.3f},{SQUARE:.3f} 0 0 1 {IN:.3f},{S - IN - SQUARE:.3f}",
                            f"H{IN + f}L{IN} {S - IN - f}")
    a.clip(a.field, f'<path d="{rect(0, 0, S, 15)}" fill="url(#gBand)"/>',
           *(stroke(f"M0 {y}H{S}", "M", 1.4, "butt") for y in (27, 36, 45, 54, 63, 72)),
           stroke("M19 52c4-10 10-19 13-15s-6 21-2 20 10-16 13-14-3 14 1 14 8-7 11-9", "K", 3.6))
    a.add(fill(f"M{IN} {S - IN - f}L{IN + f} {S - IN}V{S - IN - f}Z", "Q", ' stroke="{Q}" stroke-width="1.4" stroke-linejoin="round"'))


def settings(a):
    # A gear on the guide; a small one turning in the square corner.
    a.clip(SHAPE, f'<path d="{gear((12.5, 73.5), 8, 14, 10.5, 2.4, 5, 1.6, 0.8)}" fill="{{Q}}" fill-rule="evenodd"/>')
    a.pale(f'<path d="{gear((C0 + 1, C0 - 1), 8, 31.5, 25, 8, 11.5, 4.2, 1.6)}" fill="{{P}}" fill-rule="evenodd"/>')


def terminal(a):
    # A dark screen across the guide, the prompt in the accent.
    a.add(fill(rect(LO, 17, HI, 66, 4), "N"),
          stroke("M23 30L35 38.5L23 47", "A", 5.4),
          stroke("M41 53H55", "A", 5.4))


def test(a):
    # A flask: glass in P, the liquid in the accent, two bubbles.
    flask = "M36 13H50V33L70 64Q73 71 65 71H21Q13 71 16 64L36 33Z"
    a.pale(fill(flask, "P"), stroke("M33 13H53", "P", 5))
    a.clip(flask, fill("M0 50H86V86H0Z", "A"),
           '<circle cx="36" cy="60" r="3.2" fill="{P}"/><circle cx="48" cy="56" r="2.4" fill="{P}"/>')


# App: (title, hue, accent hue or None, draw), in home grid order.
ICONS = {
    "phone": ("Phone: a handset", 145.0, None, phone),
    "messages": ("Messages: a speech bubble", 212.5, None, messages),
    "email": ("Mail: an envelope", 280.0, None, email),
    "browser": ("Browser: a globe", 235.0, None, browser),
    "store": ("Store: a bag", 190.0, None, store),
    "music": ("Music: two quavers", 325.0, None, music),
    "camera": ("Camera: a lens", 32.5, 320.0, camera),
    "gallery": ("Gallery: two leaves", 302.5, None, gallery),
    "maps": ("Maps: a map and pin", 257.5, (0.66, 0.19, 30.0), maps),
    "calendar": ("Calendar: a month", 10.0, None, calendar),
    "clock": ("Clock: a dial", 77.5, None, clock),
    "calculator": ("Calculator: four keys", 167.5, 70.0, calculator),
    "notes": ("Notes: a ruled page", 100.0, None, notes),
    "settings": ("Settings: gears", 55.0, None, settings),
    "terminal": ("Terminal: a prompt", 122.5, (0.88, 0.2, 140.0), terminal),
    "test": ("Test: a flask", 347.5, 165.0, test),
}


if __name__ == "__main__":
    root = Path(sys.argv[1]) if len(sys.argv) > 1 else REPO / "apps"
    for app, (title, hue, accent, draw) in ICONS.items():
        out = root / app / "assets" / "icon.svg"
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(render(title, hue, accent, draw))
    print(f"{len(ICONS)} icons written")
