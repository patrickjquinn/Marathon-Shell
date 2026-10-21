#!/usr/bin/env python3
"""Settings back-swipe — pop sub-pages, not background the app.

Regresses build-20's MARATHON_SHELL_PID fix. Before the fix,
AppRunnerLifecycleObject::verifyCallerIsShell() rejected every
back/forward DBus call with AccessDenied → handleSystemBack returned
false → UIStore.closeApp() backgrounded Settings. After the fix, the
runner accepts the call, MApp.canNavigateBack reads true, and the
nav-stack pops correctly.

Sequence:
  - LaunchApp(settings) via busctl
  - tap "Display" entry
  - screenshot Display page
  - swipe right on nav-bar pill (back gesture)
  - screenshot — should be back on Settings main, NOT backgrounded to home
  - capture pgrep marathon-app-runner --app-id settings → should still be running

If the app disappears from the process table after one back-swipe, that's
the bug returning.
"""

from __future__ import annotations

from pathlib import Path
import sys
import time

sys.path.insert(0, str(Path(__file__).parent.parent))
from qemu_driver import QemuDriver  # noqa: E402


def run(drv: QemuDriver, since: str) -> int:
    fails = 0

    rc, out, _ = drv.ssh(
        "grep -E '^firstRunComplete=true' '/home/user/.config/marathon-os/"
        "Marathon Shell.conf' 2>/dev/null && echo yes || echo no")
    if "yes" not in out:
        print("  SKIP  OOBE not complete")
        return 0

    drv.ssh("sudo -u user -i bash -lc "
            "'busctl --user call org.marathonos.Shell "
            "/org/marathonos/Shell/Navigation "
            "org.marathonos.Shell.Navigation1 LaunchApp s settings'")
    time.sleep(4)
    drv.screenshot("01-settings-main")

    # "Display" entry sits in the System section. Approximate y from a 720x1440
    # canvas; will refine when we wire Accessible.name lookups.
    drv.tap(360, 760)
    time.sleep(2)
    drv.screenshot("02-display-page")

    # Back-swipe — drag right-to-left on nav pill is forward, LEFT-to-RIGHT
    # is back. Generous distance to clear any threshold.
    drv.swipe(40, drv.height - 30, drv.width - 40, drv.height - 30,
              steps=20, duration_ms=300)
    time.sleep(1.5)
    drv.screenshot("03-after-back-swipe")

    rc, out, _ = drv.ssh(
        "pgrep -af 'marathon-app-runner.*--app-id settings' | head -2")
    if "marathon-app-runner" not in out:
        print("  FAIL  back-swipe backgrounded Settings (the build-20 bug returned)")
        fails += 1
    else:
        print(f"  OK    Settings still running: {out.strip().splitlines()[0]}")

    return fails


if __name__ == "__main__":
    print("scenarios are entry points for run_scenarios.py")
    sys.exit(2)
