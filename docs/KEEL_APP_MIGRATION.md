# Moving a Marathon app to Keel

Spec: docs/design/2026-10-11-keel-for-marathon-design.md (§3, §4).
New apps: copy apps/template (the minimal Keel app: page, pulley, list + context menu, cover,
Nemo.Configuration, tests). Fuller reference: apps/notes.

## Rules
- Keel is never modified. Use `import Sailfish.Silica 1.0` then `import Marathon.Silica 1.0` (this order,
  every file; tests/lint/check-silica-imports.sh enforces it). No `MarathonUI.*` imports remain.
- Follow the Sailfish design doc (~/Downloads/"Sailfish OS app design second pass.md"): Theme sizes,
  colours, margins only; no hard-coded colours/px; Theme.horizontalPageMargin; pulley menus instead of
  toolbars/FABs; RemorseItem/RemorsePopup for destructive actions; Dialog accept/reject by gesture
  (no Accept/Cancel buttons); ViewPlaceholder for empty states; covers instead of cards.
- WCAG 2.2 AA via Marathon.Silica (its controls already carry roles/keys). Custom interactive items:
  set Accessible.role/name, activeFocusOnTab, Keys, and add a `FocusFrame { parent: root }`.
- Manifest: delete the `"toolkit": "marathonui",` line (Keel is the default).
- Root file: `ApplicationWindow` (Marathon.Silica) with `appId`, `initialPage`, optional `cover`.
  The runner calls `handleBack()`; ApplicationWindow already pops pages / minimises.
- Give the app a `cover:` (CoverBackground; ≤3 lines of state, Theme.fontSizeMedium+, CoverAction
  for the main action). See apps/notes/cover/NotesCover.qml.

## MarathonUI → Keel
| MarathonUI | Use |
| --- | --- |
| MApp, MPage, MStackView | ApplicationWindow, Page, pageStack.push/pop |
| MTopBar, MTopHairline | PageHeader (in the flickable's header / first item) |
| MSection, MSectionHeader | SectionHeader in a Column |
| MSettingsListItem | ListItem / ValueButton / TextSwitch / DetailItem |
| MButton, MIconButton, MCircularIconButton | Button, IconButton |
| MLabel, MText | Label (Theme.fontSize*, Theme.primaryColor/secondaryColor/highlightColor) |
| MEmptyState | ViewPlaceholder (inside a Silica flickable) |
| MConfirmDialog | Dialog (+DialogHeader); RemorsePopup/RemorseItem for deletes |
| MActivityIndicator | BusyIndicator / BusyLabel |
| MSnackbar | Notices.show(text) |
| MSearchField, MTextField, MTextInput, MTextArea | SearchField, TextField, TextArea |
| MToggle, MSlider | TextSwitch / Switch, Slider |
| MSheet, MModal | DockedPanel, Dialog |
| MTabBar | TabView + TabBar (Marathon.Silica), pages as TabItem |
| MPageIndicator | PageIndicator (Marathon.Silica) |
| MFilterChip | FilterChip (Marathon.Silica) |
| MCard, MFloatingActionButton | redesign: ListItem rows; PullDownMenu actions |
| Icon { name: "x" } | `Icon { source: "image://theme/icon-m-<name>" }`, Sailfish names. Every name used must be in marathon-icon-theme/icon-map.txt; add missing ones (Phosphor glyph names from shell/qml/ui/PhosphorGlyphs.js), then run marathon-icon-theme/generate.py and commit the SVGs. |
| HapticService | `import Nemo.Ngf 1.0` → NonGraphicalFeedback { event: "feedback_press" } (events: shell/src/services/ngfevents.h) |
| SettingsManagerCpp.get/set (app storage) | `import Nemo.Configuration 1.0` → ConfigurationValue { key: "/apps/<appId>/<name>" } |
| NotificationService (posting) | `import Nemo.Notifications 1.0` → Notification { appName; summary; body; remoteActions } |
| MarathonOS.Shell services (*Cpp / *Service context properties) | `import Marathon.Platform 1.0`: Permissions, Lifecycle, Navigation, Contacts, CallHistory, Telephony, Sms, MediaLibrary, Calendar, WorldClock, Sensors, Location, Alarms, Settings, Network, Bluetooth, Display, Power, Audio, Security, Updates, DavSync, AppStore, Apps, AppInstaller (tools/marathon-app-runner/platformtypes.cpp). Same objects, same API; only the names change. |
| Router / app routes | keep the app's existing route handling (MApp's) on ApplicationWindow if used |

## Verify (host)
- `KEEL_QML=$HOME/Developer/Shipwright/build/keel/qml` for everything below.
- Tests: add `apps/<app>/tests/` (copy apps/notes/tests/run.sh); keep or port existing logic
  tests; add tests for each page loading and its main interactions. Run `sh apps/<app>/tests/run.sh`.
- Build the app module: `cmake -S . -B build-<app> -G Ninja -DBUILD_TESTING=ON -DKEEL_QML=$KEEL_QML`
  then `ninja -C build-<app> <app>` — no qmlcachegen errors, no unresolved types.
- `sh tests/lint/check-silica-imports.sh` and `sh tests/lint/check-icon-map.sh . $KEEL_QML/Sailfish/Silica`.
- Visual check headless: write a small qml that loads each page at 720x1440 and grab it
  (`QT_QPA_PLATFORM=offscreen`, `Window.contentItem.grabToImage`) and look at the PNGs.
