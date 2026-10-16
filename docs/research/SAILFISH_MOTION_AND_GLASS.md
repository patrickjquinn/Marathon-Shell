# Sailfish motion and glass: research and plan

Research of 2026-10-15. The question: why Sailfish OS reads as glassy and alive
while Marathon (on Keel's Silica port) reads as flat and lifeless, which of
Sailfish's mechanisms are public, and what Marathon should change.

**Policy: ideas and constants are taken; code is not copied.** Every file cited
below is read for its mechanism and numbers only. Nothing LGPL or BSD is pasted
into this repo; Keel's own BSD ports stay in Shipwright.

## 1. Sources

| Key | Source | Commit / version | Licence | Used for |
|---|---|---|---|---|
| L | [sailfishos/lipstick](https://github.com/sailfishos/lipstick) | `28f86bd5` | LGPL-2.1 | Compositor: window textures, gestures, touch, frame pacing |
| M | [dm8tbr/sailfishsilica-qt5](https://github.com/dm8tbr/sailfishsilica-qt5) (2014 mirror) | `10d400ee` | BSD files only (94/95) | Older Silica QML. `PanelBackground.qml` there has no licence header, so it is excluded |
| U | Shipwright `keel/silica/upstream/sailfishsilica-qt5-1.2.156/` | Shipwright `6e194e7e` | BSD (Jolla) | Pristine Silica QML from SFOS 5.2.0.15 (`sailfishsilica-qt5` 1.2.156-1.37.1); provenance in `keel/silica/PROVENANCE.md` |
| K | Shipwright `keel/silica/` (Keel's port) | `6e194e7e` | MIT (Keel code) + BSD (ported QML) | What Marathon actually runs: 133 ported QML files, 39 verbatim, Qt 6 syntax edits only |
| G | [nemomobile-ux/glacier-home](https://github.com/nemomobile-ux/glacier-home) | `df8ffad3` | MIT (Jolla copyright headers) | Open QML home on Lipstick: gestures, shader windows |
| A | [AsteroidOS/asteroid-launcher](https://github.com/AsteroidOS/asteroid-launcher) | `0ba0eb50` | BSD | Open QML home on Lipstick |
| N | [sailfishos/ngfd](https://github.com/sailfishos/ngfd) | `3372625b` | LGPL-2.1 | Haptic event table |
| F | [sailfishos/qt-mobility-haptics-ffmemless](https://github.com/sailfishos/qt-mobility-haptics-ffmemless) | `9774ad58` | LGPL-2.1 | ffmemless effect backend |
| H | [mer-hybris/qt5-qpa-hwcomposer-plugin](https://github.com/mer-hybris/qt5-qpa-hwcomposer-plugin) | `31f4f650` | LGPL-2.1 | vsync and update timing |

**Not open** (not read, not used): `lipstick-jolla-home-qt5` (Jolla's home,
switcher, events view, blur), Silica's C++ plugin (`libsailfishsilicaplugin.so`:
Theme, GlassItem, the private item types), Silica's `qmldir` and
`plugins.qmltypes`. The SFOS community meeting of 2026-10-15
([agenda](https://forum.sailfishos.org/t/34402),
[minutes](https://irclogs.sailfishos.org/meetings/sailfishos-meeting/2026/))
and the 2026-10-29 agenda thread ([t/35051](https://forum.sailfishos.org/t/35051),
as of 2026-10-15) announce no new open-sourcing of either.

So Sailfish's "glass" is not a public blur shader: in the open parts it is
translucency over a pre-blurred ambience wallpaper plus a highlight tint.

## 2. Mechanisms

### Glass

| Mechanism | Constants | Where |
|---|---|---|
| Apps draw no blur; they are translucent and the compositor paints the pre-blurred ambience wallpaper behind | — | U `ApplicationWindow.qml:83-100,183-201` |
| PanelBackground: vertical gradient of `highlightBackgroundColor` | 0.15 → 0.3 opacity | U `PanelBackground.qml:60-63`; DockedPanel's only background U `DockedPanel.qml:74-76` |
| DialogHeader band: transparent rect + `dialog.background` (null by default) + same tint | — | U `DialogHeader.qml:107-146`, U `PageStack.qml:115` |
| Highlight backgrounds are always ~0.3 opacity | `highlightBackgroundOpacity` ≈ 0.3 | U `BackgroundItem.qml:42`, `ContextMenu.qml:392-395`, `PullDownMenu.qml:92-101` |
| Dimmed content fades | to 0.4 | U `ApplicationWindow.qml:319-320` (Keel matches) |
| Highlight colour: hue, full saturation, value 0.9 (matches Jolla "water" #7ff0fe → #00cde7) | — | K `plugin/src/palette.rs:171-182` |
| Blur: cache a quarter-res blurred wallpaper once per change, never live | — | G compositor shaders; L has no blur shaders |

### Motion

| Mechanism | Constants | Where |
|---|---|---|
| Page drag follows the finger 1:1; snap duration scaled by remaining distance; edge shadow | commit `itemSizeMedium`; base 400 ms; shadow opacity `min(opacityHigh, |offset/width|·0.7)` | U `PageStack.qml:123,316-325,645`; U `private/PageEdgeTransition.qml:82-84` |
| Page push/pop | XAnimator 400 ms InOutQuad | U `PageStack.qml:118,880-925` |
| Ambience change cross-fade | 600 ms delay timer; 400 ms fade out/in InOutQuad; wallpaper cross-fade | U `ApplicationWindow.qml:230-283,521-566` |
| Overscroll: content opacity falls with bounce distance, recovers | `0.4 + 0.6·(1 − d/2xl)^1.5`; back over 200 ms | U `private/BoundsBehavior.qml:37-58` |
| Switch glow | 50 ms (450 ms busy) InOutQuad; 500 ms pulse | U `Switch.qml:69-123` |
| Press feedback | 48 ms delay, ≥ 64 ms hold, no fade | U `BackgroundItem.qml:41-86` |
| Flick limits | decel `1500·ratio`; max velocity `5000·ratio`, or 11250 when ratio is exactly 1.5 (Jolla's 7500·1.5) | K `plugin/cpp/theme.h:205-206,320` |
| Already identical in Keel | page 400 ms; context menu 200 ms; remorse 4000 + 200/150/150 ms; scroll decorator 300/2000 + 400 ms fade; DockedPanel 500 ms OutQuad, dismiss `min(size/3, dp(90))`; slider 300 ms; busy 2000 ms; fades 200 ms InOutQuad; add/remove 150 ms | K vs U |
| Edge gesture: 1:1 follow, clamped; app opacity fades with progress; 200 ms OutQuint commit/cancel | edge 20 dp; commit 0.15·min(W,H); lock 0.25·min(W,H) | G `src/qml/compositor/ScreenGestureArea.qml:34-134`, G `src/qml/GlacierCompositor.qml:133-321`, A `src/qml/compositor/compositor.qml:109` |
| Settle animations stop on press (finger catches a moving surface) | — | G `GlacierCompositor.qml:162-166` |
| Launch zoom from the icon (scale, not width/height), icon pulse until first commit | 300 ms; `isLaunching` 5 s fail-safe | L `src/components/launcheritem.cpp:371-380` |

### Compositor

| Mechanism | Detail | Where |
|---|---|---|
| Zero-copy live window textures | `WindowPixmapItem` samples the client buffer via `textureProvider()`; crop/zoom via texcoords | L `src/compositor/windowpixmapitem.cpp:1032,474-479` |
| Rounded corners without MSAA | opaque octagon body + 4 smoothstep-blended corner triangles | L `windowpixmapitem.cpp:481-545,302-313` |
| Windows survive exit for close/minimise animations | delayed removal while referenced; on unmap, copy the buffer once into a cover-size FBO | L `src/compositor/lipstickcompositorwindow.cpp:208-219`; L `windowpixmapitem.cpp:1072-1097` |
| Touch interception | after TouchBegin the client gets moves directly; when the shell steals a gesture, `wl_touch.cancel` | L `lipstickcompositorwindow.cpp:273-295,424-440,499-513` |
| Frame pacing | frame callbacks after each compositor render; hidden clients throttled to 1 Hz | L `src/compositor/lipstickcompositor.cpp:117,691,977-995` |
| vsync | update delivered 5 ms after vsync; vsync on demand with 50 ms timeout | H `hwcomposer/hwcomposer_backend_v20.cpp:439-483` |
| Wake touch hygiene | block touch 100 ms on wake; eat events until a fresh TouchBegin | L `src/touchscreen/touchscreen.cpp:82-102,207-218` |
| Shader effects fed straight from the Wayland item | `setPaintEnabled(false)` on the source | G `src/qml/compositor/WindowWrapperMystic.qml:36-63` |

### Haptics

ngfd `data/plugins.d/50-ffmemless.ini:67-135` (rumble, via F onto evdev
FF_RUMBLE, the same path as the L5 vibrator):

| Event | Duration | Magnitude |
|---|---|---|
| touch | 40 ms | 24000 (weak 20000, strong 30000) |
| release | 20 ms | 24000 |
| drag_start | 20 ms | 25000 |
| drag_fail | 25 ms | 25000 |
| drag_boundary | 30 ms | 25000 |
| drag_end | 40 ms | 25000 |
| short | 80 ms | 24000 |
| strong | 80 ms | 65535 |

Fire `drag_start` when a gesture crosses its commit threshold.
`pulldown_highlight`/`pulldown_lock` are already mapped
(`shell/src/services/ngfevents.h:22-23`).

## 3. Marathon audit (2026-10-15)

### Systemic causes

| # | Finding | Where |
|---|---|---|
| S1 | **Every MMotion bezier is 4 values, which Qt runs as linear.** Qt needs 6-value groups ending `1, 1`. Probe at t = 0.3: 4-value 0.300, 6-value 0.645. The "modal" overshoot never overshoots | `shell/qml/theme/MMotion.qml:97,112,172-232`; users `MarathonAppWindow.qml:450-457`, `MarathonShell.qml:1654-1662`, `NotificationToast.qml:230-243`, `ConnectionToast.qml:105`, `ErrorToast.qml:164`, `MRipple.qml:45` |
| S2 | Predictive back: `backProgress` computed, nothing drawn; `back*` tokens unused; UI_DESIGN_SYSTEM.md:54 promises 1.0 → 0.9 | `MarathonNavBar.qml:340-344`, `MMotion.qml:90-109` |
| S3 | No springs in chrome; `snapIntoGrid` "spring" is a NumberAnimation | `MarathonShell.qml:1621,1644` |
| S4 | No velocity handoff: single-sample `Date.now()` velocity, fixed 240/260/300/350 ms OutCubic settles | NavBar, Peek, switcher |
| S5 | Grid entrance stagger is a no-op (PauseAnimation inside ParallelAnimation) | `shell/qml/ui/MEntrance.qml:72-77` |
| S6 | No ListView/GridView add/remove/displaced transitions anywhere | — |
| S7 | No origin rect for launch or restore | `MarathonAppGrid.qml:217`, `TaskCard.qml:170` |
| S8 | `MARATHON_PRESENT_PIPELINE` (frame callbacks) default off (~15 fps client scroll per its own comment); wp_presentation not wired | `shell/src/wayland/waylandcompositor.cpp:243-249` |
| S9 | Flick max velocity `5000·ratio` on Marathon's ratios (≠ 1.5): ~33% slower than Jolla's 7500·ratio | K `theme.h:206` |
| S10 | oneplus6 sets `QT_QUICK_BACKEND=software` globally, so Keel disables pulley glow, context-menu effect, opacity ramps, modal panels | `packaging/packages/device-oneplus-enchilada-marathon/50-gpu-acceleration.conf:23` |
| S11 | 23 distinct durations, 3 overlapping ladders, ~60% literals; Behaviors with no easing (QS scrim, pill width, nav icon colours, bottom bar width) | shell QML |
| S12 | Haptics fixed full magnitude, 10/25/50 ms only, none at gesture thresholds; no UI sounds | `shell/src/managers/hapticmanager.cpp:103-159` |

### Glass: the "teal slab"

`marathon-silica/Marathon/Silica/DialogHeaderBackdrop.qml:17-18` puts opaque
`overlayBackgroundColor` (#0a0a0f) under the DialogHeader band, the flat dark
wallpaper (`KeelAmbienceBackground.qml`) gives the tint nothing to frost, and the
saturated green-cyan highlight is loud. Fix: the backdrop becomes a crop of the
blurred `image://keelambience` wallpaper, and the default wallpaper gets
texture. `marathon-silica/.../PullDownMenu.qml:11-12` passes a solid colour
while active where Silica uses 0.3 (visual check needed).

### Interactions

| Interaction | Today |
|---|---|
| Launch | from screen centre, 0.92 → 1 over 240 ms (linear, S1); splash → app hard cut (`MarathonAppWindow.qml:329`); home hidden instantly (`MarathonShell.qml:595`) |
| Back | only the pill moves; `backExit` 0.9 + fade 180 ms fixed (`MarathonShell.qml:2450-2472`); in Keel apps, pill-left is a plain `pageStack.pop()` (`marathon-silica/.../ApplicationWindow.qml:27-40`) |
| Minimise | tracked scale 1 → 0.65 + opacity about centre (good); card frame fades in at 30% and enables a full-screen layer mid-gesture (`:1433`); ends in a pop (`:1629-1642`) |
| Switcher | close × only; neighbours teleport (`TaskCard.qml:101-128`); restore from centre; velocity bug `MarathonTaskSwitcher.qml:72` (`Date.now() - startY`) |
| Pager / pill | pager flat 180 ms; pill down → QS untracked (`MarathonNavBar.qml:403-410`); right canned; pill settle 240 ms OutCubic; hold → Pilot halo good |
| Peek | progress snaps on release, only x animated (`MarathonPeek.qml:46-102,316`); `Logger.info` per move (`:43`) |
| Quick settings | drag 1:1 good; release 300 ms without velocity (`MarathonShell.qml:1688-1699`); scrim pops (`:1802`) |
| Lock | opacity only; SmoothedAnimation lags the finger (`MarathonLockScreen.qml:219,860-905`); unlock → home instant (`MarathonShell.qml:617-626`) |
| Keyboard | hide pops; relayout per frame (`VirtualKeyboard.qml:16-22`, `MarathonShell.qml:1468`) |
| Other | Pilot glow static; `KeelDialogLayer` not animated; first page push stutters because QML recompiles every launch |

**Keep:** tracked QS shade + rubber-band, tracked peek, minimise scale tracking,
Pilot halo, pager nudge, live Keel covers, cached backdrop blur.

## 4. Plan

Status as of 2026-10-16 (shell r435, verified on the HackberryPi CM5 with injected touches and scanout captures; flips at 60 fps). Status is maintained by the lead. Constraints for every item: works on all
device profiles (differences only via DeviceProfile keys); no `layer.samples`
(etnaviv MSAA trap); no per-frame z/visible churn (Qt stacking walk); GLES2 on
etnaviv/lima.

### Tier 1: correctness (cheap, systemic)

| # | Item | Basis | Status |
|---|---|---|---|
| 1.1 | 6-value bezier curves in MMotion and every caller | S1 | done |
| 1.2 | Fix MEntrance stagger (sequential pause per delegate) | S5 | done |
| 1.3 | Velocity from a ~60 ms sample window; fix switcher `Date.now() - startY` | S4, Glacier | done |
| 1.4 | Easing on the bare Behaviors; collapse duration ladders onto MMotion tokens | S11 | done (bare Behaviors; ladders not yet collapsed) |
| 1.5 | Drop per-move `Logger.info` in Peek | Peek | done |
| 1.6 | Haptic ticks at gesture commit thresholds with ngfd's durations/magnitudes | §2 Haptics, S12 | done (tick tier; light/medium/heavy unchanged) |

### Tier 2: tracked gestures

| # | Item | Basis | Status |
|---|---|---|---|
| 2.1 | Predictive back visual (1.0 → 0.9 scale + edge shadow, distance-scaled snap) in the shell | S2, PageStack | done |
| 2.2 | Settles seeded with release velocity (spring, or duration = remaining/velocity); press stops a running settle | S3, S4, Glacier | done (GestureTracker) |
| 2.3 | Minimise into the card's rect, no mid-gesture layer flip, no end pop | Minimise | done |
| 2.4 | Launch/restore from the icon/card rect (scale), splash → app cross-fade, home fades | S7, launcheritem | done |
| 2.5 | Pill down → QS tracked; QS release with velocity; scrim fades | QS | done |
| 2.6 | Peek release with velocity, progress animated | Peek | done |
| 2.7 | Lock follows the finger 1:1; unlock reveals home | Lock | done |
| 2.8 | Switcher swipe-to-close; neighbours animate (`displaced`) | Switcher, S6 | done |
| 2.9 | Keel back drives Silica's page drag (Keel request 6) | Back | blocked on Keel |

### Tier 3: glass and aliveness

| # | Item | Basis | Status |
|---|---|---|---|
| 3.1 | DialogHeaderBackdrop = crop of blurred ambience wallpaper; textured default wallpaper | Teal slab | done (backdrop); textured default wallpaper awaiting decision |
| 3.2 | PullDownMenu active tint at 0.3 | Teal slab | planned |
| 3.3 | Overscroll opacity curve on shell lists | BoundsBehavior | planned |
| 3.4 | ListView/GridView add/remove/displaced transitions (150 ms, Silica's) | S6 | partial (Hub, switcher) |
| 3.5 | Keyboard show/hide animated without per-frame relayout | Keyboard | done |
| 3.6 | Pilot glow pulse; KeelDialogLayer enter/exit | Other | partial (dialog frosts the app behind; glow pulse and enter/exit not done) |
| 3.7 | Ambience change cross-fade (Keel request 8) | Silica 600/400 ms | blocked on Keel |
| 3.8 | Flick velocity 7500·ratio (Keel request 9) | S9 | done Marathon-side (Marathon.Silica override); Keel request 9 open |
| 3.9 | oneplus6: GPU backend instead of global `QT_QUICK_BACKEND=software` | S10 | planned |

### Tier 4: compositor (structural)

| # | Item | Basis | Status |
|---|---|---|---|
| 4.1 | Zero-copy live window textures (C++ QQuickItem over `QWaylandQuickItem::textureProvider()`) replacing `ShaderEffectSource { recursive: true }` in TaskCard | WindowPixmapItem | done (WindowTextureItem) |
| 4.2 | Rounded corners without MSAA (octagon + smoothstep corners) | WindowPixmapItem | done |
| 4.3 | Frame callbacks after render by default; hidden clients 1 Hz; wp_presentation | S8, lipstickcompositor | done (wp_presentation not wired) |
| 4.4 | `wl_touch.cancel` when the shell steals a gesture | lipstickcompositorwindow | done |
| 4.5 | Hidden-vs-destroyed window split + one-shot cover snapshot on unmap, so close/minimise animate after exit | lipstickcompositorwindow | partial (cover snapshot on close) |
| 4.6 | Wake touch hygiene (100 ms block, eat until fresh TouchBegin) | touchscreen | done |
| 4.7 | Cache precompiled QML so the first page push doesn't stutter | Other | planned |
