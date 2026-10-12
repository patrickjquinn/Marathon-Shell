# UX playbook audit: Store, Browser, Maps, Terminal

2026-10-12. Read-only code audit against the UX Playbook (21 laws plus build checklist). Jakob's law here means Sailfish OS / Jolla app conventions (Keel Silica). Paths are relative to `apps/` unless they start with `marathon-silica/`.

Size reference (Keel `theme.h`, pixelRatio 1): itemSizeExtraSmall 70, itemSizeSmall 80, iconSizeMedium 64, iconSizeSmallPlus 48, iconSizeSmall 32. A 44 pt touch target is roughly **Theme.itemSizeExtraSmall**, so anything under that counts as below the default target size.

## Summary

| Severity | Count |
|---|---|
| P0 broken | 0 |
| P1 clearly violates playbook | 13 |
| P2 polish | 29 |
| **Total** | **42** |

All four apps follow Silica conventions well: Theme tokens are used almost everywhere, PageHeader, PullDownMenu, ViewPlaceholder, RemorsePopup and ContextMenu sit where they should, empty states have copy that tells the user how to fix things, and every app has a cover with a CoverAction. The gaps cluster in four areas:

1. **Long operations and failures with no exit.** Store installs can't be cancelled, can't be resumed and can stay stuck on "Waiting" forever. Maps tells users to "Try again" on a GPU where that can never work. Terminal goes into a silent loop when the shell can't start.
2. **Offline.** Store keeps no catalogue cache, so it shows only a placeholder when offline, and its detail pages render empty sections. Browser and Maps search handle offline well.
3. **Primary-action discipline.** Every Store list row carries a full Button, Maps route preview has two equal Buttons, and Maps uses a pill-shaped FilterChip with a tinted fill, which the user has rejected.
4. **Reach.** Terminal has no way to scroll back through output, and Copy sits far from the selection.

---

## Store (`apps/store`)

Good:
- GetButton keeps the same footprint while it shows progress, so rows don't reflow.
- Percent progress (ProgressCircle or ProgressBar) and Notices on success or failure. The button flips to "Open", which gives the flow a designed end state.
- Uninstall goes through RemorsePopup in the PullDownMenu, placed far from "Open".
- Search is debounced and guarded by a generation counter.
- AppListPage has a "Try again" pulley and fix-it copy.
- The type scale stays within 5 sizes.

### Install / update flow (GetButton, AppDetailPage, StoreBackend)

**A1-01 · P1 · Doherty (progress + cancel past 10 s)**
- Where: `store/components/GetButton.qml:47-95`, `store/pages/AppDetailPage.qml:140-147`, `store/models/StoreBackend.qml:731-775`
- Problem: Flatpak installs and updates often run for tens of seconds to minutes. Once one starts, the button is replaced by a ProgressCircle or ProgressBar and nothing can be tapped. The backend has no cancel verb at all; it only has install, update, uninstall, update-all, open and refresh-state.
- Fix:
  - Add `marathon-store://cancel/<id>` to the handler.
  - On the detail page, add a PullDownMenu item "Cancel installation" (or an `icon-m-cancel` IconButton next to the ProgressBar) while `busy`.
  - In rows, add a ListItem ContextMenu with "Cancel".
  - The cover could also take a CoverAction `icon-cover-cancel` in job mode.
- Effort: M

**A1-02 · P1 · Zeigarnik/Ovsiankina (resumption), Doherty**
- Where: `store/models/StoreBackend.qml:29-30, 731-746, 792-813`
- Problem 1: `jobs` exists only in memory and is filled only by `startJob()`. If the Store is reopened (or frozen/killed) mid-install, the row shows "Get" again even though flatpak is still running, which invites a duplicate install.
- Problem 2: If the handler never writes a progress file, the job stays `pending` ("Waiting") forever. There is no timeout.
- Fix:
  - In `refreshState()`, scan `stateDir/install-progress-*.json` for running records newer than N minutes and rebuild `jobs` and `_verbs` from them.
  - Fail a job with "The Store helper didn't respond. Try again." when no record shows up within about 30 s.
- Effort: M

