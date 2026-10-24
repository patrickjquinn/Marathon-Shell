#!/usr/bin/env python3
"""Turns a gate run's raw device output into metrics and a verdict.

usage: analyse.py GATE RAW_DIR OUT_DIR
Writes OUT_DIR/result.json and CSVs; the thresholds are the playbook's.
"""
import csv
import json
import re
import statistics
import sys
from collections import defaultdict
from pathlib import Path

TICK_HZ = 100
FRAME_GAP_IDLE = 0.25
TRACE_RE = re.compile(
    r"^\s*(?P<comm>.+?)-(?P<pid>\d+)\s+(?:\(\s*(?P<tgid>[\d-]+)\)\s+)?\[\d+\]\s+\S+\s+"
    r"(?P<ts>\d+\.\d+):\s+(?P<ev>\w+):\s?(?P<rest>.*)$")
SCHED_RE = re.compile(r"prev_pid=(\d+) .*prev_state=(\S+) ==> .*next_pid=(\d+)")
DBUS_HEAD_RE = re.compile(r"^(signal|method call|method return|error) time=(\d+\.\d+) (.*)$")


def pct(values, q):
    if not values:
        return None
    s = sorted(values)
    return s[min(len(s) - 1, int(round(q / 100 * (len(s) - 1))))]


def stats_ms(values):
    return {"n": len(values), "p50": pct(values, 50), "p95": pct(values, 95),
            "p99": pct(values, 99), "max": max(values) if values else None}


def read(raw, name):
    p = raw / name
    return p.read_text(errors="replace") if p.exists() else ""


def steps(raw):
    out = {"ok": 0, "skip": 0, "fail": 0, "list": []}
    for line in read(raw, "steps.tsv").splitlines():
        name, status, detail = (line.split("\t") + ["", ""])[:3]
        out[status] = out.get(status, 0) + 1
        out["list"].append({"step": name, "status": status, "detail": detail})
    return out


def wall_marks(raw):
    """label -> wall time, from marks.txt ("<wall> <label> begin|end")."""
    marks = {}
    for line in read(raw, "marks.txt").splitlines():
        t, label = line.split(" ", 1)
        marks[label] = float(t)
    return marks


def windows(marks):
    """name -> (begin, end) for every "<name> begin"/"<name> end" pair."""
    out = {}
    for label, t in marks.items():
        if label.endswith(" begin"):
            name = label[:-6]
            end = marks.get(name + " end")
            if end is not None:
                out[name] = (t, end)
    return out


class Trace:
    def __init__(self, raw):
        self.vblank, self.submits, self.sched, self.marks = [], [], [], {}
        for line in read(raw, "trace.txt").splitlines():
            m = TRACE_RE.match(line)
            if not m:
                continue
            ts, ev, rest = float(m["ts"]), m["ev"], m["rest"]
            if ev == "drm_vblank_event_delivered":
                self.vblank.append(ts)
            elif ev == "v3d_submit_cl_ioctl":
                tgid = m["tgid"] if m["tgid"] and m["tgid"] != "-" else m["pid"]
                self.submits.append((ts, int(tgid), m["comm"].strip()))
            elif ev == "sched_switch":
                s = SCHED_RE.search(rest)
                if s:
                    self.sched.append((ts, int(s[1]), s[2], int(s[3])))
            elif ev == "tracing_mark_write" and "GATE " in rest:
                self.marks[rest.split("GATE ", 1)[1].strip()] = ts
        self.windows = windows(self.marks)
        self.overrun = sum(int(x) for x in re.findall(r"overrun: (\d+)", read(raw, "trace-overrun.txt")))

    def frames(self, begin, end):
        """Composited frames and vblanks missed while the shell was animating
        (gaps under 250 ms); longer gaps are idle, not drops."""
        ts = [t for t in self.vblank if begin <= t <= end]
        gaps = [b - a for a, b in zip(ts, ts[1:])]
        short = [g for g in gaps if g < 0.025]
        period = statistics.median(short) if short else 1 / 60
        missed = sum(max(0, round(g / period) - 1) for g in gaps if g < FRAME_GAP_IDLE)
        animating = sum(g for g in gaps if g < FRAME_GAP_IDLE)
        return {"frames": len(ts), "missed": missed, "animating_s": round(animating, 3),
                "period_ms": round(period * 1000, 3),
                "longest_gap_ms": round(max([g for g in gaps if g < FRAME_GAP_IDLE], default=0) * 1000, 2)}

    def busy_spans(self, tid, begin, end):
        """How long the thread stayed runnable each time it woke, preemption
        included: the time the GUI thread could not take new work."""
        spans, start = [], None
        for ts, prev, state, nxt in self.sched:
            if nxt == tid and start is None:
                start = ts
            elif prev == tid and start is not None and not state.startswith("R"):
                if begin <= start <= end:
                    spans.append((ts - start) * 1000)
                start = None
        return spans

    def rates(self, begin, end):
        counts = defaultdict(int)
        names = {}
        for ts, tgid, comm in self.submits:
            if begin <= ts <= end:
                counts[tgid] += 1
                names.setdefault(tgid, comm)
        dur = max(end - begin, 1e-9)
        return {tgid: {"comm": names[tgid], "gpu_jobs_per_s": round(n / dur, 2)} for tgid, n in counts.items()}


