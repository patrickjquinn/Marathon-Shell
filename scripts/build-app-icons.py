#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Patrick Quinn
# SPDX-License-Identifier: Apache-2.0
"""Draw apps/<app>/assets/icon.svg for every first-party Marathon app.

Adapted from Shipwright's icons/make-icons.py, so Marathon's apps and the
Shipwright apps (Reef, Shoal, Pilot) are one family in the Sailfish OS icon
system (sailfishos.org/design/icons): an 86 x 86 icon, one of the 16 base
shapes, a gradient frame round a cream face of the same shape, one flat
object on the face. Spec: docs/design/app-icon-spec.md.

    scripts/build-app-icons.py [apps-dir]

- Shape. The square corner names the family: Reef the leaf, Shoal the
  bottom right, Pilot the top right, Marathon's own apps the bottom left.
- Colour. One hue per icon. The frame runs from its mid tone (bottom left)
  to its light tone (top right); the object is its deep tone D, with at
  most one darker plane E and one pale plane T; cut-outs are the face's
  cream. Hues are steps of 22.5 degrees round the OKLCH wheel.
- Object. Every object is the frame's shape inset to the guide line
  (OBJ), as Jolla's template guides metaphors inside: whole, sliced by a
  straight line, as its rim, turned, or set in further. The
  three round corners are quarter circles about the centre, so any circle
  or arc about the centre runs parallel to the contour. The square corner
  is the one cue the shape gives; a metaphor uses it (tail, fold, hand,
  tip, the = key) or leaves it alone.
- Cut-outs. At most two kinds per icon, in cream: CUT_W strokes with round
  caps (straight lines through or about the centre, or arcs about it) and
  DOT_R dots.
"""

import math
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
S, IN = 86.0, 0.3            # canvas, inset
ROUND, SQUARE = 42.7, 1.423  # corner radii
FACE_INSET = 8.0
OBJ = 16.0                   # the guide inset every object is built from
MARATHON = (True, True, True, False)  # (tl, tr, br, bl): bottom left square
CUT_W = 3.6                  # stroke of every cut-out line
DOT_R = 3.0                  # radius of every cut-out dot
C0 = 43.0                    # centre of every round corner's arc
R = ROUND - OBJ              # radius of the object's round contour
LO, HI = IN + OBJ, S - IN - OBJ  # the object's bounds


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
    """One hue's tones as gradient stop pairs (bottom left, top right): frame
    F, object D, darker plane E, pale plane T, cream face C, and the radial
    blend R (light centre, deep edge)."""
    y = 0.09 if 45 <= h <= 110 else 0.0  # yellows go brown when deep
    return {"F": (oklch(0.62, 0.18, h), oklch(0.80, 0.14, h + 15)),
            "D": (oklch(0.45 + y, 0.16, h), oklch(0.57 + y, 0.15, h + 6)),
            "E": (oklch(0.37 + y, 0.14, h), oklch(0.48 + y, 0.14, h + 6)),
            "T": (oklch(0.80, 0.09, h), oklch(0.88, 0.07, h + 6)),
            "C": ("#F1EBD3", "#FCF8EA"),
            "R": (oklch(0.68 + y, 0.13, h + 6), oklch(0.45 + y, 0.16, h))}


def base(tl, tr, br, bl, d=0.0):
    """The base shape, each corner True (round) or False (square); `d`
    insets it, keeping round corners concentric."""
    r = [(ROUND - d) if c else SQUARE for c in (tl, tr, br, bl)]
    a, b = IN + d, S - IN - d
    return (f"M{a + r[0]:.3f},{a:.3f} H{b - r[1]:.3f} A{r[1]:.3f},{r[1]:.3f} 0 0 1 {b:.3f},{a + r[1]:.3f} "
            f"V{b - r[2]:.3f} A{r[2]:.3f},{r[2]:.3f} 0 0 1 {b - r[2]:.3f},{b:.3f} "
            f"H{a + r[3]:.3f} A{r[3]:.3f},{r[3]:.3f} 0 0 1 {a:.3f},{b - r[3]:.3f} "
            f"V{a + r[0]:.3f} A{r[0]:.3f},{r[0]:.3f} 0 0 1 {a + r[0]:.3f},{a:.3f} Z")


def inset(d=OBJ):
    return base(*MARATHON, d=d)


