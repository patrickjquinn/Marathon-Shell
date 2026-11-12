# Interface excellence audit: shell and UI framework

2026-11-12. Audit of the shell (`shell/qml`, `shell/src`), Marathon.Silica (`marathon-silica/`) and the Keel fork's
Silica (`keel-silica/silica/`, marked **fork**) against *Design Techniques for Interface Excellence* (40 techniques).
Read-only. Claims marked ✔ were re-checked by hand against the code; the rest come from the four discipline audits
and carry `path:line` evidence.

## Scorecard

| Area | Meets | Partial | Misses | Headline |
|---|---|---|---|---|
| Easing and timing | 1 | 7 | 1 | Tokens are good; only 58 of 193 shell durations use the reduce-motion-aware helpers; ease-in on app close |
| Spatial continuity | 3 | 4 | 2 | Launch morphs from the icon; closing never returns to it |
| Choreography and manipulation | 0 | 9 | 1 | GestureTracker is excellent; one-off drags, rubber banding and re-grab lag behind |
| Typography | 2 | 4 | 1 | Spec, MTypography and the rendered face disagree; no long-form measure or leading |
| Colour | 0 | 2 | 2 | HSV ambience highlights; light ambiences fail AA; glass cards fail on bright wallpapers |
| Layout and interaction | 1 | 5 | 1 | Silica controls are physically small, especially on the Q25; toggles not optimistic |

What is already right and should be kept: `GestureTracker` (1:1 tracking, velocity-carrying critically damped spring,
re-grab via `press()`), the launch shared-element zoom from the icon/card (`WindowOrigins`), minimise into the switcher
card, splash→first-frame overlap, QS over-pull resistance, keyboard keys with no press animation, kerning left on,
optically centred play glyphs, the backdrop glyph polarity flip at WCAG luminance 0.179, a flat searchable Settings.

## Ranked fixes

Ordered by user impact per unit of work. Device cost is safe on the Q25 (Mali-G57) and L5 (etnaviv) unless noted.

### 1. Exits: go where the app went (revised)
The checklist's "close back into the trigger" does not map onto Marathon's model. Back at an app's root (`backExit`,
`shell/qml/MarathonShell.qml:3125-3153` ✔) does not close the app: it calls `Tasks.minimizeForegroundApp()`, so the app
lives on as a switcher card, or returns to the app that opened it (`returnTo`). Pill-up already minimises into the card
continuously. Real closes (`closeApp`→`slideOut`, `MarathonAppWindow.qml:570-596`) come from an app quitting or
crashing; users close apps by swiping cards away, which has its own animation. Many launches have no icon on screen
(search, notifications, speed keys, links). So, minor:
- Back-exit: shrink into the switcher card when it is on screen (reuse minimise); a page-pop style move when
  returning to the caller; otherwise keep the quick fade.
- `slideOut` uses ease-in (`InQuad`/`InCubic`, `:579/:587` ✔): change to ease-out.
- Short swipe-up: `resetGesture` springs the dock back while `backExit` shrinks (`MarathonNavBar.qml:334-337`).

### 2. Remove ease-in and everyday bounce
- 12 shell ease-in sites: app close (above), `SystemHUD.qml:132`, `PowerMenu.qml:246/254/262`,
  `WiFiPasswordDialog.qml:301`, `MarathonAppGrid.qml:223`, `ScreenshotPreview.qml:129/166`, `MarathonShell.qml:3207`,
  `ChargingOverlay.qml:142`. Fork: `PageStack.qml:714` (every page pop in every app), `FastScrollAnimation.qml:153`.
- `Easing.OutBack` on the uninstall card (`MarathonAppGrid.qml:618`) and the edit Done pill (`MarathonShell.qml:1466`);
  underdamped springs on the QS slider thumb (`MQSSlider.qml:113-116`, damping 0.35) and `MEntrance` (0.25).
  `docs/UI_DESIGN_SYSTEM.md` §4.1/§8.1 prescribe this underdamping, so change the spec in the same commit.

