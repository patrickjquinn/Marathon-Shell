# Requests to Shipwright (Keel / Pacific)

Things Marathon needs from Keel or Pacific that can't be done cleanly from this
repo. Each has a Marathon-side workaround or gap noted.

## Status (Shipwright's reply of 2026-10-16)

| # | State |
|---|---|
| 1, 6 | Draft protocol on Shipwright's `system-back` branch; Marathon's review below |
| 3, 7, 8, 9 | Released in Keel 0.1.0-32 |
| 2, 4, 5 | Planned (5 after back) |
| 10, 11, 12, 13 | Not started (11: Marathon is moving off the software backend) |

Keel 0.1.0-33 adds `<app-id>/app.show` to every app; it needs keel-shell's
`Activate()` to work under `marathon-keel-host`.

### Review of the system-back draft (PROTOCOL.md 4.3)

- **Progress 0–1 of the page's width: yes.** The pill's travel is shorter than
  the page; the host maps it (full at about 40% of the width).
- **500 ms for an app that never answers: fine for `BackRequested`, too long
  for `BackStarted`.** The finger is already moving when the drag starts and the
  host has to pick a visual (page follows inside the app, or the whole app moves
  aside) within a frame or two. Proposal: the app publishes its back state ahead
  of time, e.g. a `BackState(b pageWillFollow)` signal sent whenever it changes
  (page-stack depth, `backNavigation`, a menu opening, a page with
  `systemBack()`), so the host decides without a round trip. `BackStarted` stays
  for the hand-off and `BackResult` confirms it; the host waits at most about
  100 ms for that, then falls back to moving the app. This also covers
  request 13.
- **Reports during the drag: not needed.** One addition: after `BackCommitted`
  or `BackCancelled`, a `BackFinished(u serial)` once the page's snap animation
  ends, so the host can release the gesture and the pill at the same moment.
- Marathon will send `BackRequested` instead of the Escape it injects today,
  and fall back to minimising on `false` or timeout.

## 1. System back for hosted apps

Keel has no entry point for a host's system back: nothing in keel/silica handles
`Qt::Key_Back`/`Key_Escape`, PageStack only navigates by its own swipe, and
keel/shell/PROTOCOL.md v1 has no Back message. Marathon's back gesture therefore
can't reach Pacific or any Keel app hosted by `marathon-keel-host`.

Proposal: a `BackRequested` call in `org.shipwright.keel.Shell1` (or
`Keys.onBackPressed` on `ApplicationWindow`) with a handled/unhandled reply.
Behaviour: close an open menu; otherwise `pageStack.navigateBack()` when
`currentPage.backNavigation`; a Dialog rejects. Unhandled lets the host minimise.
Marathon would send it instead of the Escape it injects today
(`AppLifecycleManager::handleSystemBack`).

Pacific additionally: treat back as web-history back before popping the page
(`BrowserPage` has `backNavigation: false`).

Marathon today: no back in Keel-hosted apps.

## 2. Closed-pulley indicator opacity

`PulleyMenuBase` draws the closed indicator at full opacity (`_inactiveOpacity:
1.0`, busy pulse between 1.0 and `highlightBackgroundOpacity`), matching
Sailfish, where it sits at the physical screen edge. Hosts with an opaque status
bar draw it mid-screen, where a solid bar reads as an artefact.

Proposal: a public `property real inactiveOpacity` (default 1.0) on
PulleyMenuBase used by the closed branch of `highlightItem.opacity`, the
bounce-back fade target, and the busy pulse (`inactiveOpacity` ↔
`inactiveOpacity * Theme.highlightBackgroundOpacity`). No API break.

Marathon today: tints `highlightColor` while `!active` (d76ba583), which also
dims the first-show hint and narrows the busy pulse.

## 3. Pacific: placeholder over the bookmarks search field

`ViewPlaceholder` places itself at `rotatingItem.height/3 - height/2`
regardless of the list header. BookmarksPage's header (PageHeader + SearchField,
~210 × pixel ratio) overlaps it when height/pixelRatio < ~780, e.g. 720x720.
Fix in BookmarksPage: `verticalOffset: Math.max(0, list.headerItem.height +
Theme.paddingLarge - (list.height/3 - height/2))`, or have ViewPlaceholder stay
below `flickable.headerItem`.

