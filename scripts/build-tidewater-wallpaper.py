#!/usr/bin/env python3
"""Render the Tidewater wallpaper to shell/resources/wallpapers/tidewater.jpg.

Qt's SVG renderer has no filters, so the grain has to be baked into a
raster. Deterministic (fixed seed); re-run after changing the palette:
    python3 scripts/build-tidewater-wallpaper.py
"""

from pathlib import Path

import numpy as np
from PIL import Image

W, H = 1440, 2880
FIELD = 4  # the colour field is smooth: build it at 1/4 and upsample
OUT = Path(__file__).resolve().parent.parent / "shell/resources/wallpapers/tidewater.jpg"
rng = np.random.default_rng(20261016)


def lin(hex_):
    c = np.array([int(hex_[i:i + 2], 16) for i in (1, 3, 5)], float) / 255
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def srgb(c):
    c = np.clip(c, 0, 1)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * c ** (1 / 2.4) - 0.055)


def value_noise(w, h, cells):
    g = rng.random((cells + 2, int(cells * h / w) + 2))
    img = Image.fromarray(np.ascontiguousarray(g.T, np.float32))
    return np.asarray(img.resize((w, h), Image.BICUBIC), float)


def fbm(w, h, base, octaves=4):
    out = np.zeros((h, w))
    amp, total = 1.0, 0.0
    for o in range(octaves):
        out += amp * value_noise(w, h, base * 2 ** o)
        total += amp
        amp *= 0.5
    return out / total


fw, fh = W // FIELD, H // FIELD
x, y = np.meshgrid(np.linspace(0, 1, fw), np.linspace(0, 2, fh))
# A gentle domain warp keeps the edges organic without fraying them.
wx = (fbm(fw, fh, 2, 2) - 0.5) * 0.18
wy = (fbm(fw, fh, 2, 2) - 0.5) * 0.18
xs, ys = x + wx, y + wy


def smoothstep(e0, e1, v):
    t = np.clip((v - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def blob(cx, cy, rx, ry):
    return np.exp(-(((xs - cx) / rx) ** 2 + ((ys - cy) / ry) ** 2) * 1.6)


def over(base, colour, alpha):
    a = np.clip(alpha, 0, 1)[..., None]
    return base * (1 - a) + colour * a


def wave(base, y0, slope, amp, freq, phase, body, rim, edge=0.012):
    """A sheet below a sweeping curve, lit along its crest, casting a
    soft shadow onto whatever lies above it."""
    crest = y0 - slope * xs + amp * np.sin(freq * xs * np.pi + phase) \
        + 0.5 * amp * np.sin(2.3 * freq * xs * np.pi + 1.7 * phase)
    d = ys - crest
    base = base * (1 - 0.45 * np.exp(np.minimum(d, 0) / 0.05) * (d < 0))[..., None]
    depth = np.clip(d / 0.45, 0, 1) ** 0.7
    # Faint contour striations running with the crest.
    lines = 1 + 0.06 * np.sin(d * 140 + 6 * wx) * np.exp(-d / 0.3)
    colour = (lin(rim) * (1 - depth[..., None]) + lin(body) * depth[..., None]) * lines[..., None]
    return over(base, colour, smoothstep(-edge, edge, d))


top, mid = lin("#0c1033"), lin("#1b2c86")
img = top + (mid - top) * np.clip(y / 0.95, 0, 1)[..., None]
sky = fbm(fw, fh, 3, 3)
img = over(img, lin("#2a52d8"), 0.55 * blob(0.0, 0.55, 0.55, 0.45) * sky * 1.4)
img = over(img, lin("#6a45d2"), 0.85 * blob(0.95, 0.38, 0.6, 0.42))
img = over(img, lin("#ff9a66"), 0.90 * blob(0.92, 0.63, 0.30, 0.20))
img = wave(img, 1.05, 0.55, 0.06, 1.1, 0.4, "#18338f", "#4a72e6")
img = wave(img, 1.32, 0.50, 0.07, 0.9, 2.1, "#08566e", "#23b3b8")
img = wave(img, 1.55, 0.40, 0.05, 1.3, 4.0, "#06464f", "#4fdcbc")
img = wave(img, 1.80, 0.30, 0.05, 1.0, 1.0, "#071a40", "#2763b4")

# A slow light-and-shadow wash, then upsample.
img *= (0.82 + 0.36 * fbm(fw, fh, 2, 3))[..., None]
field = np.stack([np.asarray(Image.fromarray(img[..., c].astype(np.float32))
                             .resize((W, H), Image.BICUBIC)) for c in range(3)], -1)

# Film grain: luminance-weighted, slightly stronger in the shadows, so it
# reads as a surface rather than a dither pattern.
out = srgb(field)
lum = out @ np.array([0.2126, 0.7152, 0.0722])
grain = rng.normal(0, 1, (H, W))
grain = 0.6 * grain + 0.4 * np.asarray(Image.fromarray(grain.astype(np.float32))
                                        .resize((W // 2, H // 2), Image.BILINEAR)
                                        .resize((W, H), Image.BICUBIC))
out += (grain * (0.018 + 0.012 * (1 - lum)))[..., None]

OUT.parent.mkdir(parents=True, exist_ok=True)
Image.fromarray((np.clip(out, 0, 1) * 255 + 0.5).astype(np.uint8)).save(
    OUT, quality=86, subsampling=2, optimize=True, progressive=True)
print(f"{OUT} {OUT.stat().st_size // 1024} KiB, mean luma {lum.mean():.3f}")
