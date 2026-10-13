#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Patrick Quinn
# SPDX-License-Identifier: Apache-2.0
"""Draw apps/<app>/assets/icon.svg for every first-party Marathon app.

Shipwright's icon system (Shipwright icons/make-icons.py), itself built on
Jolla's launcher template (sailfishos.org/design/icons). Spec:
docs/design/app-icon-spec.md.

    scripts/build-app-icons.py [apps-dir]

- Shape. 86 x 86, the Sailfish base shape; Marathon's family squares the
  bottom-left corner, beside Reef (leaf), Shoal (bottom right) and Pilot
  (top right).
- Colour. One OKLCH hue per icon: a gradient frame round a cream face, the
  object in the hue's deep tone with a darker facet, a lighter plane and a
  pale tint; details cut out in the face's cream.
- Object. One flat object on the face, built from the frame: the shape set
  in concentrically, or circles and arcs about the centre.
"""

import math
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
S, IN = 86.0, 0.3            # canvas, inset (template)
ROUND, SQUARE = 42.7, 1.423  # corner radii (template)
FACE_INSET = 8.0
MARATHON = (True, True, True, False)  # (tl, tr, br, bl)
C0 = 43.0
CUT = 3.4                    # width of a cut-out line


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
    """Shipwright's tones, each a gradient pair (bottom left, top right):
    frame F, object D, facet E, plane L, tint T, cream face C, and the
    radial R (light centre, deep edge)."""
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


class Art:
    """One icon's layers; `{name}` in a layer is a palette colour."""

    def __init__(self, colours):
        self.c, self.parts, self.n = colours, [], 0

    def add(self, svg):
        self.parts.append(svg.format(**self.c))

    def plane(self, shape_d, region_d, fill):
        """Paint `region_d` in `fill`, clipped to `shape_d`."""
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
    # The handset, bowed into the square corner, its ends turned in as ear
    # and mouth pieces.
    c, r, a1, a2 = (54.5, 32.0), 26.0, 82.0, 188.0
    a.add(line(arc(r, a1, a2, c), "D", 10))
    for ang in (a1, a2):
        (x0, y0), (x1, y1) = pt(r, ang, c), pt(r - 8, ang, c)
        a.add(line(f"M{x0:.2f} {y0:.2f}L{x1:.2f} {y1:.2f}", "D", 15))


def messages(a):
    # The shape is already a bubble, its tail the square corner: two
    # nested, the typing dots cut out.
    a.add(f'<path d="{inset(15)}" fill="{{T}}"/><path d="{inset(23)}" fill="{{D}}"/>')
    a.add("".join(f'<circle cx="{x}" cy="43" r="3.4" fill="{{C}}"/>' for x in (33, 43, 53)))


def email(a):
    # The shape inset as the envelope, its flap a darker facet, the fold cut.
    env = inset(17)
    a.add(f'<path d="{env}" fill="{{D}}"/>')
    a.plane(env, "M0 0H86V31L43 48L0 31Z", "E")
    a.add(line("M20 31 L43 48 L66 31"))


def browser(a):
    # The globe: a disc about the centre, a meridian and the equator cut out.
    a.add('<circle cx="43" cy="43" r="25" fill="{D}"/>')
    a.add(line("M43 18 A11 25 0 0 0 43 68 A11 25 0 0 0 43 18 M18 43 H68 M23 31 H63 M23 55 H63", w=3))


def store(a):
    # The bag: the shape inset below its rim, the handle an arc above.
    bag = inset(17)
    a.add(line(arc(10, 180, 360, (43, 36)), "E", 4.5))
    a.plane(bag, "M0 33H86V86H0Z", "D")
    a.plane(bag, "M0 33H86V39H0Z", "E")
    a.add('<circle cx="33" cy="45" r="2.8" fill="{C}"/><circle cx="53" cy="45" r="2.8" fill="{C}"/>')


def music(a):
    # Two quavers on one beam.
    a.add('<g fill="{D}" transform="translate(0 3)"><ellipse cx="31" cy="59" rx="7.5" ry="5.6" transform="rotate(-22 31 59)"/>'
          '<ellipse cx="56" cy="53" rx="7.5" ry="5.6" transform="rotate(-22 56 53)"/>'
          '<rect x="34.5" y="27" width="4" height="32"/><rect x="59.5" y="21" width="4" height="32"/>'
          '<path d="M34.5 24 L63.5 17 V26 L34.5 33 Z"/></g>')