def pt(r, a):
    """The point at radius r and angle a (degrees, clockwise from 3 o'clock)
    about the centre."""
    return C0 + r * math.cos(math.radians(a)), C0 + r * math.sin(math.radians(a))


def arc(r, a1, a2):
    """An arc of radius r about the centre from a1 to a2 degrees, clockwise."""
    (x1, y1), (x2, y2) = pt(r, a1), pt(r, a2)
    big = 1 if (a2 - a1) % 360 > 180 else 0
    return f"M{x1:.2f} {y1:.2f} A{r} {r} 0 {big} 1 {x2:.2f} {y2:.2f}"


def cut(d, colour="C"):
    return (f'<path d="{d}" fill="none" stroke="{{{colour}}}" stroke-width="{CUT_W}" '
            'stroke-linecap="round" stroke-linejoin="round"/>')


def dots(*xy, colour="C"):
    return "".join(f'<circle cx="{x:.2f}" cy="{y:.2f}" r="{DOT_R}" fill="{{{colour}}}"/>' for x, y in xy)


class Art:
    """One icon's layers; `{name}` in a layer is a palette colour."""

    def __init__(self, colours):
        self.c, self.parts, self.n = colours, [], 0

    def add(self, svg):
        self.parts.append(svg.format(**self.c))

    def plane(self, shape_d, region_d, fill):
        """Paint `region_d` in `fill`, clipped to the shape `shape_d`."""
        self.n += 1
        self.parts.append(f'<clipPath id="p{self.n}"><path d="{shape_d}"/></clipPath>'
                          f'<path d="{region_d}" fill="{self.c[fill]}" clip-path="url(#p{self.n})"/>')


def render(title, hue, draw):
    tones = palette(hue)
    art = Art({k: f"url(#g{k})" for k in tones})
    face = inset(FACE_INSET)
    art.add(f'<path d="{face}" fill="{{C}}"/>')
    art.parts.append(f'<clipPath id="face"><path d="{face}"/></clipPath>'
                     f'<path d="{face}" fill="none" stroke="#000000" stroke-opacity="0.08" '
                     'stroke-width="3" clip-path="url(#face)"/>')
    draw(art)
    diag = 'x1="0.717" y1="85.283" x2="85.283" y2="0.717"'
    radial = 'cx="40" cy="40" r="24"'
    grads = "\n".join(
        f'    <{"radialGradient" if k == "R" else "linearGradient"} id="g{k}" gradientUnits="userSpaceOnUse" '
        f'{radial if k == "R" else diag}>\n'
        f'      <stop offset="0" stop-color="{a}"/>\n      <stop offset="1" stop-color="{b}"/>\n'
        f'    </{"radialGradient" if k == "R" else "linearGradient"}>'
        for k, (a, b) in tones.items())
    body = "\n".join("  " + p for p in art.parts)
    return f'''<?xml version="1.0" encoding="UTF-8"?>
<!-- {title}. Generated by scripts/build-app-icons.py; spec in docs/design/app-icon-spec.md. -->
<svg xmlns="http://www.w3.org/2000/svg" width="86" height="86" viewBox="0 0 86 86">
  <defs>
{grads}
  </defs>
  <path d="{inset(0)}" fill="url(#gF)"/>
{body}
</svg>
'''


def phone(a):
    # The handset runs the inset's rim round the square corner: a stroke
    # along the contour, its ends turned inward as ear and mouth piece.
    w, a1, a2 = 10.0, 250, 20
    r = R - w / 2
    m = LO + w / 2
    (x1, y1), (x2, y2) = pt(r, a1), pt(r, a2)
    (e1, f1), (e2, f2) = pt(r - 8, a1 + 14), pt(r - 8, a2 - 14)
    a.add(f'<path d="M{e1:.2f} {f1:.2f}L{x1:.2f} {y1:.2f}A{r} {r} 0 0 0 {m} {C0}V{S - m}H{C0}'
          f'A{r} {r} 0 0 0 {x2:.2f} {y2:.2f}L{e2:.2f} {f2:.2f}" fill="none" stroke="{{D}}" '
          f'stroke-width="{w}" stroke-linecap="round" stroke-linejoin="round"/>')
    a.add(f'<path d="M{x1:.2f} {y1:.2f}L{e1:.2f} {f1:.2f}M{x2:.2f} {y2:.2f}L{e2:.2f} {f2:.2f}" '
          f'fill="none" stroke="{{D}}" stroke-width="{w + 4}" stroke-linecap="round"/>')