### 3. Two drag bugs where the object trails the finger ✔
- `shell/qml/components/ShareSheet.qml:110`: `Behavior on y { enabled: !dragArea.drag.active }`, but the MouseArea has
  no `drag.target`, so `drag.active` is always false and the 320 ms tween runs throughout the drag. Use
  `!dragArea.pressed`.
- **fork** `keel-silica/silica/qml/private/SliderBase.qml:106,117`: the `SmoothedAnimation` on the knob and progress
  bar stays on while dragging (`animateValue` is never cleared). Add `&& !slider.drag.active`.

### 4. Touch targets: Silica controls are small on the Q25 ✔
Silica's `pixelRatio` is `dpi/160 × userScale / 2` (`crates/marathon-shell-native/src/ambience.rs:374`), i.e. 1/320 in;
Sailfish tuned 1.0 at ~245 ppi. The Q25 also renders at `force_dpi = 240` on a 295 ppi panel
(`devices/zinwa/q25/device.toml:56-59`). Result on the Q25: IconButton/list rows 5.2 mm, Buttons and notification
actions 4.6 mm, nav-bar buttons 3.9 mm, against 7-7.6 mm targets. The QS slider's hit area is the track ±16 raw px
(`shell/qml/ui/MQSSlider.qml:121-124` ✔), 3.2-3.7 mm on every device, below even WCAG's 3.8 mm floor.
`Constants.touchTargetMinimum` (`shell/qml/core/Constants.qml:115`) exists and is used nowhere ✔.
- Now: make the QS slider MouseArea fill its row; fill the PIN cell (`MCircularIconButton.qml:74`); pad nav buttons
  and Silica controls to `touchTargetMinimum` with `containmentMask`/negative margins (hit area, not visual size).
- Decision for you: the forced 240 dpi is a deliberate density choice for the 720x720 screen. Raising Silica's ratio
  (≈dpi/250) or the Q25's dpi enlarges everything; the hit-area route keeps the density. Validate either at
  `MARATHON_FORCE_DPI` with `scripts/device-snap.sh`.

### 5. Reduce motion should remove motion, everywhere
`dur()`/`durationFor()` only shorten to 80 ms; travel and scale remain (`MMotion.qml:150-152,397-399`); only
`MEntrance.qml:41-47` does it right. The PIN shake ignores it. The fork has zero references, so the setting does
nothing in any Keel app. Add `MMotion.travel(px)`/`startScale(s)` returning 0/1 under reduce motion (keep ~150 ms
fades), and a Theme-level `motionScale` in the fork driven by `MarathonA11ySettings`.

### 6. Contrast: glass cards and light-ambience highlights ✔
- Light ambiences build the highlight in HSV (s 0.65, v 0.5; `ambience.rs:271-277` ✔). On #f5f5f5: teal #2d806b
  4.37:1, yellow #80802d 3.82:1 (both fail AA); blue 10.7:1. Generate it in Oklch (fixed L and C, wallpaper hue; the
  `palette` crate is already a dependency in `theme.rs`) and pass it through `theme.rs` `readable()`.
- Lock-screen and notification glass over bright wallpapers (estimated over "Moos Sunset"): secondary text ~2.2:1,
  primary ~4.4:1. Size `MGlassPlatter`'s tint from `service.brightest` as `KeelAmbienceBackground` does, targeting
  4.5:1 for secondary text (the test only asks 3:1, `tests/ui/tst_keelambiencebackground.qml:78`). Estimate; confirm
  on the device.

### 7. Toggles: optimistic, with visible rollback
QS Wi-Fi/BT/cellular/hotspot keep the old state and pulse until the backend answers; after 10 s the pending state is
dropped silently (`shell/qml/core/SystemControlStore.qml:28-62`); airplane mode has no pending state. Settings'
Wi-Fi/BT switches show neither busy nor failure (`apps/settings/pages/WiFiPage.qml:91-98`,
`BluetoothPage.qml:136-143`). Flip to the target immediately, keep the pulse, and on failure revert with a toast
(generalise the hotspot path, `SystemControlStore.qml:65-72`).