def camera(a):
    # The body is the shape inset and cut short; the lens a ring about the
    # centre, the glass one radial blend.
    body = inset(16)
    a.add('<rect x="27" y="19" width="15" height="8" rx="2.5" fill="{E}"/>')
    a.plane(body, "M0 24H86V66H0Z", "D")
    a.add('<circle cx="43" cy="45" r="14" fill="{C}"/><circle cx="43" cy="45" r="10.5" fill="{R}"/>'
          '<circle cx="43" cy="45" r="3.8" fill="{E}"/><circle cx="39.5" cy="41.5" r="2.2" fill="{C}"/>'
          '<circle cx="62" cy="31.5" r="2.4" fill="{T}"/>')


def gallery(a):
    # The picture: the shape inset, a pale sky, two hills on arcs, the sun.
    pic = inset(16)
    a.add(f'<path d="{pic}" fill="{{T}}"/>')
    a.plane(pic, "M2 76 A28 28 0 0 1 58 76 Z", "E")
    a.plane(pic, "M32 80 A25 25 0 0 1 82 80 Z", "D")
    a.add('<circle cx="55" cy="32" r="5.5" fill="{C}"/>')


def maps(a):
    # The shape turned so its square corner points down is the pin.
    a.add('<ellipse cx="43" cy="68.5" rx="13" ry="3.6" fill="{T}"/>')
    a.add(f'<path d="{inset(23)}" transform="translate(0 -4) rotate(-45 43 43)" fill="{{D}}"/>')
    a.add('<circle cx="43" cy="39" r="7" fill="{C}"/>')


def calendar(a):
    # The page: the shape inset, its top band a facet held by two rings,
    # the days as dots and today a disc.
    page = inset(16)
    a.add(f'<path d="{page}" fill="{{T}}"/>')
    a.plane(page, "M0 0H86V33H0Z", "D")
    a.add(line("M33 13V24M53 13V24", "E", 4.2))
    days = [(x, y) for y in (42, 52, 62) for x in (30, 39, 48, 57)][:10]
    a.add("".join(f'<circle cx="{x}" cy="{y}" r="2.6" fill="{{D}}"/>' for x, y in days if (x, y) != (48, 52)))
    a.add('<circle cx="48" cy="52" r="4.6" fill="{E}"/>')


def clock(a):
    # The dial about the centre; the hour hand points into the square corner.
    a.add('<circle cx="43" cy="43" r="26" fill="{D}"/>')
    ticks = " ".join("M{:.2f} {:.2f}L{:.2f} {:.2f}".format(*pt(21, t), *pt(24, t)) for t in (0, 90, 180, 270))
    a.add(line(ticks, "T", 2.6))
    (hx, hy), (mx, my) = pt(11, 135), pt(17, 270)
    a.add(line(f"M{mx:.2f} {my:.2f}L43 43L{hx:.2f} {hy:.2f}"))
    a.add('<circle cx="43" cy="43" r="3" fill="{C}"/>')


def calculator(a):
    # Four keys, each the shape in small; the = key the lighter plane.
    k = 19.5 / S
    keys = ((22, 22, "D", "M{0} {1}h7M{2} {3}v7"), (44.5, 22, "D", "M{0} {1}h7"),
            (22, 44.5, "D", "M{4} {5}l5 5M{6} {5}l-5 5"), (44.5, 44.5, "L", "M{0} {7}h7M{0} {8}h7"))
    for x, y, tone, sym in keys:
        a.add(f'<path d="{inset(0)}" transform="translate({x} {y}) scale({k:.5f})" fill="{{{tone}}}"/>')
        cx, cy = x + 9.75, y + 9.75
        a.add(line(sym.format(cx - 3.5, cy, cx, cy - 3.5, cx - 2.5, cy - 2.5, cx + 2.5, cy - 2.2, cy + 2.2), w=2.6))


