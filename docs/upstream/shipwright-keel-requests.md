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
