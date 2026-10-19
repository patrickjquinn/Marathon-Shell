#!/usr/bin/env python3
"""Scroll bench: the same scripted fling for any foreground app, measured
from the kernel side so Marathon apps, the shell and Android compare alike.

Runs on the device as root, stdlib only. Injects touches through uinput and
records ftrace (trace_clock mono, the clock of time.monotonic()):
  drm_vblank_event_delivered  each page flip the compositor gets
  gpu_scheduler:drm_sched_job each v3d render job, with the submitting tgid

Each round: touch down, fling (DIST px over FLING_MS, STEP_MS steps; the
panel reports at 100 Hz), optionally hold still HOLD_MS, lift,
wait CATCH_MS, touch down again without moving (the catch), lift, idle.
Rounds alternate direction so a list doesn't run into its end.

usage: scroll_bench.py [--rounds N] [--x X] [--y0 Y0] [--dist D]
                       [--fling-ms MS] [--catch-ms MS] [--out FILE.json]
Coordinates are panel pixels (720x720 on the HackberryPi).
"""
import argparse
import fcntl
import json
import os
import re
import statistics
import struct
import time

TRACE = "/sys/kernel/tracing"
EVENTS = ["drm/drm_vblank_event_delivered", "gpu_scheduler/drm_sched_job"]

EV_SYN, EV_KEY, EV_ABS = 0, 1, 3
SYN_REPORT, BTN_TOUCH = 0, 0x14A
ABS_X, ABS_Y = 0, 1
ABS_MT_SLOT, ABS_MT_POSITION_X, ABS_MT_POSITION_Y, ABS_MT_TRACKING_ID = 0x2F, 0x35, 0x36, 0x39
INPUT_PROP_DIRECT = 1
UI_SET_EVBIT, UI_SET_KEYBIT, UI_SET_ABSBIT = 0x40045564, 0x40045565, 0x40045567
UI_SET_PROPBIT = 0x4004556E
UI_DEV_CREATE, UI_DEV_DESTROY = 0x5501, 0x5502
ABS_MAX = 32767
FRAME_GAP = 0.004  # submits from one process closer than this are one frame


class Touch:
    def __init__(self, width, height):
        self.w, self.h = width, height
        self.fd = os.open("/dev/uinput", os.O_WRONLY | os.O_NONBLOCK)
        fcntl.ioctl(self.fd, UI_SET_EVBIT, EV_KEY)
        fcntl.ioctl(self.fd, UI_SET_EVBIT, EV_ABS)
        fcntl.ioctl(self.fd, UI_SET_KEYBIT, BTN_TOUCH)
        fcntl.ioctl(self.fd, UI_SET_PROPBIT, INPUT_PROP_DIRECT)
        axes = (ABS_X, ABS_Y, ABS_MT_SLOT, ABS_MT_POSITION_X, ABS_MT_POSITION_Y, ABS_MT_TRACKING_ID)
        for a in axes:
            fcntl.ioctl(self.fd, UI_SET_ABSBIT, a)
        absmax = [0] * 64
        absmin = [0] * 64
        for a in (ABS_X, ABS_Y, ABS_MT_POSITION_X, ABS_MT_POSITION_Y):
            absmax[a] = ABS_MAX
        absmax[ABS_MT_SLOT] = 4
        absmax[ABS_MT_TRACKING_ID] = 65535
        name = b"scroll-bench".ljust(80, b"\0")
        dev = name + struct.pack("<HHHHi", 3, 1, 1, 1, 0)
        dev += struct.pack("<64i", *absmax) + struct.pack("<64i", *absmin)
        dev += struct.pack("<64i", *([0] * 64)) + struct.pack("<64i", *([0] * 64))
        os.write(self.fd, dev)
        fcntl.ioctl(self.fd, UI_DEV_CREATE)
        self.tid = 100

    def _ev(self, t, c, v):
        os.write(self.fd, struct.pack("<qqHHi", 0, 0, t, c, v))

    def _pos(self, x, y):
        ax = max(0, min(ABS_MAX, int(x * ABS_MAX / self.w)))
        ay = max(0, min(ABS_MAX, int(y * ABS_MAX / self.h)))
        self._ev(EV_ABS, ABS_MT_POSITION_X, ax)
        self._ev(EV_ABS, ABS_MT_POSITION_Y, ay)
        self._ev(EV_ABS, ABS_X, ax)
        self._ev(EV_ABS, ABS_Y, ay)

    def down(self, x, y):
        self.tid += 1
        self._ev(EV_ABS, ABS_MT_SLOT, 0)
        self._ev(EV_ABS, ABS_MT_TRACKING_ID, self.tid)
        self._pos(x, y)
        self._ev(EV_KEY, BTN_TOUCH, 1)
        self._ev(EV_SYN, SYN_REPORT, 0)
        return time.monotonic()

    def move(self, x, y):
        self._pos(x, y)
        self._ev(EV_SYN, SYN_REPORT, 0)

    def up(self):
        self._ev(EV_ABS, ABS_MT_SLOT, 0)
        self._ev(EV_ABS, ABS_MT_TRACKING_ID, -1)
        self._ev(EV_KEY, BTN_TOUCH, 0)
        self._ev(EV_SYN, SYN_REPORT, 0)
        return time.monotonic()

    def close(self):
        fcntl.ioctl(self.fd, UI_DEV_DESTROY)
        os.close(self.fd)