**A1-03 · P1 · Peak-end (failure state), offline**
- Where: `store/models/StoreBackend.qml:283-301`, `store/pages/DiscoverTab.qml:23, 77-82`, `store/pages/AppsTab.qml:62-77`
- Problem: Nothing from the catalogue is persisted.
  - Offline, Discover shows only "Can't reach Flathub".
  - The "Top charts" section in the Apps tab disappears without explanation.
  - Every category opens to an error.
  - Each launch with no network is a blank store, even right after a successful session.
- Fix:
  - Write the last collections and appstream records to a JSON file under `StandardPaths.CacheLocation`, and load it before the network.
  - While showing cached data, set the TabBar/PageHeader description, or add an InfoLabel line: "Offline. Showing apps from <time>. Pull down to refresh."
- Effort: M

**A1-04 · P1 · Doherty (loading state), Peak-end (failure)**
- Where: `store/pages/AppDetailPage.qml:35-46, 189-239, 315-360`
- Problem: Detail loads (appstream, summary, reviews) have no loading or failed state.
  - Offline, or when opened from Installed, the page shows the "About" SectionHeader with nothing under it.
  - The fact cells read "–", "No ratings" and "–".
  - There's no message and no retry.
- Fix:
  - Track `loading` and `failed` per fetch.
  - Show a BusyIndicator under the header until appstream lands.
  - On failure, show an InfoLabel "Couldn't load details" with hint "Check your connection, then pull down to try again", plus a PullDownMenu "Try again" item.
  - Hide sections that are empty.
- Effort: S

**A1-05 · P1 · Hick, Von Restorff, Jakob**
- Where: `store/components/AppRow.qml:88-95`, `store/pages/DiscoverTab.qml:202-205`
- Problem: Every AppRow ends in a full Silica `Button` (Get, Open or Update). Discover alone shows 10 to 15 equal-weight primary buttons, plus up to 24 on the Apps tab. Nothing stands out, the row and the button are two adjacent tap targets that do different things, and Jolla Store list delegates carry no button: install lives on the detail page.
- Fix:
  - Remove the button from browse rows. Show state as a secondary Label ("Installed", "Update") or the ProgressCircle while busy.
  - Keep the single primary GetButton on the detail page.
  - The Installed tab's update rows can keep an action, or rely on the existing "Update all" pulley.
  - Trade-off: this adds one tap to installs from lists.
- Effort: M

**A1-06 · P2 · Von Restorff (colour-only signal)**
- Where: `store/pages/AppDetailPage.qml:527-544`
- Problem: Risky permissions differ from safe ones only by `Theme.errorColor` on the icon and label.
- Fix: Put risky entries under their own SectionHeader ("Sensitive access"), or add an `icon-s-warning` and a word cue in the detail text.
- Effort: S

**A1-07 · P2 · Similarity (same function, same look; no hidden links)**
- Where: `store/pages/AppDetailPage.qml:564-588`
- Problem: The "Website" and "Report a problem" rows are tappable, but they render as the same DetailItem as static rows. Nothing shows they're links.
- Fix: Move them to PullDownMenu items ("Visit website", "Report a problem"), which is the Silica norm, or give link rows a trailing `icon-m-right` and a pressed highlight.
- Effort: S

**A1-08 · P2 · Doherty (skeleton past 1 s)**
- Where: `store/pages/AppDetailPage.qml:261-281`, `store/pages/ScreenshotViewer.qml:37-52`
- Problem: In the screenshot strip, tiles stay empty while loading and after an error, which shows as blank gaps offline. The viewer shows a BusyIndicator, but nothing when an image fails.
- Fix: Reserve the tile with a faint `icon-m-image` placeholder while Loading or on Error. In the viewer, show an InfoLabel "Couldn't load screenshot" on `Image.Error`.
- Effort: S

**A1-09 · P2 · Peak-end (error copy that explains the fix)**
- Where: `store/models/StoreBackend.qml:694-701`, `store/pages/AppDetailPage.qml:148-159`
- Problem: Any flatpak error that isn't recognised is shown as the raw flatpak line, in both a Notice and the inline label. The strings aren't wrapped in `qsTr`.
- Fix: Map more cases (remote not found, already installed, permission, signature), default to "Couldn't finish. Try again later.", log the raw line, and wrap the strings in qsTr.
- Effort: S

