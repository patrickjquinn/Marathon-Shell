# E-paper display class: compositor policy

Status: implemented in part by [EINK_MODE.md](EINK_MODE.md), which
differs here in three places: the fast waveform starts on input rather
than on a burst of frames, whole-screen changes count toward a clear
budget instead of each clearing, and the theme is ink on paper. The
first device is the Minimal Phone MP01, a 600x800 e-paper panel behind a
Pango CPLD, but this policy must hold for any e-paper panel. Kernel side:
`devices/minimal/mp01/kernel/eink-refresh-api.md`.

## Rule zero: a capability, not a device

The shell behaves as described here because the display is **e-paper**,
never because the device is an MP01. No `DEVICE_ID`, compatible string or
driver name is checked in shell code (DEVICE_OVERLAYS.md seam 1/2).

How the shell learns the display class, in order of preference:

1. **The DRM connector says so.** This needs a future upstream
   `panel type` / EPD connector property. Probe it at output creation,
   as the shell already probes for HDR and VRR capability.
2. **DeviceProfile until then.** The manifest's `[profile]` sets
   `display_technology = "epaper"`, exposed as
   `DeviceProfile.displayTechnology`. The trait cannot be probed before
   the first frame, which is exactly what seam 2 is for. Default: `"lcd"`;
   `"oled"` is the other emissive value.
3. **Refresh controls are probed separately.** The interim kernel ABI is
   a `refresh_mode` and a `full_refresh` attribute on the panel's device.
   Find it by walking from the DRM connector's graph to the panel device,
   or, until that link exists, from a profile path
   (`epaper_control = "/sys/bus/i2c/devices/7-004b"`). The shell then
   depends on the attribute names only. A panel with the class but no
   controls still gets the rendering policy, and simply never triggers a
   refresh.

## What changes when `displayTechnology == "epaper"`

### Motion

- `MMotion.reduceMotion` is forced on, and the user toggle is hidden.
  Every animation already collapses to 0 ms or a cross-fade under it; on
  e-paper a cross-fade is also wrong (see the next point).
- **No opacity ramps.** A fade becomes several partial updates through
  grey levels, which turns into ghosting. Under the e-paper class,
  cross-fades become a cut. This needs one new switch next to
  `reduceMotion` (`MMotion.instant`) for the few places that fade even
  under reduceMotion: the lock-screen settle, the quick-settings open
  ramp and the charging overlay.
- No blinking caret: steady, or toggle at 1 Hz at most. No spinners: use
  a static "working" glyph or a progress bar that steps in coarse
  increments, about 10%. No marquees, no animated wallpapers, no
  pulsing indicators.
- Swipe gestures follow the finger in `fast` mode (see Refresh
  scheduling) and snap to their end state instead of easing.

### Rendering

- **Damage, always.** Submit tight `FB_DAMAGE_CLIPS` for every commit.
  This CPLD diffs frames itself, but a host-side EPD controller can only
  pick per-region waveforms from damage, and tight damage keeps the
  shell honest about what changes.
- **Do not redraw what did not change.** Clocks and status icons update
  only when their value changes. The status-bar clock drops seconds and
  updates once a minute, aligned to the minute.
- **Frame pacing.** Commit on change only, with no continuous vsync-driven
  repaint. At most one commit per refresh period while something is
  moving: the panel cannot show 60 Hz, and every extra frame is a
  partial update that adds ghosting.
- **Monochrome-safe theme.** The panel has about 16 grey levels and
  nothing finer. Use a high-contrast light theme and no translucency or
  glass. Thin hairlines may disappear on this panel. Whether the class
  needs a heavier minimum stroke or text weight is an open design
  question, to be settled on the device with screenshots. The thin
  weights are deliberate, so do not change them by default.
- **Dithering.** Images and video go through ordered dithering to 16
  levels in the compositor, ideally in a shader on the final composite.
  Untreated gradients band and then ghost.

### Refresh scheduling (the controller)

There are four modes, named for what they do: `quality`, `clean`, `text`
and `fast`. They map onto whatever the panel offers. The policy is a small
state machine in the compositor, driven by what it renders:

- **Resting mode** is the user's choice, `quality` by default, from
  Settings > Display.
- **Moving:** when the compositor commits more than N frames in a short
  window (LuneOS uses 6 frames in 250 ms), switch to `fast`. When it has
  committed nothing for about 1 s, switch back to the resting mode. On the
  MP01, switching between `quality`, `text` and `fast` is silent, while
  switching into `clean` flashes twice. So the moving/resting pair must
  never include `clean`.
- **Rate limit:** at most one mode change per 200 ms, which is stock's rule.
  A change requested inside the window is applied when the window expires.
  It is not dropped.
- **Full refresh (clear)** happens on whole-screen content changes, not
  on a timer:
  - unlock, and the lock screen appearing;
  - app switch, launcher open, and an app's first frame;
  - leaving `fast` after a long scroll (more than about 2 s of motion);
  - the hardware refresh key short press (MP01: keycode 252, handled
    by the shell's key filter, not a daemon);
  - optionally, after K partial updates on an unchanged layout. K is
    user-tunable and off by default.

  Coalesce: one clear per 500 ms at most. Issue it **after** the new
  frame has been committed and scanned out (the page-flip event), never
  before, otherwise the clear wipes the old content and the panel then
  ghosts the new.
- **Video/camera:** while a video surface or the viewfinder is
  fullscreen, lock to `fast` and suppress automatic clears. Clear once
  when it closes.
- **Per-app override:** an app may declare a preferred mode in its
  manifest, for example a reader asking for `quality`. The shell applies
  it while the app is focused.

### Power

- E-paper keeps its picture with no power. Doze turns the panel's
  controller off (DPMS off, so the kernel unprepares the panel and powers
  the CPLD down) as soon as the screen content is final, and the screen
  still shows the last frame. The always-on lock screen is therefore
  free: draw it once, clear, then display-off.
- Before display-off, clear and redraw the final frame in `quality`, so
  that the image left on the panel is clean.
- The frontlight is the backlight device. Blank turns it off, but the
  image stays.

### Input feedback

- Touch feedback must appear within one fast refresh (about 120-250 ms
  on this class). Use an immediate inverted or outlined pressed state,
  drawn in `fast`, instead of ripples.
- Scrolling lists render in `fast`, and a clear is issued once scrolling
  settles.

## Implementation sketch (for later)

- `DeviceProfile.displayTechnology` plus an `EpaperController` service
  (C++) that owns the attribute files, the rate limit, the clear
  coalescing and the moving/resting state. It is fed by the compositor's
  frame-commit and page-flip signals, using `QQuickWindow::frameSwapped`
  only as a fallback. All writes go to the kernel interface; no daemon is
  involved (rules H1 and B12).
- `MMotion.instant` and the theme overrides are keyed off
  `displayTechnology`.
- Settings > Display gets a "Refresh" section (mode, auto-clear) when
  the class is `epaper`.
- When the upstream KMS property exists, the controller sets the mode in
  the atomic commit instead of writing sysfs. Nothing above it changes.
