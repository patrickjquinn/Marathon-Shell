#!/usr/bin/env python3
"""Analyse an epdprobe run from camera video (EPAPER_GPU_TCON.md §4.1, §4.3, §3.2, §4.4).

Inputs: the plan manifest (epdplan.py), the probe log, the 240 fps video and optionally
the 4K static video. Outputs in --out: one JSON per trial, a TSV summary per experiment,
clock.json, decision.json, and rectified PGM snapshots of the static captures. The decision
step prints the Tier A configuration the measurements imply.
"""

import argparse
import itertools
import json
import subprocess
import sys
from collections import defaultdict
from pathlib import Path

import numpy as np

STD = [f"P{i}" for i in range(24)] + ["ref", "black"]


# ---------------------------------------------------------------- inputs

class Log:
    def __init__(self, path):
        self.meta, self.codes, self.flips, self.trials = {}, [], {}, {}
        self.modes, self.clears, self.notes, self.touches, self.regs = [], [], [], [], []
        self.inputs = {}
        cur, code = None, None
        for line in open(path):
            if line.startswith("#"):
                continue
            f = line.rstrip("\n").split("\t")
            t, kind, a = int(f[0]) / 1e9, f[1], f[2:]
            if kind == "meta":
                self.meta = dict(kv.split("=", 1) for kv in a)
            elif kind == "trial":
                cur = int(a[0])
                self.trials[cur] = {"t0": t, "t1": None, "name": a[2]}
            elif kind == "end" and cur in self.trials:
                self.trials[cur]["t1"] = t
            elif kind == "code":
                code = {"seq": int(a[0]), "id": int(a[1]), "writes": [], "trial": cur}
                self.codes.append(code)
            elif kind == "bl":
                bit, lvl = int(a[1]), int(a[2])
                if code is not None and -1 <= bit <= 8 and int(a[0]) == code["seq"]:
                    code["writes"].append((t, lvl, bit))
            elif kind == "flip":
                self.flips[(int(a[0]), int(a[1]))] = int(a[2]) / 1e9
            elif kind == "mode":
                self.modes.append((t, a[0], cur))
            elif kind == "clear":
                self.clears.append((t, cur))
            elif kind == "note":
                self.notes.append((t, a[0] if a else "", cur))
            elif kind == "touch":
                self.touches.append((t, a[0]))
            elif kind == "reg":
                self.regs.append([t] + [int(x) for x in a])
            elif kind == "input":
                self.inputs[int(a[0])] = a
        self.regs = np.array(self.regs, float).reshape(-1, 5)
        self.l0 = int(self.meta.get("l0", 0))
        for c in self.codes:
            c["t"] = c["writes"][0][0] if c["writes"] else None

    def note(self, seq, text):
        return next((t for t, s, c in self.notes if c == seq and s == text), None)

    def mode_switches(self, seq):
        return [(t, m) for t, m, c in self.modes if c == seq]


def probe(path):
    out = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
                          "stream=width,height:packet=pts_time", "-of", "json", path],
                         capture_output=True, text=True, check=True).stdout
    j = json.loads(out)
    pts = np.sort(np.array([float(p["pts_time"]) for p in j["packets"] if "pts_time" in p]))
    return pts, j["streams"][0]["width"], j["streams"][0]["height"]


def frames(path, width, src_wh, select=None, duration=None):
    h = int(round(width * src_wh[1] / src_wh[0] / 2)) * 2
    vf = f"scale={width}:{h},format=gray"
    if select:
        vf = f"select='{select}',{vf}"
    cmd = ["ffmpeg", "-v", "fatal", "-i", path]
    if duration:
        cmd += ["-t", str(duration)]
    cmd += ["-vf", vf, "-fps_mode", "passthrough", "-f", "rawvideo", "-"]
    p = subprocess.Popen(cmd, stdout=subprocess.PIPE, bufsize=width * h * 4)
    size = width * h
    try:
        while True:
            b = p.stdout.read(size)
            if len(b) < size:
                break
            yield np.frombuffer(b, np.uint8).reshape(h, width)
    finally:
        p.stdout.close()
        p.kill()
        p.wait()


# ---------------------------------------------------------------- geometry

def homography(src, dst):
    a = []
    for (x, y), (u, v) in zip(src, dst):
        a.append([x, y, 1, 0, 0, 0, -u * x, -u * y, -u])
        a.append([0, 0, 0, x, y, 1, -v * x, -v * y, -v])
    _, _, vt = np.linalg.svd(np.array(a, float))
    return vt[-1].reshape(3, 3) / vt[-1, -1]


def project(hm, x, y):
    p = hm @ np.stack([x, y, np.ones_like(x)])
    return p[0] / p[2], p[1] / p[2]


def otsu(img):
    hist = np.bincount(img.ravel().astype(np.uint8), minlength=256).astype(float)
    p = hist / hist.sum()
    w = np.cumsum(p)
    mu = np.cumsum(p * np.arange(256))
    with np.errstate(divide="ignore", invalid="ignore"):
        sb = (mu[-1] * w - mu) ** 2 / (w * (1 - w))
    return int(np.nanargmax(sb))


def components(mask):
    """Connected components (8-way) of a boolean image via run-length union-find."""
    parent, runs, prev = [], [], []
    for y in range(mask.shape[0]):
        row = np.concatenate(([0], mask[y].view(np.int8), [0]))
        d = np.diff(row)
        starts, ends = np.flatnonzero(d == 1), np.flatnonzero(d == -1)
        cur = []
        for s, e in zip(starts, ends):
            k = len(runs)
            runs.append((y, s, e))
            parent.append(k)
            for pk, ps, pe in prev:
                if ps <= e and s <= pe:
                    a, b = k, pk
                    while parent[a] != a:
                        a = parent[a]
                    while parent[b] != b:
                        b = parent[b]
                    parent[max(a, b)] = min(a, b)
            cur.append((k, s, e))
        prev = cur
    comps = {}
    for k, (y, s, e) in enumerate(runs):
        r = k
        while parent[r] != r:
            r = parent[r]
        n = e - s
        c = comps.setdefault(r, [0, 0.0, 0.0, s, e, y, y])
        c[0] += n
        c[1] += (s + e - 1) / 2 * n
        c[2] += y * n
        c[3], c[4], c[5], c[6] = min(c[3], s), max(c[4], e), min(c[5], y), max(c[6], y + 1)
    return [{"area": c[0], "cx": c[1] / c[0], "cy": c[2] / c[0], "x0": c[3], "x1": c[4],
             "y0": c[5], "y1": c[6]} for c in comps.values()]


def find_panel(img, manifest):
    h, w = img.shape
    thr = otsu(img)
    cands = []
    for c in components(img < thr):
        bw, bh = c["x1"] - c["x0"], c["y1"] - c["y0"]
        if not (0.01 * w < bw < 0.15 * w and 0.65 < bw / max(bh, 1) < 1.5):
            continue
        if c["x0"] <= 1 or c["y0"] <= 1 or c["x1"] >= w - 1 or c["y1"] >= h - 1:
            continue
        fill = c["area"] / (bw * bh)
        if fill < 0.7:
            continue
        m = max(2, int(0.35 * bw))
        ring = img[max(0, c["y0"] - m):c["y1"] + m, max(0, c["x0"] - m):c["x1"] + m].astype(float)
        inner = img[c["y0"]:c["y1"], c["x0"]:c["x1"]].astype(float)
        ring_mean = (ring.sum() - inner.sum()) / max(ring.size - inner.size, 1)
        if ring_mean < thr:
            continue
        hole = img[int(round(c["cy"])), int(round(c["cx"]))] > thr
        cands.append({**c, "fill": fill, "hole": bool(hole), "size": bw * bh})
    if len(cands) < 4:
        raise SystemExit(f"fiducials: found {len(cands)} candidates, need 4 "
                         "(use --calib-time to pick a frame with the clean layout)")
    best, best_score = None, -1
    for combo in itertools.combinations(cands, 4):
        sizes = [c["size"] for c in combo]
        pts = np.array([(c["cx"], c["cy"]) for c in combo])
        ctr = pts.mean(0)
        order = np.argsort(np.arctan2(pts[:, 1] - ctr[1], pts[:, 0] - ctr[0]))
        q = pts[order]
        area = 0.5 * abs(np.dot(q[:, 0], np.roll(q[:, 1], 1)) - np.dot(q[:, 1], np.roll(q[:, 0], 1)))
        score = area * min(sizes) / max(sizes) * (2 if sum(c["hole"] for c in combo) == 1 else 1)
        if score > best_score:
            best, best_score = combo, score
    pts = np.array([(c["cx"], c["cy"]) for c in best])
    ctr = pts.mean(0)
    ang = np.arctan2(pts[:, 1] - ctr[1], pts[:, 0] - ctr[0])
    holes = [i for i, c in enumerate(best) if c["hole"]]
    tl = holes[0] if len(holes) == 1 else int(np.argmin(pts.sum(1)))
    order = sorted(range(4), key=lambda i: (ang[i] - ang[tl]) % (2 * np.pi))
    fid = manifest["layout"]["fiducials"]
    centres = [(x + fw / 2, y + fh / 2) for x, y, fw, fh in fid]
    panel_pts = [centres[0], centres[1], centres[3], centres[2]]     # TL, TR, BR, BL
    hm = homography(panel_pts, [tuple(pts[i]) for i in order])
    return hm, {"hole_found": len(holes) == 1, "centres": pts[order].tolist(), "threshold": thr}


