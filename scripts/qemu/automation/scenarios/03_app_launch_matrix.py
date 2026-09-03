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
import os
import sys
import time

sys.path.insert(0, str(Path(__file__).parent.parent))
from qemu_driver import QemuDriver  # noqa: E402


# Order picks the cheapest first so a partial run still covers breadth.
# "contacts" intentionally not listed — there's no contacts app on disk
# yet (Phone owns recents + dial pad; contacts surface lives inside it).
APPS = [
    "calculator", "clock", "notes", "settings",
    "calendar", "messages", "phone",
    "music", "gallery", "camera",
    "email", "browser", "maps",
    "store", "terminal",
]


def busctl(drv: QemuDriver, method: str, arg: str = "") -> tuple[int, str, str]:
    # --machine=user@.host hops onto the user session bus from our root
    # ssh — without it busctl can't find $DBUS_SESSION_BUS_ADDRESS.
    cmd = (
        "busctl --machine=user@.host --user call org.marathonos.Shell "
        "/org/marathonos/Shell/Navigation "
        "org.marathonos.Shell.Navigation1 "
        f"{method} s '{arg}'"
    )
    return drv.ssh(cmd)


def runner_pids(drv: QemuDriver) -> set[int]:
    """PIDs of every live app-runner.

    Not matched by app id: the runner is exec'd inside bwrap and, with
    the warm pool enabled, keeps its `--pool` argv even after adopting
    an app, so the app id appears in no process's argv. comm is
    truncated to 15 chars ("marathon-app-ru"); matching comm rather
    than the full cmdline also stops pgrep self-matching our own ssh
    command.
    """
    rc, out, _ = drv.ssh(
        "ps -e -o pid=,comm= | awk '$2 ~ /^marathon-app/ {print $1}'")
    return {int(t) for t in out.split() if t.isdigit()}


# Best-effort unlock. Scenario 02 does not reliably provision a
# passcode (see its notes), so this is a no-op on most runs -- it
# exists for images that were set up with the documented PIN.
DEV_PIN = os.environ.get("MARATHON_DEV_PIN", "027602")


def wake_display(drv: QemuDriver):
    """Wake the panel and stop the session locking mid-run.

    Two traps, both of which make a healthy shell look broken.

    Doze display-off is default-on, so an idle guest blanks the screen
    and every screendump comes back uniformly black.

    Worse, the session idle-LOCKS, and the lock screen sits above
    everything: launches happen behind it and taps land on the PIN
    keypad, so before/after frames are identical and every app reads as
    "input produced no visible change". A full 07 run looked exactly
    like that -- 14 apps, every delta 0.00% -- against a shell that was
    working fine. Unlocking is not an option for a generic harness: the
    PIN is whatever OOBE was given.

    SettingsManager.screenTimeout == 0 is "Never", and it gates off both
    the screen-off timer and the lock timer, so set that for the run.
    """
    drv.ssh("marathon-dev wake 2>/dev/null || true")
    for prop in ("screenTimeout", "autoLockTimeout"):
        drv.ssh("busctl --machine=user@.host --user call org.marathonos.Shell "
                "/org/marathonos/Shell/Settings org.marathonos.Shell.Settings1 "
                f"SetProperty sv {prop} i 0 2>/dev/null || true")
    time.sleep(1.0)
    # If the session already locked, clear it -- screenTimeout=0 only
    # prevents the NEXT lock, it does not dismiss a lock already up, and
    # the lock screen composites above the app so every tap lands on it.
    drv.ssh(f"marathon-dev unlock {DEV_PIN} 2>/dev/null || true")
    time.sleep(1.5)


def reset_runners(drv: QemuDriver):
    """Close running apps so the next launch starts on page one.

    The old close pkill'd "marathon-app-runner --app-id <id>", which
    matches nothing under the warm pool -- so "ensure clean state" was
    a silent no-op and each app was relaunched on whatever page the
    previous iteration left it on, quietly invalidating recipes that
    assume a first page.

    marathon-dev close is the shell's own supported path; fall back to
    signalling the runners directly on images that predate it.
    """
    rc, _, _ = drv.ssh("marathon-dev close 2>/dev/null")
    if rc != 0:
        for pid in runner_pids(drv):
            drv.ssh(f"kill -TERM {pid} 2>/dev/null || true")
    time.sleep(1.5)


