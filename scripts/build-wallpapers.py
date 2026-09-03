#!/usr/bin/env python3
"""Render the 12 Marathon wallpapers from docs/redesign/marathonos/project/wallpapers.jsx
to static SVG files under shell/resources/wallpapers/.

The JSX components emit deterministic, code-driven SVG (no runtime React
state, no images). Rendering each by hand-transcribing to a 390×844 SVG
gives us byte-for-byte the same content the canvas shows, with none of the
React runtime cost. Re-run after the JSX changes:
    ./scripts/build-wallpapers.py

Slate Aurora (the DS default) is already vendored at slate-aurora.svg —
we don't regenerate it here.
"""

from pathlib import Path

OUT = Path("shell/resources/wallpapers")
H_Y = 540  # HORIZON_Y from wallpapers.jsx
SVG_OPEN = (
    '<?xml version="1.0" encoding="UTF-8"?>\n'
    '<svg xmlns="http://www.w3.org/2000/svg" width="390" height="844" '
    'viewBox="0 0 390 844" preserveAspectRatio="xMidYMid slice">\n'
)


def horizon(opacity=0.5, sun=False):
    """Replicates the shared Horizon helper from the JSX."""
    parts = [
        '  <g>\n',
        f'    <line x1="0" y1="{H_Y}" x2="390" y2="{H_Y}" '
        f'stroke="#1de9b6" stroke-width="0.7" opacity="{opacity}"/>\n',
        f'    <line x1="0" y1="{H_Y}" x2="390" y2="{H_Y}" '
        f'stroke="#5dffdc" stroke-width="0.3" opacity="{opacity * 0.7}"/>\n',
    ]
    if sun:
        parts.append(
            f'    <circle cx="195" cy="{H_Y}" r="2.5" fill="#5dffdc" opacity="0.95"/>\n'
            f'    <circle cx="195" cy="{H_Y}" r="8" fill="#1de9b6" opacity="0.18"/>\n'
        )
    parts.append('  </g>\n')
    return "".join(parts)


def write(name, body):
    path = OUT / f"{name}.svg"
    path.write_text(SVG_OPEN + body + "</svg>\n")
    print(f"  {path}")


def carbon():
    body = (
        '  <defs>\n'
        '    <linearGradient id="streak" x1="0" y1="1" x2="1" y2="0">\n'
        '      <stop offset="0" stop-color="#00897b" stop-opacity="0.18"/>\n'
        '      <stop offset="1" stop-color="#040404" stop-opacity="0"/>\n'
        '    </linearGradient>\n'
        '  </defs>\n'
        '  <rect width="390" height="844" fill="#040404"/>\n'
        '  <rect width="390" height="844" fill="url(#streak)"/>\n'
        '  <line x1="0" y1="700" x2="390" y2="200" '
        'stroke="rgba(29,233,182,0.08)" stroke-width="0.8"/>\n'
    )
    write("carbon", body)


def indigo_dusk():
    dots = []
    for i in range(30):
        seed = i * 73
        x = (seed * 13) % 390
        y = (seed * 7) % 844
        r = ((seed % 3) + 1) * 0.4
        o = ((seed % 5) + 1) * 0.05
        dots.append(
            f'    <circle cx="{x}" cy="{y}" r="{r}" opacity="{o:.2f}"/>\n'
        )
    body = (
        '  <defs>\n'
        '    <radialGradient id="dusk1" cx="0.5" cy="0.4" r="0.7">\n'
        '      <stop offset="0" stop-color="#1de9b6" stop-opacity="0.35"/>\n'
        '      <stop offset="0.5" stop-color="#3b3bb0" stop-opacity="0.25"/>\n'
        '      <stop offset="1" stop-color="#040404" stop-opacity="0"/>\n'
        '    </radialGradient>\n'
        '  </defs>\n'
        '  <rect width="390" height="844" fill="#040404"/>\n'
        '  <rect width="390" height="844" fill="url(#dusk1)"/>\n'
        '  <g fill="#fff">\n'
        + "".join(dots)
        + '  </g>\n'
    )
    write("indigo-dusk", body)


def long_run():
    arcs = [
        (360, "#5dffdc", 1.2, 0.85),
        (280, "#1de9b6", 1.0, 0.65),
        (210, "#00bfa5", 0.9, 0.50),
        (150, "#00897b", 0.8, 0.40),
        (90,  "#006b5d", 0.7, 0.30),
    ]
    arc_lines = "".join(
        f'    <path d="M {195 - r} {H_Y} A {r} {r} 0 0 1 {195 + r} {H_Y}" '
        f'stroke="{c}" stroke-width="{w}" opacity="{o}"/>\n'
        for r, c, w, o in arcs
    )
    body = (
        '  <defs>\n'
        f'    <radialGradient id="lr-glow" cx="0.5" cy="{H_Y / 844:.4f}" r="0.5">\n'
        '      <stop offset="0" stop-color="#1de9b6" stop-opacity="0.20"/>\n'
        '      <stop offset="1" stop-color="#040404" stop-opacity="0"/>\n'
        '    </radialGradient>\n'
        '  </defs>\n'
        '  <rect width="390" height="844" fill="#040404"/>\n'
        '  <rect width="390" height="844" fill="url(#lr-glow)"/>\n'
        '  <g fill="none" stroke-linecap="round">\n'
        + arc_lines
        + '  </g>\n'
        + horizon(opacity=0.6, sun=True)
    )
    write("long-run", body)


