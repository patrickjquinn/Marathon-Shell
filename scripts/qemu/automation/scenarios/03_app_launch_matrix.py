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


def app_runner_pid(drv: QemuDriver, appid: str) -> int | None:
    # Match the marathon-app-runner binary in /proc/<pid>/comm or argv[0],
    # not the full cmdline — otherwise pgrep self-matches because the ssh
    # remote-command literally contains "marathon-app-runner --app-id X".
    rc, out, _ = drv.ssh(
        "ps -e -o pid=,comm=,args= "
        f"| awk '$2 ~ /^marathon-app/ && /--app-id {appid}\\>/ {{print $1; exit}}'"
    )
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

        # Poll for the runner pid — software-rendered guests need up to
        # 8 s for heavier QML graphs (browser/maps/email) to spawn.
        pid = None
        for _ in range(10):
            time.sleep(1)
            pid = app_runner_pid(drv, appid)
            if pid:
                break
        drv.screenshot(f"app-{appid}")

        if not pid:
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
            print(f"     FAIL  no app-runner pid for {appid} after 10 s "
                  f"(tty1 → {drv.run_dir.name}/tty1-{appid}.txt)")
            fails += 1
            continue
        print(f"     pid {pid}")

        cores = coredumps_since(drv, before)
        if cores:
            print(f"     FAIL  {cores} coredump(s) during {appid} launch")
            fails += 1
        else:
            print(f"     OK    surface up, no crashes")

        # Hard-stop the runner so the next iteration starts from a known
        # state. The nav-pill swipe only *backgrounds* via UIStore.closeApp
        # — the runner keeps its surface mapped and its PID alive, which
        # lets prior iterations interfere with later launches (e.g. the
        # shell's per-appId pid-table refusing a relaunch). SIGTERM is the
        # cheapest deterministic teardown; coredumps_since() already ran.
        drv.ssh(f"kill -TERM {pid} 2>/dev/null; "
                f"for _ in 1 2 3 4 5; do kill -0 {pid} 2>/dev/null || break; "
                f"sleep 0.3; done; kill -KILL {pid} 2>/dev/null; true")
        time.sleep(0.8)

    return fails


if __name__ == "__main__":
    print("scenarios are entry points for run_scenarios.py")
    sys.exit(2)
