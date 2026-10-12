# UX playbook audit: shell entry surfaces

Date: 2026-10-12. Branch `feat/keel-framework-1a` at f995afaa (read-only audit). Covers lock screen, PIN, first-run setup, home grid, dock and nav corners, app context menu, search, app switcher, Hub and peek, and the app launch splash and failure screens.

**Units.** Keel's `Theme.pixelRatio` is `dpi/261` in 0.25 steps (`shell/src/services/ambienceservice.cpp:38`), so 1.0 on the PinePhone and Librem 5. At that ratio `Theme.itemSizeExtraSmall` (70 px) is about 44 pt, `iconSizeSmall` (32 px) about 20 pt, and 48 px about 30 pt. The legacy `Constants.scaleFactor` is `dpi/160`, about 1.69 on the PinePhone, so "N × scaleFactor" is roughly N pt.

**Screenshots.** The judgments use `v_lock`, `v_home`, `v_u_pin`, `v_hub`, `v_r_switcher`, `v_n_switcher`, `v_menu`, `v_u_search`, `r395_oobe` and `r395_shell`. `v_u_search` and `v_menu` predate the current code (the boxed search field and the menu overlap are fixed), so for those two surfaces the code is the reference.

## Summary

| Severity | Count |
| --- | --- |
| P0 broken | 3 |
| P1 clearly violates playbook | 15 |
| P2 polish | 36 |

**Top issues**

1. **SE-49 (P0).** Tapping a notification in the Hub does nothing. The `notificationTapped` signal is never connected, and it passes id 0.
2. **SE-15 (P0).** A 4- or 5-digit quick PIN can't be entered on the lock PIN pad. Settings allows 4–6 digits, but the pad only submits at 6 and has no OK key.
3. **SE-32 (P0).** The home pager and the grid compute items-per-page with two different formulas. At the 150 % display size (offered in first-run setup), apps past the second page are unreachable.
4. **SE-22 / SE-23 (P1).** First-run setup teaches the wrong gesture model: it never teaches pill-left for back or the left-edge Hub peek. It also shows two "advance" buttons at once.
5. **SE-16 / SE-17 (P1).** PIN errors vanish after 1.2 s, the lockout has no countdown, and the keypad jumps about 55 px when an error appears and again while the user re-types.

**Cross-cutting**

- The PIN screen, `MCircularIconButton`, the switcher's empty state and the grid decorations still sit on the legacy `Constants.scaleFactor`, `MColors` and `MTypography` system. Everything else in scope uses Keel `Theme`.
- Same-function-same-look breaks between surfaces in three places: the phone/camera shortcuts, notification rows, and the PIN pads.
- Reduced motion is honoured where `MMotion` is used and bypassed where durations are hard-coded.

---

## Cross-cutting

| ID | Sev | Law | File:line | What's wrong | Proposed fix | Effort |
|---|---|---|---|---|---|---|
| SE-01 | P2 | Prägnanz, Similarity | `shell/qml/ui/MCircularIconButton.qml:20-21,55`; callers `MarathonLockScreen.qml:374`, `MediaPlaybackManager.qml:180,191`, `MarathonPinScreen.qml:26-31,264-` | `MCircularIconButton` multiplies `buttonSize`/`iconSize` by `Constants.scaleFactor` (dpi/160). Callers mix "design px" (PIN: 56) with Theme tokens (lock: `iconSize: Theme.iconSizeSmall`), which then gets scaled a second time and clamped at 45 % of the width. Two scale systems round differently per device, so proportions between surfaces drift. | Make `MCircularIconButton` take device px (`width`, `iconSize` = Theme tokens). Remove `scaleFactor` from it and from the PIN screen (34 uses). | M |
| SE-02 | P2 | Von Restorff (reduced motion) | `MarathonPinScreen.qml:340-357,400-427`; `MarathonOOBE.qml:735-772` (infinite loop); `TaskCard.qml:647-659`; `MarathonPeek.qml:224-227,320-327`; `MarathonPageView.qml:67-87` | These hard-coded durations and `OutBack` overshoots ignore `MMotion.reduceMotion`. The OOBE coachmark nudge loops forever. | Route through `MMotion.dur()` / `durationFor()`, and gate loops with `MMotion.gate()`, as the lock chevron already does. | S |