**A1-10 · P2 · Localisation (Postel: strict output)**
- Where: `store/models/StoreBackend.qml:56-110, 670-679`
- Problem: Category labels and info-row labels ("Developer", "Installed size", and so on) aren't wrapped in `qsTr`.
- Fix: Wrap them in `qsTr`, or `QT_TR_NOOP` plus `qsTr` at render time.
- Effort: S

**A1-11 · P2 · Honest labelling**
- Where: `store/models/StoreBackend.qml:119`, `store/pages/DiscoverTab.qml:145-148`
- Problem: The "Editors' pick" header also appears when `heroApp` falls back to the first verified or popular app, which nobody picked.
- Fix: Use "App of the day" only when `appOfTheDay` is set, and "Featured" otherwise.
- Effort: S

**A1-12 · P2 · Similarity, failure recovery**
- Where: `store/pages/AppsTab.qml:15-21`
- Problem: Discover and Installed each have a PullDownMenu with Refresh. The Apps tab has none, so offline there's no way to retry Top charts from that tab.
- Fix: Add the same PullDownMenu (Refresh calls `store.loadCatalog()`). That also means adding a `topMargin` like the sibling tabs, because TabItems with a pulley need it.
- Effort: S

**A1-13 · P2 · Jakob (Silica remorse copy)**
- Where: `store/pages/AppDetailPage.qml:30`
- Problem: The remorse text says "Uninstalled %1" during the countdown, before anything has happened. Silica uses the progressive form.
- Fix: Change it to `qsTr("Uninstalling %1")`.
- Effort: S

**A1-14 · P2 · Proximity, layout overlap**
- Where: `store/pages/DiscoverTab.qml:77-82, 278-291`
- Problem: The offline ViewPlaceholder turns on whenever `catalogAppCount === 0`, but the local "Updates available" rows still render. The centred placeholder text can sit on top of them.
- Fix: Disable the placeholder when `updateApps.length > 0` and show an inline InfoLabel above the updates instead.
- Effort: S

### Store cover (`store/cover/StoreCover.qml`)
Good: it shows the running job's percent, otherwise the update count with an "Update all" action, and in idle mode a search action that focuses the field. Cancel is covered in A1-01.

---

## Browser (`apps/browser`)

Good:
- The toolbar sits at the bottom (thumb zone) and the suggestion list grows upward from it.
- Load progress shows from t=0, under 100 ms.
- The error page has fix-it copy for each error domain (offline, DNS, certificate) and a "Try again" button that keeps the failed URL.
- A crashed renderer gets a Reload overlay.
- Tabs are restored on launch.
- Close all, Clear history and Delete all go through Remorse.
- ViewPlaceholders carry hints, and private mode is shown by colour plus an icon plus a label.

### MainPage (`browser/pages/MainPage.qml`, `browser/BrowserApp.qml`, `browser/BrowserLogic.js`)

**A1-15 · P1 · Postel (never clear input on error)**
- Where: `browser/pages/MainPage.qml:22-26, 34-37`, `browser/BrowserApp.qml:177-183`
- Problem: `open()` calls `stopEditing()` before `navigateTo()` checks the input. For a rejected address (`javascript:`, `data:`, `file:`), the field closes, a Notice appears, and the next `startEditing()` puts `tab.url` back in the field, so the typed text is lost.
- Fix: Run `Logic.resolveInput()` first. On error, keep the field open with its text, select the offending scheme, and show the Notice.
- Effort: S

**A1-16 · P1 · Jakob, Miller (recognition over recall)**
- Where: `browser/BrowserLogic.js:77-80`, `browser/pages/MainPage.qml:131`, `browser/BrowserApp.qml:108-119`
- Problem: When the address field is focused while empty or unchanged (always the case for a new tab), `suggestions()` returns `[]`. The user sees a dim overlay and a keyboard with no bookmarks or history. Sailfish Browser shows favourites and recent pages at this exact moment.
- Fix: For an empty query, return the bookmarks, then the 5 to 8 most recent history entries, in the same suggestion ListItems (optionally under SectionHeaders "Bookmarks" and "Recent").
- Effort: S

