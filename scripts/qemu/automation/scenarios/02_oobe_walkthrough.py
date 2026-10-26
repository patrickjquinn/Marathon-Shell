#!/usr/bin/env python3
"""OOBE walkthrough — drive first-run setup to the home screen.

Setup is six beats over the wallpaper, driven by the real nav bar:
Hello (swipe up on the bar to begin), Get online ("Not now"), Keep it
private (passcode twice), Make it yours and Easy to read ("Continue"),
Your Hub (the left-edge peek, or "Not now" after the demo), then Off you
go (flick the bar up). Each step takes a screenshot named NN-step.png.

The guest has no accessibility client, so buttons are found by tapping
upwards from the bar until the frame changes: on every beat that moves on
by a button, that button is the lowest control. Taps that land on the bar
itself do nothing between the first and last beats. The passcode goes in
through the virtio keyboard, which the passcode beat reads. What this
scenario asserts is that setup completes with the passcode stored, which
is what unblocks scenarios 03/04/05.
"""

from __future__ import annotations

from pathlib import Path
import os
import sys
import time

sys.path.insert(0, str(Path(__file__).parent.parent))
from qemu_driver import QemuDriver  # noqa: E402


# The passcode setup stores, and therefore the one the rest of the harness
# must use to unlock. Matches the PIN the project's device docs use.
OOBE_PIN = os.environ.get("MARATHON_DEV_PIN", "027602")
CONF = "/home/user/.config/marathon-os/Marathon Shell.conf"
QUICKPIN = "/home/user/.config/marathon/quickpin.conf"
SETTLE = 1.5


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
    shots = iter(range(1, 1000))

    def shot(name: str) -> str:
        label = f"{next(shots):02d}-{name}"
        drv.screenshot(label)
        return label

    def oobe_done() -> bool:
        _, out, _ = drv.ssh(
            f"grep -E '^firstRunComplete=true' '{CONF}' 2>/dev/null && echo yes || echo no")
        return "yes" in out

    def check(ok: bool, what: str):
        nonlocal fails
        print(f"  {'OK  ' if ok else 'FAIL'}  {what}")
        if not ok:
            fails += 1

    def flick_bar():
        drv.swipe(drv.width // 2, drv.height - 30, drv.width // 2, int(drv.height * 0.55),
                  steps=20, duration_ms=300)
        time.sleep(SETTLE)

    def tap_lowest(x: int, name: str) -> bool:
        before = shot(f"{name}-before")
        y = drv.height - 30
        while y > drv.height // 2:
            drv.tap(x, y)
            time.sleep(SETTLE)
            if frame_delta(drv, before, shot(name)) >= 0.02:
                return True
            y -= int(drv.height * 0.015)
        return False

    def type_pin():
        for ch in OOBE_PIN:
            drv.key(ch)
            time.sleep(0.3)
        time.sleep(1.0)

    if oobe_done():
        print("  SKIP  firstRunComplete=true — OOBE already done")
        return 0

    shot("hello")
    flick_bar()
    # Get online scans for up to 6 s behind a busy indicator first.
    time.sleep(7)
    check(tap_lowest(int(drv.width * 0.27), "online-not-now"), "Not now leaves Get online")

    shot("passcode")
    type_pin()
    shot("passcode-confirm")
    type_pin()
    shot("look")
    rc, _, _ = drv.ssh(f"test -s '{QUICKPIN}'")
    check(rc == 0, "the passcode twice is stored")

    check(tap_lowest(drv.width // 2, "look-continue"), "Continue leaves Make it yours")
    check(tap_lowest(drv.width // 2, "size-continue"), "Continue leaves Easy to read")

    # The Hub practice moves on 1.5 s after the peek; a flick on the bar
    # does nothing until then. If setup has not finished, either the edge
    # swipe missed (the demo plays after 8 s, then Not now is the lowest
    # control) or the flick did. Only a flick counts as finishing: if the
    # fallback's taps end setup themselves, they hit the bar or the finish
    # beat's own Not now, so the flick had failed.
    shot("hub")
    drv.swipe(2, drv.height // 2, int(drv.width * 0.7), drv.height // 2,
              steps=24, duration_ms=400)
    time.sleep(4)
    shot("hub-peeked")
    flick_bar()
    flicked = oobe_done()
    if not flicked:
        time.sleep(16)
        tap_lowest(drv.width // 2, "hub-not-now")
        if not oobe_done():
            flick_bar()
            flicked = oobe_done()
    check(flicked, "the flick up on the bar completes setup (firstRunComplete=true)")
    shot("home")

    print(f"==> OOBE walkthrough finished with {fails} failure(s)")
    return fails


if __name__ == "__main__":
    print("scenarios are entry points for run_scenarios.py")
    sys.exit(2)