### 8. Re-grabbing moving surfaces
QS drags start from the target height, not the drawn one, so the shade jumps on re-grab
(`MarathonShell.qml:2257`, `MarathonQuickSettings.qml:131`): seed from `drawnHeight`. The minimise dock runs a fixed
`NumberAnimation` that ignores the pill (`MarathonShell.qml:1866,2133-2143`): drive it with a GestureTracker.
`MHubRow` does not stop `snapBack` on press (`ui/MHubRow.qml:345-360`). Hub rows, toasts and ShareSheet dismiss on
distance only: use GestureTracker `release()`/`settleTo()` with velocity.

### 9. Rubber banding
Hard stops on the switcher (`MarathonTaskSwitcher.qml:247`), QS scroll (`:385`), Search, Hub weather; the fork's
SilicaFlickable is `StopAtBounds` without a pulley. Put QS's resistance curve (`dim - dim/(d*c/dim+1)`) in
`GestureTracker::move` and use `DragAndOvershootBounds` in those views and the Marathon.Silica flickable wrapper.

### 10. Stable lists (layout shift)
Wi-Fi APs re-sort by strength (`network.rs:947`) every 30 s scan (`:1045`) into a Repeater over a JS array, rebuilding
every row (`WiFiPage.qml:185-187`); "Connecting…"/"Pairing…" rows push the list down. Use a keyed ListModel, freeze
order while the page is open, reserve a slot for status rows.

### 11. Timing and frequency clean-ups
- Fork page push/pop 400 ms (`PageStack.qml:131` ✔) and `DockedPanel` 500 ms: set both to ~300.
- Lock-screen chevron loops 800 ms ×2 ×3 on every wake (`MarathonLockScreen.qml:879-890` ✔), ~4.8 s of full-screen
  redraw: run once, or only after a failed swipe.
- 29 animations have no easing (Linear) and 57 durations are literals; add a strong ease-out token
  `[0.23, 1, 0.32, 1]`. The six Bezier roles return `Easing.Bezier` but `easingCurveFor()` has no callers ✔, so the
  `hero` and `sheet` users run without their curve.
- Exits: add `exitFactor: 0.8`; symmetric Behaviors today (ShareSheet 320/320, KeelDialogLayer 240/240).
- PIN dot 1.3× pop on every digit; QS tile press scale 0.92 (use 0.96-0.97); app-grid stagger uncapped
  (`index*20`, OOBE `index*30`, up to ~720 ms): cap at ~200 ms.
- Quick taps on app icons (<100 ms) show no press state: copy BackgroundItem's `tapFlash` into IconCell.

### 12. Typography
- Settle the face: the spec says "Slate" (`docs/UI_DESIGN_SYSTEM.md:121`), `MTypography.qml:30-47` says Sora, and
  Source Sans 3 Light renders (fork `config.rs:330`, `marathon-fonts/60-marathon-sail-sans.conf` ✔). Sora (592 KB)
  is used only by the boot handover text. Use Regular, not Light, at `fontSizeSmall` and below.
- Long-form text (Legal, notification bodies, TextSwitch descriptions): `lineHeight: 1.1` and cap width at ~34 em;
  `PermissionDialog.qml:14` documents lineHeight 1.5 and never applies it.
- Tabular figures: the lock clock and call timer have no `tnum` ✔. Harmless today (Source Sans 3 digits are
  equal-width, and it has no `tnum` feature), but a switch to Sora (proportional digits) would make them jitter.
- Tracking: −2% on the huge lock clock, +2% on 11-12 px badges. Widows: NBSP before the last word of headings.

### 13. Accessibility and affordance
MHubRow has no Accessible role/name and swipe is the only way to dismiss a notification (no button, hint or a11y
action). OSK keys are unnamed; QS tiles, notification actions and the app grid aren't keyboard-focusable; 71 shell
files import raw `Sailfish.Silica` and bypass Marathon.Silica's accessible wrappers. On the Q25, trackpad gesture mode
never moves focus. ComboBox commits on Up/Down while closed and exposes no expanded/selected state. **fork** Keel's
Button, Switch, Slider, ComboBox, ListItem, MenuItem and ContextMenu have no Accessible properties.

