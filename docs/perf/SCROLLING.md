# Scrolling and frame pacing

Measured 2026-10-19 on the HackberryPi CM5 (V3D, 720x720 at 60 Hz, EDT
touch at about 43 Hz; the first rounds' uinput bench sent 100 Hz). The benchmark is Android (Waydroid, LineageOS 20) on the same
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

## After (shell r479 from this branch, same bench)

Move-to-motion: `--pre-ms 200 --dist 300 --fling-ms 600` (500 px/s after a
200 ms rest); the delay runs from the first move to the first scanout frame
that moved, so it includes the 10 px drag threshold.

| | Before | After | Android Files (after) |
|---|---|---|---|
| Home pager drag cadence | 30 fps, steps 20/40/60/80 px | 60 fps, even 35 px | |
| Pager repeated frames per swipe | 3-4 | 1-2 (at the release snap) | |
| Pager move-to-motion | 70-114 ms | 87-137 ms | |
| Frames page idle | 60 fps, 2 GPU jobs a frame | 0 fps | |
| Shell GUI bursts in pager swipes | 3 x 8.5-10.2 ms | none over 3.4 ms | |
| Settings drag step change (lower = smoother) | 3.3-5.7 px | 0.8-2.3 px | 2.8-3.2 px (was 5.4-6.2) |
| Settings move-to-motion | 146-190 ms | 140-206 ms | 143-191 ms |
| Settings fling from 1600 px/s | 1.07 s, long crawl | 0.32 s | 0.73 s |
| Press during a fling | stops | stops | stops |
| Row pressed by a scroll | after 48 ms of rest | not before 100 ms (Android's tap timeout) | |

Touch is read by Qt's evdevtouch in filtered mode without Qt Quick's touch
compression (`7bacc1fa`). The filter's `prediction` is left off: Qt seeds a
new touch's velocity from the previous one with the same id, so a predicted
press could land far from the finger (the pill's swipe up went to the app).

## Fling strength and scroll-start delay (second round)

Kmsgrab frame times now come from `-use_wallclock_as_timestamps`; the
delay grows over a run's four rounds on both systems, so medians are given.

| | Before this round | After | Android Files (same run) |
|---|---|---|---|
| Settings move-to-motion | 140-206 ms | 91-157 ms (median ~132) | 117-147 ms (median ~128) |
| Fling release / finger (1600 px/s) | 0.7x | 0.9x | ~1.0x (27 px a frame) |
| Fling glide | 0.32 s | ~0.6 s | ~0.6 s |
| Press during a fling | stops | stops | stops |

Changes: raw evdevtouch reports applied as they come, without Qt Quick's
touch compression (the Kalman filter mode is `TOUCH_FILTER=1`);
Marathon.Silica flings at the least-squares speed of the content's last
100 ms (Android's VelocityTracker) and decelerates at 3500 x ratio; the
pager's snap duration comes from the release speed. Tried and dropped: an
Android-style resampler at frame time (it halved app frame rates by
scheduling an extra empty sync) and flushing the filtered point into the
frame (apps at 30 fps).

## Tap-through and the home pager (third round)

- A press that stops a moving view only stops it: Marathon.Silica's views,
  the pager, the switcher grid and search carry a `FlingStopper` while they
  move and for 50 ms after a fling ends (the finger came down a frame or two
  before the view saw it). 14 presses 60-350 ms into flings in Settings
  activated nothing; a tap on the resting list opens its page.
- The pager (2000 px/s swipe, scanout meter, 4 swipes):

| | Before | After |
|---|---|---|
| Drag steps | 20/40 px (100 Hz panel on 60 Hz) | 32-36 px |
| Repeated frames, drag and snap | 0-1 | 0 |
| Snap after release | lurch to 140 px a frame | carries on at ~31 px a frame, decelerating to 0 |
| Move-to-motion | 60-88 ms | 61-106 ms |
| Shell GUI bursts | max 3.2 ms | max 1.8 ms |

  Shell items now get one touch move a frame, sampled at frame time minus
  5 ms (`TouchResampler`); touches a client's surface grabbed pass as they
  come. The snap flick starts at the pages' release speed (Qt starts a
  SnapOneItem flick at maximumFlickVelocity). Left: one frame of the snap
  moves about 25% less than its neighbours, as Qt's flick timeline starts at
  the release, mid-frame.

## A real finger, and Pacific's flings (fourth round)

- The HackberryPi's panel reports every 21-23 ms (about 43 Hz), one slot,
  a new tracking id per touch, BTN_TOUCH and no pressure. The uinput bench
  sent 100 Hz. `scripts/bench/touch_trace.py` records a panel passively
  (no grab) and replays it through uinput at the recorded spacing; `--times`
  logs each gesture's first move and lift for the scanout meter.
- Replaying a real finger's trace (9 gestures on home) through the old
  resampler did not stall, but every other frame of a drag had no new
  move: 5 ms latency and 8 ms prediction do not span a 23 ms gap.
- `TouchResampler` now samples half the panel's spacing plus 2 ms back
  (learnt across touches), interpolating, or predicting up to half a
  spacing at the slower of the last two reports' speeds (none across a
  turn). The content never steps back the way the finger goes, nor at the
  lift. On by default; `MARATHON_TOUCH_RESAMPLE=0` turns it off.

| Real-finger replay, 3 runs each | Raw (default) | Resampled |
|---|---|---|
| Move to first motion, median | 159-184 ms | 158-159 ms |
| Repeated frames while dragging | 12-19 | 0-1 |
| Backward steps | 4 | 3 |

  Interpolating a full spacing back was as even but 30-45 ms later;
  predicting from 5 ms, or damping the prediction, stepped unevenly; the
  raw touch until the drag distance, then a growing latency, started later.
- Marathon.Silica takes Pacific's fling rules: release speed over the last
  50 ms, no fling after a 40 ms rest before the lift, and a fling caught
  and flung again the same way adds the caught speed (at least 350 CSS
  px/s, the new one at least half of it, caught no more than 100 ms
  before; carried flings may reach 18000 CSS px/s). Settings, three
  same-way 3000 px/s flicks 150 ms apart: the second glides at about 80 px
  a frame against 45 before (1.8x); the first is unchanged.

## Project Butter's steps (fifth round)

Android 4.1's Project Butter tackled the same lag with vsync-paced frames,
triple buffering, touch prediction and an input CPU boost. Marathon's
versions:

| Butter | Marathon | Commits | Off switch |
|---|---|---|---|
| Vsync pacing | The compositor latches 8 ms after each vblank and sends frame callbacks at the vblank, so a client draws with the newest touch and makes the same flip; the shell's own frames latch at that phase too | 81b75d68, b756094a | `MARATHON_FRAME_PHASE_MS=0` |
| Touch prediction | The shell samples touch at each frame's latch, raw until the drag distance; apps resample theirs at their own frame time in `marathon-app-runner` | c01e70a6, 8a4fa977 | `MARATHON_TOUCH_RESAMPLE=0`, `MARATHON_APP_TOUCH_RESAMPLE=0` |
| Input boost | A 1.5 s CPU floor on input, written off the GUI thread; it rests at `cpuinfo_min_freq`, also after a shell killed mid-boost | 535f4528, 1cfa3271 | |
| Triple buffering | Not needed: apps hold 60 fps here | | |

A drag keeps the finger's point under it from its second move
(`synchronousDrag`, f4f46305; pulley menus fixed in b9055dea). The home
pager does the same (4d30fd29) and snaps from the release velocity with
`flickDeceleration: 12000`, in about a quarter second (c05885c3).
Resampling apps' touch in the compositor was tried and made it worse.

Strip captures now pass `-fps_mode passthrough` to ffmpeg (33029a76).
Without it, duplicated frames skewed the timing, and earlier
move-to-motion numbers, the fourth round's included, read 25-40 ms long.
The meter is now tracking lag: how far behind the finger the content is
once it has moved 50, 100 and 150 px, from a 43 Hz uinput replay.

| Shell 4d1798ae | First motion | Lag at 50 / 100 / 150 px | |
|---|---|---|---|
| Home pager | 67 ms | 51 / 70 / 84 ms | even 10 px steps |
| Settings (Marathon) | 70 ms | 44 / 70 / 85 ms | 0-1% vblanks without motion |
| Material Files (Android) | 69 ms | 77 / 93 / 112 ms | |

A fling leaves at about 0.9x the finger's speed and glides about 0.6 s; a
same-way fling carries the caught speed.

## Next steps

- Qt's Wayland client renders, then waits for the frame callback, then
  swaps (`QWaylandGLContext::swapBuffers`), so an app shows touch a frame
  old; Android samples at frame start and queues at once. Measure
  `QSG_RENDER_LOOP=basic` for apps, or wait before polish instead.
- Cap touch prediction at 8 ms, as Android's InputConsumer does (half a
  43 Hz gap is about 11 ms).
- Latch from measured render time, as KWin does, not a fixed 8 ms.
- Flickable takes a device's own velocity when it advertises
  `QInputDevice::Capability::Velocity`; check resampled events don't.
- Render-thread Animators for fixed transitions (app open, pager settle).
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
