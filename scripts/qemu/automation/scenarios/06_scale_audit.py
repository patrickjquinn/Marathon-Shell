#!/usr/bin/env python3
"""Scale audit — boot, screenshot UI at every userScaleFactor.

User flagged that buttons look "weirdly tall with small text" at the
test scale. This walks every userScaleFactor Marathon supports and
captures key surfaces so the regressions read obviously side-by-side.

Per-scale steps:
  1. force firstRunComplete=true (skip OOBE — we want the home grid)
  2. write ui/userScaleFactor=$f into Marathon Shell.conf
  3. restart marathon-shell.service via the user instance
  4. wait until shell is back up
  5. capture lock, home, calculator, dialer surfaces
"""

from __future__ import annotations

from pathlib import Path
import sys
import time

sys.path.insert(0, str(Path(__file__).parent.parent))
from qemu_driver import QemuDriver  # noqa: E402


SCALES = [0.75, 1.0, 1.25, 1.5]
USER_CONF = "/home/user/.config/marathon-os/Marathon Shell.conf"


def set_config(drv: QemuDriver, factor: float) -> None:
    drv.ssh(
        f"sudo -u user mkdir -p '/home/user/.config/marathon-os' && "
        f"printf '[system]\\nfirstRunComplete=true\\n[ui]\\nuserScaleFactor={factor}\\n' "
        f"| sudo -u user tee '{USER_CONF}' >/dev/null"
    )


def restart_shell(drv: QemuDriver) -> None:
    # The user-systemd manager needs the user's XDG_RUNTIME_DIR + DBUS env.
    # `machinectl shell user@` would set both but isn't always available;
    # `runuser -u user -- systemctl --user restart` lets pam_systemd resolve
    # the user session and forward the unit.
    drv.ssh(
        "runuser -u user -- env XDG_RUNTIME_DIR=/run/user/1000 "
        "systemctl --user restart marathon-shell.service"
    )


def wait_shell_up(drv: QemuDriver, timeout: int = 40) -> bool:
    deadline = time.time() + timeout
    while time.time() < deadline:
        rc, out, _ = drv.ssh(
            "pgrep -f marathon-shell-bin >/dev/null && echo up || echo down")
        if "up" in out:
            time.sleep(3)  # let QML scene-graph hydrate before screencap
            return True
        time.sleep(1)
    return False


def unlock_and_home(drv: QemuDriver) -> None:
    # Lock screen swipe up to unlock. No PIN on this image.
    drv.swipe(drv.width // 2, drv.height - 60,
              drv.width // 2, drv.height // 3,
              steps=18, duration_ms=350)
    time.sleep(0.6)


def open_calculator(drv: QemuDriver) -> None:
    # Calculator is in the home grid. Without knowing exact icon coords at
    # every scale we just dump the home shot — the user can read button
    # chrome from the grid icons. For an in-app shot, scenario 03 covers
    # app launch with stable PIDs.
    pass


def run(drv: QemuDriver, since: str) -> int:
    fails = 0
    for factor in SCALES:
        tag = f"{factor:.2f}".replace(".", "_")
        print(f"  ==> scale={factor}")
        set_config(drv, factor)
        restart_shell(drv)
        if not wait_shell_up(drv):
            print(f"  FAIL  shell never came up at scale={factor}")
            fails += 1
            continue
        drv.screenshot(f"scale_{tag}_01_lock")
        unlock_and_home(drv)
        drv.screenshot(f"scale_{tag}_02_home")

    # leave config at default for subsequent runs
    set_config(drv, 1.0)
    restart_shell(drv)
    wait_shell_up(drv)

    return fails


if __name__ == "__main__":
    print("scenarios are entry points for run_scenarios.py")
    sys.exit(2)
