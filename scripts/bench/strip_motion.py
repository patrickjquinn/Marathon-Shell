#!/usr/bin/env python3
"""Displayed motion from a kmsgrab strip: how far the content moved on each
frame that reached the panel, so judder, repeated frames and catch-up jumps
show directly (the user's view, whatever drew the frame).

Capture on the device while the bench runs, e.g.
  ffmpeg -device /dev/dri/card0 -f kmsgrab -framerate 120 -i - -t 6 \
    -vf "hwdownload,format=bgr0,crop=W:H:X:Y,format=gray" -f rawvideo strip.gray

usage: strip_motion.py strip.gray W H [--fps 120] [--horizontal] [--json]
The strip is reduced to a 1-D profile along the scroll axis; consecutive
distinct samples are matched by the shift that minimises the profile
difference.
"""
import argparse
import json
import statistics
import sys


def profiles(data, w, h, horizontal):
    n = len(data) // (w * h)
    out = []
    for i in range(n):
        f = data[i * w * h:(i + 1) * w * h]
        if horizontal:
            out.append([sum(f[y * w + x] for y in range(h)) / h for x in range(w)])
        else:
            out.append([sum(f[y * w:(y + 1) * w]) / w for y in range(h)])
    return out


def shift(a, b, maxs):
    best, bs = None, 0
    n = len(a)
    for s in range(-maxs, maxs + 1):
        lo, hi = max(0, s), min(n, n + s)
        if hi - lo < n // 2:
            continue
        err = 0.0
        for i in range(lo, hi):
            d = a[i] - b[i - s]
            err += d * d
        err /= (hi - lo)
        if best is None or err < best:
            best, bs = err, s
    return bs, best


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("file")
    ap.add_argument("w", type=int)
    ap.add_argument("h", type=int)
    ap.add_argument("--fps", type=float, default=120.0)
    ap.add_argument("--max-shift", type=int, default=90)
    ap.add_argument("--horizontal", action="store_true")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--pts", help="ffmpeg showinfo log (-copyts): wall-clock grab time per frame")
    ap.add_argument("--bench", help="scroll_bench JSON: report move-to-first-motion per round")
    a = ap.parse_args()
    data = open(a.file, "rb").read()
    prof = profiles(data, a.w, a.h, a.horizontal)
    frames = []  # (sample index, shift from previous distinct frame)
    prev = prof[0]
    for i in range(1, len(prof)):
        p = prof[i]
        diff = max(abs(x - y) for x, y in zip(p, prev))
        if diff < 1.0:
            continue
        s, _ = shift(prev, p, a.max_shift)
        frames.append((i, s))
        prev = p
    dt = 1.0 / a.fps
    rows = [{"t_ms": round(i * dt * 1000, 1), "shift": s} for i, s in frames]
    # motion segments: runs of distinct frames with gaps under 50 ms
    segs, cur = [], []
    for r in rows:
        if cur and r["t_ms"] - cur[-1]["t_ms"] > 50:
            segs.append(cur)
            cur = []
        cur.append(r)
    if cur:
        segs.append(cur)
    report = []
    for sg in segs:
        if len(sg) < 4:
            continue
        gaps = [b["t_ms"] - a_["t_ms"] for a_, b in zip(sg, sg[1:])]
        sh = [abs(r["shift"]) for r in sg]
        # frame-to-frame change of speed: judder shows as large alternation
        acc = [abs(y - x) for x, y in zip(sh, sh[1:])]
        report.append({
            "start_ms": sg[0]["t_ms"], "dur_ms": round(sg[-1]["t_ms"] - sg[0]["t_ms"], 1),
            "frames": len(sg),
            "gap_p50_ms": statistics.median(gaps),
            "gaps_over_25ms": sum(1 for g in gaps if g > 25),
            "mean_shift_px": round(statistics.mean(sh), 2),
            "mean_abs_dshift_px": round(statistics.mean(acc), 2) if acc else 0,
            "shifts": [r["shift"] for r in sg],
        })
    if a.pts and a.bench:
        import re
        pts = [float(x) for x in re.findall(r"pts_time:([0-9.]+)", open(a.pts).read())]
        moved = {i for i, s in frames if s != 0}
        lat = []
        for r in json.load(open(a.bench))["round_times"]:
            t = r["move_rt"]
            first = next((i for i in range(len(prof)) if i < len(pts) and pts[i] >= t and i in moved), None)
            lat.append(None if first is None else round((pts[first] - t) * 1000, 1))
        print("move to first displayed motion (ms):", lat)
    if a.json:
        print(json.dumps({"segments": report}, indent=1))
    else:
        for r in report:
            print("seg @%.0fms %4.0fms frames=%d gap50=%.1f >25ms=%d mean=%.1fpx |dshift|=%.2f" % (
                r["start_ms"], r["dur_ms"], r["frames"], r["gap_p50_ms"], r["gaps_over_25ms"],
                r["mean_shift_px"], r["mean_abs_dshift_px"]))
            print("   ", r["shifts"])


if __name__ == "__main__":
    main()