def processes(raw, label):
    """pid -> {comm, cmdline, cgroup, gpu_ns} from an inventory; a DRM client
    open on several fds counts once."""
    procs = defaultdict(dict)
    client, engines = {}, defaultdict(dict)
    for line in read(raw, f"inventory-{label}.txt").splitlines():
        m = re.match(r"^/proc/(\d+)/(comm|cgroup|cmdline):(.*)$", line)
        if m:
            procs[int(m[1])][m[2]] = m[3].strip()
            continue
        m = re.match(r"^/proc/(\d+)/fdinfo/(\d+):drm-client-id:\s+(\d+)", line)
        if m:
            client[(m[1], m[2])] = m[3]
            continue
        m = re.match(r"^/proc/(\d+)/fdinfo/(\d+):drm-engine-(\w+):\s+(\d+) ns", line)
        if m:
            key = client.get((m[1], m[2]), f"fd{m[2]}")
            engines[int(m[1])][(key, m[3])] = int(m[4])
    for pid, by_engine in engines.items():
        procs[pid]["gpu_ns"] = sum(by_engine.values())
    return procs


def android_gpu_pct(raw, name, seconds):
    """GPU time of Android's processes over a window, as % of the GPU."""
    a, b = processes(raw, f"{name}-begin"), processes(raw, f"{name}-end")
    ns = sum(max(0, p.get("gpu_ns", 0) - a.get(pid, {}).get("gpu_ns", 0))
             for pid, p in b.items() if is_android(p) and pid in a)
    return round(ns / (seconds * 1e9) * 100, 3) if seconds else None


def is_android(proc):
    return "lxc.payload" in proc.get("cgroup", "")


def snapshot(raw, label):
    """pid -> (cpu ticks, run count) and the snapshot's wall time."""
    out, t = {}, None
    for line in read(raw, f"snapshot-{label}.txt").splitlines():
        if line.startswith("T "):
            t = float(line[2:])
            continue
        m = re.match(r"^/proc/(\d+)/(stat|schedstat):(.*)$", line)
        if not m:
            continue
        pid, kind, body = int(m[1]), m[2], m[3]
        cpu, runs = out.get(pid, (0, 0))
        if kind == "stat":
            fields = body[body.rfind(")") + 2:].split()
            cpu = int(fields[11]) + int(fields[12])
        else:
            runs = int(body.split()[2])
        out[pid] = (cpu, runs)
    return out, t


def per_process(raw, name):
    a, ta = snapshot(raw, f"{name}-begin")
    b, tb = snapshot(raw, f"{name}-end")
    if not a or not b:
        return None, []
    dur = tb - ta
    procs = processes(raw, f"{name}-end")
    rows = []
    for pid, (cpu, runs) in b.items():
        if pid not in a:
            continue
        p = procs.get(pid, {})
        rows.append({"pid": pid, "comm": p.get("comm", ""), "cmdline": p.get("cmdline", "")[:80],
                     "android": is_android(p),
                     "cpu_pct_core": round((cpu - a[pid][0]) / TICK_HZ / dur * 100, 3),
                     "wakeups_per_s": round((runs - a[pid][1]) / dur, 2)})
    return dur, rows


