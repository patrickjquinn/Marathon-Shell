#!/usr/bin/env python3
"""Simulate e-paper ink under three timing controllers and render a comparison GIF.

global-stock : a global-counter TCON (one update in flight, the rest wait) with the
               stock MP01 Hybrid policy: switch to the binary waveform after six moving
               frames in 250 ms, back to greyscale after 1 s still.
global-tierA : the same TCON, driven the Tier A way: binary waveform from touch-down,
               content-anchored dither while moving, the freshest predicted frame
               handed over as the TCON goes idle, greyscale refine 300 ms after motion.
gpu-tierB    : per-pixel state on the GPU: every pixel starts at once, retargets from
               its estimated optical state (early cancel), hybrid binary-then-grey per
               pixel, with one saturation frame into a rail and a per-pixel net-DC counter.

Ink model, per pixel and per 85 Hz panel frame with drive v in {-1, 0, +1}:
    x += v * RATE * (1 + GAMMA * (h - x) * v)      x = reflectance, 0 black, 1 white
    h += (x - h) * dt / TAU                          h = slow memory of past state
A pixel that sat long at one rail moves away from it more slowly, so a fixed-length
waveform leaves a residue of the old image: ghosting. All constants are illustrative,
not MP01 measurements.
"""

import argparse

import numpy as np
from PIL import Image, ImageDraw

HZ = 85.0
DT = 1.0 / HZ
W, H = 192, 144
RATE, GAMMA, TAU = 1 / 9.0, 0.4, 0.6
BIN_FRAMES, GREY_FRAMES = 12, 48
LEVELS = 16
T_DOWN, T_UP, T_END = 0.10, 0.60, 3.20
DRAG_V, FLING_TAU = 330.0, 0.25
BAYER8 = np.array([[0, 32, 8, 40, 2, 34, 10, 42], [48, 16, 56, 24, 50, 18, 58, 26],
                   [12, 44, 4, 36, 14, 46, 6, 38], [60, 28, 52, 20, 62, 30, 54, 22],
                   [3, 35, 11, 43, 1, 33, 9, 41], [51, 19, 59, 27, 49, 17, 57, 25],
                   [15, 47, 7, 39, 13, 45, 5, 37], [63, 31, 55, 23, 61, 29, 53, 21]]) / 64.0


def scroll(t):
    if t < T_DOWN:
        return 0.0
    if t < T_UP:
        return DRAG_V * (t - T_DOWN)
    s0 = DRAG_V * (T_UP - T_DOWN)
    return s0 + DRAG_V * FLING_TAU * (1 - np.exp(-(t - T_UP) / FLING_TAU))


def fling_done(t):
    return t > T_UP and DRAG_V * np.exp(-(t - T_UP) / FLING_TAU) < 15.0