## 4. Pacific: exits started outside the Keel host

D-Bus activation (`org.shipwright.pacific.ui.service`) and generated web-app
launchers start Pacific in Desktop mode, which installs no SIGTERM handler, so
a SIGTERM there skips `aboutToQuit` and the session marker survives ("closed
unexpectedly"). Marathon launches the app itself under `marathon-keel-host`
(Shell mode), which handles this; a SIGTERM handler in Desktop mode would cover
the other paths.

## 5. Pilot's overlay under a Keel host

Pilot's overlay (`shoal/pilot/ui/Overlay.qml`) is made only in Keel's Direct
mode (`createOverlay` in `app/cpp/launcher.cpp` returns null otherwise) and is
marked for Lipstick with `Shell.setLipstickProperty(window, "CATEGORY",
"dialog")`, a no-op outside Direct mode. Under `marathon-keel-host` (Shell
mode) Pilot therefore falls back to its main window's sheet, which comes up as
an app instead of over the app the person was in.

Proposal: in Shell mode, make the overlay too, and mark it the way covers are
marked (PROTOCOL.md section 3): title `keel:dialog` (or `keel:dialog:<name>`)
set before `show()`, for instance by `setLipstickProperty(…, "CATEGORY",
"dialog")` setting that title when not in Direct mode. A host-provided
`KEEL_SHELL_DIALOG_TITLE` could carry the marker as `KEEL_SHELL_COVER_TITLE`
does.

Marathon today: a second top-level window titled `keel:dialog` from an app the
shell launched is shown above the app on screen (or the home screen) with the
keyboard, between the status and navigation bars, and the app is kept from
freezing while it shows (`KeelDialogLayer.qml`). The pill hold calls
`ShowSheetFor` with the foreground app's Wayland client PID.

## 6. System back driving Silica's page drag

Extends entry 1. A one-shot `BackRequested` pops without the motion Silica's
own swipe has: the page follows the finger 1:1, commits past
`_flickThreshold` (`Theme.itemSizeMedium`), snaps with a duration scaled by the
remaining distance from the 400 ms base, and draws the edge shadow
(`PageStack.qml:123,316-325,645`, `private/PageEdgeTransition.qml:82-84`).
Marathon's back is a drag along the bottom pill, so it has a progress to feed.

Proposal: host hooks to drive an interactive back on the current PageStack,
e.g. in `org.shipwright.keel.Shell1`: `BackStart()`, `BackUpdate(progress)`
(0..1 of the page width), `BackCommit()` and `BackCancel()`, mapped onto the
same lateral offset and snap the swipe uses. `BackStart` replies unhandled
when there is nothing to pop (menu open, `backNavigation: false`, Dialog
handled as in entry 1), so the host can fall back to its own minimise.

Marathon today: pill-left calls `pageStack.pop()` in Marathon.Silica's
ApplicationWindow; the page jumps after release.

## 7. GlassItem painted on the GPU

`KeelGlassItem` is a `QQuickPaintedItem` (`plugin/cpp/private/glassitem.h`),
so every animated frame repaints on the CPU and re-uploads the texture. The
glow animates often: Switch fades it over 50 ms (450 ms while busy) and pulses
every 500 ms while busy (`Switch.qml:69-123`). On etnaviv and lima the upload
is the expensive part.

Proposal: render GlassItem as a scene-graph node (a QSGGeometryNode with a
small GLES2-compatible shader, or a cached texture with colour/opacity changed
through the material), so animating `color`, `brightness` or `falloffRadius`
doesn't touch pixels on the CPU.

Marathon today: no workaround; switch and busy glows cost a texture upload per
frame.

## 8. Ambience-change cross-fade in ApplicationWindow

Silica hides the ambience switch: `ThemeTransaction` defers the new ambience
while a 600 ms timer runs, the window (or an opaque current page) fades out
over 400 ms InOutQuad and back in over 400 ms, and the wallpaper cross-fades
(`ApplicationWindow.qml:230-283,521-566`). Keel's ApplicationWindow applies
the new ambience in one frame, so colours and wallpaper snap.

Proposal: carry the same states and timings in Keel's ApplicationWindow,
driven by Keel.Ambience's about-to-change signal.

Marathon today: ambience changes snap in Keel apps.

## 9. maximumFlickVelocity on non-1.5 pixel ratios

`Theme.maximumFlickVelocity` is `measured() ? 11250 : 5000 * m_pixelRatio`
with `measured()` true only when the ratio is exactly 1.5 (`theme.h:206,320`).
11250 is Jolla's 7500 × 1.5, so every other ratio gets two thirds of Jolla's
speed; Marathon's devices are never at exactly 1.5, so long lists feel ~33%
slow.

Proposal: `7500 * m_pixelRatio` for the computed branch (identical at 1.5), or
an env/ambience override (e.g. `KEEL_MAX_FLICK_VELOCITY`).

Marathon today: no override; Keel apps flick at 5000·ratio.

## 10. Opt-in glass page and dialog background

Silica's DialogHeader band is a transparent rect over `dialog.background`
(null by default, `PageStack.qml:115`) plus the highlight tint
(`DialogHeader.qml:107-146`). On Sailfish it frosts because Lipstick paints the
blurred ambience wallpaper behind the translucent app. A host without that
gets the tint over whatever is under the window.

Proposal: an opt-in default `pageBackground` / `dialog.background` component
that draws the crop of the blurred ambience wallpaper (`image://keelambience`)
under the page, positioned in window coordinates, so DialogHeader bands and
PanelBackground's 0.15 → 0.3 gradient frost as on Sailfish. Off by default
keeps Lipstick hosts unchanged.

Marathon today: `DialogHeaderBackdrop.qml` in marathon-silica supplies the
backdrop; it was an opaque `overlayBackgroundColor`, which made the tinted band
read as a flat slab.

## 11. Software scene graph: degrade instead of dropping effects

When `GraphicsInfo.api` is Software, Keel turns off the pulley's layer
(`PulleyMenuBase.qml:175`), ContextMenu's and OpacityRampEffect's shaders and
DockedPanel's modal effect (`DockedPanel.qml:144`). The cause on Marathon is
Marathon's own: the oneplus6 device package sets `QT_QUICK_BACKEND=software`
globally, which Marathon will fix. Only if Keel wants to support software
hosts: a plain-opacity fallback (e.g. a fading Rectangle in place of the
pulley glow, a dimming Rectangle for modal panels) would keep the feedback
without shaders.

Marathon today: oneplus6 loses those effects until its backend is fixed.

## 12. Theme resolves the ambience type once per process

Theme looks up the `Keel.Ambience` type id once, in a `static const` in
`theme.cpp`. If a Theme is created before anything has imported `Keel`, it
never sees the ambience for the rest of the process, so colours and the
wallpaper stay at their defaults. A full qmltestrunner run hits this.

Proposal: resolve the type lazily, retrying until it is registered, or
register `Keel.Ambience` from the Silica plugin's own initialisation.

Marathon today: tests import `Keel` before Silica to work around it.

## 13. Page-stack depth and the previous page for host back

To draw a host back gesture the way Silica's PageStack does, the host needs to
know, before back is sent, whether it will pop a page or leave the app, and
needs something to show underneath while the page is dragged.

Proposal: alongside request 6, expose the page-stack depth (a property or a
`Shell1` signal on change) and a snapshot or texture of the page below the
current one.

Marathon today: during a back drag the app moves aside over a dimmed home,
whether back will pop a page or leave the app.

## 14. Pilot: the on-screen app on a host without Sailjail entries

pilotd's `ShowSheetFor(pid)` finds the app through `/proc/<pid>/cmdline` and a
desktop entry with `[X-Sailjail]` names (`onscreen::app_for_pid`). A Marathon
app is a `marathon-app-runner` with neither, and a pooled runner's command line
does not name its app.

Proposal: let the host say which Keel app a window belongs to, e.g. a
`ShowSheetForApp(s appId)` beside `ShowSheetFor`, or an `[onscreen]` setting in
`pilotd.toml` naming a D-Bus method that maps a pid to a Keel app id.

Marathon today: shoal-pilotd's `0003-pilotd-marathon-onscreen.patch` calls the
shell's `Navigation1.AppIdForPid` for a `marathon-app-runner` and uses
`org.marathonos.<id>`.