def notes(a):
    # The page: the shape inset, its square corner folded over, ruled.
    page = inset(16)
    a.add(f'<path d="{page}" fill="{{D}}"/>')
    f = 13.0
    lo, hi = 16.3, S - 16.3
    a.add(f'<path d="M{lo - 1} {hi - f}V{hi + 1}H{lo + f}Z" fill="{{C}}"/>')
    a.add(f'<path d="M{lo} {hi - f}L{lo + f} {hi}V{hi - f}Z" fill="{{L}}" stroke="{{L}}" '
          'stroke-width="1" stroke-linejoin="round"/>')
    a.add(line(f"M{lo + 8} 32H{hi - 8}M{lo + 8} 42H{hi - 8}M{lo + f + 6} 52H{hi - 14}"))


def gear(teeth, ro, ri, tip, root, c=(C0, C0)):
    """A gear outline: `teeth` teeth from ri to ro, `tip` and `root` the
    half-widths of tooth and gap at their radii, in degrees."""
    step, d = 360.0 / teeth, ""
    for i in range(teeth):
        t = i * step - 90
        for r, a in ((ri, t - step / 2 + root), (ro, t - tip), (ro, t + tip), (ri, t + step / 2 - root)):
            x, y = pt(r, a, c)
            d += f"{'L' if d else 'M'}{x:.2f} {y:.2f}"
    return d + "Z"


def settings(a):
    # The wheel about the centre, the hub cut out.
    a.add(f'<path d="{gear(8, 26, 19.5, 9, 4)}" fill="{{D}}" stroke="{{D}}" stroke-width="2.5" '
          'stroke-linejoin="round"/>')
    a.add('<circle cx="43" cy="43" r="9" fill="{C}"/>')


def terminal(a):
    # The screen: the shape inset in the facet; the prompt and the cursor.
    a.add(f'<path d="{inset(16)}" fill="{{E}}"/>')
    a.add(line("M27 33 L36 42 L27 51", w=3.8))
    a.add(line("M42 52 H57", "T", 3.8))


def test(a):
    # A flask: the glass in the tint, the liquid in the deep tone, bubbles cut.
    flask = "M38 20 H48 V34 L64 60 Q67 66 60 66 H26 Q19 66 22 60 L38 34 Z"
    a.add(f'<path d="{flask}" fill="{{T}}" stroke="{{T}}" stroke-width="2" stroke-linejoin="round"/>')
    a.plane(flask, "M0 50 Q21.5 46 43 50 T86 50 V86 H0 Z", "D")
    a.add(line("M34 19 H52", "E", 4))
    a.add('<circle cx="37" cy="58" r="2.6" fill="{C}"/><circle cx="48" cy="55" r="1.9" fill="{C}"/>')


# App: (title, hue, draw), in home grid order; hues are 22.5-degree steps,
# no two grid neighbours closer than 45 degrees.
ICONS = {
    "phone": ("Phone: a handset", 145.0, phone),
    "messages": ("Messages: nested speech bubbles", 212.5, messages),
    "email": ("Mail: an envelope", 280.0, email),
    "browser": ("Browser: a globe", 235.0, browser),
    "store": ("Store: a bag", 190.0, store),
    "music": ("Music: two quavers", 325.0, music),
    "camera": ("Camera: a lens", 32.5, camera),
    "gallery": ("Gallery: a picture", 302.5, gallery),
    "maps": ("Maps: a pin", 257.5, maps),
    "calendar": ("Calendar: a month", 10.0, calendar),
    "clock": ("Clock: a dial", 77.5, clock),
    "calculator": ("Calculator: four keys", 167.5, calculator),
    "notes": ("Notes: a ruled page", 100.0, notes),
    "settings": ("Settings: a wheel", 55.0, settings),
    "terminal": ("Terminal: a prompt", 122.5, terminal),
    "test": ("Test: a flask", 347.5, test),
}


if __name__ == "__main__":
    root = Path(sys.argv[1]) if len(sys.argv) > 1 else REPO / "apps"
    for app, (title, hue, draw) in ICONS.items():
        out = root / app / "assets" / "icon.svg"
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(render(title, hue, draw))
    print(f"{len(ICONS)} icons written")