## Lock screen (`MarathonLockScreen.qml`, `MediaPlaybackManager.qml`)

| ID | Sev | Law | File:line | What's wrong | Proposed fix | Effort |
|---|---|---|---|---|---|---|
| SE-03 | P1 | Similarity, honest copy | `MarathonLockScreen.qml:687-723` | The "N more notifications · earlier today" row is styled exactly like the tappable cards above it but has no MouseArea, so it looks like a button and isn't one. "earlier today" is hard-coded even for notifications that are days old. | Make it a `BackgroundItem` that unlocks to the Hub (`navigateToPage(-2)`). Drop "earlier today" or derive it from the oldest timestamp. | S |
| SE-04 | P2 | Prägnanz (grid) | `:575-576`, `:284-285` vs `:475-476,736-737` | Notification cards and the call strip use `paddingSmall` (6 px) side margins, while the activity bar and phone/camera row use `horizontalPageMargin`. `v_lock.png` shows the card edge at x≈8 and the phone ring at x≈33. | Use `Theme.horizontalPageMargin` for every lock-screen column. | S |
| SE-05 | P2 | Similarity | `:600-683` vs `shell/qml/ui/MHubRow.qml` | The same notification renders two ways. On the lock it's a boxed black card with a generic teal bell, title Small, body ExtraSmall and time Tiny. In the Hub it's a box-less row with a glass-ring monogram and time ExtraSmall. | Reuse `MHubRow` (or one shared delegate) on the lock, over a light scrim if needed. | M |
| SE-06 | P2 | Doherty (<100 ms ack) | `:849-854` | A tap that isn't a drag only logs. The user gets no response. | On tap, restart the chevron bob and briefly brighten "Swipe up to unlock" (Sailfish shows a hint on tap). | S |
| SE-07 | P2 | Prägnanz (type scale) | `:426,434,440,577,592,609,618,717`; `MediaPlaybackManager.qml:91,98,114` | The lock uses six sizes (Huge×1.9/1.6, Large, Medium, Small, ExtraSmall, Tiny). Timestamps at Tiny (20 px) are the outlier. | Make timestamps ExtraSmall (as in the Hub) and the media artist ExtraSmall. That leaves 4–5 sizes. | S |
| SE-08 | P2 | Proximity, layout robustness | `:403`, `:543-546` | The clock top (170/190) and media card top (360) are JSX magic numbers × `scaleFactor`. The media card, two notification cards and the "more" row have no overflow handling and can reach the bottom phone/camera row on screens ≤1280 px tall. | Chain anchors with Theme spacing. When media is active, cap notifications at 1 plus the "more" row. | S |
| SE-09 | P2 | Honest state | `:253,356` | `callActive` includes `"ringing"`, so an incoming call shows "Call · 00:00" with only an end-call button and no answer button. | Show "Incoming call" while ringing and add an answer ring, or hide the strip while the incoming-call screen owns ringing. | S |
| SE-10 | P2 | Prägnanz, honest viz | `:487-536` | The activity "rings" are concentric borders that only switch opacity at >0 %, so they show no progress. The text names Move and Stand, but three rings are drawn. | Draw real arcs (`Shape` + `PathArc`), or drop the rings and keep one text line covering all three. | S |
| SE-11 | P2 | Accessibility | `MediaPlaybackManager.qml:179-209` | `a11yName` defaults to the icon id, so a screen reader announces "skip-back", "play" and "skip-forward". | Set "Previous track", "Play"/"Pause", "Next track". | S |
| SE-12 | P2 | Fitts | `MediaPlaybackManager.qml:120-160` | The scrubber's hit height is paddingLarge + 2×paddingMedium = 48 px (≈30 pt), and it only seeks on tap (no drag). | Set the hit height to `itemSizeExtraSmall` and seek on drag, or use the Silica `Slider`. | S |
| SE-13 | P2 | Similarity, user direction (no tinted fills) | `MCircularIconButton.qml:23,43` (used at `MediaPlaybackManager.qml:190-197`) | The `"primary"` variant is permanently "lit": a `highlightBackgroundColor` fill at rest. That is a tinted fill, which the user rejected. | Primary = highlight-colour ring and glyph. Fill only while pressed (keeps the kept glass-ring style). | S |
| SE-14 | P2 | Doherty, feedback | `MediaPlaybackManager.qml:29-41` | Tapping the media card while locked calls `AppLaunchService.launchApp` underneath the lock. Nothing visible happens. | Use the same "unlock, then open" path as notification taps (`MarathonShell.qml:1767-`). | S |

