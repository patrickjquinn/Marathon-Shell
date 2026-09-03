#!/usr/bin/env python3
"""OOBE walkthrough — drive through onboarding, screenshot every page.

Tests the user-reported chain:
  - Qt.rgba(20, 184, 166, X) clipping → selected scale option is
    actually visible (build 20's fix)
  - PIN setup hit areas + press feedback
  - OOBE → home transition with selected scale persisting
  - back-swipe from OOBE pages pops in-stack (not "background app")

Each step takes a screenshot named NN-step-name.png. Goldens are not
compared here any more: the previous ones were auto-bootstrapped from a
run where OOBE never advanced, so they encoded the Welcome frame and
"passed" it forever. What this scenario asserts now is that OOBE
actually completes -- which is what unblocks scenarios 03/04/05.
"""

from __future__ import annotations

from pathlib import Path
import os
import sys
import time

sys.path.insert(0, str(Path(__file__).parent.parent))
from qemu_driver import QemuDriver  # noqa: E402


# The passcode OOBE sets, and therefore the one the rest of the harness
# must use to unlock. Matches the PIN the project's device docs use.
OOBE_PIN = os.environ.get("MARATHON_DEV_PIN", "027602")


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


def run(drv: QemuDriver, since: str) -> int:
    fails = 0

    # Skip if firstRunComplete is already true — we're not in OOBE.
    rc, out, _ = drv.ssh(
        "grep -E '^firstRunComplete=' '/home/user/.config/marathon-os/"
        "Marathon Shell.conf' 2>/dev/null || echo firstRunComplete=false")
    if "true" in out.lower():
        print("  SKIP  firstRunComplete=true — OOBE already done")
        return 0

    # 01. Welcome screen
    drv.screenshot("01-welcome")

    # Advance OOBE by tapping the primary button, which this design puts
    # bottom-RIGHT, not bottom-centre. The old code centre-tapped the
    # bottom band -- landing ~17 px left of the button's edge -- so OOBE
    # never advanced past Welcome: all six "step" screenshots were the
    # same frame, both visual_diffs compared Welcome against a golden
    # bootstrapped from Welcome, and firstRunComplete stayed false, which
    # silently skipped scenarios 03/04/05 on every fresh image.
    NEXT = (int(drv.width * 0.733), int(drv.height * 0.868))
    SKIP = (int(drv.width * 0.840), int(drv.height * 0.131))

    def oobe_done() -> bool:
        rc, out, _ = drv.ssh(
            "grep -E '^firstRunComplete=true' '/home/user/.config/"
            "marathon-os/Marathon Shell.conf' 2>/dev/null && echo yes || echo no")
        return "yes" in out

    # "Create a passcode" keypad, measured on the 720x1440 canvas. This
    # page has only Back/Next -- no Skip -- and Next does nothing until
    # six digits are entered, which is where the walkthrough used to
    # stall for good.
    PAD = {"1": (208, 570), "2": (360, 570), "3": (511, 570),
           "4": (208, 721), "5": (360, 721), "6": (511, 721),
           "7": (208, 873), "8": (360, 873), "9": (511, 873),
           "0": (360, 1024)}

    def type_pin():
        for ch in OOBE_PIN:
            drv.tap(*PAD[ch])
            time.sleep(0.35)
        time.sleep(0.8)

    # Walk the pages. The page count is not fixed (seven dots at the time
    # of writing) and some pages need input before Next does anything, so
    # drive it adaptively: tap Next, and if the frame did not change,
    # type the passcode before retrying. That avoids hard-coding which
    # page index is the passcode page.
    #
    # Caveat, measured: under the software renderer a page can take
    # longer than the 1.5 s settle to repaint, so "frame did not change"
    # also fires on merely-slow pages and types digits into them
    # harmlessly. OOBE does complete, but do NOT assume this leaves a
    # passcode provisioned -- observed runs finish with no
    # quickpin.conf. That is fine for automation (no lock prompt to
    # satisfy); it is not a substitute for a real passcode-setup test.
    for step in range(2, 16):
        if oobe_done():
            break
        prev = f"{step:02d}-before-next"
        drv.screenshot(prev)
        drv.tap(*NEXT)
        time.sleep(1.5)
        cur = f"{step:02d}-oobe-step"
        drv.screenshot(cur)
        if frame_delta(drv, prev, cur) < 0.02:
            type_pin()                       # passcode / confirm page
            drv.screenshot(f"{step:02d}-pin-typed")
            drv.tap(*NEXT)
            time.sleep(1.5)
            drv.screenshot(f"{step:02d}-after-pin-next")

    # Late pages may still offer Skip (e.g. optional account setup).
    if not oobe_done():
        drv.tap(*SKIP)
        time.sleep(2.5)
        drv.screenshot("90-after-skip")

    if not oobe_done():
        print("  FAIL  OOBE did not complete — 03/04/05 will skip")
        fails += 1
    else:
        drv.screenshot("99-oobe-complete")
        print("  OK    OOBE complete (firstRunComplete=true)")

    print(f"==> OOBE walkthrough finished with {fails} failure(s)")
    return fails


if __name__ == "__main__":
    print("scenarios are entry points for run_scenarios.py")
    sys.exit(2)
