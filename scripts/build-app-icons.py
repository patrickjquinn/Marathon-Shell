#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Patrick Quinn
# SPDX-License-Identifier: Apache-2.0
"""Draw apps/<app>/assets/icon.svg for every first-party Marathon app.

Shipwright's frame-and-face system on Jolla's launcher template
(sailfishos.org/design/icons). Spec: docs/design/app-icon-spec.md; colours:
docs/design/colour-palette.md.

    scripts/build-app-icons.py [apps-dir]     # needs picosvg (pip)

The drawing uses clip paths, which Qt's SVG renderer does not apply;
picosvg flattens each icon to plain paths before it is written.

- Shape. The Sailfish base shape; the square corners name the category.
- Frame, gap, object. The frame; a cream gap; the object is the same shape
  inset again, so every object contours its frame at one gap.
- Metaphor. Cut into the object in cream, or laid in its other tones,
  clipped to it. Matte: flat tones lit softly from the top; no highlights,
  glass or shadows.
"""

import math
import sys
from pathlib import Path

from picosvg.svg import SVG

REPO = Path(__file__).resolve().parent.parent
S, IN = 86.0, 0.3            # canvas, inset (template)
ROUND, SQUARE = 42.7, 1.423  # corner radii (template)
FACE_INSET = 8.0
OBJ = 16.0                   # the object: the shape inset again, 8 inside the face
# Each category squares its own corners (tl, tr, br, bl): Jolla's icon story
# picks a base shape per metaphor; Marathon picks one per category.
COMMS = (True, True, True, False)    # the bubble's tail
PLACES = (True, True, False, True)   # the pin's point
MEDIA = (True, True, True, True)     # the lens, the disc
TIME = (False, True, True, True)     # the page's corner
TOOLS = (False, True, False, True)   # two squared corners, machined
C0 = 43.0
CUT = 3.2                    # width of a cut-out line


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


def palette(h):
    """One hue's matte tones, each a pair of stops (top, bottom): frame F,
    object D, darker E, lighter L, tint T, cream C."""
    y = 0.09 if 45 <= h <= 110 else 0.0  # yellows go brown when deep
    f = 0.06 if 55 <= h <= 110 else 0.0  # and olive in the frame

    def tone(L, C):
        return oklch(L + 0.03, C, h + 4), oklch(L - 0.02, C, h)
    return {"F": tone(0.68 + f, 0.16),
            "D": tone(0.50 + y, 0.15),
            "E": tone(0.39 + y, 0.13),
            "L": tone(0.64 + y, 0.13),
            "T": tone(0.85, 0.07),
            "C": ("#F7F3E5", "#EFE9D4")}


def base(tl, tr, br, bl, d=0.0):
    """The base shape, each corner True (round) or False (square); `d`
    insets it, keeping round corners concentric."""
    r = [(ROUND - d) if c else SQUARE for c in (tl, tr, br, bl)]
    a, b = IN + d, S - IN - d
    return (f"M{a + r[0]:.3f},{a:.3f} H{b - r[1]:.3f} A{r[1]:.3f},{r[1]:.3f} 0 0 1 {b:.3f},{a + r[1]:.3f} "
            f"V{b - r[2]:.3f} A{r[2]:.3f},{r[2]:.3f} 0 0 1 {b - r[2]:.3f},{b:.3f} "
            f"H{a + r[3]:.3f} A{r[3]:.3f},{r[3]:.3f} 0 0 1 {a:.3f},{b - r[3]:.3f} "
            f"V{a + r[0]:.3f} A{r[0]:.3f},{r[0]:.3f} 0 0 1 {a + r[0]:.3f},{a:.3f} Z")




def pt(r, a, c=(C0, C0)):
    """The point at radius r, angle a (degrees clockwise from 3 o'clock)."""
    return c[0] + r * math.cos(math.radians(a)), c[1] + r * math.sin(math.radians(a))


def arc(r, a1, a2, c=(C0, C0)):
    """An arc of radius r about c from a1 to a2 degrees, clockwise."""
    (x1, y1), (x2, y2) = pt(r, a1, c), pt(r, a2, c)
    big = 1 if (a2 - a1) % 360 > 180 else 0
    return f"M{x1:.2f} {y1:.2f} A{r} {r} 0 {big} 1 {x2:.2f} {y2:.2f}"


def line(d, tone="C", w=CUT, cap="round"):
    return (f'<path d="{d}" fill="none" stroke="{{{tone}}}" stroke-width="{w}" '
            f'stroke-linecap="{cap}" stroke-linejoin="round"/>')


def rrect(x0, y0, x1, y1, r):
    return (f"M{x0 + r} {y0}H{x1 - r}A{r} {r} 0 0 1 {x1} {y0 + r}V{y1 - r}A{r} {r} 0 0 1 {x1 - r} {y1}"
            f"H{x0 + r}A{r} {r} 0 0 1 {x0} {y1 - r}V{y0 + r}A{r} {r} 0 0 1 {x0 + r} {y0}Z")