**Good, keep:**

- DND suppresses the screen wake (`:158`), and the "Show on lock screen" privacy setting is honoured (`:76`).
- The chevron bob is gated by `MMotion.gate` and limited to 3 loops.
- Phone/camera are glass-ring buttons at `itemSizeSmall` (≈48 pt) with a11y names.
- The Sailfish-style ExtraLight clock with weekday and date lines matches `v_lock.png` well.

## PIN screen (`MarathonPinScreen.qml`)

| ID | Sev | Law | File:line | What's wrong | Proposed fix | Effort |
|---|---|---|---|---|---|---|
| SE-15 | **P0** | Postel, Tesler | `MarathonPinScreen.qml:36-43,153-163,431-540`; `apps/settings/pages/QuickPinDialog.qml:45-46` | `handleInput` verifies only when `pin.length === 6`. The pad has no OK key, and `Keys.onPressed` ignores Return. Settings offers a quick PIN of "4–6 digits", so a 4- or 5-digit PIN can never be submitted from the pad. The user is forced into password mode with no explanation. | Put an accept key (Silica `Keypad` style) in the bottom-left slot, enabled at ≥4 digits, and handle Return. Alternatively, have `SecurityManager` expose the stored PIN length and auto-submit at that length. Then drop the hard-coded 6-dot row. | S |
| SE-16 | P1 | Peak-end, error copy | `:178-199,377-398,676-690` | `errorTimer` wipes the error and PIN after 1.2 s. "Incorrect PIN (3 attempts remaining)" and "Too many failed attempts. Locked for 30 seconds." vanish before they can be read. The lockout text is static (no countdown), and the keypad stays enabled during lockout. Long messages sit in a fixed 300×40 box with no wrap. | Keep the error until the next digit. During lockout, set keys to `disabled` (opacityLow) and show a live countdown via a 1 s Timer reading `lockoutSecondsRemaining`. Let the error label wrap at the column width. | S |
| SE-17 | P1 | Fitts (layout shift) | `:377-383` | The error row toggles `visible` inside an `anchors.centerIn` Column. When an error appears, the keypad jumps by half of (row + spacing), about 55 px on the PinePhone. It jumps back 1.2 s later, while the user is re-typing. | Reserve the row's height and animate only `opacity`. | S |
| SE-18 | P1 | Correctness | `:282-303` | `Behavior on text` animates `pinScreen.parent.children[1]`, an unrelated shell sibling: it fades that sibling out and in and tries to set its `text`. Because the Behavior owns the title's change, "Enter PIN" → "Enter password" may never apply (verify in password mode). | Delete the Behavior, or target the title by id with a plain opacity fade. | S |
| SE-19 | P2 | Consistency | `:158-162` | Hardware Backspace clears the whole PIN. The on-screen delete removes one digit. | Use `pin = pin.slice(0, -1)`. | S |
| SE-20 | P2 | Sailfish fidelity | whole file (34 × `scaleFactor`, raw `Text`, `MColors`) | This is the last full surface on the legacy scale system. In `v_u_pin.png` the status bar is an opaque band, while the lock's is transparent. Keel ships `Sailfish/Silica/Keypad.qml`, Sailfish's own lock keypad. | Rebuild the pad on Silica `Keypad` plus Theme tokens. Share it with the first-run setup (fixes SE-26). | M |
| SE-21 | P2 | Hick (mystery glyph) | `:476-492` | A keyboard glyph inside the digit grid switches to password mode. It's an unlabelled icon in a slot users expect to be OK or empty. | Add a "Use password" text button next to Cancel, and give the slot to the accept key from SE-15. | S |

