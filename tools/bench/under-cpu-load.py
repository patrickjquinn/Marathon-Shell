#!/usr/bin/env python3
"""Run a command with one CPU worker per available core, then stop every worker."""

import os
from pathlib import Path
import subprocess
import sys
import time

if len(sys.argv) < 2:
    raise SystemExit("usage: under-cpu-load.py command [arguments...]")


def cpu_ticks():
    fields = [int(value) for value in Path("/proc/stat").read_text().splitlines()[0].split()[1:9]]
    return sum(fields), fields[3] + fields[4]


workers = [
    subprocess.Popen([sys.executable, "-c", "while True: pass"])
    for _ in os.sched_getaffinity(0)
]
start = time.monotonic()
print(f"Starting {len(workers)} CPU workers; settling for two seconds", file=sys.stderr, flush=True)
try:
    time.sleep(2)
    total_before, idle_before = cpu_ticks()
    measured_start = time.monotonic()
    result = subprocess.run(sys.argv[1:], timeout=900, check=False)
    total_after, idle_after = cpu_ticks()
    total = total_after - total_before
    busy = 100 * (1 - (idle_after - idle_before) / total) if total else 0
    print(f"Measured CPU busy: {busy:.2f}% over {time.monotonic() - measured_start:.2f}s", file=sys.stderr)
finally:
    for worker in workers:
        worker.terminate()
    for worker in workers:
        worker.wait()
    print(f"CPU workers stopped after {time.monotonic() - start:.1f}s", file=sys.stderr, flush=True)
raise SystemExit(result.returncode)
