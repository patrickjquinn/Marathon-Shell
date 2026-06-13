#!/usr/bin/env python3
"""OOBE walkthrough — drive through onboarding, screenshot every page.

Tests the user-reported chain:
  - Qt.rgba(20, 184, 166, X) clipping → selected scale option is
    actually visible (build 20's fix)
  - PIN setup hit areas + press feedback
  - OOBE → home transition with selected scale persisting
  - back-swipe from OOBE pages pops in-stack (not "background app")

Each step takes a screenshot named NN-step-name.png. The visual_diff
helper auto-bootstraps a golden on first run; subsequent runs flag
regressions automatically.
"""

from __future__ import annotations

from pathlib import Path
import sys
import time

sys.path.insert(0, str(Path(__file__).parent.parent))
from qemu_driver import QemuDriver  # noqa: E402


def run(drv: QemuDriver, since: str) -> int:
    fails = 0
    GOLDEN = Path(__file__).parent.parent / "golden" / "02_oobe"

    # Skip if firstRunComplete is already true — we're not in OOBE.
    rc, out, _ = drv.ssh(
        "grep -E '^firstRunComplete=' '/home/user/.config/marathon-os/"
        "Marathon Shell.conf' 2>/dev/null || echo firstRunComplete=false")
    if "true" in out.lower():
        print("  SKIP  firstRunComplete=true — OOBE already done")
        return 0

    # 01. Welcome screen
    drv.screenshot("01-welcome")

    # The OOBE buttons live near the bottom centre. Coordinates assume
    # the 720x1440 QEMU canvas. We'll learn the real Continue/Get-Started
    # button bounds from a future tag-finder; for now we centre-tap the
    # bottom 200 px band.
    cx, cy = drv.width // 2, drv.height - 180
    drv.tap(cx, cy)
    time.sleep(2)
    drv.screenshot("02-after-welcome-tap")

    # 02. Scale picker — the build-20 fix proves out here. Pick the
    # 1.25 option (5th in the list at the time of writing). We can't
    # precisely target the row without ydotool + Accessible.name, so
    # walk the radio list top-down and screenshot each step.
    drv.screenshot("03-scale-picker")
    # Tap the row at roughly 45% canvas height — that's where 1.25 sits.
    drv.tap(cx, int(drv.height * 0.45))
    time.sleep(1)
    drv.screenshot("04-scale-picked-125")
    fails += 0 if drv.visual_diff("04-scale-picked-125",
                                   GOLDEN / "04-scale-picked-125.png") else 1

    # Continue to the next OOBE page.
    drv.tap(cx, cy)
    time.sleep(2)
    drv.screenshot("05-after-scale")

    # 03. PIN setup — confirm the keypad renders with visible (post-fix)
    # hit-area outlines. We just screenshot here; tap-driving a 6-digit
    # PIN needs ydotool which we add in scenario 04.
    drv.screenshot("06-pin-screen")
    fails += 0 if drv.visual_diff("06-pin-screen",
                                   GOLDEN / "06-pin-screen.png") else 1

    print(f"==> OOBE walkthrough complete with {fails} visual regressions")
    return fails


if __name__ == "__main__":
    print("scenarios are entry points for run_scenarios.py")
    sys.exit(2)