**Good, keep:**

- The 3+3 dot chunking (`:329-332`), and the dots' a11y name "n of 6 digits entered".
- `BusyIndicator` during auth.
- Emergency call reachable without auth.
- The underline-only Silica password field.
- One primary action per mode.

## First-run setup (`MarathonOOBE.qml`)

| ID | Sev | Law | File:line | What's wrong | Proposed fix | Effort |
|---|---|---|---|---|---|---|
| SE-22 | P1 | Jakob (platform convention = Marathon gestures) | `MarathonOOBE.qml:642-673` | The coachmarks teach "Swipe Down from the top for Quick Settings", "Swipe Right across the home grid to reach the Hub" and "Swipe Left from the Hub". They never teach the actual model: pill **left = back**, pill **right = forward**, pill **up = home/switcher**, pill **down = Quick Settings**, and **left-edge swipe = Hub peek**. Back is the most-used gesture and is missing. | Rewrite the cards around the pill. Animate the glyph on a pill silhouette and add a fifth card for the left-edge Hub peek. | S |
| SE-23 | P1 | Hick (one primary action) | `:787-797` vs `:1105-1130` | Each gesture card shows an inner "Continue" and the outer "Next" at the same time. Both advance, at different granularity. | Hide the outer Next on this page until the last card, or make Next step through the cards and remove Continue. | S |
| SE-24 | P1 | Von Restorff (colour-only) | `:221-245` (display size), `:553-582` (12/24-hour) | The selected option is shown only by `highlightColor` text. The size buttons read "75 90 100 110 125 140 150" with no unit and no "default" marker. | Add a check glyph on the selected row, as the Wi-Fi rows already do (`:472-478`). For sizes, show "%" and mark 100 "Default", or use a Silica `ComboBox`/`Slider` with a value label. | S |
| SE-25 | P1 | Correctness, Tesler | `:191-205` vs `shell/main.cpp:588-597`, `ambienceservice.cpp:38-42` | The preview multiplies `Theme.fontSize*` by `Constants.userScaleFactor`, but Theme already includes userScale through `pixelRatio`. The comment ("Silica's tokens don't follow userScaleFactor") is stale. At 150 %, the preview shows 225 %. | Drop the multiplier. | S |
| SE-26 | P2 | Similarity, Miller | `:875-899,915-1040` vs `MarathonPinScreen.qml:319-360,431-540` | The passcode pad differs from the lock pad. The dots have no 3+3 chunking, the bottom-left is blank (the lock has the keyboard key), and sizing uses a different formula with a "44 device-px" floor (`:829`) that is ≈26 pt at 270 dpi. | Use one shared keypad and dots component (see SE-20), with the floor at `Theme.itemSizeExtraSmall`. | M |
| SE-27 | P2 | Peak-end | `:1093-1103` | The "You're all set" page still shows Back beside Get Started. | Hide Back on the final page so the end state has one action. | S |
| SE-28 | P2 | User direction (no tinted fills), Similarity | `:1106-1108` (render: `r395_oobe.png`) | Next and Get Started render as teal-tinted filled rects, and Back as a grey filled rect. Disabled Next is hard to tell from enabled. This conflicts with the rejected "tinted fills". It may be intentional (Sailfish wizard). | **Decide:** keep Silica `Button`, or make the primary a glass-ring/outline style consistent with `MCircularIconButton`. In either case, disabled = `opacityLow`. | S |
| SE-29 | P2 | Zeigarnik/Ovsiankina (resume) | `:17` | `currentPage` isn't persisted. A shell restart mid-setup returns to Welcome. Wi-Fi and scale persist, the step doesn't. | Persist the step, e.g. `SettingsManagerCpp.set("oobe/step", n)`, and restore it on load. | S |
| SE-30 | P2 | Similarity, Postel (locale) | `:30,286,293` "WiFi" vs `:656` "Wi-Fi"; `:518` | The spelling mixes "WiFi" and "Wi-Fi" (QS uses "Wi-Fi"). The date format `"dddd, MMMM d, yyyy"` is hard-coded US, while the lock shows `"d MMMM"`. | Use "Wi-Fi" everywhere, and `Qt.locale().toString(date, Locale.LongFormat)`. | S |
| SE-31 | P2 | Prägnanz (type scale) | `:150,158,363,371,508,773,783,840-842,1063,1072` | Seven sizes are in use (Huge, ExtraLarge, Large, computed `titleSize`, Medium, Small, ExtraSmall). | Use Large for titles, Small for body and ExtraSmall for hints. Keep Huge only for the time preview and ExtraLarge only for Welcome/Done. | S |