def disc(r, c=(C0, C0)):
    return f"M{c[0] - r} {c[1]}A{r} {r} 0 1 0 {c[0] + r} {c[1]}A{r} {r} 0 1 0 {c[0] - r} {c[1]}Z"


def poly(*p):
    return "M" + "L".join(f"{x:.2f} {y:.2f}" for x, y in p) + "Z"


class Art:
    """One icon's layers; `{name}` in a layer is a palette colour."""

    def __init__(self, colours, corners):
        self.c, self.corners, self.parts, self.n = colours, corners, [], 0
        self.obj = base(*corners, d=OBJ)

    def shape(self, d):
        """This icon's base shape, inset by d."""
        return base(*self.corners, d=d)

    def add(self, svg):
        self.parts.append(svg.format(**self.c))

    def fill(self, tone, d=None):
        """The object, or `d`, in `tone`."""
        self.add(f'<path d="{d or self.obj}" fill="{{{tone}}}"/>')

    def clip(self, svg, to=None):
        """`svg`, clipped to the object (or to the path `to`)."""
        self.n += 1
        self.parts.append(f'<clipPath id="k{self.n}"><path d="{to or self.obj}"/></clipPath>'
                          f'<g clip-path="url(#k{self.n})">{svg.format(**self.c)}</g>')

    def plane(self, region, tone, to=None):
        self.clip(f'<path d="{region}" fill="{{{tone}}}"/>', to)