**A1-17 · P2 · Doherty (cancel past 10 s), target distance**
- Where: `browser/pages/MainPage.qml:347-357`
- Problem: Stop is only in the DockedPanel menu, so stopping a slow load takes two taps. That's the case most likely to need it on an L5 with a weak signal.
- Fix: While `loading`, put stop in the toolbar, for example by turning the forward IconButton (rarely enabled) into `icon-m-close` "Stop loading".
- Effort: S

**A1-18 · P2 · Postel (validate on blur, fix-it error)**
- Where: `browser/BrowserLogic.js:70-75`, `browser/pages/SettingsPage.qml:13-19`
- Problem: The custom homepage is accepted without validation ("foo bar" becomes "https://foo bar"), and an empty value is dropped without a word when the page is left.
- Fix: Validate on EnterKey and on blur. Set `errorHighlight: true` and show a description such as "Enter a web address, like example.com". Keep the text.
- Effort: S

**A1-19 · P2 · Jakob, Fitts (keep destructive actions small and distant)**
- Where: `browser/pages/SettingsPage.qml:119-147`
- Problem: "Clear history" and "Clear cookies and site data" are two centred full Buttons, the most prominent controls on the page. Sailfish Browser uses a "Clear browsing data" Dialog: one TextSwitch per data type, then DialogHeader Accept.
- Fix: Replace both with one ValueButton or BackgroundItem "Clear browsing data" that opens a Dialog with TextSwitches (History, Cookies and site data), then Remorse on accept.
- Effort: M

**A1-20 · P2 · Similarity (no fake disabled state)**
- Where: `browser/pages/BookmarksPage.qml:52-57`, `browser/pages/MainPage.qml:362-366`
- Problem: In private mode, the bookmark pulley item is tinted `secondaryColor` and the menu bookmark button is set to `opacityLow`. Both stay enabled, so they look disabled but respond with a Notice.
- Fix: Set `enabled: false` and hide the pulley item, or keep them fully enabled-looking. Explain once in the Bookmarks ViewPlaceholder hint.
- Effort: S

**A1-21 · P2 · Sailfish fidelity (hard-coded colour, tinted fills)**
- Where: `browser/pages/TabsPage.qml:87, 145-152`
- Problem: The tab frame uses `Qt.rgba(0, 0, 0, 0.55)`, which isn't a Theme value and breaks on light ambiences. The close button sits on a tinted filled disc.
- Fix: Use `Theme.rgba(Theme.highlightDimmerColor, Theme.opacityHigh)` for the frame, and drop the disc (use a plain IconButton with `icon.highlighted`).
- Effort: S

**A1-22 · P2 · Localisation, Postel**
- Where: `browser/BrowserLogic.js:61, 66, 85, 87, 151-161`
- Problem 1: Suggestion titles ("Go to", "Search X for") and error strings aren't translatable.
- Problem 2: `dateGroup` treats the last 24 hours as "Today", so a page visited at 23:00 yesterday is grouped under Today.
- Problem 3: "localhost:8080" goes to the search engine.
- Fix:
  - Return keys and translate them in QML.
  - Group history by calendar day.
  - Treat `host:port` and `localhost` as addresses.
- Effort: S

### Browser cover
Good: it shows the page thumbnail, title and host, and a "New tab" CoverAction, the same as Sailfish Browser.

---

## Maps (`apps/maps`)

Good:
- The bottom panel keeps search, place and navigation controls in the thumb zone.
- Search has a debounce, a stale-response guard, offline copy that explains the problem, and a "Try again" pulley.
- If there's no location fix, the user is asked to tap a start point (with Cancel).
- The banner and cover show turn-by-turn info, the voice can be muted, and a background task keeps navigation alive.
- PlacePage shows a "Finding a route" label and a BusyIndicator.

### MapPage (`maps/pages/MapPage.qml`, `maps/MapsApp.qml`)

**A1-23 · P1 · Peak-end (failure state needs a real recovery path)**
- Where: `maps/pages/MapPage.qml:33-63`, `maps/MapsApp.qml:103-115`
- Problem: On this GPU, WebGL is disabled, so MapLibre always fails. The page shows "Can't show the map / The map couldn't start its graphics. Try again, or close and reopen Maps." and a "Try again" Button. Neither retrying nor reopening can ever work, so the main recovery advice is a dead end. Meanwhile search, place details, the route list and spoken turn-by-turn all still work, and the copy never mentions them.
- Fix:
  - Classify the failure (WebGL or context unavailable is permanent; a renderer crash is transient).
  - For a permanent failure: hide Try again and say "This phone can't draw the map yet. You can still search for places and get spoken directions." Make "Search places" the single primary action, and drop the full-screen overlay in favour of a centred InfoLabel above the bottom panel.