**Good, keep:**

- Skip jumps to the passcode step, which can't be skipped, with the reason in a comment.
- The Wi-Fi scan has a spinner, then a "No networks found" empty state with a recovery hint.
- Rows show "Connecting…" with an inline spinner, and connected networks get a check.
- The step `PageIndicator`, the designed end page, and the Marathon mark (no sparkle).

## Home grid, pager, dock, nav corners (`MarathonAppGrid.qml`, `MarathonPageView.qml`, `MarathonBottomBar.qml`, `MarathonNavBar.qml`)

| ID | Sev | Law | File:line | What's wrong | Proposed fix | Effort |
|---|---|---|---|---|---|---|
| SE-32 | **P0** | Correctness, Miller | `MarathonPageView.qml:139-146` vs `MarathonAppGrid.qml:15-18` | `pageCount` uses the pager's own guess (4/5 base cols and rows ÷ userScale). The grid computes its capacity from `Theme.iconSizeLauncher × 1.5`. They disagree. On 720×1440 at 150 % (pixelRatio 1.5), the grid holds 3×3 = 9 per page, but the pager assumes 3×4 = 12. With 22 apps it creates 2 pages, and apps 19–22 are unreachable. At 110 % the grid holds 25 but the pager assumes 16, which adds a blank trailing page. | Compute `itemsPerPage` once (a helper or singleton that both read), or have each grid page report its capacity and bind `pageCount` to it. | S |
| SE-33 | P1 | Similarity | `MarathonBottomBar.qml:23-54` vs `MarathonLockScreen.qml:765-797` | The same Phone/Camera shortcuts look different. The home dock uses a grey `primaryColor@0.1` filled disc at `itemSizeExtraSmall`. The lock uses a glass-ring `MCircularIconButton` at `itemSizeSmall` (compare `v_home.png` with `v_lock.png`). | Build `DockButton` from `MCircularIconButton` `variant:"secondary"` at `itemSizeSmall`, keeping the vertical-drag passthrough. | S |
| SE-34 | P1 | Fitts, Hick | `MarathonBottomBar.qml:73-96,206-207` | The Hub and Open-apps page glyphs are 32 px boxes (≈20 pt, below the 24 px floor). The scrub area adds `paddingMedium`, for a total of ~56 px (≈34 pt). The "inbox" and "layers" glyphs are unlabelled and have no a11y names. | Make the indicator row `itemSizeExtraSmall` tall, with each glyph's hit width ≥ `itemSizeExtraSmall`. Add `Accessible.name` "Hub" and "Open apps". | S |
| SE-35 | P2 | User direction (tinted fills), Sailfish fidelity | `MarathonAppGrid.qml:130-151` | Icon press shows a teal `MColors.tealHalo` fill behind the icon, which is a tinted fill. | Use Sailfish launcher press feedback: highlight the icon itself (opacity/`highlighted` overlay). Keep the 0.95 scale. | S |
| SE-36 | P2 | Prägnanz, Theme tokens | `MarathonAppGrid.qml:289-423,311-318` | Icon-frame decorations left over from the old design system: an 8 px drop shadow, a black 1 px ring and a white top hairline. In `v_home.png` they show as dark outlines on the Foot/Htop icons. Grid margins are hard-coded (10, +12). The badge is a fixed 20×20 px teal disc with `MTypography` text (≈12 pt). | Remove the frame overlays (icons carry their own shape). Use Theme margins. Badge: `Theme.iconSizeExtraSmall`, `Theme.fontSizeTiny`, highlight colour. | S |
| SE-37 | P2 | Proximity, Prägnanz | `MarathonAppGrid.qml:17,62-63` | Rows stretch to fill the height. In `v_home.png` the row pitch is ≈242 px for 86 px icons, so the grid floats and its rhythm changes with screen height. | Use a fixed row pitch (icon + label + 2×paddingLarge), top-aligned as in Sailfish's launcher, and let rows = fit. | S |
| SE-38 | P2 | Fitts, contrast | `MarathonNavBar.qml:98-188` | The search and keyboard corner glyphs are 24 px with a 48 px hit area (≈30 pt), drawn at 0.6 opacity next to the pill gesture zones. | Make the hit area `itemSizeExtraSmall` square. Use `secondaryColor` instead of primary@0.6. | S |