def render(title, hue, corners, draw):
    tones = palette(hue)
    art = Art({k: f"url(#g{k})" for k in tones}, corners)
    art.add(f'<path d="{art.shape(FACE_INSET)}" fill="{{C}}"/>')
    draw(art)
    grads = "\n".join(
        f'    <linearGradient id="g{k}" gradientUnits="userSpaceOnUse" x1="0" y1="0" x2="0" y2="86">\n'
        f'      <stop offset="0" stop-color="{a}"/>\n      <stop offset="1" stop-color="{b}"/>\n'
        f'    </linearGradient>'
        for k, (a, b) in tones.items())
    body = "\n".join("  " + p for p in art.parts)
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="86" height="86" viewBox="0 0 86 86">
  <defs>
{grads}
  </defs>
  <path d="{base(*corners)}" fill="url(#gF)"/>
{body}
</svg>
'''


LO, HI = IN + OBJ, S - IN - OBJ  # the object's bounds


def band(c, ro, ri, a1, a2):
    """The ring between ri and ro about c, from a1 to a2 clockwise."""
    (x1, y1), (x2, y2), (x3, y3), (x4, y4) = pt(ro, a1, c), pt(ro, a2, c), pt(ri, a2, c), pt(ri, a1, c)
    return f"M{x1:.2f} {y1:.2f}A{ro} {ro} 0 0 1 {x2:.2f} {y2:.2f}L{x3:.2f} {y3:.2f}A{ri} {ri} 0 0 0 {x4:.2f} {y4:.2f}Z"


def phone(a):
    # A call: the handset cut out of the object, bowed into the square
    # corner, its voice rings opening toward the round one.
    a.fill("D")
    c, ro, ri, a1, a2 = (55.5, 30.5), 32.0, 23.5, 98.0, 172.0
    pads = "".join(f'<path d="{rrect(c[0] + ri - 7.5, c[1] + t0, c[0] + ro, c[1] + t0 + 12, 3.6)}" '
                   f'transform="rotate({ang} {c[0]} {c[1]})" fill="{{C}}"/>' for ang, t0 in ((a1, -7.5), (a2, -4.5)))
    a.add(f'<path d="{band(c, ro, ri, a1, a2)}" fill="{{C}}"/>' + pads)
    a.clip(line(arc(10, 105, 165, c), "L", 3) + line(arc(17, 108, 162, c), "L", 3))


def messages(a):
    # A conversation: a bubble inside the bubble, the typing dots cut out.
    a.fill("T")
    a.fill("D", a.shape(OBJ + 8))
    a.add("".join(f'<circle cx="{x}" cy="43" r="3" fill="{{C}}"/>' for x in (34, 43, 52)))


def email(a):
    # The object is the envelope: the flap darker above the fold.
    a.fill("D")
    a.plane("M0 0H86V30L43 49L0 30Z", "E")
    a.clip(line("M10 27 L43 49 L76 27"))


def browser(a):
    # The web: a globe's meridian and equator cut through the object, and
    # the pointer on it.
    a.fill("D")
    a.plane("M43 8 A13 35 0 0 1 43 78 A13 35 0 0 1 43 8Z", "L")
    a.clip(line("M43 8 A13 35 0 0 0 43 78 A13 35 0 0 0 43 8 M8 43 H78"))
    a.add(f'<path d="{poly((44, 44), (63, 51), (55, 54.5), (61.5, 61), (58, 64.5), (51.5, 58), (48, 66))}" '
          'fill="{C}" stroke="{C}" stroke-width="1.6" stroke-linejoin="round"/>')


def store(a):
    # The shelf: one app of each kind, each its category's shape.
    a.fill("D")
    k, w = 15.0 / S, 15.0
    for (x, y), corners in zip(((26, 26), (45, 26), (26, 45), (45, 45)), (COMMS, MEDIA, TIME, TOOLS)):
        a.add(f'<path d="{base(*corners)}" transform="translate({x} {y}) scale({k:.5f})" fill="{{C}}"/>')


def music(a):
    # A record: grooves about the centre, the label cut out.
    a.fill("E")
    a.add("".join(f'<circle cx="43" cy="43" r="{r}" fill="none" stroke="{{L}}" stroke-width="1"/>'
                  for r in (13, 16.5, 20, 23.5)))
    a.add(f'<path d="{disc(9.5)}" fill="{{C}}"/><path d="{disc(2.4)}" fill="{{E}}"/>')


def camera(a):
    # The aperture: six blades in turn round the opening.
    R0, ri = ROUND - OBJ, 9.0
    V = [pt(ri, 60 * k - 90) for k in range(6)]

    def hit(p, q):
        dx, dy, fx, fy = q[0] - p[0], q[1] - p[1], p[0] - C0, p[1] - C0
        A, B, Cc = dx * dx + dy * dy, 2 * (fx * dx + fy * dy), fx * fx + fy * fy - (R0 + 4) ** 2
        t = (-B + math.sqrt(B * B - 4 * A * Cc)) / (2 * A)
        return p[0] + t * dx, p[1] + t * dy
    P = [hit(V[k], V[(k + 1) % 6]) for k in range(6)]
    a.fill("E")
    for k, tone in zip(range(6), "DLDLDL"):
        v1, v2, p0, p1 = V[(k + 1) % 6], V[(k + 2) % 6], P[k], P[(k + 1) % 6]
        a.clip(f'<path d="{poly(v1, p0, p1, v2)}" fill="{{{tone}}}" stroke="{{C}}" stroke-width="1.6" '
               'stroke-linejoin="round"/>')


def gallery(a):
    # A picture through the round object: sky, two hills, the sun.
    a.fill("T")
    a.plane(disc(30, (24, 76)), "L")
    a.plane(disc(28, (64, 82)), "D")
    a.add('<circle cx="54" cy="32" r="6" fill="{C}"/>')


def maps(a):
    # A folded map, its panels in turn, and the heading arrow on it.
    a.fill("D")
    a.plane("M0 0H34.3V86H0Z", "L")
    a.plane("M51.7 0H86V86H51.7Z", "E")
    a.add(f'<path d="{poly((43, 25), (56, 59), (43, 51), (30, 59))}" fill="{{C}}" '
          'stroke="{C}" stroke-width="2" stroke-linejoin="round" transform="rotate(30 43 43)"/>')


def calendar(a):
    # The page: its top band held by two rings, the days cut out, today lit.
    a.fill("D")
    a.plane("M0 0H86V33H0Z", "E")
    a.clip(f'<path d="{rrect(30, 9, 35, 24, 2.5)}{rrect(51, 9, 56, 24, 2.5)}" fill="{{C}}"/>')
    days = [(x, y) for y in (39, 48.5, 58) for x in (24, 33.5, 43, 52.5)]
    a.clip("".join(f'<path d="{rrect(x, y, x + 6, y + 6, 1.4)}" fill="{{{"L" if (x, y) == (43, 48.5) else "C"}}}"/>'
                   for x, y in days))


def clock(a):
    # The dial: the quarter hour swept out to the object's edge, the hour
    # hand into the square corner.
    a.fill("D")
    a.plane("M43 43V0H86V43Z", "L")
    a.add("".join('<circle cx="{:.2f}" cy="{:.2f}" r="1.5" fill="{{C}}"/>'.format(*pt(21, t))
                  for t in range(0, 360, 30) if t not in (0, 270)))
    (hx, hy), (mx, my) = pt(13, 217.5), pt(20, 0)
    a.add(line(f"M43 43L{hx:.2f} {hy:.2f}", w=3.8) + line(f"M43 43L{mx:.2f} {my:.2f}", w=2.8))
    a.add('<circle cx="43" cy="43" r="3.4" fill="{C}"/>')


def notes(a):
    # The page, its square corner folded over, ruled.
    a.fill("D")
    f = 14.0
    a.add(f'<path d="{poly((LO - 1, LO + f + 1.5), (LO - 1, LO - 1), (LO + f + 1.5, LO - 1))}" fill="{{C}}"/>')
    a.add(f'<path d="{poly((LO, LO + f), (LO + f, LO), (LO + f, LO + f))}" fill="{{L}}"/>')
    a.clip(line(f"M{LO + 8} 40H{HI - 8}M{LO + 8} 49H{HI - 8}M{LO + 8} 58H{HI - 20}"))


def settings(a):
    # Adjustment: three sliders, each at its own setting.
    a.fill("D")
    for y, x in ((30, 52), (43, 32), (56, 45)):
        a.clip(line(f"M10 {y}H76"))
        a.add(f'<circle cx="{x}" cy="{y}" r="5.6" fill="{{E}}" stroke="{{C}}" stroke-width="3"/>')


def calculator(a):
    # Four keys: the object quartered by cut gaps; the = key lit.
    a.fill("D")
    a.plane("M43 43H86V86H43Z", "L")
    a.clip(line("M43 0V86M0 43H86", w=3.6, cap="butt"))
    s = 4.2
    a.add(line(f"M{31 - s} 31H{31 + s}M31 {31 - s}V{31 + s}M{55 - s} 31H{55 + s}"
               f"M{31 - s * .75} {55 - s * .75}L{31 + s * .75} {55 + s * .75}M{31 + s * .75} {55 - s * .75}L{31 - s * .75} {55 + s * .75}"
               f"M{55 - s} 52.5H{55 + s}M{55 - s} 57.5H{55 + s}", w=2.8))


def terminal(a):
    # A console: the screen dark under a title bar, the prompt and cursor.
    a.fill("E")
    a.plane("M0 0H86V27H0Z", "D")
    a.add(line("M27 37 L35 45 L27 53", w=3.2))
    a.add(f'<path d="{rrect(40, 50, 54, 54, 1)}" fill="{{T}}"/>')


def test(a):
    # A trial: the object is the vessel, the liquid line across it, bubbles.
    a.fill("T")
    wave = "M0 46 Q21.5 41 43 46 T86 46"
    a.plane(wave + "V86H0Z", "D")
    a.clip(line(wave, w=2.4))
    a.add('<circle cx="36" cy="60" r="2.8" fill="{C}"/><circle cx="48" cy="56" r="2" fill="{C}"/>'
          '<circle cx="43" cy="66" r="1.6" fill="{C}"/>')


def template(a):
    # A fresh sheet: the object ruled as a grid, a new app's plus on it.
    a.fill("T")
    a.clip(line("".join(f"M{v} 0V86M0 {v}H86" for v in range(25, 70, 9)), "L", 1.2))
    a.add(line("M43 30V56M30 43H56", "D", 5))


# App: (title, hue, shape, draw), in home grid order. Hues: five category
# families round the wheel from Marathon teal (172), skipping the olive band;
# see docs/design/colour-palette.md.
ICONS = {
    "phone": ("Phone: a call", 192.0, COMMS, phone),
    "messages": ("Messages: nested speech bubbles", 154.0, COMMS, messages),
    "email": ("Mail: an envelope", 172.0, COMMS, email),
    "browser": ("Browser: a globe", 234.0, PLACES, browser),
    "store": ("Store: a bag", 266.0, PLACES, store),
    "music": ("Music: a sound", 320.0, MEDIA, music),
    "camera": ("Camera: an aperture", 338.0, MEDIA, camera),
    "gallery": ("Gallery: a picture", 302.0, MEDIA, gallery),
    "maps": ("Maps: a pin", 250.0, PLACES, maps),
    "calendar": ("Calendar: a month", 56.0, TIME, calendar),
    "clock": ("Clock: a dial", 70.0, TIME, clock),
    "calculator": ("Calculator: four keys", 8.0, TOOLS, calculator),
    "notes": ("Notes: a ruled page", 84.0, TIME, notes),
    "settings": ("Settings: a wheel", 36.0, TOOLS, settings),
    "terminal": ("Terminal: a prompt", 354.0, TOOLS, terminal),
    "template": ("Template: a blueprint", 46.0, TOOLS, template),
    "test": ("Test: a flask", 22.0, TOOLS, test),
}


if __name__ == "__main__":
    root = Path(sys.argv[1]) if len(sys.argv) > 1 else REPO / "apps"
    for app, (title, hue, corners, draw) in ICONS.items():
        out = root / app / "assets" / "icon.svg"
        out.parent.mkdir(parents=True, exist_ok=True)
        flat = SVG.fromstring(render(title, hue, corners, draw)).topicosvg().tostring(pretty_print=True)
        out.write_text(f"<!-- {title}. Generated by scripts/build-app-icons.py; spec in "
                       f"docs/design/app-icon-spec.md. -->\n{flat}")
    print(f"{len(ICONS)} icons written")
