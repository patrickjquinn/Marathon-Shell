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
import os
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
    # Music: tap the "Library" bottom tab. The old target was a
    # chevron-down at (30, 80) that this UI no longer has, so the tap
    # hit dead space and the app read as unresponsive.
    "music":       ("tap", 540, 1287, 0.02),

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
    # Email: the "Sign in with Google" CTA sits at y=828 on the account
    # setup surface, not 750 -- the old y landed in the copy above it.
    "email":       ("tap", 360, 828, 0.01),

    # Browser: tap the URL bar centre — focuses + raises keyboard.
    # Browser: the address bar moved when the bottom bar was rebuilt --
    # it is now centre-left at (313, 1285), with the tab controls to its
    # right. y=1340 was below it, in the home-pill strip.
    "browser":     ("tap", 313, 1285, 0.005),

    # Store: tap the "Apps" bottom tab, which swaps the whole view.
    #
    # It used to swipe the catalog from y=900. The Discover content ends
    # around y=810 and the list is not scrollable when it fits, so the
    # swipe began in empty space and moved nothing. It passed only on
    # runs where enough Flathub cards had loaded to make the list
    # overflow -- i.e. it was measuring the network, not the app.
    "store":       ("tap", 270, 1287, 0.02),

    # Terminal: no recipe. A fresh prompt has no control that repaints a
    # measurable area -- the key row, a body tap and the row chevron all
    # produce the same reading, and typing a character puts one monospace
    # glyph on a 720x1440 canvas. Measured: every candidate came back at
    # 0.02%, which is what the status-bar clock alone contributes when it
    # ticks over mid-capture; a no-op capture measures 0.000%. So that
    # 0.02% was the clock, not the tap, and any threshold low enough to
    # "pass" would pass a dead app too. Driving this properly needs a
    # region-cropped diff over the text area rather than a whole-frame
    # one.
    "terminal":    None,
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

    wake_display(drv)
    fails = 0

    for app_id, recipe in RECIPES.items():
        print(f"  ==> {app_id}")

        if recipe is None:
            print(f"     SKIP  no recipe (QEMU-specific gap; see comment)")
            continue

        # Wake + unlock per app, not once per scenario. Scenario 06
        # restarts greetd on its way out, so 07 meets a FRESH shell whose
        # screenTimeout is back at the default -- the panel then blanks
        # part-way through the pass and every remaining screendump comes
        # back as the same 3.5 KB black frame. Re-asserting per app costs
        # a couple of ssh round-trips and removes the whole class.
        wake_display(drv)

        # Clean slate: the recipes below tap coordinates that assume the
        # app's FIRST page, so a resident instance left on a sub-page
        # would silently invalidate them.
        reset_runners(drv)

        if not busctl_launch(drv, app_id):
            print(f"     FAIL  busctl LaunchApp returned !true")
            fails += 1
            continue

        runners_after_launch = runner_pids(drv)

        # Wait for the app to actually be on screen before touching it.
        #
        # A fixed 2 s sleep was not enough. reset_runners() closes every
        # app first, so each launch here is fully cold, and cold QML
        # under the software renderer can take well past 10 s to reach a
        # first frame -- scenario 03 polls up to 12 s for exactly this.
        # Tapping at 2 s hit the launcher, or a half-built scene, and the
        # before/after frames then differed by ~0.01%, which reads as
        # "the app ignored the input" when the app simply was not there
        # yet.
        #
        # Poll until the frame stops being the pre-launch one, then let
        # it settle. WebEngine apps get longer to finish compositing.
        drv.screenshot(f"{app_id}-prelaunch")
        for _ in range(14):
            time.sleep(1.0)
            drv.screenshot(f"{app_id}-before")
            if frame_delta(drv, f"{app_id}-before", f"{app_id}-prelaunch") > 0.02:
                break
        time.sleep(2.5 if app_id in ("browser", "maps") else 1.5)
        drv.screenshot(f"{app_id}-before")

        # Drive input through the QemuDriver, not marathon-touchctl.
        #
        # This scenario shelled out to marathon-touchctl directly,
        # bypassing drv.tap/drv.swipe. Those deliberately default to the
        # QMP virtio-tablet path because, as qemu_driver documents,
        # marathon-touchctl "is present in the image and exits 0 under
        # QEMU while injecting nothing the compositor ever sees". So every
        # recipe here landed on the right pixel and did nothing: 10 of 11
        # apps reported ~0.01% delta, i.e. "unresponsive", while 04 and 05
        # -- which go through the driver -- passed against the same shell.
        #
        # touchctl remains available on real hardware via
        # MARATHON_USE_TOUCHCTL=1, which drv.tap honours.
        if recipe[0] == "tap":
            _, x, y, min_diff = recipe
            drv.tap(x, y)
        elif recipe[0] == "swipe":
            _, x1, y1, x2, y2, min_diff = recipe
            drv.swipe(x1, y1, x2, y2, steps=22)
        else:
            print(f"     FAIL  unknown recipe verb {recipe[0]}")
            fails += 1
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
        # A runner disappearing across the interaction means the recipe
        # killed the app. Compare counts rather than a specific pid --
        # pool adoption reuses the spare's pid, so there is no stable
        # per-app pid to track.
        if len(runner_pids(drv)) < len(runners_after_launch):
            print(f"     FAIL  an app-runner died during interaction")
            fails += 1

    return fails


if __name__ == "__main__":
    print("scenarios are entry points for run_scenarios.py")
    sys.exit(2)