def frame_delta(drv: QemuDriver, a: str, b: str) -> float:
    """Fraction of pixels differing between two captured screenshots."""
    pa, pb = drv.run_dir / f"{a}.png", drv.run_dir / f"{b}.png"
    if not (pa.exists() and pb.exists()):
        return 0.0
    try:
        from PIL import Image
        import numpy as np
    except ImportError:
        return 0.0
    xa = np.asarray(Image.open(pa).convert("RGB"), dtype=np.int16)
    xb = np.asarray(Image.open(pb).convert("RGB"), dtype=np.int16)
    if xa.shape != xb.shape:
        return 1.0
    d = np.abs(xa - xb).max(axis=-1)
    return float((d > 12).sum() / d.size)


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

    wake_display(drv)
    pre_cores = coredumps_since(drv, since)

    # An app "launched" if the screen stopped being the home screen.
    # That is the assertion this scenario actually cares about, and
    # unlike process bookkeeping it cannot be fooled by the warm pool
    # (adoption reuses the spare's pid, so a launch adds no new pid for
    # the app) or by the sandbox hiding the runner's argv.
    reset_runners(drv)
    busctl(drv, "Navigate", "home")
    time.sleep(2.5)
    drv.screenshot("home-reference")

    for appid in APPS:
        print(f"\n  ==> {appid}")
        before = drv.ssh(f"date -u +'%Y-%m-%d %H:%M:%S UTC'")[1].strip()
        wake_display(drv)
        reset_runners(drv)

        rc, out, err = busctl(drv, "LaunchApp", appid)
        if rc != 0:
            print(f"     busctl exit {rc}: {(out or err).strip()[:100]}")

        # Snap tty1 immediately after the LaunchApp returns — the shell
        # prints the runner's QProcess stderr-tail synchronously when the
        # runner exits abnormally, and /dev/vcs1 is just the on-screen
        # framebuffer (~80×25 chars), so anything older than the last
        # second scrolls off into the void. We don't know yet whether
        # this app will fail; if it does, the run-dir keeps the snap so
        # diagnosis doesn't depend on a follow-up SSH session.
        _, vcs0, _ = drv.ssh("cat /dev/vcs1 2>/dev/null | tr -s ' ' "
                             "| tail -c 6000")

        # Software-rendered guests need up to ~12 s for the heavier QML
        # graphs (browser/maps/email) to reach a first frame.
        surfaced = False
        for _ in range(12):
            time.sleep(1)
            drv.screenshot(f"app-{appid}")
            if frame_delta(drv, f"app-{appid}", "home-reference") > 0.02:
                surfaced = True
                break

        if not surfaced:
            # vcs0 (captured right after LaunchApp) holds the synchronous
            # qWarning the shell emits when QProcess::errorOccurred fires;
            # vcs1 (now) holds whatever the polling loop pushed onto the
            # framebuffer. Save both — vcs0 is the one that usually has
            # the QML compile error / bwrap stderr-tail.
            _, vcs1, _ = drv.ssh("cat /dev/vcs1 2>/dev/null | tr -s ' ' "
                                 "| tail -c 6000")
            (drv.run_dir / f"tty1-{appid}.txt").write_text(
                "=== vcs at LaunchApp+0 ===\n" + vcs0 +
                "\n\n=== vcs at LaunchApp+10s ===\n" + vcs1)
            print(f"     FAIL  {appid} never replaced the home screen in 12 s "
                  f"(tty1 → {drv.run_dir.name}/tty1-{appid}.txt)")
            fails += 1
            continue

        cores = coredumps_since(drv, before)
        if cores:
            print(f"     FAIL  {cores} coredump(s) during {appid} launch")
            fails += 1
        else:
            print(f"     OK    surface up, no crashes")

        # Hard-stop the runners so the next iteration starts from a known
        # state. The nav-pill swipe only *backgrounds* via UIStore.closeApp
        # -- the runner keeps its surface mapped and its PID alive, which
        # lets prior iterations interfere with later launches (e.g. the
        # shell's per-appId pid-table refusing a relaunch).
        reset_runners(drv)

    return fails


if __name__ == "__main__":
    print("scenarios are entry points for run_scenarios.py")
    sys.exit(2)
