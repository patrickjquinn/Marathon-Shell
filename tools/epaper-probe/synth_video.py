#!/usr/bin/env python3
"""Render synthetic camera recordings of a probe run from a toy CPLD + ink model.

Inputs: the plan manifest, the probe log and the frame dump from
`epdprobe --dry-run --dump`. Outputs: OUT.mp4 (240 fps section), OUT.static.mp4 (the
4K-section stand-in at 30 fps, if the plan has one), OUT.tsv (the log plus synthetic
busy-flag register samples) and OUT.truth.json (the injected behaviour and the true t10
of every E1/E2 step).

CPLD model, per 8x8 panel cell: an internal frame clock (default 85 Hz, random phase);
a DSI frame reaches it `--delay` ms after its vblank; the diff is on 4-bit levels; a change
starts on the next internal tick and drives for W internal frames with a first-order
reflectance response (tau = W/4). K1 decides whether a change waits for updates elsewhere
(per-pixel/region/global); K2 what a change to a cell already in flight does
(restart/queue/lost). A clear flashes black, then white, then settles on the current frame.
"""

import argparse
import json
import subprocess
import sys

import numpy as np

PW, PH, CELL = 800, 600, 8
NX, NY = PW // CELL, PH // CELL
R_BLACK, R_WHITE = 0.06, 0.75
AMBIENT, GAIN = 0.5, 0.55
CLEAR_S = 0.7


def refl(level):
    return R_BLACK + (R_WHITE - R_BLACK) * np.asarray(level, float) / 15.0


def parse_log(path):
    rows = []
    for line in open(path):
        f = line.rstrip("\n").split("\t")
        rows.append((int(f[0]), f[1], f[2:]))
    return rows


class Cpld:
    def __init__(self, k1, k2, waves, hz, track):
        self.k1, self.k2, self.waves, self.hz = k1, k2, waves, hz
        n = NX * NY
        yy, xx = np.divmod(np.arange(n), NX)
        self.cx0, self.cy0 = xx * CELL, yy * CELL
        self.recv = np.full(n, 15)
        self.target = np.full(n, 15)
        self.changed = np.zeros(n, bool)
        self.t0 = np.full(n, -1e9)
        self.r0 = np.full(n, R_WHITE)
        self.r1 = np.full(n, R_WHITE)
        self.tau = np.ones(n)
        self.end = np.full(n, -1e9)
        self.groups, self.clears = [], []
        self.track = track
        self.hist = {c: [(-1e9, R_WHITE, R_WHITE, 1.0, -1e9)] for c in track}

    def r_now(self, t, idx=slice(None)):
        e = np.exp(-np.maximum(t - self.t0[idx], 0) / self.tau[idx])
        return np.where(t >= self.end[idx], self.r1[idx], self.r1[idx] + (self.r0[idx] - self.r1[idx]) * e)

    def r_hist(self, c, t):
        for ts, r0, r1, tau, te in reversed(self.hist[c]):
            if ts <= t:
                return r1 if t >= te else r1 + (r0 - r1) * np.exp(-(t - ts) / tau)
        return R_WHITE

    def _record(self, mask):
        for c in self.track:
            if mask[c]:
                self.hist[c].append((self.t0[c], self.r0[c], self.r1[c], self.tau[c], self.end[c]))

    def start(self, mask, t, mode):
        if not mask.any():
            return
        rails = (self.target[mask] % 15 == 0) & (self.recv[mask] % 15 == 0)
        w = (self.waves[mode] + np.where(rails, 0, 4 if mode == "quality" else 2)) / self.hz
        self.r0[mask] = self.r_now(t, mask)
        self.r1[mask] = refl(self.recv[mask])
        self.t0[mask], self.tau[mask], self.end[mask] = t, w / 4, t + w
        self.target[mask] = self.recv[mask]
        self.changed[mask] = False
        self._record(mask)

    def arrive(self, levels, t):
        diff = levels != self.recv
        self.recv = levels
        self.changed |= diff
        if self.k2 == "lost":
            busy = self.end > t
            self.changed[diff & (busy | (self.k1 == "global" and busy.any()))] = False

    def clear(self, t):
        mid = t + CLEAR_S / 2
        self.t0[:], self.r0[:], self.r1[:] = mid, R_WHITE, refl(self.recv)
        self.tau[:], self.end[:] = CLEAR_S / 8, t + CLEAR_S
        self.target[:] = self.recv
        self.changed[:] = False
        self.clears.append((t, mid))
        self._record(np.ones(len(self.recv), bool))

    def tick(self, t, mode):
        busy = self.end > t
        self.groups = [g for g in self.groups if g[4] > t]
        pending = (self.recv != self.target) & (self.changed | (self.k2 != "lost"))
        if self.k1 == "global" and busy.any():
            pending &= busy if self.k2 == "restart" else False
        if self.k2 == "restart":
            self.start(pending & busy, t, mode)
        cand = pending & ~busy
        if self.k1 == "region":
            for x0, y0, x1, y1, _ in self.groups:
                cand &= ~((self.cx0 < x1) & (x0 < self.cx0 + CELL) & (self.cy0 < y1) & (y0 < self.cy0 + CELL))
        if cand.any():
            self.start(cand, t, mode)
            x, y = self.cx0[cand], self.cy0[cand]
            self.groups.append((x.min(), y.min(), x.max() + CELL, y.max() + CELL, self.end[cand].max()))

    def render(self, t):
        for a, mid in self.clears[-1:]:
            if a <= t < mid:
                return np.full(len(self.recv), R_BLACK if t < (a + mid) / 2 else R_WHITE)
        return self.r_now(t)