- Effort: S

**A1-24 · P1 · Hick, Von Restorff (one primary action)**
- Where: `maps/pages/MapPage.qml:283-296`
- Problem: Route preview shows two Buttons of equal weight, "Directions" and "Start". "Start" is the main next step.
- Fix: Keep "Start navigation" as a `Button` and make "Directions" a `SecondaryButton` (Keel provides it), or make the duration/summary block tappable to open the directions and drop the second button.
- Effort: S

**A1-29 · P2 · Tesler (sensible defaults)**
- Where: `maps/MapsApp.qml:66, 92-95`
- Problem: With no fix, `fix` falls back to San Francisco, and the map centres there with no indication that the location is unknown.
- Fix: Save the last good fix (ConfigurationValue) and centre on that. If there has never been one, show a world or country view with "Location unknown. Tap the location button to find yourself."
- Effort: S

**A1-31 · P2 · Peak-end (designed end state)**
- Where: `maps/pages/MapPage.qml:310-317`, `maps/MapsApp.qml:55, 309-318`
- Problem: On arrival, the bottom label only changes to "Arrived". Navigation mode, the GPS following and the background task keep running until the user taps End.
- Fix: When `arrived` becomes true, show "You've arrived at <place>" with a "Done" Button. Also call `endBackgroundTask` automatically after about 60 s.
- Effort: S

**A1-32 · P2 · Ovsiankina (resumption)**
- Where: `maps/MapsApp.qml:37-49`
- Problem: The destination, travel mode and active route live only in memory. If the freezer or OOM kills the app during navigation, it's lost.
- Fix: Save the destination and mode when navigation starts. On launch, show a bottom-panel row "Resume directions to <place>".
- Effort: M

### RoutePage (`maps/pages/RoutePage.qml`)

**A1-25 · P1 · Jakob (user-rejected pill/tinted control), Fitts**
- Where: `maps/pages/RoutePage.qml:48-72`, `marathon-silica/Marathon/Silica/FilterChip.qml:14, 31-39`
- Problem: The travel-mode picker uses FilterChip:
  - It's a pill (`radius: height / 2`) with a tinted `highlightBackgroundColor` fill when checked, which is exactly the style the user rejected.
  - Its height is `Math.max(44, itemSizeExtraSmall * 0.75)`: a hard-coded px floor, and below the 44 pt equivalent (about 52 px at ratio 1).
- Fix: Use a Silica `ComboBox { label: qsTr("Travel by") }` with MenuItems "Drive", "Walk" and "Cycle", the Jolla-standard single-choice control.
- Effort: S

**A1-26 · P2 · Doherty (busy state past 1 s)**
- Where: `maps/pages/RoutePage.qml:62-85`
- Problem: After the travel mode changes, re-routing only disables the chips and the Start button. The list keeps showing the old mode's route with no busy indication.
- Fix: Set the PageHeader `description` to "Finding a route…" and show a BusyIndicator in the header while `router.routing`. Fade the list to `opacityLow` meanwhile.
- Effort: S

**A1-28 · P2 · Similarity (same function, same name)**
- Where: `maps/pages/PlacePage.qml:33, 64`, `maps/pages/MapPage.qml:288, 293`, `maps/pages/RoutePage.qml:83, 103`
- Problem: Opening the route preview is called "Navigate" on PlacePage (in both the pulley and the button), and starting turn-by-turn is "Start" on MapPage but "Start navigation" on RoutePage.
- Fix: Use "Directions" for the preview everywhere and "Start navigation" for the start everywhere.
- Effort: S

### SearchPage / PlacePage