def samples(raw, label):
    """[(wall, {path: [lines]})] from a sample file."""
    out = []
    for line in read(raw, f"samples-{label}.txt").splitlines():
        if line.startswith("T "):
            out.append((float(line[2:]), defaultdict(list)))
        elif out and ":" in line:
            path, value = line.split(":", 1)
            out[-1][1][path].append(value)
    return out


def counters(sample):
    """Flattened counters of one sample."""
    c = {}
    for path, lines in sample.items():
        if path == "/proc/stat":
            f = [int(x) for x in lines[0].split()[1:]]
            c["cpu_busy"] = sum(f) - f[3] - f[4]
            c["cpu_all"] = sum(f)
        elif path.endswith("gpu_stats"):
            for ln in lines[1:]:
                q = ln.split()
                c[f"gpu_{q[0]}_ns"] = int(q[3])
        elif path.endswith("cpu.stat"):
            for ln in lines:
                k, v = ln.split()
                if k == "usage_usec":
                    c[f"cg:{path.rsplit('/', 1)[0]}"] = int(v)
        elif path.endswith("memory.events"):
            for ln in lines:
                k, v = ln.split()
                c[f"mem_{k}"] = int(v)
    return c


def window_counters(raw, label):
    s = samples(raw, label)
    if len(s) < 2:
        return None
    (t0, a), (t1, b) = s[0], s[-1]
    a, b = counters(a), counters(b)
    dur = t1 - t0
    d = {k: b[k] - a[k] for k in b if k in a}
    container = [k for k in d if k.startswith("cg:") and k.count("/") == 4]
    out = {"seconds": round(dur, 1),
           "system_cpu_pct": round(100 * d.get("cpu_busy", 0) / max(d.get("cpu_all", 1), 1), 3),
           "container_cpu_pct_core": round(sum(d[k] for k in container) / (dur * 1e6) * 100, 3),
           "gpu_render_pct": round(d.get("gpu_render_ns", 0) / (dur * 1e9) * 100, 3),
           "gpu_bin_pct": round(d.get("gpu_bin_ns", 0) / (dur * 1e9) * 100, 3),
           "gpu_tfu_pct": round(d.get("gpu_tfu_ns", 0) / (dur * 1e9) * 100, 3),
           "container_oom_kills": d.get("mem_oom_kill", 0),
           "container_high_events": d.get("mem_high", 0)}
    out["gpu_busy_pct"] = round(min(100.0, out["gpu_render_pct"] + out["gpu_bin_pct"] + out["gpu_tfu_pct"]), 3)
    out["per_android_uid_cpu_pct_core"] = {
        k.rsplit("/", 1)[1]: round(d[k] / (dur * 1e6) * 100, 3)
        for k in d if k.startswith("cg:") and k.count("/") == 5 and d[k] > 0}
    return out


def dbus(raw):
    msgs = []
    for line in read(raw, "dbus.txt").splitlines():
        m = DBUS_HEAD_RE.match(line)
        if m:
            f = dict(re.findall(r"(\w+)=([^ ;]+)", m[3]))
            f.update(kind=m[1], time=float(m[2]))
            msgs.append(f)
        elif msgs and line.strip().startswith("uint32 ") and "value" not in msgs[-1]:
            msgs[-1]["value"] = line.split()[1]
    return msgs


def ime(msgs, begin, end):
    """Keyboard event (CommitString or Key) to the editor's next state report,
    and the shell's answer time to that report."""
    keys = [m for m in msgs if m["kind"] == "signal" and m.get("member") in ("CommitString", "Key")
            and begin <= m["time"] <= end]
    reports = [m for m in msgs if m["kind"] == "method call" and m.get("member") == "SetSurroundingText"]
    returns = {(m.get("destination"), m.get("reply_serial")): m["time"] for m in msgs if m["kind"] == "method return"}
    rtt, lost = [], 0
    for i, k in enumerate(keys):
        limit = keys[i + 1]["time"] if i + 1 < len(keys) else k["time"] + 1.0
        nxt = next((r for r in reports if k["time"] < r["time"] <= min(limit, k["time"] + 1.0)), None)
        if nxt is None:
            lost += 1
        else:
            rtt.append((nxt["time"] - k["time"]) * 1000)
    answer = [(returns[(r.get("sender"), r.get("serial"))] - r["time"]) * 1000
              for r in reports if begin <= r["time"] <= end and (r.get("sender"), r.get("serial")) in returns]
    return {"round_trip_ms": stats_ms(rtt), "lost": lost, "keys": len(keys),
            "shell_answer_ms": stats_ms(answer)}, rtt