def sleep_until(t):
    while True:
        d = t - time.monotonic()
        if d <= 0:
            return
        time.sleep(min(d, 0.002) if d < 0.004 else d - 0.002)


def tw(path, value):
    with open(os.path.join(TRACE, path), "w") as f:
        f.write(value)


STALL_EVENTS = ("sched/sched_switch", "sched/sched_stat_runtime")


def trace_start(stall_tid=None):
    tw("tracing_on", "0")
    tw("trace", "")
    tw("trace_clock", "mono")
    tw("buffer_size_kb", "16384")
    tw("options/record-tgid", "1")
    for e in EVENTS:
        tw("events/%s/enable" % e, "1")
    if stall_tid:
        # user stacks of one thread at every switch and scheduler tick
        tw("options/userstacktrace", "1")
        tids = [int(t) for t in str(stall_tid).split(",")]
        tw("events/sched/sched_switch/filter",
           " || ".join("prev_pid == %d || next_pid == %d" % (t, t) for t in tids))
        tw("events/sched/sched_stat_runtime/filter", " || ".join("pid == %d" % t for t in tids))
        for e in STALL_EVENTS:
            tw("events/%s/enable" % e, "1")
    tw("tracing_on", "1")


def trace_stop():
    tw("tracing_on", "0")
    for e in EVENTS + list(STALL_EVENTS):
        tw("events/%s/enable" % e, "0")
    for e in STALL_EVENTS:
        tw("events/%s/filter" % e, "0")
    tw("options/userstacktrace", "0")
    with open(os.path.join(TRACE, "trace")) as f:
        text = f.read()
    tw("trace", "")
    return text


LINE = re.compile(r"^\s*(.+?)-(\d+)\s+\(\s*(\d+|-+)\)\s+\[\d+\]\s+\S+\s+([\d.]+):\s+(\w+):\s*(.*)$")


def parse(text):
    flips, submits = [], {}
    for line in text.splitlines():
        m = LINE.match(line)
        if not m:
            continue
        tgid = m.group(3)
        ts, ev = float(m.group(4)), m.group(5)
        if ev == "drm_vblank_event_delivered":
            flips.append(ts)
        elif ev == "drm_sched_job" and "ring=v3d_render" in m.group(6) and tgid.isdigit():
            submits.setdefault(int(tgid), []).append(ts)
    return flips, submits


def frames_of(ts):
    out = []
    for t in sorted(ts):
        if not out or t - out[-1][-1] > FRAME_GAP:
            out.append([t])
        else:
            out[-1].append(t)
    return [f[0] for f in out]


def pct(v, p):
    if not v:
        return None
    s = sorted(v)
    return s[min(len(s) - 1, int(round(p / 100.0 * (len(s) - 1))))]


def ms(x):
    return None if x is None else round(x * 1000.0, 2)


def comm(pid):
    try:
        with open("/proc/%d/cmdline" % pid, "rb") as f:
            c = f.read().split(b"\0")[0].decode(errors="replace")
        return os.path.basename(c) or "?"
    except OSError:
        return "exited"


def interval_stats(times, period):
    d = [b - a for a, b in zip(times, times[1:])]
    return {
        "n": len(times),
        "p50_ms": ms(pct(d, 50)), "p95_ms": ms(pct(d, 95)),
        "p99_ms": ms(pct(d, 99)), "max_ms": ms(max(d) if d else None),
        "missed_vblanks": int(sum(max(0, round(x / period) - 1) for x in d)),
    }