def messages(a):
    # The inset is the bubble and the square corner its tail.
    a.add(f'<path d="{inset()}" fill="{{D}}"/>')
    a.add(dots((C0 - 11, C0), (C0, C0), (C0 + 11, C0)))


def email(a):
    # The inset as the envelope, the flap a darker plane above the fold.
    a.add(f'<path d="{inset()}" fill="{{D}}"/>')
    (x1, y1), (x2, y2) = pt(R + 4, -158), pt(R + 4, -22)
    fold = f"M{x1:.2f} {y1:.2f}L{C0} 49L{x2:.2f} {y2:.2f}"
    a.plane(inset(), f"{fold}V0H{x1:.2f}Z", "E")
    a.add(cut(fold))


def browser(a):
    # The inset as the globe: its meridians are arcs of the face's radius.
    a.add(f'<path d="{inset()}" fill="{{D}}"/>')
    rf = ROUND - FACE_INSET
    a.add(cut(f"M{C0} {LO} A{rf} {rf} 0 0 0 {C0} {HI} A{rf} {rf} 0 0 0 {C0} {LO} M{LO - 2} {C0}H{HI + 2}"))


def store(a):
    # The inset's lower part as the bag, its handle an arc about the centre.
    a.plane(inset(), "M0 36H86V86H0Z", "D")
    a.add(f'<path d="{arc(14, 196, 344)}" fill="none" stroke="{{D}}" stroke-width="{CUT_W}" '
          'stroke-linecap="round"/>')


def music(a):
    # The inset as the record: a groove about the centre, the label cut out.
    a.add(f'<path d="{inset()}" fill="{{D}}"/>')
    a.add(cut(f"{arc(R - 7, -80, -20)} {arc(R - 7, 100, 160)}"))
    a.add(f'<circle cx="{C0}" cy="{C0}" r="8" fill="{{C}}"/><circle cx="{C0}" cy="{C0}" r="2.6" fill="{{D}}"/>')


def camera(a):
    # The inset as the body, the lens a ring about the centre.
    a.add(f'<path d="{inset()}" fill="{{D}}"/>')
    a.add(f'<circle cx="{C0}" cy="{C0}" r="13.5" fill="{{C}}"/><circle cx="{C0}" cy="{C0}" r="9.9" fill="{{R}}"/>')
    x, y = pt(4.5, -135)
    a.add(f'<circle cx="{x:.2f}" cy="{y:.2f}" r="2.4" fill="{{C}}"/>')


def gallery(a):
    # The inset as the picture: pale sky, a hill on an arc of the face's
    # radius, the sun a dot on the light's diagonal.
    a.add(f'<path d="{inset()}" fill="{{T}}"/>')
    rf = ROUND - FACE_INSET
    a.plane(inset(), f'M{62 - rf} 87A{rf} {rf} 0 0 1 {62 + rf} 87Z', "D")
    a.plane(inset(), f'M{22 - rf} 90A{rf} {rf} 0 0 1 {22 + rf} 90Z', "E")
    x, y = pt(13, -60)
    a.add(f'<circle cx="{x:.2f}" cy="{y:.2f}" r="5" fill="{{C}}"/>')


def maps(a):
    # The shape turned so its square corner points down: a pin.
    a.add(f'<g transform="translate(0 -5) rotate(-45 {C0} {C0})"><path d="{inset(22)}" fill="{{D}}"/></g>')
    a.add(f'<circle cx="{C0}" cy="{C0 - 5}" r="7.5" fill="{{C}}"/>')


def calendar(a):
    # The inset as the page, its top a darker band held by two rings.
    a.add(f'<path d="{inset()}" fill="{{D}}"/>')
    a.plane(inset(), "M0 0H86V33H0Z", "E")
    a.add(cut("M34 12V24M52 12V24"))
    a.add(dots(*((x, y) for y in (43, 53) for x in (32, 43, 54)), (32, 63)))


def clock(a):
    # The inset as the dial; the hour hand points into the square corner.
    a.add(f'<path d="{inset()}" fill="{{D}}"/>')
    (hx, hy), (mx, my) = pt(12, 135), pt(R - 7, -90)
    a.add(cut(f"M{mx:.2f} {my:.2f}L{C0} {C0}L{hx:.2f} {hy:.2f}"))


