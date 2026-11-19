#!/usr/bin/env python3
"""UI bench: what the shell and apps cost the GPU and CPU in everyday states.

Runs on the device as root, stdlib only. Each scenario is driven through the
real touchscreen and the shell's D-Bus, and measured from the kernel side:
  drm_vblank_event_delivered          each page flip
  gpu_scheduler:drm_sched_job_run/done every GPU job, its ring and DRM client
plus /proc/<pid>/fdinfo (DRM client ids, GPU memory) and /proc/<pid>/stat.

Per scenario and process it reports frames, GPU ms per frame (run->done of
every job), fragment jobs per frame (render passes: each layer, effect or
offscreen buffer adds one), GPU busy %, CPU ms per second, missed vblanks.

usage: ui_bench.py [--touch /dev/input/event3] [--scale 3.466]
                   [--only NAME[,NAME]] [--out FILE.json]
--scale maps panel pixels to touchscreen units (Q25: 2492/719).
"""
import argparse
import json
import os
import re
import struct
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import scroll_bench as sb  # noqa: E402

EVENTS = ["drm/drm_vblank_event_delivered", "gpu_scheduler/drm_sched_job_run",
          "gpu_scheduler/drm_sched_job_done"]
RUN = re.compile(r"fence=(\d+:\d+), ring=([\w-]+).*client_id:(\d+)")
DONE = re.compile(r"fence=(\d+:\d+) signaled")
EV_SYN, EV_KEY, EV_ABS = 0, 1, 3


class Panel:
    """Finger on the real touchscreen, multitouch protocol B."""

    def __init__(self, dev, scale):
        self.f = open(dev, "wb", buffering=0)
        self.scale = scale
        self.tid = int(time.time()) % 60000

    def _ev(self, t, c, v):
        self.f.write(struct.pack("llHHi", 0, 0, t, c, v))

    def _at(self, x, y):
        x, y = round(x * self.scale), round(y * self.scale)
        self._ev(EV_ABS, 0x35, x)
        self._ev(EV_ABS, 0x36, y)
        self._ev(EV_ABS, 0x00, x)
        self._ev(EV_ABS, 0x01, y)

    def drag(self, x1, y1, x2, y2, ms, hold=0.05):
        steps = max(2, int(ms / 10))
        self.tid += 1
        for i in range(steps + 1):
            if i == 0:
                self._ev(EV_ABS, 0x2F, 0)
                self._ev(EV_ABS, 0x39, self.tid)
            self._at(x1 + (x2 - x1) * i / steps, y1 + (y2 - y1) * i / steps)
            if i == 0:
                self._ev(EV_KEY, 0x14A, 1)
                self._ev(EV_KEY, 0x145, 1)
            self._ev(EV_SYN, 0, 0)
            time.sleep(ms / 1000.0 / steps)
        time.sleep(hold)
        self._ev(EV_ABS, 0x39, -1)
        self._ev(EV_KEY, 0x14A, 0)
        self._ev(EV_KEY, 0x145, 0)
        self._ev(EV_SYN, 0, 0)


def shell(method, *args):
    uid = subprocess.run(["id", "-u", "user"], capture_output=True, text=True).stdout.strip()
    cmd = ("DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/%s/bus busctl --user call "
           "org.marathonos.Shell /org/marathonos/Shell/Navigation "
           "org.marathonos.Shell.Navigation1 %s %s" % (uid, method, " ".join(args)))
    subprocess.run(["su", "user", "-s", "/bin/sh", "-c", cmd], capture_output=True)


def wake():
    if os.path.exists("/root/wake.sh"):
        subprocess.run(["/root/wake.sh"], capture_output=True)


def start_time(pid):
    try:
        with open("/proc/%d/stat" % pid) as f:
            return int(f.read().rsplit(")", 1)[1].split()[19])
    except OSError:
        return 1 << 62


def drm_clients():
    """DRM client id -> (pid, name, total memory KiB). A child that inherited
    the descriptor shows the same client id; the oldest holder opened it."""
    out = {}
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        base = "/proc/%s/fdinfo" % pid
        try:
            fds = os.listdir(base)
        except OSError:
            continue
        for fd in fds:
            try:
                with open(os.path.join(base, fd)) as f:
                    text = f.read()
            except OSError:
                continue
            m = re.search(r"drm-client-id:\s+(\d+)", text)
            if not m:
                continue
            mem = re.search(r"drm-total-memory:\s+(\d+)", text)
            client, pid = int(m.group(1)), int(pid)
            if client in out and start_time(out[client][0]) <= start_time(pid):
                continue
            out[client] = (pid, sb.comm(pid), int(mem.group(1)) if mem else 0)
    return out


def cpu_ticks(pid):
    try:
        with open("/proc/%d/stat" % pid) as f:
            st = f.read().rsplit(")", 1)[1].split()
        return int(st[11]) + int(st[12])
    except OSError:
        return None


def parse(text):
    flips, runs, done = [], {}, {}
    for line in text.splitlines():
        m = sb.LINE.match(line)
        if not m:
            continue
        ts, ev, rest = float(m.group(4)), m.group(5), m.group(6)
        if ev == "drm_vblank_event_delivered":
            flips.append(ts)
        elif ev == "drm_sched_job_run":
            r = RUN.search(rest)
            if r:
                runs[r.group(1)] = (ts, r.group(2), int(r.group(3)))
        elif ev == "drm_sched_job_done":
            d = DONE.search(rest)
            if d:
                done[d.group(1)] = ts
    jobs = []
    for fence, (t0, ring, client) in runs.items():
        if fence in done:
            jobs.append((t0, done[fence], ring, client))
    return flips, sorted(jobs)


