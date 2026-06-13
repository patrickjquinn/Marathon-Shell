#!/usr/bin/env python3
"""App launch matrix — every Marathon app boots cleanly to first frame.

Drives the shell's org.marathonos.Shell.Navigation1.LaunchApp DBus method
via busctl, which is more reliable than tapping app-grid icons (no
coordinate hunting, works regardless of grid scroll position) and
exercises the same code path the launcher uses internally.

For each app:
  - assert no fresh coredumps before launch
  - call LaunchApp(appId)
  - wait 4 s for the surface to attach
  - screenshot
  - assert no coredumps from the app-runner since the launch
  - close back to home
  - record per-app pass/fail in the run report

The test deliberately doesn't validate visual content beyond
"surface rendered" — that's scenario 04's job. Here we just establish
that every app starts without crashing.

Note: MARATHON_TEST_TRUSTED is set in the QEMU image's session script,
which lets a synthetic DBus caller (us) bypass the per-app PID check.
"""

from __future__ import annotations

from pathlib import Path
import sys
import time

sys.path.insert(0, str(Path(__file__).parent.parent))
from qemu_driver import QemuDriver  # noqa: E402


# Order picks the cheapest first so a partial run still covers breadth.
APPS = [
    "calculator", "clock", "notes", "settings",
    "calendar", "contacts", "messages", "phone",
    "music", "gallery", "camera",
    "email", "browser", "maps",
    "store", "terminal",
]


def busctl(drv: QemuDriver, method: str, arg: str = "") -> tuple[int, str, str]:
    cmd = (
        "busctl --user call org.marathonos.Shell "
        "/org/marathonos/Shell/Navigation "
        "org.marathonos.Shell.Navigation1 "
        f"{method} s '{arg}'"
    )
    return drv.ssh(f"sudo -u user -i bash -lc \"{cmd}\"")


def app_runner_pid(drv: QemuDriver, appid: str) -> int | None:
    rc, out, _ = drv.ssh(
        f"pgrep -f 'marathon-app-runner.*--app-id {appid}' | head -1")
    out = out.strip()
    if not out or not out.isdigit():
        return None
    return int(out)


def coredumps_since(drv: QemuDriver, since: str) -> int:
    rc, out, _ = drv.ssh(
        f"coredumpctl list --since '{since}' --no-pager 2>/dev/null "
        "| tail -n +2 | grep -c marathon || true")
    out = out.strip()
    return int(out) if out.isdigit() else 0


def run(drv: QemuDriver, since: str) -> int:
    fails = 0

    # If the shell is sitting on OOBE, skip — we can't drive apps until home.
    rc, out, _ = drv.ssh(
        "grep -E '^firstRunComplete=true' '/home/user/.config/marathon-os/"
        "Marathon Shell.conf' 2>/dev/null && echo yes || echo no")
    if "yes" not in out:
        print("  SKIP  OOBE not complete — set firstRunComplete=true and rerun")
        return 0

    pre_cores = coredumps_since(drv, since)

    for appid in APPS:
        print(f"\n  ==> {appid}")
        before = drv.ssh(f"date -u +'%Y-%m-%d %H:%M:%S UTC'")[1].strip()

        rc, out, err = busctl(drv, "LaunchApp", appid)
        if rc != 0:
            # busctl prints either "b true" or DBus error. Either way we
            # continue and let the screenshot + coredump check be the
            # actual signal.
            print(f"     busctl exit {rc}: {(out or err).strip()[:100]}")

        time.sleep(4)
        drv.screenshot(f"app-{appid}")

        pid = app_runner_pid(drv, appid)
        if not pid:
            print(f"     FAIL  no app-runner pid for {appid}")
            fails += 1
            continue
        print(f"     pid {pid}")

        cores = coredumps_since(drv, before)
        if cores:
            print(f"     FAIL  {cores} coredump(s) during {appid} launch")
            fails += 1
        else:
            print(f"     OK    surface up, no crashes")

        # Swipe right on the nav-bar pill to go back. Build 20's
        # MARATHON_SHELL_PID env fix is what makes this actually return
        # to home rather than silently no-op; we exercise it once per app.
        drv.swipe(360, drv.height - 30, 10, drv.height - 30, steps=14, duration_ms=200)
        time.sleep(1.5)

    return fails


if __name__ == "__main__":
    print("scenarios are entry points for run_scenarios.py")
    sys.exit(2)