def calculator(a):
    # The inset in quarters about the centre, one key each; the square
    # corner's quarter is the = key.
    a.add(f'<path d="{inset()}" fill="{{D}}"/>')
    a.plane(inset(), f"M0 {C0}H{C0}V86H0Z", "E")
    k, o = 4.5, 11.5
    tl, tr, bl, br = (C0 - o, C0 - o), (C0 + o, C0 - o), (C0 - o, C0 + o), (C0 + o, C0 + o)
    a.add(cut(f"M{tl[0] - k} {tl[1]}h{2 * k}M{tl[0]} {tl[1] - k}v{2 * k}"
              f"M{tr[0] - k} {tr[1]}h{2 * k}"
              f"M{br[0] - k * .8} {br[1] - k * .8}l{1.6 * k} {1.6 * k}M{br[0] + k * .8} {br[1] - k * .8}l{-1.6 * k} {1.6 * k}"
              f"M{bl[0] - k} {bl[1] - 3}h{2 * k}M{bl[0] - k} {bl[1] + 3}h{2 * k}"))


def notes(a):
    # The inset as the page, its square corner folded over.
    a.add(f'<path d="{inset()}" fill="{{D}}"/>')
    f = 14.0
    a.add(f'<path d="M{LO - 1} {HI - f}V{HI + 1}H{LO + f}Z" fill="{{C}}"/>')
    a.add(f'<path d="M{LO} {HI - f}L{LO + f} {HI}V{HI - f}Z" fill="{{E}}" stroke="{{E}}" '
          'stroke-width="1" stroke-linejoin="round"/>')
    a.add(cut(f"M{LO + 6} 33H{HI - 6}M{LO + 6} 43H{HI - 6}M{LO + f + 6} 53H{HI - 10}"))


def settings(a):
    # The inset as the wheel, notched NOTCH deep round its contour on the
    # radials; the square corner is left whole as one tooth. Hub cut out.
    a.add(f'<path d="{inset()}" fill="{{D}}"/>')
    notches = " ".join("M{:.2f} {:.2f}L{:.2f} {:.2f}".format(*pt(R - 6, t), *pt(R + 6, t))
                       for t in (0, 45, 90, 180, 225, 270, 315))
    a.add(f'<path d="{notches}" fill="none" stroke="{{C}}" stroke-width="7"/>')
    a.add(f'<circle cx="{C0}" cy="{C0}" r="8" fill="{{C}}"/>')


def terminal(a):
    # The inset in E as the screen; the prompt runs along the diagonals.
    a.add(f'<path d="{inset()}" fill="{{E}}"/>')
    a.add(cut("M29 33L38 42L29 51"))
    a.add(cut("M43 52H56", "T"))


def test(a):
    # A flask: the deeper inset as its body, the neck rising to the guide.
    body = inset(OBJ + 6)
    a.add(f'<path d="{body}" fill="{{T}}"/>')
    a.plane(inset(), "M38 0H48V40H38Z", "T")
    a.plane(body, "M0 48H86V86H0Z", "D")
    a.add(dots((36, 60), (48, 56)))


# App: (title, hue, draw), in home grid order; hues from the 22.5-degree wheel.
ICONS = {
    "phone": ("Phone: a receiver", 122.5, phone),
    "messages": ("Messages: a speech bubble", 212.5, messages),
    "email": ("Mail: an envelope", 280.0, email),
    "browser": ("Browser: a globe", 235.0, browser),
    "store": ("Store: a bag", 167.5, store),
    "music": ("Music: a record", 325.0, music),
    "camera": ("Camera: a lens", 32.5, camera),
    "gallery": ("Gallery: a picture", 302.5, gallery),
    "maps": ("Maps: a pin", 100.0, maps),
    "calendar": ("Calendar: a month", 10.0, calendar),
    "clock": ("Clock: a dial", 77.5, clock),
    "calculator": ("Calculator: four keys", 257.5, calculator),
    "notes": ("Notes: a ruled page", 55.0, notes),
    "settings": ("Settings: a wheel", 190.0, settings),
    "terminal": ("Terminal: a prompt", 145.0, terminal),
    "test": ("Test: a flask", 347.5, test),
}


if __name__ == "__main__":
    root = Path(sys.argv[1]) if len(sys.argv) > 1 else REPO / "apps"
    for app, (title, hue, draw) in ICONS.items():
        out = root / app / "assets" / "icon.svg"
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(render(title, hue, draw))
    print(f"{len(ICONS)} icons written")