def measure(name, body, clients_before):
    pids = {c: v[0] for c, v in clients_before.items()}
    cpu0 = {p: cpu_ticks(p) for p in pids.values()}
    t0 = time.monotonic()
    sb.trace_start()
    body()
    text = sb.trace_stop()
    secs = time.monotonic() - t0
    hz = os.sysconf("SC_CLK_TCK")
    flips, jobs = parse(text)
    d = [b - a for a, b in zip(flips, flips[1:])]
    period = sb.pct(d, 5) or 1 / 60.0
    clients = drm_clients()
    procs = {}
    for client in sorted({j[3] for j in jobs}):
        mine = [j for j in jobs if j[3] == client]
        frag = [j for j in mine if j[2] == "fragment"]
        gpu = sum(b - a for a, b, _, _ in mine)
        # a frame is the run of jobs between two vblanks
        frames = {}
        for a, _, ring, _ in frag:
            frames.setdefault(sum(1 for f in flips if f <= a), 0)
            frames[sum(1 for f in flips if f <= a)] += 1
        pid, pname, mem = clients.get(client) or clients_before.get(client) or (0, "?", 0)
        c0, c1 = cpu0.get(pid), cpu_ticks(pid) if pid else None
        procs["%s[%d]" % (pname, client)] = {
            "frames": len(frames),
            "gpu_ms_per_frame": round(gpu * 1000 / max(1, len(frames)), 2),
            "render_passes_per_frame": round(len(frag) / max(1, len(frames)), 2),
            "gpu_busy_pct": round(100 * gpu / secs, 1),
            "cpu_ms_per_s": None if c0 is None or c1 is None else round((c1 - c0) * 1000 / hz / secs, 1),
            "gpu_mem_mib": round(mem / 1024, 1),
        }
    # gaps of 100 ms or more are the UI resting between gestures
    moving = [x for x in d if x < 0.1]
    # a hitch: a late frame with smooth frames on both sides, mid-animation
    smooth = 1.5 * period
    hitches = [d[i] for i in range(1, len(d) - 1)
               if d[i] > smooth and d[i - 1] <= smooth and d[i + 1] <= smooth]
    return {
        "seconds": round(secs, 2),
        "vblank_ms": round(period * 1000, 2),
        "flips": len(flips),
        "flip_p99_ms": sb.ms(sb.pct(moving, 99)),
        "missed_vblanks": int(sum(max(0, round(x / period) - 1) for x in moving)),
        "hitches": len(hitches),
        "worst_hitch_ms": sb.ms(max(hitches) if hitches else None),
        "procs": procs,
    }


def scenarios(p):
    W = 720

    def idle_home():
        time.sleep(4)

    def home_pages():
        for i in range(4):
            if i % 2 == 0:
                p.drag(600, 400, 120, 400, 180)
            else:
                p.drag(120, 400, 600, 400, 180)
            time.sleep(1.2)

    def app_open_close():
        for _ in range(4):
            shell("LaunchApp", "s", "settings")
            time.sleep(2.0)
            shell("CloseApp", "s", "settings")
            time.sleep(1.5)

    def settings_fling():
        for i in range(6):
            if i % 2 == 0:
                p.drag(W / 2, 560, W / 2, 160, 120, 0)
            else:
                p.drag(W / 2, 160, W / 2, 560, 120, 0)
            time.sleep(1.2)

    def quick_settings():
        for _ in range(3):
            shell("ShowQuickSettings")
            time.sleep(2.0)
            shell("HideQuickSettings")
            time.sleep(1.0)

    def quick_settings_over_app():
        quick_settings()

    return [
        ("idle_home", None, idle_home),
        ("home_pages", None, home_pages),
        ("app_open_close", None, app_open_close),
        ("settings_fling", ("settings", 2.5), settings_fling),
        ("quick_settings", None, quick_settings),
        ("quick_settings_over_app", ("settings", 2.5), quick_settings_over_app),
    ]


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--touch", default="/dev/input/event3")
    ap.add_argument("--scale", type=float, default=2492 / 719)
    ap.add_argument("--only")
    ap.add_argument("--out")
    a = ap.parse_args()
    prof = [os.path.join(r, "profiling") for r, _, fs in os.walk("/sys/bus/platform/drivers/panfrost")
            if "profiling" in fs][:1]
    if prof:
        with open(prof[0]) as f:
            was = f.read().strip()
        with open(prof[0], "w") as f:
            f.write("1")
    p = Panel(a.touch, a.scale)
    sb.EVENTS[:] = EVENTS
    results = {}
    try:
        for name, app, body in scenarios(p):
            if a.only and name not in a.only.split(","):
                continue
            wake()
            shell("HideQuickSettings")
            if app:
                shell("LaunchApp", "s", app[0])
                time.sleep(app[1])
            results[name] = measure(name, body, drm_clients())
            if app:
                shell("CloseApp", "s", app[0])
                time.sleep(1.5)
            print(name, json.dumps(results[name]), flush=True)
    finally:
        if prof:
            with open(prof[0], "w") as f:
                f.write(was)
    if a.out:
        with open(a.out, "w") as f:
            json.dump(results, f, indent=1)


if __name__ == "__main__":
    main()