def analyse(rounds, flips, submits, period):
    flip_d = []
    per_round = []
    all_app = {}
    for r in rounds:
        lo, hi = r["down"], r["catch"]
        in_f = [t for t in flips if lo <= t <= hi]
        flip_d.extend(b - a for a, b in zip(in_f, in_f[1:]))
        row = {"window_ms": ms(hi - lo), "flips": interval_stats(in_f, period)}
        procs = {}
        for pid, ts in submits.items():
            fr = [t for t in frames_of(ts) if lo <= t <= hi]
            if len(fr) < 3:
                continue
            procs[pid] = interval_stats(fr, period)
            all_app.setdefault(pid, []).append(fr)
            after = [t for t in frames_of(ts) if r["catch"] <= t <= r["end"]]
            last = r["catch"]
            for t in after:
                if t - last > 0.15:
                    break
                last = t
            procs[pid]["catch_to_last_frame_ms"] = ms(last - r["catch"])
            # vblank intervals in the window that showed no new frame
            empty = 0
            for a, b in zip(in_f, in_f[1:]):
                if not any(a - period <= t < b - period for t in fr):
                    empty += 1
            procs[pid]["vblanks_without_new_frame"] = empty
        row["procs"] = {"%d:%s" % (p, comm(p)): v for p, v in procs.items()}
        per_round.append(row)
    summary = {}
    for pid, lists in all_app.items():
        d = [b - a for fr in lists for a, b in zip(fr, fr[1:])]
        summary["%d:%s" % (pid, comm(pid))] = {
            "frames": sum(len(f) for f in lists),
            "p50_ms": ms(pct(d, 50)), "p95_ms": ms(pct(d, 95)),
            "p99_ms": ms(pct(d, 99)), "max_ms": ms(max(d) if d else None),
            "missed_vblanks": int(sum(max(0, round(x / period) - 1) for x in d)),
            "catch_to_last_frame_ms": [r["procs"].get("%d:%s" % (pid, comm(pid)), {}).get("catch_to_last_frame_ms") for r in per_round],
        }
    return {
        "flips": {"p50_ms": ms(pct(flip_d, 50)), "p95_ms": ms(pct(flip_d, 95)),
                  "p99_ms": ms(pct(flip_d, 99)), "max_ms": ms(max(flip_d) if flip_d else None),
                  "missed_vblanks": int(sum(max(0, round(x / period) - 1) for x in flip_d))},
        "per_process": summary,
        "rounds": per_round,
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--rounds", type=int, default=6)
    ap.add_argument("--x", type=int, default=360)
    ap.add_argument("--y0", type=int, default=540)
    ap.add_argument("--dist", type=int, default=320)
    ap.add_argument("--fling-ms", type=int, default=100)
    ap.add_argument("--catch-ms", type=int, default=600)
    ap.add_argument("--idle-ms", type=int, default=1800)
    ap.add_argument("--step-ms", type=float, default=10.0)
    ap.add_argument("--hold-ms", type=int, default=0)
    ap.add_argument("--pre-ms", type=int, default=0, help="hold still after touch-down before moving")
    ap.add_argument("--horizontal", action="store_true")
    ap.add_argument("--width", type=int, default=720)
    ap.add_argument("--height", type=int, default=720)
    ap.add_argument("--hz", type=float, default=60.0)
    ap.add_argument("--out")
    ap.add_argument("--raw")
    ap.add_argument("--stall-tid", help="TID[,TID]: also record these threads' switches and ticks with user stacks")
    a = ap.parse_args()

    touch = Touch(a.width, a.height)
    time.sleep(0.6)
    trace_start(a.stall_tid)
    time.sleep(0.3)
    rounds = []
    step = a.step_ms / 1000.0
    try:
        for i in range(a.rounds):
            sign = -1 if i % 2 == 0 else 1
            start = a.x if a.horizontal else a.y0
            if sign > 0:
                start -= a.dist
            n = max(2, int(a.fling_ms / 1000.0 / step))

            def at(d):
                return (start + d, a.y0) if a.horizontal else (a.x, start + d)

            t0 = touch.down(*at(0))
            down_rt = time.time()
            t0 += a.pre_ms / 1000.0
            sleep_until(t0)
            move_rt = None
            for k in range(1, n + 1):
                sleep_until(t0 + k * step)
                touch.move(*at(sign * a.dist * k / n))
                if move_rt is None:
                    move_rt = time.time()
            if a.hold_ms:
                sleep_until(t0 + n * step + a.hold_ms / 1000.0)
            t_up = touch.up()
            sleep_until(t_up + a.catch_ms / 1000.0)
            t_catch = time.monotonic()
            if a.catch_ms > 0:
                t_catch = touch.down(*at(sign * a.dist // 2))
                sleep_until(t_catch + 0.12)
                touch.up()
            sleep_until(t_catch + a.idle_ms / 1000.0)
            rounds.append({"down": t0, "up": t_up, "catch": t_catch, "end": time.monotonic(),
                           "down_rt": down_rt, "move_rt": move_rt})
    finally:
        text = trace_stop()
        touch.close()
    if a.raw:
        with open(a.raw, "w") as f:
            f.write(text)
    flips, submits = parse(text)
    res = analyse(rounds, flips, submits, 1.0 / a.hz)
    res["round_times"] = rounds
    res["gesture"] = {"dist_px": a.dist, "fling_ms": a.fling_ms, "catch_ms": a.catch_ms,
                      "rounds": a.rounds, "horizontal": a.horizontal,
                      "velocity_px_s": round(a.dist / (a.fling_ms / 1000.0))}
    out = json.dumps(res, indent=1)
    if a.out:
        with open(a.out, "w") as f:
            f.write(out)
    print(out)


if __name__ == "__main__":
    main()
