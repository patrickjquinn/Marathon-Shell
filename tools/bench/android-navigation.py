#!/usr/bin/env python3
"""Measure five feed swipes with the Android app already visible.

Run as root on the 720x720 device. This sends touch input; it does not launch,
sign in, or change Android settings. Android gfxinfo is separate from the
compositor's presentation trace; collect both for end-to-end investigations.
"""

import argparse
import json
from pathlib import Path
import subprocess
import time


def android(*arguments):
    return subprocess.check_output(
        ["timeout", "20", "lxc-attach", "-P", "/var/lib/deckard/lxc",
         "-n", "deckard", "--clear-env", "--", *arguments],
        text=True, stderr=subprocess.STDOUT,
    )


def sample(package):
    processes = {}
    for path in Path("/proc").iterdir():
        if not path.name.isdecimal():
            continue
        try:
            name = (path / "cmdline").read_bytes().split(b"\0")[0].decode(errors="replace")
            if name not in (package, "system_server"):
                continue
            fields = (path / "stat").read_text().split(") ", 1)[1].split()
            io = dict(line.split(": ") for line in (path / "io").read_text().splitlines())
            processes[path.name] = {
                "name": name,
                "minor_faults": int(fields[7]),
                "major_faults": int(fields[9]),
                "cpu_ticks": int(fields[11]) + int(fields[12]),
                **{key: int(value) for key, value in io.items()},
            }
        except (FileNotFoundError, ProcessLookupError):
            pass
    vm = dict(line.split() for line in Path("/proc/vmstat").read_text().splitlines())
    return {
        "time": time.monotonic(),
        "processes": processes,
        "vm": {key: int(vm[key]) for key in ("pswpin", "pswpout", "pgmajfault")},
        "pressure": {
            name: Path("/proc/pressure", name).read_text()
            for name in ("io", "memory", "cpu")
        },
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--package", default="com.zhiliaoapp.musically")
    parser.add_argument("--output", default="/run/android-navigation")
    args = parser.parse_args()
    before = sample(args.package)
    if not any(proc["name"] == args.package for proc in before["processes"].values()):
        raise SystemExit(f"{args.package} is not running; open it before measuring")
    android("/system/bin/dumpsys", "gfxinfo", args.package, "reset")
    before = sample(args.package)
    subprocess.run(
        ["marathon-touchctl", "-"],
        input="swipe 360 530 360 190 24\nsleep 1500\n" * 5,
        text=True, capture_output=True, timeout=30, check=True,
    )
    after = sample(args.package)
    Path(args.output + ".json").write_text(
        json.dumps({"before": before, "after": after}, indent=2) + "\n"
    )
    gfx = android("/system/bin/dumpsys", "gfxinfo", args.package, "framestats")
    Path(args.output + "-gfx.txt").write_text(gfx)
    for line in gfx.splitlines():
        if any(term in line for term in (
            "Total frames", "Janky frames:", "percentile:", "Missed Vsync",
            "Slow UI thread", "Frame deadline",
        )):
            print(line)
    print("elapsed_s", after["time"] - before["time"])
    for pid, proc in after["processes"].items():
        previous = before["processes"].get(pid)
        if previous:
            print(proc["name"], {
                key: proc[key] - previous[key] for key in (
                    "major_faults", "minor_faults", "cpu_ticks", "read_bytes", "write_bytes",
                )
            })
    print("vm delta", {key: after["vm"][key] - before["vm"][key] for key in after["vm"]})


if __name__ == "__main__":
    main()
