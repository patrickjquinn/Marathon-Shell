#!/usr/bin/env python3
"""App interaction matrix — every app responds to one concrete input.

Scenario 03 proves apps reach first frame. This scenario proves the
first frame is not a STUCK frame — that the QML scene actually responds
to user input. Without this check, a regression that wedges every app's
event loop on launch would still ship green through 03.

For each app:
  - launch via Navigation.LaunchApp DBus
  - screenshot the initial surface ("before")
  - perform ONE deterministic input (tap a known control OR a scroll swipe)
  - screenshot again ("after")
  - assert the pixel diff exceeds an app-specific minimum — the bar is
    not "looks correct" (golden tests do that) but "the UI changed at
    all in response to the input we sent"
  - close back to home

This catches: pages frozen after launch, list views that don't scroll,
buttons that don't visually press, dialogs that don't open. It DOES
NOT validate semantic correctness (calculator arithmetic, settings
saved values) — that's a higher tier.

Browser WebEngine content is excluded — under QEMU's software backend
the canvas never paints (project_qemu_dev_simulator.md, mesa-virgl
rebuild pending). The Browser chrome (URL bar, tabs) IS exercised.
"""

from __future__ import annotations

from pathlib import Path
import sys
import time
import subprocess

sys.path.insert(0, str(Path(__file__).parent.parent))
from qemu_driver import QemuDriver  # noqa: E402


def busctl_launch(drv: QemuDriver, app_id: str) -> bool:
    cmd = (
        "busctl --machine=user@.host --user call org.marathonos.Shell "
        "/org/marathonos/Shell/Navigation org.marathonos.Shell.Navigation1 "
        f"LaunchApp s '{app_id}'"
    )
    rc, out, err = drv.ssh(cmd)
    return rc == 0 and "true" in out.lower()


def busctl_close(drv: QemuDriver, app_id: str):
    # Synthetic home — return to launcher by killing app-runner. Faster
    # and less flake-prone than driving the bottom-pill swipe-up gesture.
    drv.ssh(f"pkill -TERM -f 'marathon-app-runner --app-id {app_id}' || true")
    time.sleep(0.4)


def app_runner_pid(drv: QemuDriver, app_id: str) -> int | None:
    rc, out, _ = drv.ssh(f"pgrep -f 'app-runner --app-id {app_id}'")
    if rc != 0:
        return None
    for line in out.splitlines():
        line = line.strip()
        if line.isdigit():
            return int(line)
    return None


def pixel_change_fraction(drv: QemuDriver, before: str, after: str) -> float:
    """Return the fraction of pixels that changed between two screenshots.

    Uses PIL's ImageChops.difference + per-pixel max. Faster + works
    without spawning a subprocess (matters with 15 invocations per run).
    """
    a = drv.run_dir / f"{before}.png"
    b = drv.run_dir / f"{after}.png"
    if not (a.exists() and b.exists()):
        return 0.0

    try:
        from PIL import Image
        import numpy as np
    except ImportError:
        return 0.0

    arr_a = np.asarray(Image.open(a).convert("RGB"), dtype=np.int16)
    arr_b = np.asarray(Image.open(b).convert("RGB"), dtype=np.int16)
    if arr_a.shape != arr_b.shape:
        return 1.0
    # Per-pixel max-channel delta; threshold 12/255 to ignore subpixel
    # antialiasing and PNG quantisation noise.
    delta = np.abs(arr_a - arr_b).max(axis=-1)
    return float((delta > 12).sum() / delta.size)