**A1-27 · P2 · Doherty (cancel past 10 s), error copy**
- Where: `maps/MapsApp.qml:26-35, 68-71`, `maps/src/valhallaroutingclient.cpp:44-89`
- Problem: Neither the Nominatim XHR nor the Valhalla request has a timeout, so on a captive or hanging network the spinner runs forever with no cancel. `onRouteFailed` always blames the connection, even when Valhalla answers "no route", for example across water.
- Fix:
  - Add a 15 s timer or abort to `fetch`.
  - Call `setTransferTimeout(15000)` on the routing request.
  - Pass `m_lastError` through so the copy can say "No route by <mode> to this place" when that's the cause.
  - Add a pulley "Cancel" while routing.
- Effort: S

**A1-30 · P2 · Tesler, Zeigarnik, Postel**
- Where: `maps/pages/SearchPage.qml:18-25, 43, 61-65`, `maps/MapsApp.qml:126`
- Problem:
  - Pressing Enter on a 1 or 2 character query starts a search, but the results are hidden by the `length > 2` model gate, so the placeholder still says "Find a place".
  - There are no recent searches or saved places, so nothing is usable offline.
  - Results aren't biased to the user's position.
- Fix:
  - Allow submit on Enter for any non-empty query.
  - Save the last 10 chosen places (ConfigurationValue) and list them under a "Recent" SectionHeader when the query is empty.
  - Add `&viewbox=` or lat/lon bias when `fixValid`.
- Effort: M

**A1-34 · P2 · Plain language**
- Where: `maps/pages/PlacePage.qml:44-47`, `maps/MapsLogic.js` (`parseResults`)
- Problem: The PageHeader description shows the raw OSM `type` ("yes", "house", "residential").
- Fix: Map common types to readable labels, or leave the description out when the type isn't recognised.
- Effort: S

### Maps cover

**A1-33 · P2 · Fitts (keep destructive actions out of easy reach)**
- Where: `maps/cover/MapsCover.qml:91-95`
- Problem: During navigation, the only CoverAction is "End navigation". One tap on a home-screen cover, easily done by accident in a pocket or car mount, ends the route without confirmation.
- Fix: Make the navigating CoverAction "mute/unmute voice" and leave ending to the app (pulley, with Remorse).
- Effort: S

---

## Terminal (`apps/terminal`)

Good:
- The extra-keys row gives haptic feedback within 100 ms.
- Ctrl and Alt support tap-to-arm and hold-to-lock, with accessible names and descriptions.
- Closing a session uses `remorseAction`.
- The cover shows the last terminal lines plus "New session".
- The pulley puts Paste and Copy at the bottom, nearest the finger.
- Settings use standard Slider, ComboBox and TextSwitch.

### TerminalPage / TerminalView (`terminal/pages/TerminalPage.qml`, `terminal/components/TerminalView.qml`)

**A1-35 · P1 · Fitts / Jakob (core capability unreachable)**
- Where: `terminal/src/TerminalScreen.cpp:12`, `terminal/src/TerminalRenderer.h`, `terminal/components/TerminalView.qml:122-155`, `terminal/pages/TerminalPage.qml:30-33`
- Problem: The screen keeps 1000 rows of history, but the renderer has no viewport offset and the page's Flickable has `contentHeight: height`. A vertical drag only opens the pulley. Output that scrolls off (a `dmesg`, a build log) can't be read again by touch, and fingerterm on Sailfish lets you scroll back.
- Fix:
  - Give the renderer a `scrollOffset` bound to a SilicaFlickable whose `contentHeight` covers the history, so the PullDownMenu stays at the top of the history the way a Silica list works.
  - Jump to the bottom on input.
- Effort: L

**A1-36 · P1 · Peak-end (failure state), Occam**
- Where: `terminal/src/TerminalEngine.cpp:42-60, 66-68`, `terminal/TerminalApp.qml:52-60`
- Problem: If `execvp` fails (`$SHELL` unset and no `/bin/bash`), the child calls `_exit(1)`. The engine then sees EOF and emits `finished`, and with one session `_finished()` calls `start()` again straight away. The result is a silent tight respawn loop on a blank screen. If `forkpty` fails, the screen just stays blank with no message.
- Fix:
  - Fall back to `/bin/sh`.
  - If a session ends within about 2 s of starting, stop respawning and write "[Couldn't start <shell>]" into the screen, with a pulley item "Restart session".
  - Surface `forkpty` failure the same way.
- Effort: S