def make_document(rng):
    doc = np.ones((H + 420, W), np.float32)
    y = 6
    while y < doc.shape[0] - 12:
        if 282 <= y < 300:
            doc[y:y + 60, 14:W - 14] = np.linspace(0, 1, W - 28)[None, :]
            yy, xx = np.mgrid[0:20, 0:W - 28]
            doc[y + 62:y + 80, 14:W - 14] = 0.5 + 0.4 * np.sin(xx[:18] / 9.0) * np.cos(yy[:18] / 5.0)
            y += 86
            continue
        x = 10
        while x < W - 24:
            wlen = int(rng.integers(6, 22))
            glyphs = rng.random((6, wlen)) < 0.45
            glyphs[:, ::3] |= rng.random((6, (wlen + 2) // 3)) < 0.7
            doc[y:y + 6, x:x + wlen] = np.where(glyphs, 0.0, 1.0)
            x += wlen + int(rng.integers(3, 6))
        y += 12
    return doc


class Compositor:
    def __init__(self, doc):
        self.doc = doc

    def view(self, offset):
        o = int(round(offset))
        return self.doc[o:o + H]

    @staticmethod
    def grey(img):
        return np.round(img * (LEVELS - 1)) / (LEVELS - 1)

    def binary(self, offset):
        o = int(round(offset))
        ys = (np.arange(H) + o) % 8
        thresh = BAYER8[ys][:, np.arange(W) % 8]
        return (self.view(offset) > thresh).astype(np.float32)


class Ink:
    def __init__(self, x0):
        self.x = x0.copy()
        self.h = x0.copy()

    def drive(self, v):
        rate = np.clip(RATE * (1 + GAMMA * (self.h - self.x) * v), 0.02, None)
        self.x = np.clip(self.x + v * rate, 0.0, 1.0)
        self.h += (self.x - self.h) * DT / TAU


def open_loop_wave(src, dst, idx, length):
    """Fixed-length LUT waveform: 4 shaking frames for greyscale, then a pulse train."""
    v = np.zeros(src.shape, np.int8)
    shake = 4 if length == GREY_FRAMES else 0
    if idx < shake:
        v[:] = 1 if idx % 2 == 0 else -1
        return v
    need = np.ceil(np.abs(dst - src) / RATE).astype(np.int32)
    if length == BIN_FRAMES:
        need = np.where(dst != src, BIN_FRAMES, 0)
    on = (idx - shake) < need
    v[on] = np.sign(dst - src)[on]
    return v


class GlobalTcon:
    """One update in flight; pixels that change meanwhile wait for it to finish."""

    def __init__(self, x0, tier_a):
        self.tier_a = tier_a
        self.stored = Compositor.grey(x0)
        self.busy = 0
        self.mode = "grey"
        self.fast_drawn = np.zeros(x0.shape, bool)
        self.forced = np.zeros(x0.shape, bool)
        self.mask = None
        self.last_change, self.changes, self.mode_at = -10.0, [], -10.0
        self.prev_input = None

    def set_mode(self, mode, t):
        if mode == self.mode or t - self.mode_at < 0.2:
            return
        if mode == "grey":
            self.forced |= self.fast_drawn
            self.fast_drawn[:] = False
        self.mode, self.mode_at = mode, t

    def policy(self, t, comp, frame_t):
        if self.tier_a:
            active = T_DOWN <= t and not fling_done(t - 0.3)
            self.set_mode("bin" if active else "grey", t)
            ahead = 0.0
            if self.busy == 0:
                ahead = BIN_FRAMES * DT / 2 + 0.02
            if t < T_UP:
                v_est = (scroll(t) - scroll(t - 1 / 120)) * 120
                target = scroll(t) + v_est * ahead
            else:
                target = scroll(t + ahead)
            return comp.binary(target) if self.mode == "bin" else comp.grey(comp.view(target))
        img = comp.grey(comp.view(scroll(frame_t)))
        if self.prev_input is not None and np.any(img != self.prev_input):
            self.changes.append(t)
            self.last_change = t
        self.prev_input = img
        self.changes = [c for c in self.changes if t - c < 0.25]
        if len(self.changes) >= 6:
            self.set_mode("bin", t)
        elif t - self.last_change > 1.0:
            self.set_mode("grey", t)
        return img

    def step(self, t, comp, frame_t, ink):
        img = self.policy(t, comp, frame_t)
        if self.busy == 0:
            target = (img >= 0.5).astype(np.float32) if self.mode == "bin" else img
            diff = (target != self.stored) | self.forced
            if np.any(diff):
                self.mask, self.src, self.dst = diff, self.stored.copy(), target.copy()
                self.stored = np.where(diff, target, self.stored)
                self.forced[:] = False
                self.length = BIN_FRAMES if self.mode == "bin" else GREY_FRAMES
                self.idx, self.busy = 0, self.length
                if self.mode == "bin":
                    self.fast_drawn |= diff
        v = np.zeros(ink.x.shape, np.int8)
        if self.busy:
            v = open_loop_wave(self.src, self.dst, self.idx, self.length) * self.mask
            self.idx += 1
            self.busy -= 1
        ink.drive(v)


class GpuTcon:
    """Per-pixel state, as the Tier B compute shader holds it in textures."""

    EST_RATE, EST_GAMMA, QUIET_FRAMES = RATE * 0.95, GAMMA * 0.75, 13

    def __init__(self, x0):
        self.x_est = x0.copy()
        self.h_est = x0.copy()
        self.tgt = Compositor.grey(x0)
        self.grey_last = self.tgt.copy()
        self.quiet = np.full(x0.shape, 255, np.int32)
        self.tail = np.zeros(x0.shape, np.int32)
        self.dc = np.zeros(x0.shape, np.int32)

    def step(self, t, comp, frame_t, ink):
        if t < T_UP:
            v_est = (scroll(t) - scroll(t - 1 / 120)) * 120
            offset = scroll(t) + v_est * 0.03
        else:
            offset = scroll(t + 0.03)
        grey = comp.grey(comp.view(offset))
        changed = grey != self.grey_last
        self.quiet = np.where(changed, 0, np.minimum(self.quiet + 1, 255))
        self.grey_last = grey
        want = np.where(self.quiet < self.QUIET_FRAMES, comp.binary(offset), grey)

        retarget = want != self.tgt
        self.tgt = np.where(retarget, want, self.tgt)
        rail = (self.tgt == 0) | (self.tgt == 1)
        to_go = self.tgt - self.x_est
        moving = np.abs(to_go) > np.where(rail, 0.02, self.EST_RATE / 2)
        self.tail = np.where(retarget, rail.astype(np.int32), self.tail)
        tailing = ~moving & (self.tail > 0)
        v = np.where(moving, np.sign(to_go), 0)
        v = np.where(tailing, np.where(self.tgt == 1, 1, -1), v).astype(np.int8)
        self.tail = np.where(tailing, 0, self.tail)

        rate = np.clip(self.EST_RATE * (1 + self.EST_GAMMA * (self.h_est - self.x_est) * v), 0.02, None)
        self.x_est = np.clip(self.x_est + v * rate, 0, 1)
        self.h_est += (self.x_est - self.h_est) * DT / TAU
        self.dc += v
        ink.drive(v)


def run(args):
    rng = np.random.default_rng(7)
    comp = Compositor(make_document(rng))
    x0 = Compositor.grey(comp.view(0))
    names = ["global-stock", "global-tierA", "gpu-tierB"]
    inks = [Ink(x0) for _ in names]
    tcons = [GlobalTcon(x0, False), GlobalTcon(x0, True), GpuTcon(x0)]
    frames, errs = [], {n: [] for n in names}
    n_ticks = int(T_END * HZ)
    for i in range(n_ticks):
        t = i * DT
        frame_t = np.floor(t * 60) / 60
        ideal = comp.grey(comp.view(scroll(t)))
        for name, tcon, ink in zip(names, tcons, inks):
            tcon.step(t, comp, frame_t, ink)
            errs[name].append(float(np.mean(np.abs(ink.x - ideal))))
        if i % args.every == 0:
            frames.append(compose_frame(t, inks, names, errs))
    report(errs, tcons[2])
    dur = int(round(args.every * DT * 1000 * args.slow))
    frames[0].save(args.out, save_all=True, append_images=frames[1:], duration=dur, loop=0,
                   optimize=True)
    print(f"wrote {args.out}: {len(frames)} frames, {args.slow}x slow motion")


def compose_frame(t, inks, names, errs):
    scale, gap, top, bottom = 2, 10, 30, 26
    pw, ph = W * scale, H * scale
    img = Image.new("L", (3 * pw + 4 * gap, ph + top + bottom), 255)
    d = ImageDraw.Draw(img)
    for k, (ink, name) in enumerate(zip(inks, names)):
        lum = (0.12 + 0.78 * ink.x) * 255
        panel = Image.fromarray(lum.astype(np.uint8)).resize((pw, ph), Image.NEAREST)
        x = gap + k * (pw + gap)
        img.paste(panel, (x, top))
        d.text((x, 6), f"{name}   err {errs[name][-1]:.3f}", fill=0)
    phase = "finger down" if T_DOWN <= t < T_UP else ("fling" if t >= T_UP and not fling_done(t) else "rest")
    d.text((gap, top + ph + 7), f"t = {t * 1000:5.0f} ms   {phase}   (85 Hz panel frames)", fill=0)
    return img


def report(errs, tier_b):
    def window(name, a, b):
        e = errs[name][int(a * HZ):int(b * HZ)]
        return sum(e) / len(e)

    stop = next(i * DT for i in range(int(T_END * HZ)) if fling_done(i * DT))
    print(f"scroll stops at {stop * 1000:.0f} ms; error = mean |reflectance - ideal|")
    print(f"{'controller':14} {'moving':>8} {'settle(ms)':>11} {'final':>7}")
    for name, e in errs.items():
        after = range(int(stop * HZ), len(e))
        settle = next((i for i in after if max(e[i:]) < 0.04), None)
        s = f"{(settle * DT - stop) * 1000:.0f}" if settle is not None else "never"
        print(f"{name:14} {window(name, T_DOWN, stop):8.3f} {s:>11} {e[-1]:7.3f}")
    rail = (tier_b.tgt == 0) | (tier_b.tgt == 1)
    for name, sel in (("rail", rail), ("grey", ~rail)):
        dc = np.abs(tier_b.dc[sel])
        print(f"tier B net DC, {name} pixels ({sel.mean():.0%}): max {dc.max()} frames, "
              f"mean {dc.mean():.2f}")


if __name__ == "__main__":
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--out", default="epd_sim.gif")
    p.add_argument("--every", type=int, default=2, help="panel frames per GIF frame")
    p.add_argument("--slow", type=float, default=2.5, help="slow-motion factor")
    run(p.parse_args())
