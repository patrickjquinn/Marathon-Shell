#!/usr/bin/env python3
"""power-audit.py [SECONDS] [--max-cpu PCT] [--max-process PCT] [--max-wakeups N] [--max-log N]

Runs on a phone (python3, no other dependencies) and says where its power
goes over SECONDS (default 30): the CPU's busy share and how deep it slept,
the processes that used the CPU or woke it, the interrupts, and how fast the
journal grew (a service retrying in a loop shows there first). With limits
it is a regression test: it exits 1 when the whole system's CPU use, any one
process's, the wakeups or the log lines a second go over them.
scripts/power-regression runs it in each state with its budget.

    ssh root@phone python3 - 60 --max-cpu 5 < scripts/power-audit.py

Take it with the screen off and, for an idle budget, nothing playing: the
screen state is reported, since a lit screen costs the compositor work.
"""
import glob
import os
import subprocess
import sys
import time

HZ = os.sysconf("SC_CLK_TCK")


def read(path, default=""):
    try:
        with open(path) as f:
            return f.read()
    except OSError:
        return default


def processes():
    """{pid: (name, cpu ticks, context switches)} for every process."""
    out = {}
    for d in glob.glob("/proc/[0-9]*"):
        stat = read(d + "/stat")
        if not stat:
            continue
        name = stat[stat.index("(") + 1:stat.rindex(")")]
        fields = stat.rsplit(")", 1)[1].split()
        switches = 0
        for line in read(d + "/status").splitlines():
            if line.startswith(("voluntary_ctxt_switches", "nonvoluntary_ctxt_switches")):
                switches += int(line.split()[1])
        out[int(d[6:])] = (name, int(fields[11]) + int(fields[12]), switches)
    return out


def cpu_times():
    """(busy, total) jiffies over all CPUs."""
    fields = [int(x) for x in read("/proc/stat").splitlines()[0].split()[1:]]
    idle = fields[3] + fields[4]
    return sum(fields) - idle, sum(fields)


def idle_states():
    """{state name: microseconds} summed over CPUs."""
    out = {}
    for d in glob.glob("/sys/devices/system/cpu/cpu[0-9]*/cpuidle/state[0-9]*"):
        name = read(d + "/name").strip()
        out[name] = out.get(name, 0) + int(read(d + "/time", "0") or 0)
    return out


def interrupts():
    out = {}
    for line in read("/proc/interrupts").splitlines()[1:]:
        parts = line.split()
        if not parts:
            continue
        counts = []
        for p in parts[1:]:
            if p.isdigit():
                counts.append(int(p))
            else:
                break
        label = " ".join(parts[1 + len(counts):]) or parts[0]
        out[parts[0].rstrip(":") + " " + label[-40:]] = sum(counts)
    return out


def log_lines(start, end):
    try:
        out = subprocess.run(
            ["journalctl", "-q", "-o", "cat", f"--since=@{start:.0f}", f"--until=@{end:.0f}"],
            capture_output=True, text=True, timeout=60, check=False).stdout
    except (OSError, subprocess.TimeoutExpired):
        return None
    return out.count("\n")


def screen():
    # The CRTC is the truth: the shell's idle timer switches it off and
    # leaves the backlight's bl_power at 0. debugfs is root-only.
    states = [read(p) for p in glob.glob("/sys/kernel/debug/dri/*/state")]
    if any(states):
        return "on" if any("\tactive=1" in s for s in states) else "off"
    powers = [read(p).strip() for p in glob.glob("/sys/class/backlight/*/bl_power")]
    return "off" if powers and all(p not in ("", "0") for p in powers) else "on"


def main(argv):
    seconds, limits, args = 30.0, {}, list(argv)
    while args:
        a = args.pop(0)
        if a.startswith("--max-"):
            limits[a[6:]] = float(args.pop(0))
        else:
            seconds = float(a)
    t0 = time.time()
    p0, c0, i0, q0 = processes(), cpu_times(), idle_states(), interrupts()
    time.sleep(seconds)
    p1, c1, i1, q1 = processes(), cpu_times(), idle_states(), interrupts()
    lines = log_lines(t0, time.time())
    logs = None if lines is None else lines / seconds
    ncpu = os.cpu_count() or 1
    busy = 100.0 * (c1[0] - c0[0]) / max(1, c1[1] - c0[1]) * ncpu

    rows = []
    for pid, (name, ticks, sw) in p1.items():
        if pid in p0 and p0[pid][0] == name:
            cpu = 100.0 * (ticks - p0[pid][1]) / HZ / seconds
            wakes = (sw - p0[pid][2]) / seconds
            if cpu >= 0.05 or wakes >= 1:
                rows.append((cpu, wakes, name, pid))
    rows.sort(reverse=True)
    wakeups = sum(r[1] for r in rows)

    print(f"power audit: {seconds:.0f} s, screen {screen()}, {ncpu} CPUs")
    gpu = [f"{read(f).strip()}" for f in glob.glob("/sys/class/devfreq/*gpu*/cur_freq")]
    if gpu:
        print(f"GPU clock {int(gpu[0]) // 1_000_000} MHz")
    print(f"CPU busy: {busy:.1f}% of one core (all CPUs together)")
    total_idle = sum(i1.values()) - sum(i0.values())
    if total_idle > 0:
        deep = ", ".join(f"{k} {100.0 * (i1[k] - i0.get(k, 0)) / total_idle:.0f}%" for k in i1)
        print(f"idle time by state: {deep}")
    print(f"process wakeups: {wakeups:.0f}/s")
    if logs is not None:
        print(f"journal: {logs:.1f} lines/s")
    print("\nbusiest processes (CPU of one core, wakeups a second):")
    for cpu, wakes, name, pid in rows[:15]:
        print(f"  {cpu:5.1f}%  {wakes:6.0f}/s  {name} [{pid}]")
    irq = sorted(((q1[k] - q0.get(k, 0)) / seconds, k) for k in q1)
    print("\nnoisiest interrupts (a second):")
    for rate, k in reversed(irq[-8:]):
        if rate >= 0.5:
            print(f"  {rate:7.1f}  {k}")

    failed = []
    if "cpu" in limits and busy > limits["cpu"]:
        failed.append(f"CPU busy {busy:.1f}% > {limits['cpu']}%")
    if "process" in limits and rows and rows[0][0] > limits["process"]:
        failed.append(f"{rows[0][2]} {rows[0][0]:.1f}% > {limits['process']}%")
    if "wakeups" in limits and wakeups > limits["wakeups"]:
        failed.append(f"wakeups {wakeups:.0f}/s > {limits['wakeups']:.0f}/s")
    if "log" in limits and logs is not None and logs > limits["log"]:
        failed.append(f"journal {logs:.1f} lines/s > {limits['log']:.1f}/s")
    for f in failed:
        print("OVER BUDGET:", f)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