**A1-38 · P1 · Minimise target distance**
- Where: `terminal/components/TerminalView.qml:134-153`, `terminal/pages/TerminalPage.qml:76-85`
- Problem: Selecting text with a long press ends under the finger, but "Copy" is only in the pulley, so the user has to drag the whole page down from the top. Silica puts the action next to the selection.
- Fix: When a drag ends with a selection, show a small ContextMenu or IconButton "Copy" anchored near the selection end. Alternatively, copy automatically on release and show the existing "Copied to clipboard" Notice.
- Effort: M

**A1-37 · P2 · Peak-end (designed end state)**
- Where: `terminal/TerminalApp.qml:52-60`
- Problem: Typing `exit` in the last session silently swaps in a fresh shell (the scrollback is lost). With several sessions, the exited one simply disappears.
- Fix: Write "[Process exited. Tap to restart]" into the screen the way fingerterm does and restart on tap. Or, with several sessions, show a Notice "Session %1 closed".
- Effort: S

**A1-39 · P2 · Hick, Occam**
- Where: `terminal/pages/TerminalPage.qml:34-85`
- Problem: The pulley holds up to 7 items. "Smaller text" and "Larger text" duplicate the Settings slider and push Settings to the far end of the drag.
- Fix:
  - Replace the two size items with pinch-to-zoom (PinchArea on the renderer, writing to `fontSize`).
  - Order the rest as Settings, Sessions, New session, Paste, Copy.
- Effort: M

**A1-40 · P2 · Fitts (touch-target default), Von Restorff**
- Where: `terminal/components/VirtualKeyRow.qml:53, 74, 76, 108-109`
- Problem 1: Ten keys share the full width, so each is `width / 10`, about 54 px at 540 px wide. That's under `Theme.itemSizeExtraSmall` (70 px, roughly 44 pt).
- Problem 2: An armed Ctrl or Alt shows only as highlight colour plus an underline, and a locked one only as a background highlight. The two are easy to confuse.
- Fix:
  - Make the row a horizontal ListView with `width: Math.max(Theme.itemSizeExtraSmall, width / count)`, or split it into two rows.
  - Show the locked state with an `icon-s-lock` glyph next to the label.
- Effort: S

### Terminal SettingsPage (`terminal/pages/SettingsPage.qml`)

**A1-41 · P2 · Pragnanz (legibility), plain language**
- Where: `terminal/TerminalApp.qml:17`, `terminal/pages/SettingsPage.qml:29-41`
- Problem: The minimum text size is `fontSizeTiny / 2` (about 9 to 12 px), which can't be read. The slider label shows developer units ("%1 px").
- Fix: Set the minimum to `Math.round(Theme.fontSizeTiny * 0.75)` and show the value as a terminal column count ("%1 columns"), which is what a user actually trades off.
- Effort: S

### Terminal SessionsPage
Good: ListItem plus a ContextMenu "Close" with remorse. Close is offered only when there's more than one session, and the current session is shown with a background highlight, not just colour. No findings.

---

## Cross-app

**A1-42 · P2 · Similarity across apps (covers)**
- Where: `maps/cover/MapsCover.qml:23`, `terminal/cover/TerminalCover.qml:33`
- Problem: The Maps and Terminal CoverPlaceholders use medium icons (`icon-m-location`, `icon-m-keyboard`), while Store and Browser use `icon-l-*`. The placeholder renders the image at its natural size, so these two covers look visibly emptier.
- Fix: Use `icon-l-*` (or the app's launcher icon, which `CoverPlaceholder.forceFit` handles) in every cover.
- Effort: S

## Top 5 to fix first

1. **A1-23**: Maps' failure screen points users at a retry that can never work. Rewrite it to offer search and spoken directions.
2. **A1-01 + A1-02**: Store installs have no cancel, can't be resumed after a relaunch, and can show "Waiting" forever.
3. **A1-03 + A1-04**: Store offline shows a blank catalogue and broken detail pages. Add a cache plus loading and error states.
4. **A1-35**: Terminal has no way to scroll back through output.
5. **A1-25 + A1-24**: Maps' pill-shaped FilterChip with a tinted fill (rejected style) and the two equal buttons on route preview. Replace them with a ComboBox and Button + SecondaryButton.