def write_csv(path, rows):
    if not rows:
        return
    keys = list(dict.fromkeys(k for r in rows for k in r))
    with open(path, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=keys)
        w.writeheader()
        w.writerows(rows)


def gui_tids(raw):
    m = re.search(r"gui=(\d*) render=(\d*)", read(raw, "threads.txt"))
    return (int(m[1]) if m and m[1] else None, int(m[2]) if m and m[2] else None)


def gate1(raw, out):
    msgs, tr, wm = dbus(raw), Trace(raw), windows(wall_marks(raw))
    res, rows = {}, []
    for name in ("keys-baseline", "keys-pressure", "keys-images"):
        if name in wm:
            res[name], rtt = ime(msgs, *wm[name])
            rows += [{"window": name, "round_trip_ms": round(x, 3)} for x in rtt]
    write_csv(out / "ime_rtt.csv", rows)
    frame_rows = []
    for name in ("drag-baseline", "drag-pressure", "drag-images"):
        if name in tr.windows:
            f = tr.frames(*tr.windows[name])
            f["missed_per_animating_s"] = round(f["missed"] / f["animating_s"], 3) if f["animating_s"] else None
            res[name] = f
            frame_rows.append({"window": name, **f})
    bursts = [n for n in tr.windows if n.startswith("burst-")]
    for n in sorted(bursts):
        b, e = tr.windows[n]
        f = tr.frames(b, e + 1.0)
        res[n] = f
        frame_rows.append({"window": n, **f})
    write_csv(out / "frames.csv", frame_rows)
    notify = [m for m in msgs if m["kind"] == "method call" and m.get("member") == "Notify"]
    res["notify_calls"] = len(notify)
    for label in ("keys", "drag"):
        replies = [float(line.split()[2]) for line in read(raw, f"images-{label}.txt").splitlines()]
        res[f"images-{label}_notify_reply_ms"] = stats_ms(replies)
        rss = [int(x) for x in read(raw, f"images-{label}-rss.txt").split() if x.isdigit()]
        if rss:
            res[f"images-{label}_shell_rss_growth_kb"] = max(rss) - rss[0]
    base = res.get("drag-baseline", {}).get("missed_per_animating_s") or 0

    def excess(f):
        return f["missed"] - base * f["animating_s"]
    burst_excess = [excess(res[n]) for n in bursts if n in ("burst-3", "burst-4")]
    if "drag-images" in res:
        burst_excess.append(excess(res["drag-images"]))
    p99_base = (res.get("keys-baseline", {}).get("round_trip_ms") or {}).get("p99")
    literal, measured = [], []
    for name in ("keys-pressure", "keys-images"):
        w = res.get(name, {})
        p99 = (w.get("round_trip_ms") or {}).get("p99")
        if p99 is not None and p99 > 8:
            literal.append(f"{name}: keyboard round trip p99 {p99:.1f} ms > 8 ms")
        if p99 is not None and p99_base is not None:
            w["load_induced_p99_ms"] = round(p99 - p99_base, 3)
            if p99 - p99_base > 8:
                measured.append(f"{name}: load adds {p99 - p99_base:.1f} ms to the keyboard round trip p99")
        answer = (w.get("shell_answer_ms") or {}).get("p99")
        if answer is not None and answer > 8:
            measured.append(f"{name}: the Shell answers the editor's report in {answer:.1f} ms p99 > 8 ms")
        if w.get("keys") and w["lost"] > w["keys"] / 100:
            measured.append(f"{name}: {w['lost']} of {w['keys']} keystrokes got no editor report within 1 s")
    if burst_excess and max(burst_excess) > 1:
        measured.append(f"{max(burst_excess):.1f} frames dropped beyond baseline under a burst")
    if p99_base is not None and p99_base > 8:
        literal.append(f"note: baseline p99 {p99_base:.1f} ms already > 8 ms, so not load-induced")
    pressure = res.get("keys-pressure", {}).get("round_trip_ms") or {}
    drawn = res.get("drag-baseline", {}).get("frames", 0) > 0
    enough = (pressure.get("n") or 0) >= 50 and bool(burst_excess) and drawn
    if not drawn:
        measured.append("note: no vblank events in drag-baseline: the frame trace did not work")
    decision = verdict(literal + [r for r in measured if r not in literal], enough)
    decision["measured_verdict"] = verdict(measured, enough)["verdict"]
    return res, decision