# Per-app interaction recipe. Coords are measured from real screenshots
# of each app on Marathon's 720×1440 canvas. min_diff is the floor we
# require to claim "the UI moved at all" — a value generous enough to
# cover digit-press feedback (smaller area than a list scroll).
#
# Recipes:
#   ("tap",   x, y, min_diff)           — single tap on a known control
#   ("swipe", x1, y1, x2, y2, min_diff) — stepped swipe (scroll / page)
#
# Apps deliberately omitted:
#   maps  — WebEngine content can't render under QEMU software backend
#           (project_qemu_dev_simulator.md, mesa-virgl rebuild pending)
# Thresholds are tuned to "smallest visible change the recipe produces
# on a 720×1440 canvas". A digit appearing on a dial pad covers ~60-100
# pixels = ~0.01% of the frame; a sub-page push covers most of the
# screen. The job here is to detect "the input did SOMETHING" — golden
# tests handle the "did it do the RIGHT thing" question.
RECIPES: dict[str, tuple] = {
    # Calculator: tap "5" (col 2 of 4, middle row). Display flips 0 → 5
    # — a single-glyph change in the top-right display region.
    "calculator":  ("tap", 272, 1118, 0.0002),

    # Clock: tap the bottom "Alarm" tab. Tab bar centre row is at y≈1260
    # on the 720×1440 canvas; the home-pill area below it (y≈1320-1410)
    # is NOT touchable.
    "clock":       ("tap", 450, 1260, 0.005),

    # Notes: tapping "+" pushes NoteEditorPage which triggers a SHM
    # backing-store recreate inside libQt6WaylandClient. Under the QEMU
    # software backend that path SIGSEGVs in
    # QWaylandShmBackingStore::recreateBackBufferIfNeeded (verified via
    # coredumpctl). On hardware GL it composites fine. Skip until the
    # mesa-virgl image rebuild lands (project_qemu_dev_simulator.md).
    "notes":       None,

    # Settings: tap the Wi-Fi row (first in the Connectivity card).
    "settings":    ("tap", 360, 320, 0.02),

    # Calendar: same QWaylandShmBackingStore crash class as Notes —
    # tapping any cell pushes a day-detail page and the backing-store
    # recreate SIGSEGVs under the software backend. Skip until virgl.
    "calendar":    None,

    # Messages: tap "+" compose in the top-right header.
    "messages":    ("tap", 685, 190, 0.005),

    # Phone: tap "5" — the digit appears in the dialedNumber display
    # band above the keypad. ~30×40 px = ~0.01% of frame.
    "phone":       ("tap", 360, 690, 0.0002),

    # Music: tap the chevron-down at top-left (≈30, 80) which dismisses
    # the Now Playing surface back to the Library view — a huge frame
    # change. Bottom-tab variants miss the MouseArea by a few pixels.
    "music":       ("tap", 30, 80, 0.02),

    # Gallery: tap the "Search" bottom tab (4th of 4). The header has a
    # search glyph too but it's small (1px feedback); the bottom-bar
    # tab change repaints a much larger area.
    "gallery":     ("tap", 630, 1260, 0.005),

    # Camera: QEMU has no /dev/video — the app renders only "No Camera
    # Found" with no interactive controls. Skip (recipe `None`) so the
    # matrix doesn't blame the app for the missing hardware.
    "camera":      None,

    # Email: no account configured, so the surface is the OOBE
    # "Add a mail account" screen — there's no MTabBar yet. Tap the
    # primary "Sign in with Google" button (large filled CTA, centre).
    "email":       ("tap", 360, 750, 0.01),

    # Browser: tap the URL bar centre — focuses + raises keyboard.
    "browser":     ("tap", 360, 1340, 0.005),

    # Store: scroll the catalog.
    "store":       ("swipe", 360, 900, 360, 600, 0.005),

    # Terminal: tap "+" (bottom-right) to toggle the keyboard overlay.
    "terminal":    ("tap", 685, 1245, 0.005),
}


