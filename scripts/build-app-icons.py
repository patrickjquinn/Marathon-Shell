#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Patrick Quinn
# SPDX-License-Identifier: Apache-2.0
"""Draw apps/<app>/assets/icon.svg for every first-party Marathon app.

Shipwright's icon system (Shipwright icons/make-icons.py), itself built on
Jolla's launcher template (sailfishos.org/design/icons). Spec:
docs/design/app-icon-spec.md.

    scripts/build-app-icons.py [apps-dir]     # needs picosvg (pip)

The drawing uses clip paths, which Qt's SVG renderer does not apply;
picosvg flattens each icon to plain paths before it is written.

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

from picosvg.svg import SVG

REPO = Path(__file__).resolve().parent.parent
S, IN = 86.0, 0.3            # canvas, inset (template)
ROUND, SQUARE = 42.7, 1.423  # corner radii (template)
FACE_INSET = 8.0
MARATHON = (True, True, True, False)  # (tl, tr, br, bl)
C0 = 43.0
CUT = 2.6                    # width of a cut-out line


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
    frame F, object D, its lit facet H, darker facet E, plane L, tint T,
    cream face C, and the radial R (light centre, deep edge)."""
    y = 0.09 if 45 <= h <= 110 else 0.0  # yellows go brown when deep
    return {"F": (oklch(0.62, 0.18, h), oklch(0.80, 0.14, h + 15)),
            "D": (oklch(0.45 + y, 0.16, h), oklch(0.57 + y, 0.15, h + 6)),
            "E": (oklch(0.37 + y, 0.14, h), oklch(0.48 + y, 0.14, h + 6)),
            "H": (oklch(0.51 + y, 0.155, h), oklch(0.63 + y, 0.14, h + 6)),
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

    def __init__(self, colours, prefix="p"):
        self.c, self.parts, self.n, self.prefix = colours, [], 0, prefix

    def add(self, svg):
        self.parts.append(svg.format(**self.c))

    def plane(self, shape_d, region_d, fill):
        """Paint `region_d` in `fill`, clipped to `shape_d`."""
        self.n += 1
        cid = f"{self.prefix}{self.n}"
        self.parts.append(f'<clipPath id="{cid}"><path d="{shape_d}"/></clipPath>'
                          f'<path d="{region_d}" fill="{self.c[fill]}" clip-path="url(#{cid})"/>')

    def lit(self, *shapes, tone="D"):
        """The shapes in `tone`, their top-right half (toward the light) in
        the lit facet. A shape is a path, or (path, transform)."""
        els = "".join(f'<path d="{d}"' + (f' transform="{t}"' if t else "") + "/>"
                      for d, t in ((x, "") if isinstance(x, str) else x for x in shapes))
        self.n += 1
        cid = f"{self.prefix}{self.n}"
        lit = self.c["H" if tone == "D" else "L"]
        self.parts.append(f'<g fill="{self.c[tone]}">{els}</g><clipPath id="{cid}">{els}</clipPath>'
                          f'<path d="M0 0H86V86Z" fill="{lit}" clip-path="url(#{cid})"/>')


def render(title, hue, draw):
    tones = palette(hue)
    art = Art({k: f"url(#g{k})" for k in tones})
    face = inset(FACE_INSET)
    art.add(f'<path d="{face}" fill="{{C}}"/>')
    art.parts.append(f'<clipPath id="face"><path d="{face}"/></clipPath>'
                     f'<path d="{face}" fill="none" stroke="#000000" stroke-opacity="0.08" '
                     'stroke-width="3" clip-path="url(#face)"/>')
    # The object's contact shadow: its silhouette, dropped and faint.
    shadow = Art({k: "none" if k == "C" else "#000000" for k in tones}, "s")
    draw(shadow)
    art.parts.append('<g opacity="0.13" transform="translate(0 1.5)">' + "".join(shadow.parts) + "</g>")
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



def band(c, ro, ri, a1, a2):
    """The ring between ri and ro about c, from a1 to a2 clockwise."""
    (x1, y1), (x2, y2) = pt(ro, a1, c), pt(ro, a2, c)
    (x3, y3), (x4, y4) = pt(ri, a2, c), pt(ri, a1, c)
    big = 1 if (a2 - a1) % 360 > 180 else 0
    return (f"M{x1:.2f} {y1:.2f}A{ro} {ro} 0 {big} 1 {x2:.2f} {y2:.2f}L{x3:.2f} {y3:.2f}"
            f"A{ri} {ri} 0 {big} 0 {x4:.2f} {y4:.2f}Z")


def rrect(x0, y0, x1, y1, r):
    return (f"M{x0 + r} {y0}H{x1 - r}A{r} {r} 0 0 1 {x1} {y0 + r}V{y1 - r}A{r} {r} 0 0 1 {x1 - r} {y1}"
            f"H{x0 + r}A{r} {r} 0 0 1 {x0} {y1 - r}V{y0 + r}A{r} {r} 0 0 1 {x0 + r} {y0}Z")


def disc(r, c=(C0, C0)):
    return f"M{c[0] - r} {c[1]}A{r} {r} 0 1 0 {c[0] + r} {c[1]}A{r} {r} 0 1 0 {c[0] - r} {c[1]}Z"


def phone(a):
    # A call: the handset a band bowed into the square corner, its ear and
    # mouth pieces turned in; two waves about the same centre.
    c, ro, ri, a1, a2 = (55.0, 31.0), 35.0, 26.5, 98.0, 172.0
    pads = [(rrect(c[0] + ri - 8, c[1] + t0, c[0] + ro + 0.5, c[1] + t0 + 11, 3.5), f"rotate({ang} {c[0]} {c[1]})")
            for ang, t0 in ((a1, -7.0), (a2, -4.0))]
    a.lit(band(c, ro, ri, a1, a2), *pads)
    a.add(line(arc(16, 108, 162, c), "L") + line(arc(8.5, 108, 162, c), "L"))


def messages(a):
    # The shape is already a bubble, its tail the square corner: two
    # nested, the typing dots cut out.
    a.add(f'<path d="{inset(15)}" fill="{{T}}"/>')
    a.lit(inset(23))
    a.add("".join(f'<circle cx="{x}" cy="43" r="2.9" fill="{{C}}"/>' for x in (33, 43, 53)))


def email(a):
    # The shape inset as the envelope, its flap a darker facet, the fold cut.
    env = inset(17)
    a.lit(env)
    a.plane(env, "M0 0H86V31L43 48L0 31Z", "E")
    a.add(line("M18 30 L43 48 L68 30"))


def browser(a):
    # The globe: a disc about the centre, a meridian and the equator cut.
    a.lit(disc(25))
    a.add(line("M43 18 A12 25 0 0 0 43 68 A12 25 0 0 0 43 18 M18 43 H68"))


def store(a):
    # The bag: the shape inset below its rim, a hem, the handle an arc.
    bag = inset(17)
    a.add(f'<path d="{band((43, 33), 11.5, 8.5, 180, 360)}" fill="{{E}}"/>')
    a.plane(bag, "M0 33H86V86H0Z", "D")
    a.plane(bag, "M33 33H86V86Z", "H")
    a.plane(bag, "M0 33H86V37H0Z", "E")


def music(a):
    # Sound: seven bars about the centre line under one envelope.
    bars = "".join(rrect(x - 2, 43 - h / 2, x + 2, 43 + h / 2, 2)
                   for x, h in zip(range(25, 62, 6), (10, 22, 34, 44, 32, 20, 10)))
    a.lit(bars)


def camera(a):
    # The aperture: six blades in turn round a hexagonal opening.
    R0, ri = 26.0, 9.5
    V = [pt(ri, 60 * k - 90) for k in range(6)]

    def hit(p, q):
        dx, dy = q[0] - p[0], q[1] - p[1]
        fx, fy = p[0] - C0, p[1] - C0
        A, B, Cc = dx * dx + dy * dy, 2 * (fx * dx + fy * dy), fx * fx + fy * fy - R0 * R0
        t = (-B + math.sqrt(B * B - 4 * A * Cc)) / (2 * A)
        return p[0] + t * dx, p[1] + t * dy
    P = [hit(V[k], V[(k + 1) % 6]) for k in range(6)]
    a.add(f'<path d="{disc(ri + 1)}" fill="{{R}}"/>')
    for k, tone in zip(range(6), "DHEDHE"):
        v1, v2, p0, p1 = V[(k + 1) % 6], V[(k + 2) % 6], P[k], P[(k + 1) % 6]
        d = (f"M{v1[0]:.2f} {v1[1]:.2f}L{p0[0]:.2f} {p0[1]:.2f}A{R0} {R0} 0 0 1 {p1[0]:.2f} {p1[1]:.2f}"
             f"L{v2[0]:.2f} {v2[1]:.2f}Z")
        a.add(f'<path d="{d}" fill="{{{tone}}}" stroke="{{C}}" stroke-width="1" stroke-linejoin="round"/>')


def gallery(a):
    # A picture: the shape inset, two hills on arcs, the sun.
    pic = inset(16)
    a.add(f'<path d="{pic}" fill="{{T}}"/>')
    a.plane(pic, disc(30, (24, 80)), "L")
    a.plane(pic, disc(28, (62, 85)), "D")
    a.add('<circle cx="55" cy="31" r="5.5" fill="{C}"/>')


def maps(a):
    # The shape turned so its square corner points down is the pin.
    a.add('<ellipse cx="43" cy="69" rx="12" ry="3" fill="{T}"/>')
    a.lit((inset(23), "translate(0 -4) rotate(-45 43 43)"))
    a.add('<circle cx="43" cy="39" r="6.5" fill="{C}"/>')


def calendar(a):
    # The page: the shape inset, its top band held by two rings; the days
    # in the lighter plane, one marked.
    page = inset(16)
    a.add(f'<path d="{page}" fill="{{T}}"/>')
    a.plane(page, "M0 0H86V33H0Z", "D")
    a.plane(page, "M33 0H86V33H33Z", "H")
    a.add(f'<path d="{rrect(31, 12, 35, 24, 2)}{rrect(51, 12, 55, 24, 2)}" fill="{{E}}"/>')
    days = [(x, y) for y in (41, 52) for x in (26, 39.5, 53)]
    a.add("".join(f'<path d="{rrect(x, y, x + 7, y + 7, 1.6)}" fill="{{{"D" if (x, y) == (53, 52) else "L"}}}"/>'
                  for x, y in days))


def clock(a):
    # The dial; the quarter hour swept, the hour hand into the square corner.
    a.lit(disc(26))
    a.add('<path d="M43 43V20A23 23 0 0 1 66 43Z" fill="{L}"/>')
    a.add("".join('<circle cx="{:.2f}" cy="{:.2f}" r="1.3" fill="{{T}}"/>'.format(*pt(22, t)) for t in range(0, 360, 30)))
    (hx, hy), (mx, my) = pt(12, 135), pt(18, 270)
    a.add(line(f"M43 43L{hx:.2f} {hy:.2f}", w=3.4) + line(f"M43 43L{mx:.2f} {my:.2f}", w=2.4))
    a.add('<circle cx="43" cy="43" r="2.8" fill="{C}"/>')


def calculator(a):
    # Four keys, each the shape in small; the = key the lighter plane.
    k = 19.5 / S
    keys = ((22, 22, "D", "M{0} {1}h7M{2} {3}v7"), (44.5, 22, "H", "M{0} {1}h7"),
            (22, 44.5, "H", "M{4} {5}l5 5M{6} {5}l-5 5"), (44.5, 44.5, "L", "M{0} {7}h7M{0} {8}h7"))
    for x, y, tone, sym in keys:
        a.add(f'<path d="{inset(0)}" transform="translate({x} {y}) scale({k:.5f})" fill="{{{tone}}}"/>')
        cx, cy = x + 9.75, y + 9.75
        a.add(line(sym.format(cx - 3.5, cy, cx, cy - 3.5, cx - 2.5, cy - 2.5, cx + 2.5, cy - 2, cy + 2), w=2.2))


def notes(a):
    # The page: the shape inset, its square corner folded over; two lines.
    page = inset(16)
    a.lit(page)
    f = 13.0
    lo, hi = 16.3, S - 16.3
    a.add(f'<path d="M{lo - 1} {hi - f}V{hi + 1}H{lo + f}Z" fill="{{C}}"/>')
    a.add(f'<path d="M{lo} {hi - f}L{lo + f} {hi}V{hi - f}Z" fill="{{L}}"/>')
    a.add(line(f"M{lo + 9} 34H{hi - 9}M{lo + 9} 43H{hi - 9}M{lo + 9} 52H{hi - 19}"))


def gear(teeth, ro, ri, tip, root, c=(C0, C0)):
    """A gear outline: `teeth` teeth from ri to ro, `tip` and `root` the
    half-widths of tooth and gap at their radii, in degrees."""
    step, d = 360.0 / teeth, ""
    for i in range(teeth):
        t = i * step - 90
        for r, ang in ((ri, t - step / 2 + root), (ro, t - tip), (ro, t + tip), (ri, t + step / 2 - root)):
            x, y = pt(r, ang, c)
            d += f"{'L' if d else 'M'}{x:.2f} {y:.2f}"
    return d + "Z"


def settings(a):
    # The wheel about the centre, the hub cut out.
    a.lit(gear(10, 26, 21, 6.5, 4))
    a.add('<circle cx="43" cy="43" r="9" fill="{C}"/>')


def terminal(a):
    # The screen: the shape inset in the facet; the prompt and a block cursor.
    a.add(f'<path d="{inset(16)}" fill="{{E}}"/>')
    a.add(line("M28 34 L36 42 L28 50", w=3))
    a.add(f'<path d="{rrect(41, 47.5, 54, 51, 0.8)}" fill="{{T}}"/>')


def test(a):
    # A flask: the glass in the tint, the liquid lit, bubbles cut.
    flask = "M38.5 21 H47.5 V34 L63 59 Q66.5 66 59 66 H27 Q19.5 66 23 59 L38.5 34 Z"
    a.add(f'<path d="{flask}" fill="{{T}}"/>')
    a.plane(flask, "M0 49 Q21.5 45 43 49 T86 49 V86 H0 Z", "D")
    a.add(f'<path d="{rrect(35, 18, 51, 22, 1.5)}" fill="{{E}}"/>')
    a.add('<circle cx="37" cy="58" r="2.4" fill="{C}"/><circle cx="47" cy="55" r="1.7" fill="{C}"/>')


# App: (title, hue, draw), in home grid order; hues are 22.5-degree steps,
# no two grid neighbours closer than 45 degrees.
ICONS = {
    "phone": ("Phone: a call", 145.0, phone),
    "messages": ("Messages: nested speech bubbles", 212.5, messages),
    "email": ("Mail: an envelope", 280.0, email),
    "browser": ("Browser: a globe", 235.0, browser),
    "store": ("Store: a bag", 190.0, store),
    "music": ("Music: a sound", 325.0, music),
    "camera": ("Camera: an aperture", 32.5, camera),
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
        flat = SVG.fromstring(render(title, hue, draw)).topicosvg().tostring(pretty_print=True)
        out.write_text(f"<!-- {title}. Generated by scripts/build-app-icons.py; spec in "
                       f"docs/design/app-icon-spec.md. -->\n{flat}")
    print(f"{len(ICONS)} icons written")