class Sim:
    """Advances the CPLD tick by tick, in step with whatever is being rendered."""

    def __init__(self, cp, rows, dump, args, rng):
        self.cp, self.hz = cp, args.hz
        d = args.delay / 1000
        ev = []
        for t, kind, f in rows:
            if kind == "flip":
                ev.append((int(f[2]) / 1e9 + d, 0, int(f[5])))
            elif kind == "clear":
                ev.append((t / 1e9 + d, 1, None))
            elif kind == "mode":
                ev.append((t / 1e9 + d, 2, f[0]))
        self.ev = sorted(ev, key=lambda e: e[:2])
        self.dump, self.ei, self.mode, self.k = dump, 0, "quality", 0
        self.t_base = rows[0][0] / 1e9 + rng.uniform(0, 1 / args.hz)
        self.busy = []

    def advance(self, t):
        while True:
            tk = self.t_base + self.k / self.hz
            if tk > t:
                return
            while self.ei < len(self.ev) and self.ev[self.ei][0] <= tk:
                te, kind, x = self.ev[self.ei]
                if kind == 0:
                    self.cp.arrive(np.rint(self.dump[x].astype(float) / 17).astype(int).ravel(), te)
                elif kind == 1:
                    self.cp.clear(tk)
                else:
                    self.mode = x
                self.ei += 1
            self.cp.tick(tk, self.mode)
            self.busy.append((tk, bool((self.cp.end > tk).any())))
            self.k += 1


def homography(src, dst):
    a = []
    for (x, y), (u, v) in zip(src, dst):
        a.append([x, y, 1, 0, 0, 0, -u * x, -u * y, -u])
        a.append([0, 0, 0, x, y, 1, -v * x, -v * y, -v])
    _, _, vt = np.linalg.svd(np.array(a, float))
    return vt[-1].reshape(3, 3) / vt[-1, -1]