def gate2(raw, out):
    res, rows = {}, []
    for name in ("idle-baseline", "hidden-screen-on", "hidden-screen-off"):
        w = window_counters(raw, name)
        if w is None:
            continue
        dur, procs = per_process(raw, name)
        android = [p for p in procs if p["android"]]
        w["android_cpu_pct_core"] = round(sum(p["cpu_pct_core"] for p in android), 3)
        w["android_gpu_pct"] = android_gpu_pct(raw, name, dur)
        w["android_wakeups_per_s"] = round(sum(p["wakeups_per_s"] for p in android), 2)
        w["top_android"] = sorted(android, key=lambda p: -p["cpu_pct_core"])[:8]
        res[name] = w
        rows += [{"window": name, **p} for p in procs if p["cpu_pct_core"] > 0 or p["wakeups_per_s"] > 1]
    write_csv(out / "processes.csv", rows)
    kills = read(raw, "kills.txt")
    res["kills_raw"] = kills.splitlines()[-8:]
    res["use_freezer"] = read(raw, "use-freezer.txt").strip() or None
    idle = res.get("idle-baseline", {}).get("container_cpu_pct_core")
    literal, reasons = [], []
    for name in ("hidden-screen-on", "hidden-screen-off"):
        w = res.get(name)
        if not w:
            continue
        if w["container_cpu_pct_core"] > 2:
            literal.append(f"{name}: Android uses {w['container_cpu_pct_core']:.2f} % of a core > 2 %")
        if idle is not None:
            w["hidden_apps_cpu_pct_core"] = round(w["container_cpu_pct_core"] - idle, 3)
            if w["hidden_apps_cpu_pct_core"] > 2:
                reasons.append(f"{name}: hidden apps add {w['hidden_apps_cpu_pct_core']:.2f} % of a core "
                               "over Android idle > 2 %")
        if w["container_cpu_pct_core"] >= 1:
            reasons.append(f"note: {name}: Android at {w['container_cpu_pct_core']:.2f} % of a core, "
                           "above DEFER's 1 %")
        if (w["android_gpu_pct"] or 0) > 5:
            reasons.append(f"{name}: Android's processes keep the GPU {w['android_gpu_pct']:.1f} % busy > 5 %")
        if w["gpu_busy_pct"] > 5:
            literal.append(f"{name}: GPU {w['gpu_busy_pct']:.1f} % busy > 5 %, shell included")
        if w["container_oom_kills"]:
            reasons.append(f"{name}: {w['container_oom_kills']} OOM kills")
    enough = "hidden-screen-on" in res and idle is not None
    measured = verdict(list(reasons), enough)
    if res["use_freezer"] == "false":
        literal.append("playbook: Android's cached-app freezer is off (use_freezer=false)")
    literal = verdict(literal + reasons, enough)
    literal["measured_verdict"] = measured["verdict"]
    return res, literal


