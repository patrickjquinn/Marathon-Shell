# Scrolling and frame pacing

Measured 2026-10-19 on the HackberryPi CM5 (V3D, 720x720 at 60 Hz, 100 Hz
EDT touch). The benchmark is Android (Waydroid, LineageOS 20) on the same
device, measured the same way.

## Method

- `scripts/bench/scroll_bench.py` (on the device, as root): the same uinput
  fling for any foreground window (`--dist 160 --fling-ms 100`: 1600 px/s,
  10 ms steps), an optional "catch" touch during the fling, and ftrace with
  `trace_clock=mono`: page flips (`drm_vblank_event_delivered`), v3d render
  jobs per process (`gpu_scheduler:drm_sched_job`), and with `--stall-tid`
  switches and ticks of chosen threads with user stacks.
- `scripts/bench/strip_motion.py` (host): reads a kmsgrab strip captured at
  120 Hz during the bench and reports how far the content moved on each
  displayed frame, so repeated frames and catch-up jumps show, whatever drew
  them.

## Baseline (before)

| | Marathon Settings | Marathon Notes (120) | Android Files (300) |
|---|---|---|---|
| App frames p50 / p99 / max | 16.6 / 18-26 / 33 ms | 16.6 / 25-29 / 30 ms | 16.7 / 19.9 / 20.6 ms |
| Missed vblanks | 0-3 per 200 frames | 1-2 per 140 | 0 |
| Repeated frames per fling (scanout) | 1-2 | 1-5 | 0 |
| Fling from a 1600 px/s finger | 1140-1380 px/s | same | ~2000 px/s |
| Fling length | 1.07 s, 744 px | longer | 0.73 s, 664 px |
| Touch during fling | stops (last frame +15-65 ms) | stops | stops |
| Drag at 500 px/s, steps | 5/10/10 px (judder) | | 5-11 px (judder) |

Shell: compositor flips never missed. During app flings the shell's GUI
thread never ran 4 ms or more (max 1.7 ms) and its render thread max 1.8 ms:
the shell is not the bottleneck while apps scroll. Idle: Hub 0 fps, grid
0 fps, Frames page 60 fps with two GPU jobs per frame. Home pager swipes:
content moved every 33 ms in 3 of 4 swipes, 3-4 repeated frames and 90 px
jumps per swipe, and 3 GUI bursts of 8.5-10.2 ms (task-card setup).

## Causes and changes (branch perf/scrolling)

1. `845c24ca` A Waydroid card's `surfaceTree` layer was live and recursive;
   Qt re-grabs such a layer every frame, so the switcher drew 60 fps forever
   and GUI-driven motion fell to 30 fps.
2. `da429de8` `pageActive` followed `pageView.moving`, so every home swipe
   woke all task cards; it now follows whether the Frames page is on screen.
3. `a659d9bd` Touch: eglfs reads libinput on the GUI thread and stamps events
   with read time; that thread sleeps ~11 ms of each frame in polishAndSync,
   so 100 Hz reports arrived in bursts with equal timestamps, velocity was
   aliased (flings at 0.7-0.85x) and clients (Android too) got bursty
   `wl_touch` times. The shell now reads touchscreens with Qt's evdevtouch
   (own thread, filtered, one point per frame); `71-marathon-touch.rules`
   hides them from libinput. Profile keys `TOUCH_FILTER`, `TOUCH_PARAMS`;
   `MARATHON_TOUCH_FILTER=0` switches to unfiltered. Deploy needs
   `udevadm control --reload; udevadm trigger -s input` before the greetd
   restart. Not yet verified on a device.
4. `f0260a3e`, `c425ae66` Flings decelerate at 6300 x pixelRatio and cap at
   Android's 8000 dp/s (Marathon.Silica views and the shell's plain lists),
   within 15% of OverScroller's distance from 2000-6000 px/s. Keel unchanged.
   `tst_fling` covers press-to-stop and stopping at either end.
5. Blocking work on the GUI thread made asynchronous or moved off it:
   settings file sync (`3080d10f`), brightness (`3d43dcf7`), Wi-Fi scan
   (`dc0e5ede`), Bluetooth poll and calls (`7e86c4eb`), notification
   database fsyncs (`71c8fe60`), cpufreq boost writes (`8c86e422`), desktop
   entry rescans (`cdbb31cb`), UPower (`d6476660`), GeoClue (this commit).

## Next steps

- Re-measure with the bench after deploy: pager cadence, idle Frames page,
  fling velocity and drag steps with evdevtouch; then fill in the "after"
  column here.
- Remaining blocking calls from the audit: ModemManager state queries (about
  15 Gets per signal change, Librem 5), iio light polling, faillock QProcess
  on a wrong PIN, wake-path `msleep(30)` and logind Inhibit, per-call
  `servicePid` lookups, `/proc/<pid>/maps` on the first back gesture, a new
  QSettings per launch.
- Repeated frames at gesture start in Marathon apps (clients render 2-3
  frames in one vblank after idle).
- Notes rows: ContextMenu created per row, Fade labels as layers, preview of
  the whole note body; Marathon.Silica is not compiled with qmlcachegen.
- The shell keeps rendering ~850 ms after each app touch ends; find what
  animates.
- Qt's per-polish stacking-order walk (see the memory note) still needs a
  qtdeclarative patch.
