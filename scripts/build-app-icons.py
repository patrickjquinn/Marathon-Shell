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
  to its light tone (top right); the object is its deep tone with a darker
  facet and a pale tint; details are cut out in the face's cream. Hues are
  steps of 22.5 degrees round the OKLCH wheel, Store's on Marathon teal, so
  every icon has the same weight and no two neighbours on the home grid
  are within 45 degrees.
- Objects are the frame shape set in concentrically, or circles and arcs
  about the centre, with one cut-out.
"""

import math
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
S, IN = 86.0, 0.3            # canvas, inset
ROUND, SQUARE = 42.7, 1.423  # corner radii
FACE_INSET = 8.0
MARATHON = (True, True, True, False)  # (tl, tr, br, bl): bottom left square
CUT_W = 3.6                  # stroke of every cut-out line


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
    F, object D, darker facet E, lighter plane L, tint T, cream face C, and
    the radial blend R (light centre, deep edge)."""
    y = 0.09 if 45 <= h <= 110 else 0.0  # yellows go brown when deep
    return {"F": (oklch(0.62, 0.18, h), oklch(0.80, 0.14, h + 15)),
            "D": (oklch(0.45 + y, 0.16, h), oklch(0.57 + y, 0.15, h + 6)),
            "E": (oklch(0.37 + y, 0.14, h), oklch(0.48 + y, 0.14, h + 6)),
            "L": (oklch(0.56 + y, 0.15, h), oklch(0.68 + y, 0.13, h + 6)),
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


def inset(d):
    return base(*MARATHON, d=d)


def arc(r, a1, a2):
    """An arc of radius r about the centre from a1 to a2 degrees, clockwise."""
    p = lambda a: (43 + r * math.cos(math.radians(a)), 43 + r * math.sin(math.radians(a)))
    (x1, y1), (x2, y2) = p(a1), p(a2)
    big = 1 if (a2 - a1) % 360 > 180 else 0
    return f"M{x1:.2f} {y1:.2f} A{r} {r} 0 {big} 1 {x2:.2f} {y2:.2f}"


def cut(d, colour="C"):
    return (f'<path d="{d}" fill="none" stroke="{{{colour}}}" stroke-width="{CUT_W}" '
            'stroke-linecap="round" stroke-linejoin="round"/>')


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
    # The handset, ear piece at the top left, bowing to the square corner.
    a.add('<path transform="translate(14.2 13) scale(2.4)" fill="{D}" d="M5.5 4l3.2.8 1.6 4-2.1 1.7'
          'a12 12 0 0 0 5.4 5.4l1.7-2.1 4 1.6.8 3.2a2 2 0 0 1-2 2.4A17 17 0 0 1 3.1 6.5a2 2 0 0 1 2.4-2z"/>')


def messages(a):
    # The shape is already a speech bubble, its tail the square corner.
    a.add(f'<path d="{inset(16)}" fill="{{D}}"/>')
    a.add(cut("M30 36H56M30 48H46"))


def email(a):
    env = inset(17)
    a.add(f'<path d="{env}" fill="{{D}}"/>')
    a.plane(env, "M0 22L43 49L86 22V0H0Z", "E")
    a.add(cut("M19 26L43 49L67 26"))


def browser(a):
    a.add('<circle cx="43" cy="43" r="25" fill="{D}"/>')
    a.add(cut("M43 19.5A10.5 23.5 0 0 1 43 66.5A10.5 23.5 0 0 1 43 19.5Z M20 43H66"))


def store(a):
    # The Marathon mark cut through the inset shape.
    a.add(f'<path d="{inset(16)}" fill="{{D}}"/>')
    a.add('<path transform="translate(23.8 23) scale(1.6)" fill="{C}" '
          'd="M3 20V5h2.5l6.5 9 6.5-9H21v15h-2.8V10.5L13 18h-2L5.8 10.5V20z"/>')


def music(a):
    # A record: grooves catching the light, then the label.
    a.add('<circle cx="43" cy="43" r="26" fill="{E}"/>')
    a.add(f'<path d="{arc(19, 200, 250)} {arc(19, 20, 70)}" fill="none" stroke="{{T}}" '
          'stroke-width="2.4" stroke-linecap="round"/>')
    a.add('<circle cx="43" cy="43" r="9.5" fill="{T}"/><circle cx="43" cy="43" r="2.6" fill="{E}"/>')


def camera(a):
    body = "M24 29H31L35 23H51L55 29H62A6 6 0 0 1 68 35V58A6 6 0 0 1 62 64H24A6 6 0 0 1 18 58V35A6 6 0 0 1 24 29Z"
    a.add(f'<path d="{body}" fill="{{D}}" stroke="{{D}}" stroke-width="1" stroke-linejoin="round"/>')
    a.add('<circle cx="43" cy="46" r="13" fill="{C}"/><circle cx="43" cy="46" r="9.5" fill="{R}"/>'
          '<circle cx="39.5" cy="42.5" r="2.4" fill="{C}"/>')


def gallery(a):
    shape = inset(16)
    a.add(f'<path d="{shape}" fill="{{T}}"/>')
    a.plane(shape, "M10 64L31 41L44 54L52 46L76 68V86H10Z", "D")
    a.add('<circle cx="53" cy="31" r="5.5" fill="{C}"/>')


def maps(a):
    # A pin: the family shape turned so its square corner points down.
    pin = base(*MARATHON, d=24)
    a.add(f'<g transform="translate(0 -4) rotate(-45 43 43)"><path d="{pin}" fill="{{D}}"/></g>')
    a.add('<circle cx="43" cy="39" r="7" fill="{C}"/>')


def calendar(a):
    page = inset(17)
    a.add(f'<path d="{page}" fill="{{D}}"/>')
    a.plane(page, "M0 0H86V35H0Z", "E")
    a.add(''.join(f'<circle cx="{x}" cy="{y}" r="2.4" fill="{{C}}"/>'
                  for y in (44, 53) for x in (31, 39, 47, 55)) +
          '<circle cx="31" cy="62" r="2.4" fill="{C}"/><circle cx="39" cy="62" r="2.4" fill="{C}"/>')
    a.add(cut("M33 23V29M53 23V29"))


def clock(a):
    a.add('<circle cx="43" cy="43" r="26" fill="{D}"/>')
    a.add(cut("M43 43V26M43 43L54 50"))
    a.add('<circle cx="43" cy="43" r="3.4" fill="{C}"/>')


def calculator(a):
    a.add(f'<path d="{inset(16)}" fill="{{D}}"/>')
    a.add(cut("M33 27.5V38.5M27.5 33H38.5 M47.5 33H58.5 M29 49L37 57M37 49L29 57 M47.5 50H58.5M47.5 56H58.5"))


def notes(a):
    # A page with its top right corner turned down.
    page = "M28 18H50L64 32V62A6 6 0 0 1 58 68H28A6 6 0 0 1 22 62V24A6 6 0 0 1 28 18Z"
    a.add(f'<path d="{page}" fill="{{D}}"/>')
    a.add('<path d="M50 18V28A4 4 0 0 0 54 32H64Z" fill="{E}"/>')
    a.add(cut("M30 42H56M30 51H56M30 60H44"))


def settings(a):
    teeth, ro, ri = 8, 27.0, 21.0
    pts = []
    for i in range(teeth):
        c = i * 360 / teeth - 90
        for da, r in ((-15, ri), (-9, ro), (9, ro), (15, ri)):
            ang = math.radians(c + da)
            pts.append(f"{43 + r * math.cos(ang):.2f} {43 + r * math.sin(ang):.2f}")
    a.add(f'<path d="M{" L".join(pts)}Z" fill="{{D}}" stroke="{{D}}" stroke-width="2" stroke-linejoin="round"/>')
    a.add('<circle cx="43" cy="43" r="8.5" fill="{C}"/>')


def terminal(a):
    a.add(f'<path d="{inset(16)}" fill="{{E}}"/>')
    a.add(cut("M28 33L37 42L28 51"))
    a.add(cut("M42 52H56", "T"))


def test(a):
    flask = "M36 19H50V36L64 59A6 6 0 0 1 58.8 68H27.2A6 6 0 0 1 22 59L36 36Z"
    a.add(f'<path d="{flask}" fill="{{T}}" stroke="{{T}}" stroke-width="1.5" stroke-linejoin="round"/>')
    a.plane(flask, "M0 50H86V86H0Z", "D")
    a.add('<circle cx="39" cy="59" r="2.6" fill="{C}"/><circle cx="47" cy="55" r="1.9" fill="{C}"/>')


# App: (title, hue, draw), in home grid order; hues from the 22.5-degree wheel.
ICONS = {
    "phone": ("Phone: a handset", 122.5, phone),
    "messages": ("Messages: a speech bubble", 212.5, messages),
    "email": ("Mail: an envelope", 280.0, email),
    "browser": ("Browser: a globe", 235.0, browser),
    "store": ("Store: the Marathon mark", 167.5, store),
    "music": ("Music: a record", 325.0, music),
    "camera": ("Camera: a camera", 32.5, camera),
    "gallery": ("Gallery: a picture", 302.5, gallery),
    "maps": ("Maps: a pin", 100.0, maps),
    "calendar": ("Calendar: a month", 10.0, calendar),
    "clock": ("Clock: a dial", 77.5, clock),
    "calculator": ("Calculator: the four operations", 257.5, calculator),
    "notes": ("Notes: a ruled page", 55.0, notes),
    "settings": ("Settings: a gear", 190.0, settings),
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