def flowfield():
    """Track — parallel horizontal running lanes."""
    lanes = []
    for i, dy in enumerate([-90, -60, -30, 0, 30, 60, 90]):
        dist = abs(dy) / 90
        opacity = 0.55 - dist * 0.38
        width = 1.2 if i == 3 else 0.7
        lanes.append(
            f'    <line x1="20" y1="{H_Y + dy}" x2="370" y2="{H_Y + dy}" '
            f'stroke="#1de9b6" stroke-width="{width}" opacity="{opacity:.3f}"/>\n'
        )
    body = (
        '  <defs>\n'
        '    <linearGradient id="track-fade" x1="0" y1="0" x2="1" y2="0">\n'
        '      <stop offset="0" stop-color="#040404" stop-opacity="1"/>\n'
        '      <stop offset="0.15" stop-color="#040404" stop-opacity="0"/>\n'
        '      <stop offset="0.85" stop-color="#040404" stop-opacity="0"/>\n'
        '      <stop offset="1" stop-color="#040404" stop-opacity="1"/>\n'
        '    </linearGradient>\n'
        f'    <radialGradient id="track-glow" cx="0.5" cy="{H_Y / 844:.4f}" r="0.45">\n'
        '      <stop offset="0" stop-color="#00897b" stop-opacity="0.18"/>\n'
        '      <stop offset="1" stop-color="#040404" stop-opacity="0"/>\n'
        '    </radialGradient>\n'
        '  </defs>\n'
        '  <rect width="390" height="844" fill="#040404"/>\n'
        '  <rect width="390" height="844" fill="url(#track-glow)"/>\n'
        '  <g>\n'
        + "".join(lanes)
        + '  </g>\n'
        '  <rect width="390" height="844" fill="url(#track-fade)" opacity="0.6"/>\n'
    )
    write("track", body)


def mesh():
    body = (
        '  <defs>\n'
        '    <pattern id="mesh-fine" width="6" height="6" patternUnits="userSpaceOnUse">\n'
        '      <path d="M 6 0 L 0 0 0 6" fill="none" stroke="rgba(255,255,255,0.022)" stroke-width="0.3"/>\n'
        '    </pattern>\n'
        '    <pattern id="mesh-main" width="30" height="30" patternUnits="userSpaceOnUse">\n'
        '      <path d="M 30 0 L 0 0 0 30" fill="none" stroke="rgba(29,233,182,0.07)" stroke-width="0.5"/>\n'
        '    </pattern>\n'
        f'    <radialGradient id="mesh-vignette" cx="0.5" cy="{H_Y / 844:.4f}" r="0.85">\n'
        '      <stop offset="0.35" stop-color="#040404" stop-opacity="0"/>\n'
        '      <stop offset="1" stop-color="#040404" stop-opacity="0.75"/>\n'
        '    </radialGradient>\n'
        '  </defs>\n'
        '  <rect width="390" height="844" fill="#040404"/>\n'
        '  <rect width="390" height="844" fill="url(#mesh-fine)"/>\n'
        '  <rect width="390" height="844" fill="url(#mesh-main)"/>\n'
        f'  <line x1="0" y1="{H_Y}" x2="390" y2="{H_Y}" stroke="#1de9b6" stroke-width="0.9" opacity="0.55"/>\n'
        f'  <line x1="195" y1="0" x2="195" y2="844" stroke="#1de9b6" stroke-width="0.9" opacity="0.55"/>\n'
        f'  <circle cx="195" cy="{H_Y}" r="3" fill="#5dffdc" opacity="0.95"/>\n'
        f'  <circle cx="195" cy="{H_Y}" r="10" fill="#1de9b6" opacity="0.18"/>\n'
        '  <rect width="390" height="844" fill="url(#mesh-vignette)"/>\n'
    )
    write("mesh", body)