def gate3(raw, out):
    tr, res, rows = Trace(raw), {}, []
    video = (read(raw, "apps.txt").split() or [""])[-1]
    for name in ("static-switcher", "video-switcher", "video-home"):
        if name not in tr.windows:
            continue
        b, e = tr.windows[name]
        procs = processes(raw, f"{name}-end")
        rates = tr.rates(b, e)
        android = {t: r for t, r in rates.items() if is_android(procs.get(t, {}))}
        for t, r in rates.items():
            rows.append({"window": name, "tgid": t, "android": t in android,
                         "cmdline": procs.get(t, {}).get("cmdline", "")[:60], **r})
        f = tr.frames(b, e)
        sf = layer_fps(read(raw, f"sf-latency-{name}.txt"), b, e)
        res[name] = {"compositor_fps": round(f["frames"] / (e - b), 2),
                     "android_max_gpu_jobs_per_s": max((r["gpu_jobs_per_s"] for r in android.values()), default=0),
                     "android_clients": len(android), "surfaceflinger_fps": sf,
                     "hidden_task_max_fps": max(sf.values(), default=0), **f}
    write_csv(out / "render_rates.csv", rows)
    reasons = []
    for name in ("video-switcher", "video-home"):
        w = res.get(name)
        if w and w["hidden_task_max_fps"] >= 30:
            reasons.append(f"{name}: a hidden Android task renders at {w['hidden_task_max_fps']:.0f} fps >= 30")
    if res.get("video-home", {}).get("compositor_fps", 0) > 5:
        reasons.append(f"video-home: the shell composites {res['video-home']['compositor_fps']} fps for a hidden client")
    seen = any(video and video in layer for layer in res.get("video-switcher", {}).get("surfaceflinger_fps", {}))
    if not seen:
        reasons.append(f"note: no SurfaceFlinger frame record for {video or 'the video app'}")
    return res, verdict(reasons, seen)


def layer_fps(text, begin, end):
    """Each layer's presented frames per second in [begin, end]. SurfaceFlinger
    keeps a layer's last 128 frames, so a full record covers only its span."""
    out, layer, frames = {}, None, []

    def flush():
        if not layer:
            return
        inside = [t / 1e9 for t in frames if begin * 1e9 <= t <= end * 1e9]
        start = min(frames) / 1e9 if len(frames) >= 120 and min(frames) > begin * 1e9 else begin
        out[layer] = round(len(inside) / max(end - start, 1e-3), 2)
    for line in text.splitlines():
        if line.startswith("L "):
            flush()
            layer, frames = line[2:], []
            continue
        f = line.split()
        if len(f) == 3 and all(x.isdigit() for x in f):
            t = next((int(x) for x in (f[1], f[0]) if 0 < int(x) < 2**62), None)
            if t is not None:
                frames.append(t)
    flush()
    return out


def gate4(raw, out):
    tr = Trace(raw)
    gui, render = gui_tids(raw)
    rows = []
    for name, (b, e) in sorted(tr.windows.items()):
        if not name.startswith("peek-"):
            continue
        f = tr.frames(b, e + 0.3)
        spans = tr.busy_spans(gui, b, e + 0.3) if gui else []
        rspans = tr.busy_spans(render, b, e + 0.3) if render else []
        rows.append({"window": name, "kind": "launch" if "launch" in name else "baseline",
                     "gui_spans_over_16ms": sum(1 for s in spans if s > 16),
                     "gui_longest_ms": round(max(spans, default=0), 2),
                     "render_spans_over_16ms": sum(1 for s in rspans if s > 16),
                     "render_longest_ms": round(max(rspans, default=0), 2), **f})
    write_csv(out / "peeks.csv", rows)
    res = {}
    for kind in ("baseline", "launch"):
        r = [x for x in rows if x["kind"] == kind]
        if r:
            res[kind] = {"reps": len(r), "missed_mean": round(statistics.mean(x["missed"] for x in r), 2),
                         "frames_mean": round(statistics.mean(x["frames"] for x in r), 1),
                         "reps_with_gui_stall": sum(1 for x in r if x["gui_spans_over_16ms"]),
                         "reps_with_render_stall": sum(1 for x in r if x["render_spans_over_16ms"]),
                         "gui_longest_ms": max(x["gui_longest_ms"] for x in r),
                         "render_longest_ms": max(x["render_longest_ms"] for x in r),
                         "longest_gap_ms": max(x["longest_gap_ms"] for x in r)}
    literal, measured = [], []
    b, l = res.get("baseline"), res.get("launch")
    if l and l["reps_with_gui_stall"]:
        literal.append(f"GUI thread busy > 16 ms in {l['reps_with_gui_stall']}/{l['reps']} launch peeks")
    if b and l:
        for thread in ("gui", "render"):
            if l[f"reps_with_{thread}_stall"] > b[f"reps_with_{thread}_stall"]:
                measured.append(f"{thread} thread busy > 16 ms in {l[f'reps_with_{thread}_stall']}/{l['reps']} "
                                f"launch peeks (baseline {b[f'reps_with_{thread}_stall']}/{b['reps']})")
        if l["missed_mean"] > b["missed_mean"] + 1:
            measured.append(f"peek misses {l['missed_mean']} vblanks per launch vs {b['missed_mean']} alone")
    res["sched_events"] = len(tr.sched)
    drawn = bool(b and b["frames_mean"] > 0)
    if not drawn:
        measured.append("note: no vblank events in the baseline peeks: the frame trace did not work")
    enough = bool(b and l and tr.sched) and drawn
    decision = verdict(literal + [r for r in measured if r not in literal], enough)
    decision["measured_verdict"] = verdict(measured, enough)["verdict"]
    return res, decision