**Good, keep:**

- The whole cell is the hit target, with `Accessible.name`.
- Launch fires on release with a 15 px movement guard, and the press-scale gives feedback under 100 ms.
- The `MEntrance` stagger honours `reduceMotion`.
- The label is `fontSizeTiny`, as on Sailfish's launcher, with word-wrap to 2 lines.
- Page dashes signal by width as well as colour.
- The pager nudges when a swipe hits the boundary.

## App context menu (`AppContextMenu.qml`)

| ID | Sev | Law | File:line | What's wrong | Proposed fix | Effort |
|---|---|---|---|---|---|---|
| SE-39 | P1 | Miller (carry context forward) | `AppContextMenu.qml:59` | "App info" calls `launchAppWithRoute("settings", "appmanager", "", …)`. It opens the generic app list, not the long-pressed app, so the user has to find the app again. | Pass the app id, as a route `appmanager/<id>` or as params, and land on that app's page. | S |
| SE-40 | P2 | Jakob (Sailfish) | `:35-73` | The menu is a floating black box with a border, 60 % of the width. It isn't Sailfish's launcher pattern (long-press → edit mode with per-icon remove, or an inline Silica `ContextMenu`). "Uninstall" looks identical to "App info". | Short term: give the destructive item `errorColor` text and order it last. Longer term: a Sailfish-style edit mode. | M |

**Good, keep:**

- Uninstall goes through a confirm dialog that names the app.
- The menu flips below top-row icons (f995afaa).

## Search (`MarathonSearch.qml`)

