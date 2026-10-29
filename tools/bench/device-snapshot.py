#!/usr/bin/env python3
"""Run as root on the device; emit memory and idle CPU measurements as JSON."""

import datetime
import errno
import hashlib
import json
import os
from pathlib import Path
import sys
import time

TARGETS = {
    "marathon-shell-bin", "deckard-bridge", "deckard-containerd", "deckard-runtime",
    "marathon-audiod", "marathon-weatherd", "marathon-maild", "marathon-medialibd",
    "marathon-telephonyd", "pilotd", "marathon-keel-host",
}


def optional(path):
    try:
        return Path(path).read_text().strip().strip("\0")
    except OSError as error:
        if error.errno in {errno.ENOENT, errno.ENODATA, errno.EOPNOTSUPP}:
            return None
        raise


def processes():
    found = {}
    for process in Path("/proc").iterdir():
        if not process.name.isdecimal():
            continue
        try:
            executable = os.readlink(process / "exe")
            name = executable.rsplit("/", 1)[-1].removesuffix(" (deleted)")
            if name not in TARGETS:
                continue
            fields = (process / "stat").read_text().split(") ", 1)[1].split()
            memory = {}
            for line in (process / "smaps_rollup").read_text().splitlines():
                key, _, value = line.partition(":")
                if key in {"Rss", "Pss", "Private_Clean", "Private_Dirty"}:
                    memory[key + "_KiB"] = int(value.split()[0])
            found[int(process.name)] = {
                "executable": name,
                "path": executable,
                "ticks": int(fields[11]) + int(fields[12]),
                "threads": len(list((process / "task").iterdir())),
                "file_descriptors": len(list((process / "fd").iterdir())),
                **memory,
            }
        except (FileNotFoundError, ProcessLookupError):
            # /proc entries may disappear between enumeration and reading.
            continue
    return found


def main():
    label = sys.argv[1] if len(sys.argv) > 1 else "snapshot"
    seconds = float(sys.argv[2]) if len(sys.argv) > 2 else 30.0
    if not 1 <= seconds <= 300:
        raise SystemExit("measurement window must be 1..300 seconds")
    before = processes()
    start = time.monotonic()
    time.sleep(seconds)
    after = processes()
    elapsed = time.monotonic() - start
    hz = os.sysconf("SC_CLK_TCK")
    for pid, process in after.items():
        previous = before.get(pid)
        process["cpu_pct_one_core"] = (
            100 * (process["ticks"] - previous["ticks"]) / hz / elapsed
            if previous is not None else None
        )
        with open(f"/proc/{pid}/exe", "rb") as executable:
            process["sha256"] = hashlib.file_digest(executable, "sha256").hexdigest()
        del process["ticks"]
    temperatures = {
        zone.name: {"type": optional(zone / "type"), "millidegrees_C": optional(zone / "temp")}
        for zone in Path("/sys/class/thermal").glob("thermal_zone*")
    }
    print(json.dumps({
        "label": label,
        "utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "window_seconds": elapsed,
        "model": optional("/proc/device-tree/model"),
        "kernel": os.uname().release,
        "boot_id": optional("/proc/sys/kernel/random/boot_id"),
        "cpu_count": len(os.sched_getaffinity(0)),
        "governor": optional("/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor"),
        "loadavg": optional("/proc/loadavg"),
        "temperatures": temperatures,
        "processes": after,
    }, indent=2))


if __name__ == "__main__":
    main()