def topographic():
    """Contour — concentric ellipses centered on horizon."""
    ellipses = []
    for i in range(12):
        r = 38 + i * 28
        op = 0.55 - i * 0.04
        w = 1.2 if i == 0 else 0.55
        c = "#5dffdc" if i == 0 else "#1de9b6"
        ellipses.append(
            f'    <ellipse cx="195" cy="{H_Y}" rx="{r}" ry="{r * 0.62:.2f}" '
            f'stroke="{c}" stroke-width="{w}" opacity="{op:.3f}" fill="none"/>\n'
        )
    body = (
        '  <defs>\n'
        f'    <radialGradient id="contour-glow" cx="0.5" cy="{H_Y / 844:.4f}" r="0.45">\n'
        '      <stop offset="0" stop-color="#1de9b6" stop-opacity="0.16"/>\n'
        '      <stop offset="1" stop-color="#040404" stop-opacity="0"/>\n'
        '    </radialGradient>\n'
        '  </defs>\n'
        '  <rect width="390" height="844" fill="#040404"/>\n'
        '  <rect width="390" height="844" fill="url(#contour-glow)"/>\n'
        '  <g fill="none">\n'
        + "".join(ellipses)
        + '  </g>\n'
        + horizon(opacity=0.35)
        + f'  <circle cx="195" cy="{H_Y}" r="2.5" fill="#5dffdc" opacity="0.95"/>\n'
    )
    write("contour", body)


def drift():
    """Stride — diagonal strides on a regular lattice (60°)."""
    lines = []
    for row in range(22):
        for col in range(5):
            x = col * 90 + (45 if row % 2 else 0) - 20
            y = row * 42 - 20
            length = 22 + ((row * 7 + col * 13) % 12)
            dist = abs(y - H_Y) / 422
            op = 0.50 - dist * 0.30
            lines.append(
                f'    <line x1="{x}" y1="{y + length}" x2="{x + length * 0.7:.2f}" '
                f'y2="{y}" stroke-width="0.8" opacity="{op:.3f}"/>\n'
            )
    body = (
        '  <defs>\n'
        f'    <radialGradient id="stride-glow" cx="0.7" cy="{H_Y / 844:.4f}" r="0.55">\n'
        '      <stop offset="0" stop-color="#00897b" stop-opacity="0.20"/>\n'
        '      <stop offset="1" stop-color="#040404" stop-opacity="0"/>\n'
        '    </radialGradient>\n'
        '  </defs>\n'
        '  <rect width="390" height="844" fill="#040404"/>\n'
        '  <rect width="390" height="844" fill="url(#stride-glow)"/>\n'
        '  <g stroke="#1de9b6" stroke-linecap="round">\n'
        + "".join(lines)
        + '  </g>\n'
        + horizon(opacity=0.4)
    )
    write("stride", body)


def tundra():
    body = (
        '  <defs>\n'
        '    <linearGradient id="tundra-sky" x1="0" y1="0" x2="0" y2="1">\n'
        '      <stop offset="0" stop-color="#3a6b9c" stop-opacity="0.55"/>\n'
        '      <stop offset="0.45" stop-color="#1f3a5c" stop-opacity="0.45"/>\n'
        f'      <stop offset="{H_Y / 844:.4f}" stop-color="#040404" stop-opacity="0.95"/>\n'
        '      <stop offset="1" stop-color="#040404" stop-opacity="1"/>\n'
        '    </linearGradient>\n'
        f'    <radialGradient id="tundra-glow" cx="0.5" cy="{H_Y / 844:.4f}" r="0.4">\n'
        '      <stop offset="0" stop-color="#1de9b6" stop-opacity="0.22"/>\n'
        '      <stop offset="1" stop-color="#040404" stop-opacity="0"/>\n'
        '    </radialGradient>\n'
        '  </defs>\n'
        '  <rect width="390" height="844" fill="#040404"/>\n'
        '  <rect width="390" height="844" fill="url(#tundra-sky)"/>\n'
        '  <rect width="390" height="844" fill="url(#tundra-glow)"/>\n'
        '  <g fill="none" stroke="#1de9b6" stroke-linecap="round" opacity="0.45">\n'
        f'    <path d="M {195 - 220} {H_Y} A 220 220 0 0 1 {195 + 220} {H_Y}" stroke-width="0.7"/>\n'
        f'    <path d="M {195 - 140} {H_Y} A 140 140 0 0 1 {195 + 140} {H_Y}" stroke-width="0.6" opacity="0.7"/>\n'
        '  </g>\n'
        + horizon(opacity=0.55, sun=True)
    )
    write("tundra", body)