| ID | Sev | Law | File:line | What's wrong | Proposed fix | Effort |
|---|---|---|---|---|---|---|
| SE-41 | P2 | Minimise distance, Pareto | `MarathonSearch.qml:136-156` | Return in the field does nothing (there's no `onAccepted`). The most common flow, typing an app name and pressing Enter, needs a tap. | `onAccepted: if (searchResults.length) selectResult(searchResults[0])`. | S |
| SE-42 | P2 | Empty states, error copy | `:159`, `:227-237` | The placeholder "Search apps and settings" duplicates the centred "Search apps, settings and more" (two strings for one idea). The no-results state ("No results for "x"") offers no next step. | Keep one string. When the query is empty and there are no recents, show the 4–8 most-used apps. On no results, add a hint ("Check the spelling, or search in Settings"). | S |
| SE-43 | P2 | Fitts, Jakob | `:166-193`, `:245-280` | The clear-text hit area is 32 + 24 = 56 px (≈34 pt). The "Clear recents" text button sits at the leading edge (first thing read) with ≈52 px height, and "Recent" is a right-aligned label: an inverted Silica `SectionHeader`. | Use a Silica `SectionHeader` "Recent" (right). Put "Clear" in a pull-down/menu item or a trailing `IconButton` at `itemSizeExtraSmall`. Make the clear-text hit area ≥ `itemSizeExtraSmall`. | S |
| SE-44 | P2 | Hick (grouping) | `:52-60,329-396` | Apps, settings and pages are interleaved (capped at 20), with the type only in the subtitle. | Section the results by type with `SectionHeader`s: Apps first, then Settings. | S |

**Good, keep:**

- The Silica underline field with a highlight-on-focus glyph.
- Keyboard up/down/Return navigation of the list.
- Pressed rows use the highlight background.
- Recents with a history glyph and a11y names.

## App switcher (`MarathonTaskSwitcher.qml`, `TaskCard.qml`)

| ID | Sev | Law | File:line | What's wrong | Proposed fix | Effort |
|---|---|---|---|---|---|---|
| SE-45 | P1 | Prägnanz, uniform connectedness | `TaskCard.qml:193-213,317-323` | Each card draws the live preview and the app's cover over its bottom half on a 0.7 scrim. With list-style apps the two text layers interleave: `v_r_switcher.png` shows "On / Off / 94%" over Settings rows, with stray Wi-Fi/BT glyphs. The preview is centre-cropped, so the app's header is cut off ("Search settings" clipped). | Show one representation: the cover when the app provides one (Sailfish convention), otherwise the live preview top-aligned. | M |
| SE-46 | P1 | Doherty, Fitts | `TaskCard.qml:145-171,523-561` | A tap opens the app only if released within 300 ms, so slower deliberate taps are silently ignored. The card has no pressed state, so nothing acknowledges the touch. | Drop the time limit (keep the 15 px movement guard). Show a pressed state immediately (highlight the border plus a slight scale). | S |
| SE-47 | P2 | Similarity, Theme tokens | `MarathonTaskSwitcher.qml:90-136` | The empty switcher shows a clock in `MHaloedDisplay` (84×scaleFactor, thin, −2 tracking) with a hand-rolled `#80000000` drop shadow. Its comment claims it is "identical to the lock clock", but the lock now uses `Silica.Label` Huge×1.9 ExtraLight. | Use a Silica `ViewPlaceholder` ("No open apps" with a hint), or share the lock's clock component. | S |
| SE-48 | P2 | Correctness, polish | `MarathonTaskSwitcher.qml:71,166-168`; `TaskCard.qml:455,618-633` | `deltaTime = Date.now() - startY` subtracts a pixel coordinate. Grid margins are hard-coded (16/24). Close has no swipe-to-dismiss and no undo. The dev string "Native apps not available on macOS" ships. | Track the press time. Use Theme margins. Add swipe-up-to-close on cards. Remove the macOS string. | S |

**Good, keep:**

- The close X has a 70 px target with a 16 px hit inflation and an a11y name "Close <app>".
- "Preview unavailable" falls back to the icon and title.
- Tapping empty space returns home.

## Hub and peek (`MarathonHub.qml`, `MarathonPeek.qml`, `ui/MHubRow.qml`)

| ID | Sev | Law | File:line | What's wrong | Proposed fix | Effort |
|---|---|---|---|---|---|---|
| SE-49 | **P0** | Core flow broken | `MarathonHub.qml:135-160`; `MarathonPageView.qml:189-194`; `MarathonPeek.qml:231-240` | `MHubRow.activated` emits `hub.notificationTapped(0, appId, title)`, but neither Hub instance (pager page 0, peek panel) connects `notificationTapped`. Tapping a notification only flashes the highlight. The id is also hard-coded to 0, so the notification couldn't be marked read or dismissed even if connected. | Require the `id` role in the delegate and emit it. Connect both instances to the same handler the lock uses: `NotificationService.dismissNotification(id)` + `NavigationRouter.navigateToDeepLink(appId, …)` (`MarathonShell.qml:1767-1778`). | S |
| SE-50 | P1 | Zeigarnik (no nagging loops), Jakob | `MarathonHub.qml:120-161`, `MHubRow.qml` | The Hub has no way to dismiss or clear notifications (no swipe, no "Clear all"). Because taps are dead (SE-49), nothing ever becomes read, so unread dots and lock cards accumulate. | Add swipe-to-dismiss per row, plus a Sailfish Events-style `PullDownMenu` "Clear notifications". | M |
| SE-51 | P1 | Honest copy | `MarathonHub.qml:186-209` | `accountFor` invents labels: `messages`→"iMessage", `linear`→"Linear · Work", `work`→"Work". `v_hub.png` shows "iMessage" under an SMS from Alex Doe. | Use the sending app's display name from the app model, with no hard-coded map. | S |
| SE-52 | P2 | Accessibility, Prägnanz | `MarathonHub.qml:63,164-180`; `MHubRow.qml:28-37,122-126` | The header date is evaluated once and goes stale after midnight. App notifications get initials monograms ("BL" for "Battery low") instead of the app icon. The unread dot sits 6 px from the edge, inside the left-edge peek zone. `MHubRow` has no `Accessible.role`/`name`. | Bind the date to `SystemStatusStore.dateString`. Show the app icon when the title isn't a person. Inset the dot to `paddingMedium`. Add `Accessible.role: Button` and name it "<name>, <snippet>". | S |
| SE-53 | P2 | Occam, Similarity, Doherty | `MarathonPeek.qml:43,125-229,236-237`; `MarathonShell.qml:1262-1265` | For the first 35 % of the drag the peek shows a different UI (generic bell circles) and then cross-fades to the Hub. Its empty copy "No notifications" differs from the Hub's "Nothing new". Tapping a strip icon shows a toast instead of opening. `Logger.info` runs on every move event. | Drop the strip and slide the real Hub in from the first pixel. Use one empty string. Remove the per-frame logs. | S |

**Good, keep:**

- The Sailfish Events layout: date, then agenda with a highlight bar, then notifications.
- The quiet "Nothing new" empty state.
- Unread is shown by a dot plus a brighter snippet, not colour alone.
- The left-edge peek follows the finger, with velocity and threshold commit.

## App launch splash and failure (`MarathonAppWindow.qml`)

| ID | Sev | Law | File:line | What's wrong | Proposed fix | Effort |
|---|---|---|---|---|---|---|
| SE-54 | P2 | Doherty (>10 s), Pragnanz | `MarathonAppWindow.qml:295-306,309-370` | Between the 1 s spinner and the 20 s watchdog there's no "still opening" message and no visible cancel (only gestures). The fallback for a missing icon is a generic `grid-3x3` glyph. | At ~8 s show "Still opening…" plus a Close text button, and bring the watchdog down to ~15 s. Use the app's name initial in a glass ring instead of the grid glyph. | S |

**Good, keep:**

- The icon-on-ambience splash, with the spinner only after 1 s (matches the budget).
- The 20 s watchdog turns a stuck launch into an error state.
- The error screen uses a Silica `InfoLabel` ("<App> couldn't open") with one primary action ("Try again") and a transparent "Close".
