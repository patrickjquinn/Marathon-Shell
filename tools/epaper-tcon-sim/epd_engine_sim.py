#!/usr/bin/env python3
"""Drive the Rust e-paper engine (crates/marathon-epd) with scroll, type and tap traces through
the toy ink model of epd_sim.py, and report perceived latency and ghosting.

The compositor side (content, content-anchored Bayer stand-ins, region classes, the allow-greys
gate) runs here; every panel frame it hands the engine one target byte per pixel through
`epd-tool trace` and applies the returned 2-bit drive codes to the ink. The engine uses its
hand-made reference waveform (12-frame binary, 24-frame balanced GC-like grey), so the numbers
are illustrative, not MP01 measurements.

    cargo build --profile dev-fast -p marathon-epd   (in crates/)
    epd_engine_sim.py --tool crates/target/dev-fast/epd-tool --out sim-out/
"""

import argparse
import json
import pathlib
import struct
import subprocess

import numpy as np
from PIL import Image, ImageDraw

from epd_sim import BAYER8

HZ = 85.0
DT = 1.0 / HZ
W, H = 256, 192
RATE, GAMMA, TAU = 1 / 12.0, 0.4, 0.6
LEVELS = 16
AUTO, MONO, GREY = 0, 1, 2


class Ink:
    """epd_sim's ink: reflectance x with a slow memory h; a long-held rail resists leaving."""

    def __init__(self, x0):
        self.x = x0.copy()
        self.h = x0.copy()

    def drive(self, v):
        rate = np.clip(RATE * (1 + GAMMA * (self.h - self.x) * v), 0.02, None)
        self.x = np.clip(self.x + v * rate, 0.0, 1.0)
        self.h += (self.x - self.h) * DT / TAU