class Features:
    """Precomputed pixel index sets; one bincount per frame gives every ROI mean."""

    def __init__(self, hm, shape, specs):
        self.names, idx, lab = [], [], []
        h, w = shape
        for name, spec in specs:
            for sub_x, sub_y in self._cells(spec):
                px, py = project(hm, sub_x, sub_y)
                ok = (px >= 0) & (px < w - 0.5) & (py >= 0) & (py < h - 0.5)
                pix = np.unique(np.round(py[ok]).astype(int) * w + np.round(px[ok]).astype(int))
                idx.append(pix)
                lab.append(np.full(len(pix), len(self.names)))
                self.names.append(name)
        self.idx, self.lab = np.concatenate(idx), np.concatenate(lab)
        self.cnt = np.maximum(np.bincount(self.lab, minlength=len(self.names)), 1)
        self.slices = {}
        for i, n in enumerate(self.names):
            self.slices.setdefault(n, []).append(i)

    @staticmethod
    def _grid(x0, y0, x1, y1, step=2.0):
        xs, ys = np.arange(x0, x1, step), np.arange(y0, y1, step)
        gx, gy = np.meshgrid(xs, ys)
        return gx.ravel(), gy.ravel()

    def _cells(self, spec):
        x, y, w, h = spec["rect"]
        t = spec.get("type", "rect")
        if t == "rect":
            m = spec.get("margin", 0.15)
            yield self._grid(x + m * w, y + m * h, x + (1 - m) * w, y + (1 - m) * h)
        elif t == "grid":
            cw, ch = w / spec["nx"], h / spec["ny"]
            for j in range(spec["ny"]):
                for i in range(spec["nx"]):
                    cx, cy = x + i * cw, y + j * ch
                    yield self._grid(cx + 0.2 * cw, cy + 0.2 * ch, cx + 0.8 * cw, cy + 0.8 * ch, 1.5)
        elif t == "profile":
            bw = w / spec["nbins"]
            for i in range(spec["nbins"]):
                yield self._grid(x + i * bw, y, x + (i + 1) * bw, y + h, 1.0)
        elif t == "checker":
            c, xs, ys = spec["cell"], [], []
            for j in range(h // c):
                for i in range(w // c):
                    if (i + j) % 2 == spec["parity"]:
                        gx, gy = self._grid(x + i * c + 0.3 * c, y + j * c + 0.3 * c,
                                            x + (i + 0.7) * c, y + (j + 0.7) * c, 1.0)
                        xs.append(gx)
                        ys.append(gy)
            yield np.concatenate(xs), np.concatenate(ys)

    def __call__(self, frame):
        return np.bincount(self.lab, weights=frame.ravel()[self.idx],
                           minlength=len(self.names)) / self.cnt

    def cols(self, name):
        return self.slices[name]


def std_specs(manifest):
    lay = manifest["layout"]
    specs = [(f"P{i}", {"rect": r}) for i, r in enumerate(lay["patches"])]
    specs.append(("ref", {"rect": lay["ref"], "margin": 0.2}))
    for k, r in enumerate(lay["fiducials"]):
        if k != lay["fiducial_hole"]:
            specs.append(("black", {"rect": r, "margin": 0.25}))
    return specs


# ---------------------------------------------------------------- clock

def detect_codes(t, ref, min_gap=0.4):
    lo, hi = np.median(ref), np.percentile(ref, 99.7)
    if hi < lo * 1.08 + 2:
        raise SystemExit("no frontlight strobes visible on the reference patch")
    thr = (lo + hi) / 2
    high = ref > thr
    edges = []
    for i in np.flatnonzero(high[1:] != high[:-1]):
        u = (thr - ref[i]) / (ref[i + 1] - ref[i])
        edges.append((t[i] + u * (t[i + 1] - t[i]), bool(high[i + 1])))
    codes, last_fall = [], -1e9
    for et, rising in edges:
        if rising and et - last_fall > min_gap:
            bits = 0
            for b in range(8):
                ts = et + (0.050 + 0.025 * b + 0.0125)
                bits = bits << 1 | int(np.interp(ts, t, ref) > thr)
            codes.append({"t": et, "id": bits})
        if not rising:
            last_fall = et
    return codes, edges, {"low": float(lo), "high": float(hi), "thr": float(thr)}


def fit_clock(log, codes, edges):
    lc = [c for c in log.codes if c["t"] is not None]
    if not lc or not codes:
        raise SystemExit("no strobe codes to fit the clock")
    offs = [cc["t"] - c["t"] for cc in codes for c in lc if cc["id"] == c["id"]]
    hist = defaultdict(int)
    for o in offs:
        hist[round(o / 0.1)] += 1
    off = max(hist, key=hist.get) * 0.1
    t_ref = lc[0]["t"]
    a, b = off + t_ref, 1.0                    # cam = a + b (mono - t_ref)
    pairs = []
    for _ in range(3):
        pairs = []
        for c in lc:
            pred = a + b * (c["t"] - t_ref)
            near = [cc for cc in codes if abs(cc["t"] - pred) < (0.15 if not pairs else 0.03)
                    and cc["id"] == c["id"]]
            if near:
                pairs.append((c, min(near, key=lambda cc: abs(cc["t"] - pred))))
        if len(pairs) >= 2:
            x = np.array([c["t"] - t_ref for c, _ in pairs])
            y = np.array([cc["t"] for _, cc in pairs])
            b, a = np.polyfit(x, y, 1)
    xs, ys = [], []
    et = np.array([e[0] for e in edges])
    ep = np.array([e[1] for e in edges])
    for c, cc in pairs:
        prev = log.l0
        for wt, lvl, bit in c["writes"]:
            if lvl != prev:
                pred = a + b * (wt - t_ref)
                m = np.flatnonzero((ep == (lvl > prev)) & (np.abs(et - pred) < 0.012))
                if len(m):
                    j = m[np.argmin(np.abs(et[m] - pred))]
                    xs.append(wt - t_ref)
                    ys.append(et[j])
            prev = lvl
    xs, ys = np.array(xs), np.array(ys)
    if len(xs) >= 3:
        b, a = np.polyfit(xs, ys, 1)
        res = ys - (a + b * xs)
        keep = np.abs(res) < max(4 * np.std(res), 0.003)
        b, a = np.polyfit(xs[keep], ys[keep], 1)
        res = ys[keep] - (a + b * xs[keep])
    else:
        res = np.array([0.0])
    return {"a": float(a), "b": float(b), "t_ref": float(t_ref), "codes_log": len(lc),
            "codes_cam": len(codes), "codes_matched": len(pairs), "edges": int(len(xs)),
            "rms_ms": float(np.sqrt(np.mean(res ** 2)) * 1000),
            "max_ms": float(np.max(np.abs(res)) * 1000),
            "drift_ppm": float((b - 1) * 1e6)}


# ---------------------------------------------------------------- metrics

def med3(x):
    if len(x) < 3:
        return x
    return np.median(np.stack([np.r_[x[0], x[:-1]], x, np.r_[x[1:], x[-1]]]), 0)


def crossing(t, y, level, rising=True):
    above = y >= level if rising else y <= level
    i = np.flatnonzero(above)
    if not len(i):
        return None
    i = i[0]
    if i == 0:
        return float(t[0])
    u = (level - y[i - 1]) / (y[i] - y[i - 1]) if y[i] != y[i - 1] else 1.0
    return float(t[i - 1] + u * (t[i] - t[i - 1]))


def step_metrics(t, r, r0, r1, sigma):
    """t in ms relative to the flip; r the normalised reflectance from the flip on."""
    span = r1 - r0
    out = {"r0": float(r0), "r1": float(r1)}
    hi, lo = max(r0, r1), min(r0, r1)
    flash = max(0.0, float(r.max() - hi), float(lo - r.min())) if len(r) else 0.0
    out["flash"] = flash if flash > 5 * sigma else 0.0
    if abs(span) < 5 * sigma or len(r) < 3:
        out["changed"] = False
        return out
    frac = (r - r0) / span
    out["changed"] = True
    for name, lv in (("t10", 0.1), ("t50", 0.5), ("t90", 0.9)):
        out[name] = crossing(t, frac, lv)
    band = max(0.02 * abs(span), 5 * sigma)
    off = np.flatnonzero(np.abs(r - r1) > band)
    out["t98"] = float(t[off[-1] + 1]) if len(off) and off[-1] + 1 < len(t) else (
        float(t[0]) if not len(off) else None)
    out["overshoot"] = float(max(0.0, frac.max() - 1))
    if out["t10"] is not None and out["t90"] is not None:
        out["t0_est"] = out["t10"] - 0.048 * (out["t90"] - out["t10"])
    return out


def lstar(y):
    y = np.clip(np.asarray(y, float), 1e-6, None)
    return np.where(y > 0.008856, 116 * np.cbrt(y) - 16, 903.3 * y)


def med(xs):
    xs = [x for x in xs if x is not None]
    return float(np.median(xs)) if xs else None


def write_tsv(path, header, rows):
    with open(path, "w") as f:
        f.write("\t".join(header) + "\n")
        for r in rows:
            f.write("\t".join("" if v is None else (f"{v:.2f}" if isinstance(v, float) else str(v))
                              for v in r) + "\n")


# ---------------------------------------------------------------- video passes

class Run:
    def __init__(self, args, manifest, log):
        self.args, self.m, self.log = args, manifest, log
        self.out = Path(args.out)
        (self.out / "trials").mkdir(parents=True, exist_ok=True)
        self.results, self.summary = {}, {}

    def calib_frame(self, path, wh, pts, calib_time):
        width = self.args.width
        if calib_time is not None:
            want = np.searchsorted(pts, [calib_time - 0.3, calib_time + 0.3])
            sel = f"between(n,{want[0]},{max(want[1], want[0] + 1)})"
            fr = [f.astype(np.float32) for f in frames(path, width, wh, select=sel)]
            return np.median(np.stack(fr), 0)
        ring, means = [], []
        for n, f in enumerate(frames(path, width, wh, duration=90)):
            g = float(f.mean())
            means.append(g)
            if n % 4 == 0:
                ring.append((pts[n], f.copy()))
                ring = [r for r in ring if r[0] > pts[n] - 1.2]
            if n > 60:
                base = np.median(means[max(0, n - 120):n - 2])
                if g > base * 1.06 + 1.5:
                    use = [fr for t, fr in ring if pts[n] - 1.1 < t < pts[n] - 0.15]
                    if use:
                        return np.median(np.stack(use).astype(np.float32), 0)
        return ring[0][1].astype(np.float32)

    def pass1(self, path):
        pts, w, h = probe(path)
        wh = (w, h)
        calib = self.calib_frame(path, wh, pts, self.args.calib_time)
        hm, finfo = find_panel(calib.astype(np.uint8), self.m)
        feats = Features(hm, calib.shape, std_specs(self.m))
        obs = [t for t in self.m["trials"] if t["section"] == "observe"]
        gfeat = Features(hm, calib.shape, [("g", {"type": "grid", "rect": [0, 0, 800, 600],
                                                   "nx": 16, "ny": 12})]) if obs else None
        rows, grows = [], []
        for f in frames(path, self.args.width, wh):
            rows.append(feats(f))
            if gfeat:
                grows.append(gfeat(f))
        n = min(len(rows), len(pts))
        self.pts, self.wh, self.hm, self.path = pts[:n], wh, hm, path
        self.feats, self.shape = feats, calib.shape
        self.std = np.array(rows[:n], np.float32)
        self.grid = np.array(grows[:n], np.float32) if gfeat else None
        self.col = {k: feats.cols(k) for k in STD}
        self.ref = self.std[:, self.col["ref"]].mean(1)
        self.black = self.std[:, self.col["black"]].mean(1)
        if len(pts) != len(rows):
            print(f"warning: {len(pts)} packets but {len(rows)} decoded frames", file=sys.stderr)
        return finfo

    def clock(self):
        codes, edges, lv = detect_codes(self.pts, self.ref)
        ck = fit_clock(self.log, codes, edges)
        ck["levels"] = lv
        self.ck = ck
        self.mono = (self.pts - ck["a"]) / ck["b"] + ck["t_ref"]
        span = np.maximum(self.ref - self.black, 1e-3)
        self.R = (self.std[:, :24] - self.black[:, None]) / span[:, None]
        return ck

    def norm(self, vals, idx):
        return (vals - self.black[idx, None]) / np.maximum(self.ref[idx] - self.black[idx], 1e-3)[:, None]

    def series(self, roi, t0, t1):
        i0, i1 = np.searchsorted(self.mono, [t0, t1])
        return self.mono[i0:i1], self.R[i0:i1, int(roi[1:])]

    def window(self, seq):
        tr = self.log.trials[seq]
        return tr["t0"], tr["t1"] or (tr["t0"] + 10)

    def extra_pass(self, trials):
        """Decode only the frames of trials that need non-patch features."""
        jobs = []
        for tr in trials:
            t0, t1 = self.window(tr["seq"])
            i0, i1 = np.searchsorted(self.mono, [t0, t1])
            if i1 > i0:
                spec = [(k, v) for k, v in tr["features"].items()]
                jobs.append((i0, i1, tr, Features(self.hm, self.shape, spec)))
        if not jobs:
            return {}
        jobs.sort(key=lambda j: j[0])
        sel = "+".join(f"between(n,{a},{b - 1})" for a, b, _, _ in jobs)
        idxs = np.concatenate([np.arange(a, b) for a, b, _, _ in jobs])
        out = {j[2]["seq"]: [] for j in jobs}
        for n, f in zip(idxs, frames(self.path, self.args.width, self.wh, select=sel)):
            for a, b, tr, ft in jobs:
                if a <= n < b:
                    out[tr["seq"]].append(ft(f))
        res = {}
        for a, b, tr, ft in jobs:
            v = np.array(out[tr["seq"]], np.float32)
            k = len(v)
            res[tr["seq"]] = (self.mono[a:a + k], self.norm(v, np.arange(a, a + k)), ft)
        return res

    # ------------------------------------------------------------ per trial

    def trial_steps(self, tr, sigma):
        """Step metrics; a rail step whose start level is wrong marks the trial's base as bad."""
        res, seen = [], set()
        t0, t1 = self.window(tr["seq"])
        for st in tr["steps"]:
            tf = self.log.flips.get((tr["seq"], st["flip"]))
            if tf is None:
                continue
            later = [self.log.flips.get((tr["seq"], s["flip"])) for s in tr["steps"]
                     if s["roi"] == st["roi"] and s["flip"] > st["flip"]]
            tend = min([x for x in later if x] + [t1])
            tt, r = self.series(st["roi"], tf - 0.3, tend)
            if len(tt) < 10:
                continue
            r = med3(r)
            pre = r[(tt < tf) & (tt > tf - 0.06)]
            r0 = float(np.median(pre)) if len(pre) else float(r[0])
            r1 = float(np.median(r[tt > tend - 0.3]))
            after = tt >= tf
            m = step_metrics((tt[after] - tf) * 1000, r[after], r0, r1, sigma)
            k = after & (tt < tf + 1.5)
            m["curve"] = [np.round((tt[k] - tf) * 1000, 2).tolist(), np.round(r[k], 4).tolist()]
            if st["roi"] not in seen and st["from"] in (0, 15):
                m["base_ok"] = abs(r0 - st["from"] / 15) < 0.15
            seen.add(st["roi"])
            res.append({**st, "flip_t": tf, **m})
        return res

    def analyse(self):
        a = self.args
        log, m = self.log, self.m
        e0 = [t for t in m["trials"] if t["exp"] == "E0" and t["seq"] in log.trials]
        sigma = 0.01
        if e0:
            s0, s1 = log.note(e0[0]["seq"], "win static0"), log.note(e0[0]["seq"], "win static1")
            if s0 and s1:
                i0, i1 = np.searchsorted(self.mono, [s0 + 0.1, s1 - 0.1])
                sigma = float(np.median(np.std(self.R[i0:i1], 0)))
                refw = self.ref[i0:i1]
                spec = np.abs(np.fft.rfft(refw - refw.mean()))[1:]
                fps = (len(self.pts) - 1) / (self.pts[-1] - self.pts[0])
                pk = int(np.argmax(spec)) if len(spec) else 0
                self.summary["E0"] = {
                    "sigma_R": sigma, "ref_cv_pct": float(100 * refw.std() / refw.mean()),
                    "ref_peak_ratio": float(spec[pk] / max(np.median(spec), 1e-9)) if len(spec) else 0,
                    "ref_peak_hz": float((pk + 1) * fps / len(refw)) if len(spec) else 0}
        self.sigma = max(sigma, 0.003)
        d = np.diff(self.pts)
        self.summary.setdefault("E0", {}).update({
            "fps": float(len(d) / (self.pts[-1] - self.pts[0])), "pts_jitter_ms": float(np.std(d) * 1000),
            "pts_min_ms": float(d.min() * 1000), "pts_max_ms": float(d.max() * 1000),
            "clock_rms_ms": self.ck["rms_ms"], "clock_max_ms": self.ck["max_ms"]})
        e = self.summary["E0"]
        cv = e.get("ref_cv_pct", 0)
        e["pwm_alias_flag"] = bool(cv > 1.0 or (cv > 0.3 and e.get("ref_peak_ratio", 0) > 25))
        e["clock_ok"] = bool(e["clock_rms_ms"] < 2.0)

        fast = [t for t in m["trials"] if t["section"] == "fast" and t["seq"] in log.trials]
        extra = self.extra_pass([t for t in fast if t["features"]])
        for tr in fast:
            steps = self.trial_steps(tr, self.sigma)
            base_ok = all(s.get("base_ok", True) for s in steps)
            self.results[tr["seq"]] = {"trial": tr, "steps": steps, "base_ok": base_ok,
                                       "features": extra.get(tr["seq"])}
            out = {k: tr[k] for k in ("seq", "exp", "name", "mode", "params")}
            out["steps"] = steps
            json.dump(out, open(self.out / "trials" / f"{tr['seq']:04d}-{tr['name']}.json", "w"),
                      indent=1)
        bad = [r["trial"]["name"] for r in self.results.values() if not r["base_ok"]]
        if bad:
            self.summary["base_failures"] = bad
            print(f"warning: {len(bad)} trials did not start from their base frame and are "
                  "excluded (clear longer than idle_ms, or changes lost during it)", file=sys.stderr)
        self.level_table()
        for exp in ("E1", "E2", "E3", "E4", "E6", "E7", "E8", "E9", "E10", "E11", "E12"):
            getattr(self, "an_" + exp)()
        obs = [t for t in m["trials"] if t["section"] == "observe"]
        if obs and self.grid is not None:
            self.an_E14()

    def by_exp(self, exp):
        return [r for r in self.results.values() if r["trial"]["exp"] == exp and r["base_ok"]]

    def level_table(self):
        lv = defaultdict(list)
        for r in self.by_exp("E1"):
            if r["trial"]["mode"] != "quality":
                continue
            for s in r["steps"]:
                lv[s["from"]].append(s["r0"])
                lv[s["to"]].append(s["r1"])
        self.levels = {k: float(np.median(v)) for k, v in lv.items()}
        self.levels.setdefault(0, 0.0)
        self.levels.setdefault(15, 1.0)
        for r in self.results.values():
            for s in r["steps"]:
                if s["to"] in self.levels:
                    s["final_error"] = s["r1"] - self.levels[s["to"]]

    def e1_table(self, exp):
        groups = defaultdict(list)
        for r in self.by_exp(exp):
            for s in r["steps"]:
                groups[(r["trial"]["mode"], s["from"], s["to"])].append(s)
        rows, spread = [], defaultdict(list)
        for (mode, a, b), ss in sorted(groups.items()):
            t10 = [s.get("t10") for s in ss]
            mt = med(t10)
            spread[mode] += [x - mt for x in t10 if x is not None]
            rows.append([mode, f"{a}->{b}", len(ss), mt, med([s.get("t50") for s in ss]),
                         med([s.get("t90") for s in ss]), med([s.get("t98") for s in ss]),
                         med([s.get("t0_est") for s in ss]),
                         sum(1 for s in ss if s["flash"] > 0), med([s["flash"] for s in ss]),
                         med([s.get("final_error") for s in ss])])
        write_tsv(self.out / f"summary_{exp}.tsv",
                  ["mode", "transition", "n", "t10_ms", "t50_ms", "t90_ms", "t98_ms", "t0_est_ms",
                   "flashes", "flash_amp", "final_err"], rows)
        clock = {}
        for mode, dv in spread.items():
            if len(dv) >= 4:
                p5, p95 = np.percentile(dv, [5, 95])
                clock[mode] = {"t10_spread_ms": float(p95 - p5),
                               "grid": bool(p95 - p5 > 6.0)}
        return rows, clock

    def an_E1(self):
        rows, clock = self.e1_table("E1")
        if not rows:
            return
        per = {}
        for mode, tr, n, t10, t50, t90, t98, *_ in rows:
            per.setdefault(mode, {})[tr] = {"t10": t10, "t50": t50, "t90": t90, "t98": t98}
        spreads = [c["t10_spread_ms"] for c in clock.values()]
        self.summary["E1"] = {"table": per, "clock": clock, "levels": self.levels,
                              "start": ("internal frame grid" if spreads and np.median(spreads) > 6
                                        else "frame arrival"),
                              "t10_spread_ms": med(spreads)}

    def rail_t98(self, mode):
        t = self.summary.get("E1", {}).get("table", {}).get(mode, {})
        return med([t.get(k, {}).get("t98") for k in ("15->0", "0->15")])

    def rail_t10(self, mode):
        t = self.summary.get("E1", {}).get("table", {}).get(mode, {})
        return med([t.get(k, {}).get("t10") for k in ("15->0", "0->15")])

    def an_E2(self):
        pts = defaultdict(list)
        for r in self.by_exp("E2"):
            p = r["trial"]["params"]
            st = {s["roi"]: s for s in r["steps"]}
            a = [st.get(x) for x in p["a"]]
            b = st.get(p["b"])
            if not b or not all(a) or b.get("t10") is None or a[0].get("t98") is None:
                continue
            delta = (b["flip_t"] - a[0]["flip_t"]) * 1000
            pts[(r["trial"]["mode"], p["variant"])].append(
                {"delta": delta, "t10_b": b["t10"], "t98_a": max(x["t98"] for x in a)})
        if not pts:
            return
        rows, waits = [], {}
        for (mode, var), ps in sorted(pts.items()):
            base = self.rail_t10(mode)
            far = [q["t10_b"] for q in pts.get((mode, "far"), [])
                   if q["delta"] > q["t98_a"] + 20]
            base = med(far) or base or med([q["t10_b"] for q in ps])
            ratios = []
            for q in ps:
                gap = q["t98_a"] - q["delta"]
                rows.append([mode, var, q["delta"], q["t10_b"], q["t98_a"], q["t10_b"] - base])
                if gap > 30:
                    ratios.append((q["t10_b"] - base) / gap)
            if len(ratios) >= 2:
                waits[(mode, var)] = {"ratio": float(np.median(ratios)),
                                      "waits": bool(np.median(ratios) > 0.5), "n": len(ratios)}
        write_tsv(self.out / "summary_E2.tsv",
                  ["mode", "variant", "delta_ms", "t10_B_ms", "t98_A_ms", "excess_ms"], rows)
        v = defaultdict(list)
        for (mode, var), w in waits.items():
            v[var].append(w["waits"])
        anyw = {k: (sum(x) > len(x) / 2) for k, x in v.items()}
        if not anyw:
            k1 = "unknown"
        elif anyw.get("far"):
            k1 = "global"
        elif anyw.get("inbox") or anyw.get("adjacent"):
            k1 = "region"
        else:
            k1 = "per-pixel"
        self.summary["E2"] = {"k1": k1, "variants": {f"{a}/{b}": w for (a, b), w in waits.items()}}

    def an_E3(self):
        votes, rows = defaultdict(list), []
        for r in self.by_exp("E3"):
            tr, p = r["trial"], r["trial"]["params"]
            mode = tr["mode"]
            first = next((s for s in r["steps"] if s["flip"] == tr["steps"][0]["flip"]), None)
            if not first:
                continue
            tf = first["flip_t"]
            t0, t1 = self.window(tr["seq"])
            tt, rr = self.series(tr["steps"][0]["roi"], tf - 0.3, t1)
            rr = med3(rr)
            hi = float(np.median(rr[tt < tf])) if np.any(tt < tf) else rr[0]
            lo = self.levels.get(0, 0.0)
            span = hi - lo
            target = p.get("target", p.get("burst", [0])[-1] if p.get("burst") else 0)
            r_t = self.levels.get(target, lo + span * target / 15)
            last = self.log.flips.get((tr["seq"], tr["steps"][-1]["flip"]), tf)
            dip = float((rr[tt >= tf].min() - lo) / span) if span > 5 * self.sigma else None
            final = float(np.median(rr[tt > t1 - 0.3]))
            reached = abs(final - r_t) < 0.25 * abs(span)
            stuck = abs(final - lo) < 0.25 * abs(span) and abs(r_t - lo) > 0.4 * abs(span)
            w98 = self.rail_t98(mode)
            delta = (last - tf) * 1000
            mid = w98 is not None and delta + (self.rail_t10(mode) or 0) < 0.7 * w98
            if p.get("burst"):
                mid = True
            verdict = None
            if mid and dip is not None:
                if stuck and not reached:
                    verdict = "lost"
                elif reached and dip < 0.1:
                    verdict = "queue"
                elif reached and dip > 0.15:
                    verdict = "restart"
            if verdict:
                votes[mode].append(verdict)
            rows.append([mode, tr["name"], delta, target, dip, final, r_t, int(mid), verdict])
        write_tsv(self.out / "summary_E3.tsv",
                  ["mode", "trial", "delta_ms", "target", "dip", "final_R", "target_R", "midflight",
                   "verdict"], rows)
        if not rows:
            return
        per = {m: max(set(v), key=v.count) for m, v in votes.items() if v}
        allv = [x for v in votes.values() for x in v]
        k2 = max(set(allv), key=allv.count) if allv else "unknown"
        if "lost" in allv:
            k2 = "lost" if allv.count("lost") >= len(allv) / 3 else k2
        self.summary["E3"] = {"k2": k2, "per_mode": per,
                              "votes": {m: dict((x, v.count(x)) for x in set(v)) for m, v in votes.items()}}

    def an_E4(self):
        rows, amp = [], {}
        for r in self.by_exp("E4"):
            tr = r["trial"]
            tf = self.log.flips.get((tr["seq"], 1))
            tl = self.log.flips.get((tr["seq"], len(tr["flips"]) - 1))
            if tf is None or tl is None:
                continue
            for pr in tr["params"]["pairs"]:
                tt, rr = self.series(f"P{pr['patch']}", tf, tl + 0.5)
                p2p = float(np.percentile(rr, 97) - np.percentile(rr, 3)) if len(rr) else 0.0
                amp.setdefault(pr["name"], []).append(p2p)
        for name, v in amp.items():
            a = float(np.median(v))
            rows.append([name, a, a / self.sigma, int(a > 5 * self.sigma)])
        write_tsv(self.out / "summary_E4.tsv", ["pair", "p2p_R", "x_sigma", "driven"], rows)
        if not rows:
            return
        driven = {r[0]: bool(r[3]) for r in rows}
        rgb = [float(np.median(amp[k])) for k in ("R16", "G16", "B16") if k in amp]
        weights = (np.array(rgb) / sum(rgb)).round(3).tolist() if len(rgb) == 3 and sum(rgb) > 0 else None
        sub_bin = driven.get("128-129") or driven.get("in-bin")
        self.summary["E4"] = {"driven": driven, "luma_weights_rgb": weights,
                              "k3": "diffs before quantising" if sub_bin else "diffs quantised levels"}

    def feature_rows(self, seq, name):
        f = self.results[seq]["features"]
        if not f:
            return None, None
        t, v, ft = f
        return t, v[:, ft.cols(name)]

    def an_E6(self):
        out = {}
        ctl, sw = [], []
        for r in self.by_exp("E6"):
            p = r["trial"]["params"]
            if p["part"] == "a" and r["steps"] and r["steps"][0].get("t98") is not None:
                (ctl if p["switch_ms"] is None else sw).append(r["steps"][0]["t98"])
        if ctl and sw:
            frame = 1000 / self.summary["E0"]["fps"]
            out["a"] = {"t98_ctl": med(ctl), "t98_switch": med(sw),
                        "switch_affects_inflight": bool(med(sw) < med(ctl) - 2 * frame)}
        bres = []
        for r in self.by_exp("E6"):
            if r["trial"]["params"]["part"] != "b" or not r["features"]:
                continue
            tsw = self.log.note(r["trial"]["seq"], "switch")
            t, ramp = self.feature_rows(r["trial"]["seq"], "ramp")
            _, text = self.feature_rows(r["trial"]["seq"], "text")
            _, white = self.feature_rows(r["trial"]["seq"], "white")
            if tsw is None or t is None:
                continue
            pre, post = (t < tsw) & (t > tsw - 0.3), (t >= tsw) & (t < tsw + 2.0)
            if not pre.any() or not post.any():
                continue
            mv = lambda v: np.abs(v[post] - np.median(v[pre], 0)).max(0) > 5 * self.sigma
            g = mv(ramp)
            bres.append({"greys_redrawn": int(g[1:15].sum()), "rails_redrawn": int(g[0] + g[15]),
                         "text_redrawn": bool(mv(text)[0]), "white_redrawn": bool(mv(white)[0])})
        if bres:
            gr = np.median([b["greys_redrawn"] for b in bres])
            wh = np.mean([b["white_redrawn"] for b in bres]) > 0.5
            out["b"] = {"trials": bres, "redraw": "everything" if wh else
                        ("fast-drawn greys" if gr >= 4 else "nothing")}
        cres = []
        for r in self.by_exp("E6"):
            p = r["trial"]["params"]
            if p["part"] != "c":
                continue
            tsw = self.log.note(r["trial"]["seq"], "switch")
            if tsw is None:
                continue
            i0, i1 = np.searchsorted(self.mono, [tsw - 0.3, tsw + 1.4])
            seg = self.R[i0:i1]
            tt = self.mono[i0:i1]
            pre = seg[tt < tsw]
            if not len(pre):
                continue
            dev = np.abs(seg[tt >= tsw] - np.median(pre, 0)).max(0)
            cres.append({"from": p["from"], "to": p["to"], "moved_patches": int((dev > 5 * self.sigma).sum()),
                         "max_dev": float(dev.max()),
                         "change_flashes": int(sum(1 for s in r["steps"] if s["flash"] > 0))})
        if cres:
            out["c"] = cres
            write_tsv(self.out / "summary_E6c.tsv", ["from", "to", "moved_patches", "max_dev", "change_flashes"],
                      [[c["from"], c["to"], c["moved_patches"], c["max_dev"], c["change_flashes"]] for c in cres])
        if out:
            self.summary["E6"] = out

    def classify_ramp(self, vals):
        lo, hi = self.levels.get(0, 0.0), self.levels.get(15, 1.0)
        mid = vals[4:12]
        near = np.minimum(np.abs(mid - lo), np.abs(mid - hi)) < 0.12 * (hi - lo)
        if np.all(np.abs(mid - hi) < 0.08 * (hi - lo)):
            return "greys ignored"
        if near.mean() > 0.75:
            return "thresholded"
        return "greys or dither"

    def an_E7(self):
        out = {}
        for r in self.by_exp("E7"):
            p, tr = r["trial"]["params"], r["trial"]
            if p["part"] == "a" and r["features"]:
                t, ramp = self.feature_rows(tr["seq"], "ramp")
                _, dramp = self.feature_rows(tr["seq"], "dramp")
                if t is None or len(t) < 10:
                    continue
                fin = slice(len(t) - max(5, len(t) // 10), None)
                out.setdefault("a", {}).setdefault(tr["mode"], []).append({
                    "ramp": self.classify_ramp(np.median(ramp[fin], 0)),
                    "dramp_levels": np.median(dramp[fin], 0).round(3).tolist()})
        ex, ref = [], []
        for r in self.by_exp("E7"):
            p, tr = r["trial"]["params"], r["trial"]
            w0, w1 = self.log.note(tr["seq"], "win final0"), self.log.note(tr["seq"], "win final1")
            if w0 is None or w1 is None:
                continue
            if p["part"] == "c" and r["features"]:
                t, eb = self.feature_rows(tr["seq"], "exblack")
                _, ew = self.feature_rows(tr["seq"], "exwhite")
                k = (t >= w0) & (t < w1)
                if k.any():
                    ex.append(float(lstar(np.median(ew[k])) - lstar(np.median(eb[k]))))
            if p["part"] == "cref":
                _, a7 = self.series("P7", w0, w1)
                _, b7 = self.series("P8", w0, w1)
                if len(a7):
                    ref.append(float(lstar(np.median(b7)) - lstar(np.median(a7))))
        if ex:
            out["c"] = {"residue_dL": med(ex), "clean_ref_dL": med(ref),
                        "a3_on": bool(abs(med(ex)) <= max(self.args.ghost_budget,
                                                         abs(med(ref) or 0)))}
        if out:
            self.summary["E7"] = out

    def an_E8(self):
        rows = []
        for r in self.by_exp("E8"):
            tr, p = r["trial"], r["trial"]["params"]
            if not r["features"]:
                continue
            t, prof = self.feature_rows(tr["seq"], "bar")
            if t is None or not len(t):
                continue
            x0f = tr["features"]["bar"]["rect"][0]
            bw = tr["features"]["bar"]["rect"][2] / tr["features"]["bar"]["nbins"]
            dark = np.clip(1 - prof, 0, 1) > 0.5
            pos, width = np.full(len(t), np.nan), np.zeros(len(t))
            for i, row in enumerate(dark):
                k = np.flatnonzero(row)
                if len(k):
                    pos[i] = x0f + bw * (k[-1] + 1) - p["bar_w"]
                    width[i] = bw * len(k)
            ft = np.array([self.log.flips.get((tr["seq"], f["idx"]), np.nan) for f in tr["flips"]])
            fx = np.array([f.get("x", np.nan) for f in tr["flips"]], float)
            ok = ~np.isnan(ft) & ~np.isnan(fx)
            if ok.sum() < 3:
                continue
            ft, fx = ft[ok], fx[ok]
            moving = (t > ft[0]) & (t < ft[-1] + 0.5) & ~np.isnan(pos)
            if moving.sum() < 5:
                continue
            frame = np.median(np.diff(ft))
            speed = p["speed_px"] / frame
            cmd = fx[np.clip(np.searchsorted(ft, t[moving], side="right") - 1, 0, len(fx) - 1)]
            lag_ms = (cmd - pos[moving]) / speed * 1000
            tm = t[moving] - ft[0]
            inside = tm < (ft[-1] - ft[0])
            slope = float(np.polyfit(tm[inside], lag_ms[inside], 1)[0]) if inside.sum() > 5 else None
            steps = np.abs(np.diff(pos[moving])) > 2
            back = int(np.sum(np.diff(pos[moving]) < -3))
            ups = float(steps.sum() / max(tm[-1], 1e-3))
            trail = float(np.median(width[t > t[-1] - 0.3]))
            behav = ("lost (trail never cleared)" if trail > 2 * p["bar_w"] else
                     "queue (lag grows)" if slope and slope > 50 else
                     "restart (position steps back)" if back > 3 else "drop (lag bounded)")
            rows.append([p["k"], ups, med(list(lag_ms)), slope, back, trail, behav])
        write_tsv(self.out / "summary_E8.tsv",
                  ["k", "updates_per_s", "median_lag_ms", "lag_slope_ms_per_s", "back_steps",
                   "final_dark_px", "behaviour"], rows)
        if rows:
            self.summary["E8"] = {"rows": rows, "max_updates_per_s": max(r[1] for r in rows)}

    def an_E9(self):
        regs = self.log.regs
        if not len(regs):
            return
        bits, mov = [], []
        rise, fall = defaultdict(list), defaultdict(list)
        for exp in ("E1", "E2", "E3"):
            for r in self.by_exp(exp):
                tr = r["trial"]
                tf = self.log.flips.get((tr["seq"], tr["steps"][0]["flip"])) if tr["steps"] else None
                if tf is None:
                    continue
                t1 = self.window(tr["seq"])[1]
                rois = sorted({int(s["roi"][1:]) for s in tr["steps"]})
                i0, i1 = np.searchsorted(self.mono, [tf - 0.2, t1])
                tt, seg = self.mono[i0:i1], self.R[i0:i1][:, rois]
                if len(tt) < 10:
                    continue
                dr = np.abs(np.diff(seg, axis=0)).max(1)
                moving = np.r_[False, dr > 4 * self.sigma]
                moving = np.convolve(moving, np.ones(5), "same") > 0
                grid = np.arange(tt[0], tt[-1], 0.002)
                mg = np.interp(grid, tt, moving.astype(float)) > 0.5
                k0, k1 = np.searchsorted(regs[:, 0], [grid[0], grid[-1]])
                if k1 - k0 < 5:
                    continue
                ri = np.clip(np.searchsorted(regs[k0:k1, 0], grid, side="right") - 1, 0, k1 - k0 - 1)
                vals = regs[k0:k1, 1:][ri].astype(int)
                b = np.stack([(vals[:, c] >> bit) & 1 for c in range(4) for bit in range(8)], 1)
                b[vals.repeat(8, 1) < 0] = 0
                bits.append(b)
                mov.append(mg)
                settle = max(s["flip_t"] + (s.get("t98") or 0) / 1000 for s in r["steps"])
                for j in range(32):
                    on = grid[b[:, j] == 1]
                    on = on[on >= tf]
                    if len(on):
                        rise[j].append((on[0] - tf) * 1000)
                        fall[j].append((on[-1] - settle) * 1000)
        if not bits:
            return
        B, M = np.concatenate(bits).astype(float), np.concatenate(mov).astype(float)
        names = [f"0x{r:02x}.{bit}" for r in (0x89, 0x8B, 0x8D, 0x8F) for bit in range(8)]
        rows, best = [], None
        for j in range(32):
            if B[:, j].std() == 0 or M.std() == 0:
                continue
            phi = float(np.corrcoef(B[:, j], M)[0, 1])
            row = [names[j], phi, med(rise[j]), med(fall[j])]
            rows.append(row)
            if best is None or phi > best[1]:
                best = row
        write_tsv(self.out / "summary_E9.tsv", ["bit", "phi", "rise_after_flip_ms", "fall_minus_t98_ms"], rows)
        frame = 1000 / self.summary["E0"]["fps"]
        busy = (best is not None and best[1] > 0.6 and best[3] is not None
                and abs(best[3]) < max(25, 6 * frame))
        self.summary["E9"] = {"best": best, "busy_flag": best[0] if busy else None}

    def an_E10(self):
        rows = []
        for r in self.by_exp("E10"):
            tr = r["trial"]
            tc = next((t for t, c in self.log.clears if c == tr["seq"] and t > self.log.flips.get((tr["seq"], 0), 0) + 0.5), None)
            if tc is None:
                continue
            i0, i1 = np.searchsorted(self.mono, [tc - 0.3, tc + 3.5])
            ref, tt = self.ref[i0:i1], self.mono[i0:i1]
            pre = np.median(ref[tt < tc]) if np.any(tt < tc) else ref[0]
            dark = ref < pre * 0.7
            dips = int(np.sum(np.diff(dark.astype(int)) == 1))
            out = np.flatnonzero(np.abs(ref - pre) > 0.03 * pre)
            dur = float((tt[out[-1]] - tc) * 1000) if len(out) else 0.0
            w0, w1 = self.log.note(tr["seq"], "win final0"), self.log.note(tr["seq"], "win final1")
            shown = None
            if w0 and w1:
                _, p0 = self.series("P0", w0, w1)
                if len(p0):
                    shown = bool(np.median(p0) < 0.5)
            rows.append([tr["params"]["variant"], dur, dips, shown])
        write_tsv(self.out / "summary_E10.tsv", ["variant", "duration_ms", "flashes", "change_visible"], rows)
        if rows:
            self.summary["E10"] = {"rows": rows}

    def an_E11(self):
        rows = []
        for r in self.by_exp("E11"):
            tr = r["trial"]
            if not r["features"]:
                continue
            t, g = self.feature_rows(tr["seq"], "page")
            n = {k: self.log.note(tr["seq"], f"win {k}") for k in ("A0", "A1", "B0", "B1")}
            if None in n.values():
                continue
            a = (t >= n["A0"]) & (t < n["A1"])
            b = (t >= n["B0"]) & (t < n["B1"])
            if not a.any() or not b.any():
                continue
            la, lb = lstar(np.median(g[a], 0)), lstar(np.median(g[b], 0))
            rows.append([tr["params"]["variant"], tr["params"]["steps"],
                         float(np.sqrt(np.mean((la - lb) ** 2)))])
        write_tsv(self.out / "summary_E11.tsv", ["variant", "steps", "residue_Lstar_rms"], rows)
        if not rows:
            return
        res = {}
        for var in {r[0] for r in rows}:
            pts = sorted((r[1], r[2]) for r in rows if r[0] == var)
            ks, vs = np.array([p[0] for p in pts]), np.array([p[1] for p in pts])
            over = [k for k, v in pts if v > self.args.ghost_budget]
            res[var] = {"points": pts, "debt_per_step": float(np.polyfit(ks, vs, 1)[0]) if len(ks) > 1 else None,
                        "clean_after_steps": over[0] if over else None}
        self.summary["E11"] = res

    def an_E12(self):
        rows, _ = self.e1_table("E12")
        if not rows:
            return
        regs = self.log.regs
        temp = med([int(v) for v in regs[:, 4] if v >= 0]) if len(regs) else None
        out = {"ntc_0x8f": temp, "rows": rows}
        if self.args.baseline:
            base = {}
            for line in open(Path(self.args.baseline) / "summary_E1.tsv").readlines()[1:]:
                f = line.rstrip("\n").split("\t")
                if f[6]:
                    base[(f[0], f[1])] = float(f[6])
            ratios = [r[6] / base[(r[0], r[1])] for r in rows
                      if r[6] and base.get((r[0], r[1]))]
            out["t98_cold_over_warm"] = med(ratios)
        self.summary["E12"] = out

    def an_E14(self):
        downs = [t for t, s in self.log.touches if s == "down"]
        if not downs:
            return
        g = self.grid
        noise = np.median(np.abs(np.diff(g, axis=0)), 0) * 1.5 + 1e-3
        lat = []
        for td in downs:
            i0 = np.searchsorted(self.mono, td)
            if i0 < 30 or i0 + 240 >= len(g):
                continue
            base = np.median(g[i0 - 24:i0], 0)
            dev = np.abs(g[i0:i0 + 240] - base) > 8 * noise
            hold = 24
            for k in range(len(dev) - hold):
                cells = dev[k] & dev[k:k + hold].all(0)
                if cells.any():
                    lat.append(float((self.mono[i0 + k] - td) * 1000))
                    break
        self.summary["E14"] = {"touches": len(downs), "measured": len(lat),
                               "touch_to_ink_ms": med(lat),
                               "p90_ms": float(np.percentile(lat, 90)) if lat else None,
                               "note": "persistent-change heuristic; check against the video"}

    # ------------------------------------------------------------ static (4K)

    def strobe_offset(self, pts, glob, seqs):
        """Camera-minus-probe offset from strobe spikes; a 50 ms pulse shows at 30 fps too."""
        n = len(glob)
        base = np.array([np.median(glob[max(0, i - 15):i + 16]) for i in range(n)])
        hot = glob > base * 1.03 + 0.5
        spikes = [pts[i] for i in range(1, min(n, len(pts))) if hot[i] and not hot[i - 1]]
        codes = [c["t"] for c in self.log.codes if c["trial"] in seqs and c["t"] is not None]
        offs = np.array([s - c for s in spikes for c in codes])
        if len(offs) < 2:
            return None
        bins = np.round(offs / 0.1)
        vals, cnt = np.unique(bins, return_counts=True)
        if cnt.max() < 2:
            return None
        mode = vals[np.argmax(cnt)] * 0.1
        return float(np.median(offs[np.abs(offs - mode) < 0.15]))

    def static_pass(self, path):
        trials = [t for t in self.m["trials"] if t["section"] == "static" and t["seq"] in self.log.trials]
        if not trials:
            return
        pts, w, h = probe(path)
        wh = (w, h)
        prev, diffs, glob = None, [np.inf], []
        for f in frames(path, self.args.width, wh):
            small = f[::8, ::8].astype(np.float32)
            if prev is not None:
                diffs.append(float(np.abs(small - prev).mean()))
            glob.append(float(small.mean()))
            prev = small
        diffs, glob = np.array(diffs), np.array(glob)
        still = diffs < max(1.0, 3 * np.median(diffs[1:]))
        stable, run0 = [], None
        for n, s in enumerate(still):
            if s and run0 is None:
                run0 = n
            if not s and run0 is not None:
                stable.append((run0, n - 1))
                run0 = None
        if run0 is not None:
            stable.append((run0, len(still) - 1))
        stable = [(a, b) for a, b in stable if pts[min(b, len(pts) - 1)] - pts[a] > 1.0]
        if not stable:
            print("static video: no stable segments", file=sys.stderr)
            return
        hold = self.m["conventions"]["static_hold_ms"] / 1000
        exp = [(self.log.flips[(t["seq"], 0)] + 1.0, self.log.flips[(t["seq"], 0)] + hold - 0.3)
               for t in trials if (t["seq"], 0) in self.log.flips]
        segs = [(pts[a], pts[min(b, len(pts) - 1)]) for a, b in stable]
        best, best_n = self.strobe_offset(pts, glob, {t["seq"] for t in trials}), len(exp)
        if best is None:
            best_n = -1
            for s0, s1 in segs:
                for e0, e1 in exp:
                    off = (s0 + s1) / 2 - (e0 + e1) / 2
                    n = sum(any(a <= e0 + off and e1 + off <= b for a, b in segs) for e0, e1 in exp)
                    if n > best_n:
                        best, best_n = off, n
        a0, b0 = stable[0]
        calib_sel = f"between(n,{a0},{min(b0, a0 + 15)})"
        calib = np.median(np.stack([f.astype(np.float32) for f in
                                    frames(path, self.args.width, wh, select=calib_sel)]), 0)
        hm, _ = find_panel(calib.astype(np.uint8), self.m)
        jobs = []
        for tr, (e0, e1) in zip(trials, exp):
            i0, i1 = np.searchsorted(pts, [e0 + best, e1 + best])
            if i1 > i0:
                jobs.append((i0, i1, tr))
        sel = "+".join(f"between(n,{a},{b - 1})" for a, b, _ in jobs)
        sums = {tr["seq"]: [np.zeros(calib.shape, np.float64), 0] for _, _, tr in jobs}
        idxs = np.concatenate([np.arange(a, b) for a, b, _ in jobs])
        for n, f in zip(idxs, frames(path, self.args.width, wh, select=sel)):
            for a, b, tr in jobs:
                if a <= n < b:
                    sums[tr["seq"]][0] += f
                    sums[tr["seq"]][1] += 1
        stat = {}
        for _, _, tr in jobs:
            img = sums[tr["seq"]][0] / max(sums[tr["seq"]][1], 1)
            std = Features(hm, img.shape, std_specs(self.m))(img)
            ref, black = std[24], np.mean(std[25:])
            px, py = project(hm, *[a.ravel() for a in np.meshgrid(np.arange(0, 800, 2.0), np.arange(0, 600, 2.0))])
            ok = (px >= 0) & (px < img.shape[1] - 1) & (py >= 0) & (py < img.shape[0] - 1)
            rect = np.zeros(px.shape)
            rect[ok] = img[np.round(py[ok]).astype(int), np.round(px[ok]).astype(int)]
            pgm = np.clip(rect.reshape(300, 400), 0, 255).astype(np.uint8)
            with open(self.out / f"snap-{tr['name']}.pgm", "wb") as fh:
                fh.write(b"P5 400 300 255\n" + pgm.tobytes())
            ft = Features(hm, img.shape, list(tr["features"].items()))
            v = ft(img)
            res = {}
            for name in tr["features"]:
                vals = v[ft.cols(name)]
                res[name] = {"R": ((vals - black) / (ref - black)).round(4).tolist(),
                             "Y": (vals / ref).round(4).tolist()}
            stat[tr["name"]] = res
        self.static = stat
        out = {"aligned": best_n, "expected": len(exp)}
        if "E5-ramp256" in stat:
            r = np.array(stat["E5-ramp256"]["ramp256"]["R"])
            thr = 0.3 * abs(r[-1] - r[0]) / 15
            pad = np.r_[[r[0]] * 3, r, [r[-1]] * 3]
            persist = np.array([pad[v + 3:v + 6].mean() - pad[v:v + 3].mean() for v in range(1, 256)])
            edges = [v for v in range(1, 256) if abs(r[v] - r[v - 1]) > thr and abs(persist[v - 1]) > thr]
            out["E5_bin_edges"] = edges
            out["E5_staircase_ok"] = len(edges) == 15
        if "E5-ramp16" in stat:
            y = np.array(stat["E5-ramp16"]["ramp16"]["Y"])
            out["E5_Lstar"] = lstar(y).round(2).tolist()
            out["E5_gamma_R"] = stat["E5-ramp16"]["ramp16"]["R"]
        for mode in ("fast", "text"):
            k = f"E7b-{mode}"
            if k in stat:
                out[f"E7b_{mode}"] = self.classify_ramp(np.array(stat[k]["ramp"]["R"]))
        self.summary["static"] = out
        json.dump(stat, open(self.out / "static.json", "w"), indent=1)


# ---------------------------------------------------------------- decision

def decide(s):
    k1 = s.get("E2", {}).get("k1", "unknown")
    k2 = s.get("E3", {}).get("k2", "unknown")
    e1 = s.get("E1", {})
    fast = e1.get("table", {}).get("fast", {})
    binary = med([fast.get(k, {}).get("t98") for k in ("0->15", "15->0")])
    look = med([fast.get(k, {}).get("t50") for k in ("0->15", "15->0")])
    busy = s.get("E9", {}).get("busy_flag")
    e6 = s.get("E6", {})
    e7c = s.get("E7", {}).get("c", {})
    e11 = s.get("E11", {})
    cfg = {"K1": k1, "K2": k2, "K3": s.get("E4", {}).get("k3", "unknown"),
           "K5_start": e1.get("start", "unknown"), "binary_period_ms": binary}
    inflight = e6.get("a", {}).get("switch_affects_inflight")
    cfg["A1"] = ("on; switch at the next idle boundary" if inflight else
                 "on; switch immediately" if inflight is not None else "on; E6a not measured")
    edges = s.get("static", {}).get("E5_bin_edges")
    cfg["A2"] = f"on; bin edges {edges}" if edges else "on; L(k) bins until E5 is measured"
    redraw = e6.get("b", {}).get("redraw")
    a3 = e7c.get("a3_on")
    cfg["A3"] = ("unknown (E7c missing)" if a3 is None else
                 ("on" if a3 else "off: refine residue above the ghost budget") +
                 ("; align refine with the CPLD's own redraw" if redraw == "fast-drawn greys" else ""))
    cfg["A4"] = cfg["A5"] = "on"
    if k1 == "per-pixel" and k2 == "restart":
        cfg["A6"] = f"rate cap at the binary period ({binary} ms) only"
    elif k1 == "per-pixel" and k2 in ("queue", "lost"):
        cfg["A6"] = f"mandatory: one content state per binary period ({binary} ms)"
    elif k1 == "region":
        cfg["A6"] = "pacing per region"
    elif k1 == "global":
        cfg["A6"] = (f"late-latch to the busy edge ({busy})" if busy else
                     f"late-latch to the E1 timing model (binary update {binary} ms)")
    else:
        cfg["A6"] = "unknown"
    cfg["A7"] = {"per-pixel": "on", "region": "on; keep OSK/feedback regions disjoint from refines",
                 "global": "off; defer grey refines to >=300 ms quiet + finger up"}.get(k1, "unknown")
    cfg["A8"] = ("(a) sprint on; overdrive allowed" if k2 == "restart" else
                 "(a) sprint on" if a3 else "(a) off") + "; (b) research"
    cfg["A9"] = f"lookahead {look} ms (fast-mode t50)" if look else "unknown"
    clean = {v: d.get("clean_after_steps") for v, d in e11.items()}
    cfg["A10"] = f"clean after {clean} scroll steps (E11)" if clean else "threshold unknown (E11 missing)"
    cfg["A11"] = "Keel + protocol first"
    cfg["A12"] = "on: re-assert content after each update" if k2 == "lost" else "off"
    cfg["A13"] = "not measured (E13 is not in the default suite)"
    tree = {("per-pixel", "restart"): "Tier A ~ Caster policy",
            ("per-pixel", "queue"): "pacing mandatory, A7 on"}.get((k1, k2))
    if k1 == "region":
        tree = "region scheduling"
    if k1 == "global":
        tree = "global: late-latch, A7 off" + (", A12 guard" if k2 == "lost" else "")
    cfg["outcome"] = tree or "incomplete"
    return cfg


def check_truth(run, truth):
    fps = run.summary["E0"]["fps"]
    frame = 1000 / fps
    meas = {(r["trial"]["seq"], s["roi"], s["flip"]): s.get("t10")
            for r in run.results.values() for s in r["steps"]}
    errs = []
    for st in truth["steps"]:
        m = meas.get((st["seq"], st["roi"], st["flip"]))
        if m is not None and st["t10_ms"] is not None:
            errs.append(m - st["t10_ms"])
    errs = np.array(errs)
    within = float(np.mean(np.abs(errs) <= frame)) if len(errs) else 0.0
    k1, k2 = run.summary.get("E2", {}).get("k1"), run.summary.get("E3", {}).get("k2")
    ok = len(errs) > 0 and within >= 0.9 and k1 == truth["k1"] and k2 == truth["k2"]
    print(f"truth: {len(errs)} steps, latency error median {np.median(errs):+.2f} ms, "
          f"|err| p95 {np.percentile(np.abs(errs), 95):.2f} ms, {within:.0%} within one frame "
          f"({frame:.2f} ms); K1 {k1} (injected {truth['k1']}), K2 {k2} (injected {truth['k2']})")
    print("truth check:", "PASS" if ok else "FAIL")
    return ok, {"n": len(errs), "median_err_ms": float(np.median(errs)) if len(errs) else None,
                "within_frame": within, "k1": k1, "k2": k2}


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--manifest", required=True)
    ap.add_argument("--log", required=True)
    ap.add_argument("--video", required=True, help="240 fps recording")
    ap.add_argument("--video4k", help="4K static recording (E5, E7b)")
    ap.add_argument("--out", required=True)
    ap.add_argument("--width", type=int, default=960, help="decode width")
    ap.add_argument("--calib-time", type=float, help="video time (s) of a clean layout frame")
    ap.add_argument("--ghost-budget", type=float, default=3.0, help="L* residue budget")
    ap.add_argument("--baseline", help="a warm run's output dir, for E12")
    ap.add_argument("--truth", help="synth_video.py truth file to validate against")
    a = ap.parse_args()

    manifest = json.load(open(a.manifest))
    log = Log(a.log)
    run = Run(a, manifest, log)
    finfo = run.pass1(a.video)
    ck = run.clock()
    print(f"clock: {ck['codes_matched']}/{ck['codes_log']} codes, {ck['edges']} edges, "
          f"residual rms {ck['rms_ms']:.2f} ms, max {ck['max_ms']:.2f} ms, drift {ck['drift_ppm']:+.1f} ppm")
    json.dump({**ck, "fiducials": finfo}, open(run.out / "clock.json", "w"), indent=1)
    run.analyse()
    if a.video4k:
        run.static_pass(a.video4k)
    cfg = decide(run.summary)
    json.dump({"summary": run.summary, "tier_a": cfg}, open(run.out / "decision.json", "w"),
              indent=1, default=str)
    e0 = run.summary.get("E0", {})
    print(f"E0: fps {e0.get('fps', 0):.3f}, PTS jitter {e0.get('pts_jitter_ms', 0):.2f} ms, "
          f"sigma_R {e0.get('sigma_R', float('nan')):.4f}, ref CV {e0.get('ref_cv_pct', float('nan')):.2f}%, "
          f"PWM alias {'SUSPECT' if e0.get('pwm_alias_flag') else 'ok'}")
    print("Tier A configuration:")
    for k, v in cfg.items():
        print(f"  {k:18s} {v}")
    if a.truth:
        ok, res = check_truth(run, json.load(open(a.truth)))
        json.dump(res, open(run.out / "truth_check.json", "w"), indent=1)
        sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