def gate5(raw, out):
    res, cur = {}, None
    for line in read(raw, "footprint.txt").splitlines():
        k, v = line.split(" ", 1)
        if k == "label":
            cur = res.setdefault(v, {})
        elif cur is not None:
            cur[k] = int(v) if v.isdigit() else v
    rows = []
    for label, r in res.items():
        runs = {}
        for edge in ("begin", "end"):
            for line in read(raw, f"threads-{label}-{edge}.txt").splitlines():
                tid, count, comm = line.split(" ", 2)
                runs.setdefault(tid, {"comm": comm})[edge] = int(count)
        seconds = r.get("seconds") or 1
        woke = [{"label": label, "tid": t, "comm": v["comm"], "wakeups_per_s": round((v["end"] - v["begin"]) / seconds, 2)}
                for t, v in runs.items() if "begin" in v and "end" in v]
        r["wakeups_per_s"] = round(sum(w["wakeups_per_s"] for w in woke), 2)
        r["threads_waking"] = sum(1 for w in woke if w["wakeups_per_s"] > 0)
        rows += woke
    write_csv(out / "threads.csv", rows)
    write_csv(out / "footprint.csv", [{"label": k, **v} for k, v in res.items()])
    return res, {"verdict": "RECORD", "reasons": ["release-gate record: compare against the next bridge build"]}


def load_probe(raw):
    return dict(line.split("=", 1) for line in read(raw, "probe.txt").splitlines() if "=" in line)


def probe(raw, out):
    p = load_probe(raw)
    reasons = []
    if p.get("android.use_freezer") == "false":
        reasons.append("Android freezer off: " + p.get("android.freezer_log", ""))
    if p.get("manifest.commit") in (None, "none"):
        reasons.append("installed Deckard files carry no build manifest")
    if p.get("overlay.differing", "0") not in ("0", ""):
        reasons.append(f"{p['overlay.differing']} live overlay files differ from the packaged ones")
    return p, {"verdict": "FACTS", "reasons": reasons}


def verdict(reasons, enough):
    real = [r for r in reasons if not r.startswith("note:")]
    if real:
        return {"verdict": "PROCEED", "reasons": reasons}
    return {"verdict": "DEFER" if enough else "INCONCLUSIVE", "reasons": reasons or ["no threshold crossed"]}


GATES = {"probe": probe, "g1": gate1, "g2": gate2, "g3": gate3, "g4": gate4, "g5": gate5}


def main():
    gate, raw, out = sys.argv[1], Path(sys.argv[2]), Path(sys.argv[3])
    out.mkdir(parents=True, exist_ok=True)
    metrics, decision = GATES[gate](raw, out)
    st = steps(raw)
    if st["fail"] and decision["verdict"] in ("DEFER", "PROCEED"):
        decision["reasons"].append(f"{st['fail']} failed steps: check before trusting this verdict")
    result = {"gate": gate, "steps": st, "metrics": metrics, **decision}
    if Path(raw / "trace.txt").exists():
        result["trace_overrun_events"] = Trace(raw).overrun
    (out / "result.json").write_text(json.dumps(result, indent=2, default=str))
    print(json.dumps({"gate": gate, "verdict": result["verdict"], "steps": {k: st[k] for k in ("ok", "skip", "fail")},
                      "reasons": result["reasons"]}))


if __name__ == "__main__":
    main()
