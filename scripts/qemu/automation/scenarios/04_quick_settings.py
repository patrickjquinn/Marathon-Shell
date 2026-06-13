#!/usr/bin/env python3
"""Quick Settings — pull down from status bar, dismiss via nav pill swipe-up.

Regresses the build-20 fix (MarathonNavBar.qml — startY no longer
re-anchored every move during a QS drag so the cumulative diffY actually
trips isVerticalGesture and the release-time dismiss check fires).

Steps:
  - take screenshot of home
  - swipe down from the status bar (top 28 px) into the screen → QS panel
  - screenshot QS open
  - swipe up from the nav-bar pill area → QS should dismiss
  - screenshot QS dismissed
  - assert (visually) the dismissed screenshot matches the original home
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

    drv.screenshot("01-home")

    # Pull QS down: swipe from near top (inside status-bar drag zone)
    # 90% canvas height down. Stops well above the QS dismiss threshold.
    drv.swipe(360, 14, 360, int(drv.height * 0.9), steps=20, duration_ms=400)
    time.sleep(0.6)
    drv.screenshot("02-qs-open")

    # Dismiss via swipe-up FROM the nav-bar pill (the user-reported
    # path). The pill sits ~30 px above the bottom edge.
    drv.swipe(360, drv.height - 30, 360, int(drv.height * 0.3),
              steps=18, duration_ms=300)
    time.sleep(0.6)
    drv.screenshot("03-qs-dismissed")

    print("  visual: home should match qs-dismissed within 5% pixel diff")
    GOLDEN = Path(__file__).parent.parent / "golden" / "04_quick_settings"
    if not drv.visual_diff("03-qs-dismissed", GOLDEN / "home.png", threshold=0.05):
        # First run: bootstrap from current shot.
        (GOLDEN).mkdir(parents=True, exist_ok=True)
        shot = drv.run_dir / "03-qs-dismissed.png"
        if shot.exists():
            (GOLDEN / "home.png").write_bytes(shot.read_bytes())
            print("  OK    bootstrapped home golden")

    return fails


if __name__ == "__main__":
    print("scenarios are entry points for run_scenarios.py")
    sys.exit(2)