def cell_map(w, h, margin, ang_deg, persp):
    """Camera pixel -> panel cell index, -1 for the bezel, -2 for the room."""
    cx, cy, s = w / 2, h / 2, min(w * (1 - 2 * margin) / PW, h * (1 - 2 * margin) / PH)
    ang = np.radians(ang_deg)
    corners = []
    for x, y in ((0, 0), (PW, 0), (PW, PH), (0, PH)):
        dx, dy = (x - PW / 2) * s, (y - PH / 2) * s
        p = 1 + persp * (y / PH - 0.5)
        corners.append((cx + p * (dx * np.cos(ang) - dy * np.sin(ang)),
                        cy + p * (dx * np.sin(ang) + dy * np.cos(ang))))
    inv = np.linalg.inv(homography(((0, 0), (PW, 0), (PW, PH), (0, PH)), corners))
    yy, xx = np.mgrid[0:h, 0:w]
    q = inv @ np.stack([xx.ravel() + 0.5, yy.ravel() + 0.5, np.ones(w * h)])
    px, py = q[0] / q[2], q[1] / q[2]
    inside = (px >= 0) & (px < PW) & (py >= 0) & (py < PH)
    bezel = (px > -30) & (px < PW + 30) & (py > -30) & (py < PH + 30)
    idx = np.where(inside, np.clip(py, 0, PH - 1) // CELL * NX + np.clip(px, 0, PW - 1) // CELL, -1)
    return np.where(inside | bezel, idx, -2).astype(np.int64).reshape(h, w)


def illum_avg(bl, bl_max, ta, tb):
    i = np.searchsorted(bl[:, 0], ta, side="right") - 1
    lvl = bl[max(i, 0), 1]
    acc, t = 0.0, ta
    i += 1
    while i < len(bl) and bl[i, 0] < tb:
        acc += (bl[i, 0] - t) * lvl
        t, lvl = bl[i, 0], bl[i, 1]
        i += 1
    acc += (tb - t) * lvl
    return AMBIENT + acc / (tb - ta) / bl_max


def record(path, size, fps, exposure, drift_ppm, t_start, t_end, sim, bl, bl_max, cmap, room, noise, rng):
    """Encodes one recording of probe time [t_start, t_end]; returns its clock cam = a + b*mono."""
    b = 1 + drift_ppm * 1e-6
    a = -b * t_start
    ff = subprocess.Popen(
        ["ffmpeg", "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "gray", "-s", size,
         "-framerate", f"{fps:.6f}", "-i", "-", "-threads", "1", "-c:v", "libx264", "-preset",
         "ultrafast", "-crf", "18", "-pix_fmt", "yuv420p", path], stdin=subprocess.PIPE)
    panel, cell = cmap >= 0, np.maximum(cmap, 0)
    n = 0
    while (ta := (n / fps - a) / b) <= t_end:
        tm = ta + exposure / 2
        sim.advance(tm)
        r = sim.cp.render(tm)
        il = illum_avg(bl, bl_max, ta, ta + exposure)
        img = np.where(panel, GAIN * 255 * il * r[cell], np.where(cmap == -1, 22.0, room))
        img += rng.normal(0, noise, img.shape)
        ff.stdin.write(np.clip(img, 0, 255).astype(np.uint8).tobytes())
        n += 1
    ff.stdin.close()
    if ff.wait():
        sys.exit("ffmpeg failed")
    return {"a": a, "b": b, "frames": n}


def truth(manifest, cp, rows, args):
    flip_t = {(int(f[0]), int(f[1])): int(f[2]) / 1e9 for t, k, f in rows if k == "flip"}
    steps = []
    for tr in manifest["trials"]:
        if tr["exp"] not in ("E1", "E2"):
            continue
        for st in tr["steps"]:
            tf = flip_t[(tr["seq"], st["flip"])]
            x, y, _, _ = manifest["layout"]["patches"][int(st["roi"][1:])]
            c = (y + 48) // CELL * NX + (x + 48) // CELL
            ts = tf + np.arange(0, 0.8, 2e-4)
            r = np.array([cp.r_hist(c, t) for t in ts])
            r0, r1 = cp.r_hist(c, tf - 0.01), r[-1]
            frac = (r - r0) / (r1 - r0) if abs(r1 - r0) > 1e-6 else np.zeros_like(r)
            hit = np.flatnonzero(frac >= 0.1)
            steps.append({"seq": tr["seq"], "roi": st["roi"], "flip": st["flip"],
                          "t10_ms": float((ts[hit[0]] - tf) * 1000) if len(hit) else None})
    k1, k2 = args.behaviour.split(":")
    return {"k1": k1, "k2": k2, "delay_ms": args.delay, "hz": args.hz, "waves": args.waves,
            "fps": args.fps, "steps": steps}


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--manifest", required=True)
    ap.add_argument("--log", required=True)
    ap.add_argument("--dump", required=True, help="epdprobe --dry-run --dump output")
    ap.add_argument("--out", required=True)
    ap.add_argument("--behaviour", default="per-pixel:restart",
                    help="K1:K2, K1 in per-pixel|region|global, K2 in restart|queue|lost")
    ap.add_argument("--delay", type=float, default=20.0, help="vblank to CPLD frame arrival, ms")
    ap.add_argument("--hz", type=float, default=85.0, help="CPLD internal frame clock")
    ap.add_argument("--waves", default="quality=30,text=18,fast=10,clean=30",
                    help="rail waveform length per mode in internal frames (greys add a few)")
    ap.add_argument("--fps", type=float, default=240000 / 1001)
    ap.add_argument("--exposure", type=float, default=1 / 480)
    ap.add_argument("--size", default="480x360")
    ap.add_argument("--static-size", default="480x270")
    ap.add_argument("--drift-ppm", type=float, default=35.0)
    ap.add_argument("--noise", type=float, default=1.0)
    ap.add_argument("--seed", type=int, default=3)
    args = ap.parse_args()
    k1, k2 = args.behaviour.split(":")
    if k1 not in ("per-pixel", "region", "global") or k2 not in ("restart", "queue", "lost"):
        sys.exit(f"bad --behaviour {args.behaviour}")

    rng = np.random.default_rng(args.seed)
    manifest = json.load(open(args.manifest))
    rows = parse_log(args.log)
    dump = np.fromfile(args.dump, np.uint8).reshape(-1, NY, NX)
    meta = dict(kv.split("=", 1) for kv in next(f for t, k, f in rows if k == "meta"))
    bl = np.array([(t / 1e9, int(f[2])) for t, k, f in rows if k == "bl"], float)
    bl_max = int(meta["bl_max"])
    waves = {k: int(v) for k, v in (w.split("=") for w in args.waves.split(","))}
    track = sorted({(y + 48) // CELL * NX + (x + 48) // CELL for x, y, _, _ in manifest["layout"]["patches"]})
    cp = Cpld(k1, k2, waves, args.hz, track)
    sim = Sim(cp, rows, dump, args, rng)

    t0, t1 = rows[0][0] / 1e9, rows[-1][0] / 1e9 + 0.5
    trial_t = {int(f[0]): t / 1e9 for t, k, f in rows if k == "trial"}
    static = [trial_t[t["seq"]] for t in manifest["trials"] if t["section"] == "static" and t["seq"] in trial_t]
    split = static[0] - 2.0 if static else t1
    w, h = map(int, args.size.split("x"))
    cmap = cell_map(w, h, 0.12, 1.3, 0.03)
    room = 30 + 12 * np.linspace(-1, 1, w)[None, :] * np.ones((h, 1))
    clocks = {"main": record(args.out + ".mp4", args.size, args.fps, args.exposure, args.drift_ppm,
                             t0 - 0.5, split, sim, bl, bl_max, cmap, room, args.noise, rng)}
    if static:
        sw, sh = map(int, args.static_size.split("x"))
        smap = cell_map(sw, sh, 0.1, -0.8, 0.02)
        clocks["static"] = record(args.out + ".static.mp4", args.static_size, 30.0, 1 / 120, -20.0,
                                  split - 1.0, t1, sim, bl, bl_max, smap, np.full((sh, sw), 40.0),
                                  args.noise, rng)
    sim.advance(t1 + 1)

    regs = [f"{int(tk * 1e9)}\treg\t1\t0\t{int(busy)}\t25\n" for tk, busy in sim.busy]
    merged = sorted(open(args.log).readlines() + regs, key=lambda s: int(s.split("\t", 1)[0]))
    open(args.out + ".tsv", "w").writelines(merged)
    json.dump({**truth(manifest, cp, rows, args), "clocks": clocks},
              open(args.out + ".truth.json", "w"), indent=1)
    print(f"{args.out}: {clocks}, behaviour {args.behaviour}")


if __name__ == "__main__":
    main()
