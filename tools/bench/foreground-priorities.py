#!/usr/bin/env python3
"""Check native/Android foreground CPU and BFQ shares on the device.

Run as root after deploying Shell and Deckard. Launches Pilot, Reef, TikTok,
then Pilot again; leaves Pilot in front. Requires those apps installed, the
user-1000 Marathon session, and BFQ cgroup support. Saves aggregate readbacks,
without screenshots or personal app content. A wrong background weight fails
this check, including the native-to-Android handoff regression.
"""

import argparse
import json
from pathlib import Path
import subprocess
import time

CGROUP = Path("/sys/fs/cgroup")
APPS = CGROUP / "user.slice/user-1000.slice/user@1000.service/marathon.slice/marathon-apps"
BUS = (
    "XDG_RUNTIME_DIR=/run/user/1000 "
    "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus busctl --user call "
    "org.marathonos.Shell /org/marathonos/Shell/Navigation "
    "org.marathonos.Shell.Navigation1 GetForegroundApp"
)


def snapshot(app):
    foreground = subprocess.check_output(["su", "user", "-c", BUS], text=True).strip()
    if foreground != "s " + json.dumps(app):
        raise AssertionError(f"foreground {foreground}, expected {app}")
    paths = [CGROUP / "lxc.payload.deckard", *APPS.glob("marathon-app-*")]
    profiles = {}
    for path in paths:
        if not path.is_dir():
            continue
        values = {}
        for name in ("cpu.weight", "io.bfq.weight", "cgroup.freeze"):
            try:
                values[name] = (path / name).read_text().strip()
            except FileNotFoundError:
                pass
        profiles[str(path.relative_to(CGROUP))] = values
        front = app.startswith("deckard.") if path.name == "lxc.payload.deckard" else (
            path.name == "marathon-app-" + app
        )
        expected = ("200", "default 200") if front else ("50", "default 25")
        actual = (values.get("cpu.weight"), values.get("io.bfq.weight"))
        if actual != expected:
            raise AssertionError(f"{app}: {path.name}: {actual}, expected {expected}")
    expected_path = (
        "lxc.payload.deckard" if app.startswith("deckard.")
        else str((APPS / ("marathon-app-" + app)).relative_to(CGROUP))
    )
    if expected_path not in profiles:
        raise AssertionError(f"missing foreground cgroup: {expected_path}")
    return {"requested": app, "foreground": foreground, "profiles": profiles}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", default="/run/foreground-priorities.json")
    args = parser.parse_args()
    rows = []
    for app in ("shoal-pilot", "shipwright-reef", "deckard.com.zhiliaoapp.musically", "shoal-pilot"):
        subprocess.run(["marathon-remote", "launch", app], check=True, capture_output=True, timeout=60)
        deadline = time.monotonic() + 20
        while True:
            time.sleep(1)
            try:
                row = snapshot(app)
                break
            except AssertionError:
                if time.monotonic() >= deadline:
                    raise
        rows.append(row)
        print(json.dumps(row), flush=True)
    Path(args.output).write_text(json.dumps(rows, indent=2) + "\n")


if __name__ == "__main__":
    main()