class Engine:
    def __init__(self, tool):
        self.p = subprocess.Popen([tool, "trace", str(W), str(H)], stdin=subprocess.PIPE,
                                  stdout=subprocess.PIPE)
        self.shifts = np.array([6, 4, 2, 0], np.uint8)

    def tick(self, target, allow_grey):
        self.p.stdin.write(bytes([1 if allow_grey else 0]) + target.astype(np.uint8).tobytes())
        self.p.stdin.flush()
        raw = self.p.stdout.read(W * H // 4 + 20)
        drive = np.frombuffer(raw[:W * H // 4], np.uint8)
        codes = ((drive[:, None] >> self.shifts) & 3).reshape(H, W)
        stats = struct.unpack("<5I", raw[W * H // 4:])
        return codes, stats

    def close(self):
        self.p.stdin.write(b"\x02")
        self.p.stdin.close()
        self.p.wait()


def quantise(img):
    return np.clip(np.round(img * (LEVELS - 1)), 0, LEVELS - 1).astype(np.uint8)


def target_bytes(img, offset_y, cls):
    """Grey level, content-anchored Bayer stand-in, class."""
    ys = (np.arange(H) + int(round(offset_y))) % 8
    thresh = BAYER8[ys][:, np.arange(W) % 8]
    stand = (img > thresh).astype(np.uint8)
    return quantise(img) | stand << 4 | cls.astype(np.uint8) << 5


def document(rng, height):
    doc = np.ones((height, W), np.float32)
    y = 6
    while y < height - 14:
        if (y // 120) % 3 == 1 and y % 120 < 12 and y + 82 <= height:
            doc[y:y + 56, 16:W - 16] = np.linspace(0, 1, W - 32)[None, :]
            yy, xx = np.mgrid[0:24, 0:W - 32]
            doc[y + 58:y + 82, 16:W - 16] = 0.5 + 0.4 * np.sin(xx / 9.0) * np.cos(yy / 5.0)
            y += 90
            continue
        x = 10
        while x < W - 24:
            wlen = int(rng.integers(6, 22))
            glyphs = rng.random((7, wlen)) < 0.45
            glyphs[:, ::3] |= rng.random((7, (wlen + 2) // 3)) < 0.7
            doc[y:y + 7, x:x + wlen] = np.where(glyphs, 0.0, 1.0)
            x += wlen + int(rng.integers(3, 6))
        y += 13
    return doc


def scroll_trace(rng):
    doc = document(rng, H + 600)
    t_down, t_up, drag_v, tau = 0.10, 0.60, 330.0, 0.25

    def offset(t):
        if t < t_down:
            return 0.0
        if t < t_up:
            return drag_v * (t - t_down)
        return drag_v * (t_up - t_down) + drag_v * tau * (1 - np.exp(-(t - t_up) / tau))

    def frame(t):
        moving = t_down <= t and (t < t_up or drag_v * np.exp(-(t - t_up) / tau) > 15)
        o = offset(t)
        img = doc[int(round(o)):int(round(o)) + H]
        return img, o, np.zeros((H, W), np.uint8), not moving

    return "scroll", 3.2, frame


def type_trace(rng):
    base = document(rng, H)
    base[120:150, 8:W - 8] = 1.0
    cls = np.zeros((H, W), np.uint8)
    cls[120:150, 8:W - 8] = MONO
    typed = []
    events = []
    t = 0.15
    while t < 2.0:
        events.append((t, "key"))
        if rng.random() < 0.25:
            events.append((t + 0.06, "back"))
        t += float(rng.uniform(0.11, 0.18))
    glyph = {}

    def frame(t):
        n = 0
        typed.clear()
        for te, kind in events:
            if te > t:
                break
            if kind == "key":
                typed.append(n)
                n += 1
            elif typed:
                typed.pop()
        img = base.copy()
        for i, g in enumerate(typed):
            if g not in glyph:
                glyph[g] = rng.random((11, 7)) < 0.5
            x = 12 + 9 * (i % 26)
            y = 124 + 14 * (i // 26 % 2)
            img[y:y + 11, x:x + 7] = np.where(glyph[g], 0.0, 1.0)
        return img, 0.0, cls, True

    return "type", 2.5, frame


def tap_trace(rng):
    page1 = document(rng, H)
    page2 = document(rng, H)
    yy, xx = np.mgrid[0:100, 0:W - 40]
    page2[40:140, 20:W - 20] = 0.5 + 0.45 * np.sin(xx / 13.0 + yy / 17.0)
    row = (slice(60, 84), slice(0, W))
    cls = np.zeros((H, W), np.uint8)

    def frame(t):
        if t < 0.20:
            return page1, 0.0, cls, True
        if t < 0.32:
            img = page1.copy()
            img[row] = 1.0 - img[row]
            return img, 0.0, cls, False
        return page2, 0.0, cls, t > 0.40

    return "tap", 2.0, frame


def run(trace, tool, every):
    name, duration, frame = trace
    eng = Engine(tool)
    img0, o0, cls0, _ = frame(0.0)
    ink = Ink(np.ones((H, W)))
    # Pre-roll: the first page is drawn as a page change before the trace starts.
    for _ in range(60):
        codes, _ = eng.tick(target_bytes(img0, o0, np.full((H, W), GREY)), True)
        ink.drive(np.where(codes == 2, 1, np.where(codes == 1, -1, 0)))
    n = int(duration * HZ)
    prev_ideal = quantise(img0) / (LEVELS - 1)
    start = np.full((H, W), -1)
    x_at = np.zeros((H, W))
    lat, superseded = [], 0
    errs, frames_out, link = [], [], []
    for i in range(n):
        t = i * DT
        img, o, cls, allow = frame(t)
        ideal = quantise(img) / (LEVELS - 1)
        changed = np.abs(ideal - prev_ideal) >= 0.5
        superseded += int(np.count_nonzero(changed & (start >= 0)))
        start = np.where(changed, i, start)
        x_at = np.where(changed, ink.x, x_at)
        codes, stats = eng.tick(target_bytes(img, o, cls), allow)
        ink.drive(np.where(codes == 2, 1, np.where(codes == 1, -1, 0)))
        crossed = (start >= 0) & (np.abs(ink.x - ideal) <= 0.5 * np.abs(ideal - x_at))
        lat.extend(((i - start[crossed] + 1) * DT * 1000).tolist())
        start = np.where(crossed, -1, start)
        prev_ideal = ideal
        errs.append(float(np.mean(np.abs(ink.x - ideal))))
        link.append(stats[2] > 0 or stats[0] > 0)
        if i % every == 0:
            frames_out.append(compose(name, t, ideal, ink.x, codes, errs[-1], stats))
    eng.close()
    rest = int(0.3 * HZ)
    final = np.abs(ink.x - ideal)
    lat = np.array(lat) if lat else np.array([np.nan])
    metrics = {
        "trace": name,
        "latency_ms_p50": round(float(np.percentile(lat, 50)), 1),
        "latency_ms_p90": round(float(np.percentile(lat, 90)), 1),
        "changes_measured": int(lat.size),
        "changes_superseded": superseded,
        "error_mean": round(float(np.mean(errs)), 4),
        "error_rest_mean": round(float(np.mean(errs[-rest:])), 4),
        "ghost_p99_at_end": round(float(np.percentile(final, 99)), 3),
        "link_active_frames": int(sum(link)),
        "frames": n,
    }
    return metrics, frames_out


def compose(name, t, ideal, x, codes, err, stats):
    pad, top = 8, 22
    img = Image.new("L", (3 * W + 4 * pad, H + top + 18), 255)
    d = ImageDraw.Draw(img)
    for k, (title, arr) in enumerate((("ideal", ideal), ("ink", x),
                                       ("drive (black/white)", None))):
        if arr is None:
            arr = np.where(codes == 1, 0.0, np.where(codes == 2, 1.0, 0.55))
        lum = (0.12 + 0.78 * arr) * 255
        xpos = pad + k * (W + pad)
        img.paste(Image.fromarray(lum.astype(np.uint8)), (xpos, top))
        d.text((xpos, 5), title, fill=0)
    d.text((pad, top + H + 4),
           f"{name}  t={t * 1000:5.0f} ms  err {err:.3f}  active {stats[0]}  hold {stats[1]}", fill=0)
    return img


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--tool", required=True, help="path to epd-tool")
    ap.add_argument("--out", default="sim-out")
    ap.add_argument("--every", type=int, default=3, help="panel frames per GIF frame")
    ap.add_argument("--slow", type=float, default=2.0, help="slow-motion factor")
    args = ap.parse_args()
    out = pathlib.Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    rng = np.random.default_rng(7)
    all_metrics, gif = [], []
    for trace in (scroll_trace(rng), type_trace(rng), tap_trace(rng)):
        m, frames = run(trace, args.tool, args.every)
        all_metrics.append(m)
        gif.extend(frames)
        print(json.dumps(m))
    (out / "metrics.json").write_text(json.dumps(all_metrics, indent=1) + "\n")
    dur = int(round(args.every * DT * 1000 * args.slow))
    gif[0].save(out / "engine_traces.gif", save_all=True, append_images=gif[1:], duration=dur,
                loop=0, optimize=True)
    print(f"wrote {out / 'engine_traces.gif'} ({len(gif)} frames) and {out / 'metrics.json'}")


if __name__ == "__main__":
    main()