def striae():
    lines = []
    for i in range(140):
        y = (i / 140) * 844
        dist = abs(y - H_Y) / 422
        op = max(0.04, 0.30 - dist * 0.26)
        w = 0.3 + (1 - dist) * 0.5
        lines.append(
            f'    <line x1="24" y1="{y:.2f}" x2="366" y2="{y:.2f}" '
            f'stroke-width="{w:.3f}" opacity="{op:.3f}"/>\n'
        )
    body = (
        '  <defs>\n'
        '    <linearGradient id="striae-glow" x1="0" y1="0.4" x2="1" y2="0.6">\n'
        '      <stop offset="0" stop-color="#040404" stop-opacity="0"/>\n'
        '      <stop offset="0.5" stop-color="#1de9b6" stop-opacity="0.10"/>\n'
        '      <stop offset="1" stop-color="#040404" stop-opacity="0"/>\n'
        '    </linearGradient>\n'
        '  </defs>\n'
        '  <rect width="390" height="844" fill="#040404"/>\n'
        '  <rect width="390" height="844" fill="url(#striae-glow)"/>\n'
        '  <g stroke="#1de9b6" stroke-linecap="round">\n'
        + "".join(lines)
        + '  </g>\n'
        + horizon(opacity=0.85)
    )
    write("striae", body)


def halftone():
    dots = []
    for row in range(38):
        for col in range(18):
            x = col * 22 + (11 if row % 2 else 0)
            y = row * 22
            dx = x - 195
            dy = y - H_Y
            dist = (dx * dx + dy * dy) ** 0.5
            t = min(1, dist / 460)
            r = max(0.3, 3.0 * (1 - t))
            op = max(0.04, 0.6 * (1 - t))
            dots.append(
                f'    <circle cx="{x}" cy="{y}" r="{r:.3f}" opacity="{op:.3f}"/>\n'
            )
    body = (
        '  <rect width="390" height="844" fill="#040404"/>\n'
        '  <g fill="#1de9b6">\n'
        + "".join(dots)
        + '  </g>\n'
        + horizon(opacity=0.25)
    )
    write("halftone", body)


def pulse():
    rings = []
    for i, r in enumerate([40, 90, 150, 220, 300, 400, 520, 680]):
        sw = 1.2 if i == 0 else 0.5
        op = 0.55 - i * 0.06
        rings.append(
            f'    <circle cx="195" cy="{H_Y}" r="{r}" '
            f'stroke-width="{sw}" opacity="{op:.3f}"/>\n'
        )
    body = (
        '  <defs>\n'
        f'    <radialGradient id="pulse-glow" cx="0.5" cy="{H_Y / 844:.4f}" r="0.5">\n'
        '      <stop offset="0" stop-color="#00bfa5" stop-opacity="0.28"/>\n'
        '      <stop offset="1" stop-color="#040404" stop-opacity="0"/>\n'
        '    </radialGradient>\n'
        '  </defs>\n'
        '  <rect width="390" height="844" fill="#040404"/>\n'
        '  <rect width="390" height="844" fill="url(#pulse-glow)"/>\n'
        '  <g fill="none" stroke="#1de9b6" stroke-linecap="round">\n'
        + "".join(rings)
        + '  </g>\n'
        + horizon(opacity=0.55, sun=True)
    )
    write("pulse", body)


def twilight():
    """Dawn — sunrise gradient + horizon + single morning star."""
    body = (
        '  <defs>\n'
        '    <linearGradient id="dawn-sky" x1="0" y1="0" x2="0" y2="1">\n'
        '      <stop offset="0" stop-color="#1f2840" stop-opacity="0.55"/>\n'
        '      <stop offset="0.30" stop-color="#3a4055" stop-opacity="0.45"/>\n'
        '      <stop offset="0.50" stop-color="#5a4a4a" stop-opacity="0.35"/>\n'
        f'      <stop offset="{H_Y / 844:.4f}" stop-color="#040404" stop-opacity="0.95"/>\n'
        '      <stop offset="1" stop-color="#040404" stop-opacity="1"/>\n'
        '    </linearGradient>\n'
        f'    <radialGradient id="dawn-sun" cx="0.5" cy="{H_Y / 844:.4f}" r="0.45">\n'
        '      <stop offset="0" stop-color="#5dffdc" stop-opacity="0.35"/>\n'
        '      <stop offset="0.4" stop-color="#1de9b6" stop-opacity="0.15"/>\n'
        '      <stop offset="1" stop-color="#040404" stop-opacity="0"/>\n'
        '    </radialGradient>\n'
        '  </defs>\n'
        '  <rect width="390" height="844" fill="#040404"/>\n'
        '  <rect width="390" height="844" fill="url(#dawn-sky)"/>\n'
        '  <rect width="390" height="844" fill="url(#dawn-sun)"/>\n'
        '  <circle cx="285" cy="160" r="1.0" fill="#f5f5f5" opacity="0.85"/>\n'
        '  <circle cx="285" cy="160" r="3" fill="#f5f5f5" opacity="0.15"/>\n'
        + horizon(opacity=0.7, sun=True)
    )
    write("dawn", body)


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    print("Writing wallpapers:")
    carbon()
    indigo_dusk()
    long_run()
    flowfield()
    mesh()
    topographic()
    drift()
    tundra()
    striae()
    halftone()
    pulse()
    twilight()
    print("Done.")