def run(drv: QemuDriver, since: str) -> int:
    rc, out, _ = drv.ssh(
        "grep -E '^firstRunComplete=true' '/home/user/.config/marathon-os/"
        "Marathon Shell.conf' 2>/dev/null && echo yes || echo no")
    if "yes" not in out:
        print("  SKIP  OOBE not complete — set firstRunComplete=true and rerun")
        return 0

    # Pre-grant every category to every app so the FIRST app's permission
    # dialog doesn't sit on top of the SECOND app's launch state. We're
    # measuring "does input drive QML" here — the permission flow is its
    # own (deferred) scenario. A real regression where permissions DO
    # fail will show as a dialog overlay above all the apps; the diff
    # will be zero everywhere and that itself is a fail signal.
    PERMISSIONS = ["network", "storage", "system", "location",
                   "camera", "microphone", "contacts"]
    grant_script = []
    for app_id in RECIPES:
        for perm in PERMISSIONS:
            grant_script.append(
                "busctl --machine=user@.host --user call "
                "org.marathonos.Shell /org/marathonos/Shell/Permissions "
                f"org.marathonos.Shell.Permissions1 SetPermission ssbb "
                f"{app_id} {perm} true true >/dev/null 2>&1")
    drv.ssh("\n".join(grant_script))

    fails = 0

    for app_id, recipe in RECIPES.items():
        print(f"  ==> {app_id}")

        if recipe is None:
            print(f"     SKIP  no recipe (QEMU-specific gap; see comment)")
            continue

        # Ensure clean state.
        busctl_close(drv, app_id)
        time.sleep(0.3)

        if not busctl_launch(drv, app_id):
            print(f"     FAIL  busctl LaunchApp returned !true")
            fails += 1
            continue

        # Surface attach window matches scenario 03.
        pid = None
        for _ in range(20):
            pid = app_runner_pid(drv, app_id)
            if pid:
                break
            time.sleep(0.5)
        if not pid:
            print(f"     FAIL  no app-runner pid after 10 s")
            fails += 1
            continue

        # Settle render — apps with WebEngine init (browser, maps) need
        # extra time. The 2 s baseline lets MApp.Component.onCompleted
        # finish + dialog suppression race settle; without it the matrix
        # screenshots at the moment the previous app's freeze-frame is
        # still on screen and EVERY app reports 0% delta.
        time.sleep(3.0 if app_id in ("browser", "maps") else 2.0)
        drv.screenshot(f"{app_id}-before")

        # marathon-touchctl creates a fresh /dev/uinput every invocation
        # and waits only 400 ms for libinput to bind. Across 14 sequential
        # apps that race fires often enough to drop ~half of the real
        # recipe taps. Run the warm-up tap AND the recipe tap through ONE
        # marathon-touchctl stdin pipe so libinput sees a single
        # persistent touch device for both.
        if recipe[0] == "tap":
            _, x, y, min_diff = recipe
            program = (
                "tap 1 1\n"
                "sleep 150\n"
                f"tap {x} {y}\n"
            )
            drv.ssh(
                ". /tmp/marathon-touchctl.env 2>/dev/null; "
                f"printf '{program}' | marathon-touchctl -")
        elif recipe[0] == "swipe":
            _, x1, y1, x2, y2, min_diff = recipe
            program = (
                "tap 1 1\n"
                "sleep 150\n"
                f"swipe {x1} {y1} {x2} {y2} 22\n"
            )
            drv.ssh(
                ". /tmp/marathon-touchctl.env 2>/dev/null; "
                f"printf '{program}' | marathon-touchctl -")
        else:
            print(f"     FAIL  unknown recipe verb {recipe[0]}")
            fails += 1
            busctl_close(drv, app_id)
            continue

        # Press-state feedback animates ~120-200 ms; persistent state
        # changes (digit added to display) need a bit longer to settle
        # the binding propagation.
        time.sleep(1.5)
        drv.screenshot(f"{app_id}-after")

        delta = pixel_change_fraction(drv, f"{app_id}-before", f"{app_id}-after")
        if delta >= min_diff:
            print(f"     OK    delta {delta*100:.2f}% ≥ {min_diff*100:.2f}%")
        else:
            print(f"     FAIL  delta {delta*100:.2f}% < {min_diff*100:.2f}% "
                  "(input produced no visible change)")
            fails += 1

        # Crash check after interaction — the recipe shouldn't kill the runner.
        if not app_runner_pid(drv, app_id):
            print(f"     FAIL  app-runner died during interaction")
            fails += 1

        busctl_close(drv, app_id)

    return fails


if __name__ == "__main__":
    print("scenarios are entry points for run_scenarios.py")
    sys.exit(2)
