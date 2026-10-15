# Requests to Shipwright (Keel / Pacific)

Things Marathon needs from Keel or Pacific that can't be done cleanly from this
repo. Each has a Marathon-side workaround or gap noted.

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