### 14. Lower priority
Arcs (give the launch Translate's x and y different curves: free); QS tile glyph cross-fade (opacity only; skip the
blur, a MultiEffect layer per tile is too costly on both GPUs); masks (keep `clip`/`WindowTextureItem.radius`, not
MultiEffect); Weather gradients in Oklab; safe areas (no device has cutouts yet; add `corner_radius`/`cutouts` to
`device.toml` when one does); first-use hints for the Hub edge peek and pill-right forward.

## The spec needs updating too

`docs/UI_DESIGN_SYSTEM.md` contradicts the checklist and the code in places: §4.1/§8.1 prescribe underdamped bounce on
everyday UI; §4.2 describes a ~600 ms push through `MStackView`/`pushStiffness`, which don't exist; §4.4 defines
reduce motion as "shorten to 80 ms" and cites a missing `ease(token)`; §8.1 requires scale on every interactive
surface while Silica controls only highlight; the typeface (§ line 121) and text colours (#9a9a9a vs #bababa) are
stale; `MSpacing.touchTargetMin` doesn't exist. Change the spec with the code, or the drift returns.

## Status (2026-11-12, feat/q25-batch-1)

Done, in the order agreed (each a commit or two; tests, build and lint pass; not yet seen on a device):
1. Drag bugs: share sheet and slider knob track the finger.
2. Touch targets: Button/IconButton/SecondaryButton and circular buttons reach 7 mm of the real panel by hit area;
   PIN keys take their cell; the QS slider takes its row. `Constants.touchTargetMinimum` is now physical.
3. Ease-in removed from 12 shell exits and the fork's page/fast-scroll fades; OutBack removed from everyday UI.
   Measured: Qt `SpringAnimation` damping is not a ratio; the "underdamped" roles do not overshoot, and
   MEntrance's stiffness-1/damping-1 fade took over 2 s (now a timed fade). Spec §4.1 corrected.
4. Reduce motion: launch and close fade without travel, the PIN pad stops shaking, apps swap pages in place.
5. Contrast: light-ambience highlights reach 4.5:1 at every hue (Oklch); glass tint deepens with wallpaper
   brightness to keep #bababa at 4.5:1 (glass reads darker over bright wallpapers).
6. QS and Settings Wi-Fi/Bluetooth/cellular/hotspot/flight switches flip at once and say if they fail.
7. Shade and notification rows can be caught mid-motion.
8. Rubber banding on the switcher, Hub filters and search results.
9. Wi-Fi and Bluetooth rows keep their places while the page is open.
10. Timing: fork page/panel 300 ms; stagger capped at 200 ms; 20% shorter sheet/dialog exits; no linear UI
    animations; chevron bobs once; quick-tap feedback on icons; QS press 0.96; no PIN-dot pop.
11. Typography: Legal measure and leading, permission dialog leading, tabular lock clock and call timer,
    tighter display clock; spec and MTypography name Source Sans 3.
12. Accessibility: named keyboard keys; keyboard-focusable QS tiles; notification rows readable, Return to
    open, Delete to dismiss.

Left, with reasons:
- Nav-bar button height (3.9 mm on the Q25): only a taller bar can fix it; that is the density decision.
- List rows, switches and chips keep their hit areas: neighbours sit edge to edge.
- Minimise mid-flight re-grab: lands within 300 ms; catching it means undoing the switcher handoff.
- Short swipe-up dock/exit overlap, and exiting into the switcher card: no safe small fix; needs a design pass.
- QS scroll rubber band: its end starts the shade-close drag.
- Light weights for small text: Sailfish's look; a design call.
- Q25 trackpad focus navigation, visible notification dismiss control, safe areas, Weather gradients in Oklab,
  arcs and blur crossfades: not started.
- Pre-existing, seen while testing: Marathon.Silica `Tabs::test_titlesShrinkToFitBeforeScrolling` fails at the
  batch's base too; two test-stub warnings (`UIStore.openSearch`, `HAVE_WAYLAND`).

To check by eye: glass darkness over bright wallpapers, PIN/QS/slider hit areas, the shorter exits and page
transitions, the light-ambience highlight colours, and reduce motion on and off.
