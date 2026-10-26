# UX playbook audit: shell system surfaces

Date: 2026-10-12 · Scope: quick settings, status bar, nav bar/pill, on-screen keyboard, notification/error/connection toasts, volume/brightness HUD, power menu, permission dialog, confirm dialog, share sheet, clipboard history, Wi-Fi password dialog, lock-screen network agent, incoming call, alarm, cell broadcast, screenshot preview · Method: I read the code against the UX playbook's build checklist and numeric defaults. For Jakob's law the baseline is Sailfish/Keel Silica conventions plus Marathon's pill gesture model. I also checked the current PinePhone screenshots (`v_qs.png`, `r395_shell.png`). Read-only; nothing ran on a device. `BluetoothPairDialog.qml` was deleted from the tree while this audit ran, so it isn't covered.

Size conversion used throughout: the PinePhone runs Keel at `Theme.pixelRatio` 1.25 (720/540, quarter-stepped) at about 270 ppi. 44 pt is about 74 px, which is about 59 Silica units. `Theme.itemSizeExtraSmall` (70 u = 88 px) clears it. `iconSizeExtraSmall + 2×paddingMedium` (48 u = 60 px, about 36 pt) does not. Marathon's `Constants.scaleFactor` is dp (160 dpi base), so `44 * scaleFactor` is about 44 pt.

## Summary

The newest surfaces are already close to Sailfish. The QS switch grid, power menu, permission dialog and Wi-Fi dialog use glass rings, DialogHeader-style corner actions, the ambience backdrop and `Silica.Theme` tokens throughout. The older surfaces have not caught up. The keyboard, language selector, screenshot preview and confirm dialog still use hard-coded px, hex colours and their own card styles.

The serious problems are functional, not visual:

- **Broken input.** Long-press never works on a key unless it has accent alternates, and the accent popup closes the moment the finger lifts. So accents, backspace auto-repeat and the language switcher are all unreachable.
- **Fake or lying controls.** The QS Hotspot tile starts an AP that every Marathon phone shares, with the hard-coded password `marathon2025`. Settings › Quick settings toggles tiles the shell never reads. The share sheet shares nothing. The connection toast says "Connected" when the radio has only been switched on.
- **Inconsistent dismissal.** The four toasts use four different gestures: swipe up, swipe down, swipe right, or none. The error toast eats every tap on the screen for 5 s.
- **Gesture model gaps.** Pulling down on the pill does not open QS. A swipe up in the outer 15 % of the pill opens search or the keyboard instead of going home.

Counts: **P0 4 · P1 22 · P2 31** (57 findings).

Severity: P0 broken · P1 clearly violates playbook · P2 polish. Effort: S under 1 h · M about half a day · L a day or more.

### Dismissal consistency matrix

| Surface | Tap outside | Swipe | Pill back | Auto |
| --- | --- | --- | --- | --- |
| Quick settings | closes (also on gaps *inside* the shade) | up | closes | – |
| Notification banner | – | **up** | – | 5 s |
| Error toast | closes, **and swallows the tap anywhere on screen** | **down** | – | 5 s |
| Connection toast | – | **none** | – | 3 s |
| Screenshot preview | – | **right** (and also opens Gallery, SS-19) | – | 3 s |
| Power menu | cancels | – | cancels (pending step first) | – |
| Confirm dialog | cancels | – | covered by dialog | – |
| Permission dialog | blocked | – | covered (hardware Back only) | – |
| Wi-Fi password | **dismisses and wipes the typed password** | – | covered | – |
| Share sheet / Clipboard | closes | – | closes | – |
| Alarm | – | up anywhere = **dismiss** | covered | – |
| Cell broadcast | **falls through to the UI beneath** | – | covered | – |

Target: banners swipe **up** to dismiss and tap to open. Full-screen dialogs ignore taps outside, and Back means Cancel. Sheets and menus close on tap outside and on Back.

---

## Cross-cutting

**SS-01 · P2 · Von Restorff (reduced motion) · `shell/qml/theme/MMotion.qml:19-20,171,408`**
Problem: only `MMotion.durationFor()` honours `reduceMotion`. The raw `MMotion.quick`/`moderate` constants don't, and neither do the literal durations. Surfaces that ignore it: NotificationToast (`:208-240`), StatusBar (`:53-136`), SystemHUD (`:83`), PermissionDialog (`:256-259`), IncomingCall (`:187-198`), ErrorToast (`:137-196`, 250-400 ms literals), ConnectionToast (`:264-281`), ConfirmDialog (`:390-432`), ShareSheet (`:137-142`), Clipboard (`:293-298`), ScreenshotPreview (`:102-160`, including a 0.8-opacity white full-screen flash). The infinite pulse in the cell broadcast overlay (`:96-109`) ignores it too.
Fix: route every one through `MMotion.durationFor(role)`, or gate them with `enabled: !MMotion.reduceMotion`. Make the screenshot flash and the broadcast pulse static under reduce-motion.
Effort: M.

**SS-02 · P2 · Jakob (localisation) · many files**
Problem: user-facing strings are not wrapped in `qsTr`:
- ConnectionToast: all strings.
- ErrorToast: `"Error"`, `"Close"`.
- WiFiPasswordDialog: all strings.
- Network agent: all strings.
- IncomingCall: `"Incoming call"`, `"Decline"`, `"Answer"`, the unlock note.
- Alarm: `"Snooze"`, `"Dismiss"`, `"↑ Swipe up to dismiss"`.
- Cell broadcast: all category titles and the hold copy.
- ShareSheet, ClipboardManager: all strings.
- ConfirmDialog: default `"Confirm"`/`"Cancel"`.
- NotificationToast: `"Reply..."`, `"Send"`.
- LanguageSelector: `"Select Language"`.
- Accessible names: NavBar `"Search"`/`"Keyboard"`, MQSSlider `"Brightness"`/`"Volume"`, PowerMenu `"Power"`.

Fix: wrap each in `qsTr()`. Emergency-alert titles matter most because WEA/ETWS have to be localised.
Effort: S.

**SS-03 · P2 · Similarity (iconography) · `ErrorToast.qml:125`, `ShareSheet.qml:60`, `ClipboardManager.qml:273`, `MarathonShell.qml:~2050`**
Problem: these use Sailfish bitmap icons (`image://theme/icon-m-close`, `icon-m-delete`), while every other surface uses Phosphor `GlyphIcon`. Airplane is `"plane"` in the status bar and toast but `"airplane-tilt"` in QS. The ethernet toast icon `"plug-zap"` doesn't exist in `PhosphorGlyphs.js`, so it renders blank.
Fix: use one icon family, for example a Marathon.Silica `IconButton` that takes a glyph name. Use one airplane glyph. Replace `plug-zap` with a glyph that exists (`plugs-connected`/`cable`).
Effort: S.

**SS-04 · P2 · Occam (dead code) · various**
Problem, mention only:
- `components/QuickSettingsTile.qml` (255 lines) is unused but still listed in `shell/CMakeLists.txt:290`.
- `MarathonNavBar.qml:449-459`: `gestureProgressResetTimer` is never started.
- `PredictionBar.qml:79-86`: the "..." label sits inside a bar that is invisible whenever it would show.
- `SystemHUD.qml:30-33`: `hide()` sets `hudVisible=false` before `fadeOut` runs, so the fade is never seen.

Fix: delete them, or (for the HUD) set `visible` only from `opacity > 0`.
Effort: S.

---

## Quick settings (`components/MarathonQuickSettings.qml`, `ui/MQSTile.qml`, `ui/MQSSlider.qml`)

Good:
- `MQSTile` is the kept glass ring at `itemSizeExtraSmall`. Its MouseArea covers the full grid cell (~132×120 px, comfortably over 44 pt).
- It exposes `Accessible.checkable/checked`, which tells a switch from an action.
- On is shown by fill, border and label colour together, so it isn't colour-only.
- The reveal is coupled to the gesture and gated on `reduceMotion`.
- Ambiences sit in a top strip as in Sailfish, and the current one is marked by border and highlight label.

**SS-05 · P0 · Tesler / fake control (security) · `shell/src/services/systemcontrolstore.cpp:227-237`; `MarathonQuickSettings.qml:125`**
Problem: the Hotspot tile calls `createHotspot("Marathon Hotspot", "marathon2025")`. Every Marathon phone broadcasts the same SSID with a password that is public in the source, and the user is never shown it. `setIsHotspotOn(true)` is also set before NM answers. If creation fails (`connectionFailed` is only surfaced in OOBE), the tile stays lit with no AP running.
Fix: generate a per-device passphrase on first use and store it. Show SSID and password in Settings › Hotspot, and open that page on long-press. Drive the tile from `NetworkManagerCpp.isHotspotActive` rather than optimistically, and roll back on failure with an error toast.
Effort: M.

**SS-06 · P0 · Fake control · `MarathonQuickSettings.qml:116-145`; `apps/settings/pages/QuickSettingsPage.qml:40-48`**
Problem: Settings › Quick settings lets the user switch tiles on and off and reset them (`Settings.enabledQuickSettingsTiles`, `quickSettingsTileOrder`). The shell's tile list is hard-coded and never reads either setting (`grep enabledQuickSettingsTiles shell/qml` finds nothing). Every toggle on that page is a no-op.
Fix: filter and order `tiles`/`moreTiles` by `SettingsManagerCpp.enabledQuickSettingsTiles` and `quickSettingsTileOrder`, keeping the existing sensor guard for Rotation. Otherwise remove the settings page.
Effort: M.

**SS-07 · P1 · Doherty (feedback for 1-10 s) · `ui/MQSTile.qml:283-334`; `systemcontrolstore.cpp:129-224`**
Problem: Wi-Fi, Bluetooth, Mobile data and Location toggles are asynchronous (NM, BlueZ, ModemManager) and often take 1-3 s. The tile gives a press scale, then reverts to its old state until the backend confirms. It reads as "didn't take", and users tap again, which toggles it back.
Fix: add `busy` to `MQSTile`, as Silica `Switch.busy` does: set it on tap, clear it on the state-changed signal or a 10 s timeout, and pulse the ring border meanwhile.
Effort: M.

**SS-08 · P2 · Jakob · `ui/MQSTile.qml:329-334`**
Problem: long-press does nothing. In Sailfish's top menu a long-press on a switch opens its settings page, and the dead `QuickSettingsTile.qml` used to have `longPressed`.
Fix: add `signal pressAndHold`, and open `settings://wifi`, `bluetooth`, `hotspot`, `display` and so on.
Effort: S.

**SS-09 · P2 · Similarity · `MarathonQuickSettings.qml:143,149,459-467`**
Problem: Power is a one-shot action but is drawn as a glass ring identical to the switches. Screenshot, also a one-shot action, is drawn as a plain glyph shortcut. Same function, two looks; different function, same look.
Fix: move Power into the shortcut row, or into the power menu only via the power key. Keep rings for switches only.
Effort: S.

**SS-10 · P2 · Hick (labels) · `MarathonQuickSettings.qml:118-143`**
Problem: some labels are ambiguous or don't match the rest of the shell:
- "Auto" (auto-brightness) gives no hint of what it is automating.
- "Night" (night light).
- "Saver".
- "Silent" means DND, but the toast and status bar never say "Silent".
- "Flight" vs "Airplane mode" in ConnectionToast.

Fix: use "Auto-bright", "Night light", "Power saver", and one airplane term shared by tile, toast and status bar.
Effort: S.

**SS-11 · P2 · Proximity (1:2) · `MarathonQuickSettings.qml:273,367,455`**
Problem: the column spacing between groups (ambiences, switch grid, slider, shortcuts) is `paddingMedium`, the same as `rowSpacing` inside the switch grid. Groups don't separate, and you can see this in `v_qs.png`.
Fix: keep `rowSpacing: paddingMedium` inside grids and use `paddingLarge` (2×) between groups.
Effort: S.

**SS-12 · P2 · Fitts / accidental dismiss · `MarathonQuickSettings.qml:65-68`**
Problem: the root `TapHandler` closes the shade on any tap that lands on no control, including the gaps between the ambience strip, the rows and the "More controls" header. A near-miss on a tile closes QS.
Fix: close only on taps below the content (`point.position.y > content.y + content.height`). Sailfish doesn't close the top menu on taps inside it.
Effort: S.

**SS-13 · P2 · Fidelity (hard-coded px) · `MarathonQuickSettings.qml:197-213,474-484`**
Problem: the drag handle is a fixed `72×6` px rectangle in `Qt.rgba(1,1,1,0.72)`. The terminus hairlines are `height: 1` with raw colours.
Fix: size the handle from `Theme.itemSizeExtraSmall` and `Theme.paddingSmall`, colour it `Theme.rgba(Theme.primaryColor, Theme.opacityHigh)`, and use `Theme.lineWidth` for the hairlines.
Effort: S.

**SS-14 · P2 · Accessible names / Fitts · `MarathonQuickSettings.qml:155-194`**
Problem: `QSShortcut` (Screenshot, Camera, Alarm, Note, Settings) has no `Accessible.role` or `name`. Its hit height is about `iconSizeSmall + paddingSmall + fontSizeTiny line`, roughly 72 px or 43 pt, which is borderline.
Fix: add `Accessible.role: Button`, `Accessible.name: label` and `onPressAction`. Set a minimum height of `Theme.itemSizeExtraSmall`.
Effort: S.

**SS-15 · P2 · Similarity · `ui/MQSSlider.qml:5-17,46`; `SystemHUD.qml:92`**
Problem: the slider shows a bare "9"/"70" while the volume HUD shows "70%". The file's header comment describes a different control (44 px row, teal gradient, white thumb).
Fix: append "%" (or drop the number in both places) and replace the comment with a one-liner.
Effort: S.

---

## Status bar (`components/MarathonStatusBar.qml`, `src/services/statusbariconservicecpp.cpp`)

Good: all sizes are Theme tokens (`iconSizeExtraSmall`, `fontSizeExtraSmall/Small/Tiny`, `horizontalPageMargin`), the numbers use `tnum`, the clock is centred and battery is on the left as in Sailfish, and the low-battery glyph switches at 25 % and 10 %.

**SS-16 · P1 · Similarity / misleading signal · `MarathonStatusBar.qml:158-164`**
Problem: when Do Not Disturb is on, the status bar shows a plain `"bell"`, the glyph that normally means sound is on. The QS tile for the same state uses `"bell-slash"`.
Fix: `name: "bell-slash"`.
Effort: S.

**SS-17 · P1 · Von Restorff (colour/opacity-only) + contrast · `statusbariconservicecpp.cpp:66-103`; `MarathonStatusBar.qml:166-209`**
Problem:
- Bluetooth off, on and connected use the same glyph at opacity 0.3, 0.6 and 1.0. White at 0.3 on the dark bar is about 2.4:1, below the WCAG 1.4.11 3:1 floor, and the three states can't be told apart.
- Wi-Fi off and disconnected return `"wifi-off"`, and connected at zero strength returns `"wifi-zero"`. Neither glyph exists in `PhosphorGlyphs.js`, so both render blank.
- Both icons show "always", so the bar carries a dim ghost icon most of the time (visible in `r395_shell.png`).

Fix: follow Sailfish. Hide Bluetooth when off, use `bluetooth` when on and `bluetooth-connected` when connected, all at full opacity. Hide Wi-Fi when off. Use `wifi-slash` only for enabled but not connected, and `wifi-low` for zero strength. Encode strength by glyph, not opacity.
Effort: S.

**SS-18 · P2 · Accessible names · `MarathonStatusBar.qml:24-209`**
Problem: `GlyphIcon` sets `Accessible.ignored: true`, and the bar has no accessible summary. A screen reader gets nothing for battery, signal or Wi-Fi state.
Fix: on the bar `Item`, add `Accessible.role: StaticText` with a name that summarises the state ("Battery 82 %, Wi-Fi connected, …").
Effort: S.

---

## Nav bar / pill (`components/MarathonNavBar.qml`, wired in `MarathonShell.qml:1102-1200`)

Good: the axis locks after 10 px (a thumb that arcs up during a back swipe stays a back swipe). Predictive back tracks the finger 1:1 and settles with an eased spring on cancel. `onCanceled` resets the state. Back closes the keyboard first, then overlays, then the app, which is the right order.

**SS-19 · P1 · Jakob (Marathon gesture model) · `MarathonNavBar.qml:266-291,384-411`**
Problem: the gesture model says pulling down on the pill opens quick settings. The code clamps `currentY = Math.max(0, diffY)`, and a downward vertical gesture only acts when QS is already open. If it's closed, a pull-down is logged as "GESTURE CANCELLED". QS can only be opened from the status bar.
Fix: in the vertical branch, when `diffY < 0 && !UIStore.quickSettingsOpen`, drive `UIStore.quickSettingsHeight` from `-diffY` and on release reuse the status-bar open/close thresholds (`MarathonShell.qml:~1680`).
Effort: M.

**SS-20 · P1 · Hick / Occam (hidden modes) · `MarathonNavBar.qml:238-241,318-339`**
Problem: a swipe up that starts in the left or right 15 % of the bar (about 108 px each side on the PinePhone) toggles search or the keyboard instead of going home. The primary "up = home" gesture silently changes meaning depending on where the thumb lands, and nothing on screen says so.
Fix: remove the zone swipes. The search and keyboard buttons already exist (SS-21). Keep swipe-up as home everywhere on the pill.
Effort: S.

**SS-21 · P1 · Fitts · `MarathonNavBar.qml:105-106,137,151-152,181`**
Problem: the search and keyboard buttons are `iconSizeExtraSmall` (24 u) with `anchors.margins: -paddingMedium`. That gives a 48 u hit area, about 60 px or 36 pt, under the 44 pt default. Their MouseAreas (z 300) also take presses that start on them, so a back or forward swipe that begins at the far edge fails.
Fix: make each hit area `Theme.itemSizeExtraSmall` square, keeping the glyph at 24 u. Forward drags past `Theme.startDragDistance` to the nav MouseArea (`propagateComposedEvents`, or a `TapHandler` instead of a MouseArea).
Effort: S.

**SS-22 · P2 · Fitts (scale-dependent thresholds) · `MarathonNavBar.qml:260,318,349,372,384,395,412`**
Problem: commit thresholds are raw px (10, 30, 40, 50, 60, 100, and 500 px/s). On the L5 (scale about 1.8) the same physical swipe covers 1.8× more px than on a 160 dpi panel, so gestures feel different on each device. `shortSwipeThreshold` and `longSwipeThreshold` are scaled; these aren't. The release path also logs with emoji banners ("⬆⬆⬆ MINIMIZE GESTURE TRIGGERED ⬆⬆⬆").
Fix: multiply by `Constants.scaleFactor`, or use `Theme.startDragDistance` and its multiples. Drop the banner logs.
Effort: S.

**SS-23 · P2 · Fidelity · `MarathonNavBar.qml:70-71`**
Problem: the pill is sized from unrelated tokens: `Constants.cardBannerHeight` for width and `spacingXSmall` for height.
Fix: name dedicated tokens (`pillWidth`, `pillHeight`) from `Theme.itemSizeLarge` and `Theme.paddingSmall`.
Effort: S.

---

## On-screen keyboard (`keyboard/**`)

Good:
- Sensitive, URL, email and number fields turn prediction and autocorrect off (`MarathonKeyboard.qml:16`).
- Autocorrect can be undone.
- Letter keys have no boxes, function keys sit on a faint backdrop, and a pressed key gets the ambience highlight, as in Sailfish.
- Every key press gets a haptic and a visual state within one frame.

**SS-24 · P0 · Postel / broken control · `keyboard/UI/Key.qml:173-218`**
Problem: alternate (accent) characters can never be entered. A long-press shows the popup while the key's MouseArea still holds the grab. The popup's own MouseAreas (`:157-166`) never see the touch, and `onReleased` unconditionally sets `showingAlternates = false`, so the popup closes the moment the finger lifts. The 60+ accented characters in every layout are unreachable.
Fix: do slide-to-select inside the key's MouseArea. In `onPositionChanged` while `showingAlternates`, map `mouse.x` to the alternate under the finger and highlight it. In `onReleased`, emit `alternateSelected(thatChar)` if one is highlighted. Remove the popup's MouseAreas.
Effort: M.

**SS-25 · P1 · Doherty / broken control · `keyboard/UI/Key.qml:183-184,206-218`; `Layouts/QwertyLayout.qml:280-292,333-342`; `Layouts/DynamicLayout.qml:112-114,173-175`**
Problem: `longPressTimer` only starts when `alternateChars.length > 0`, so `pressAndHold` never fires on keys without alternates. As a result:
- Backspace hold-to-repeat is dead.
- Emoji long-press, the only in-layout path to the language selector on QWERTY and Dynamic (the default layout), is dead.

Fix: always start the timer, and show the alternates only when there are some: `onTriggered: { if (alternateChars.length) showingAlternates = true; pressAndHold() }`.
Effort: S.

**SS-26 · P1 · Von Restorff (state visibility) · `Layouts/QwertyLayout.qml:245-251`; `keyboard/UI/Key.qml:19`**
Problem: caps lock sets `iconName: "chevrons-up"`, which doesn't exist in `PhosphorGlyphs.js`, so the shift key goes blank. One-shot shift sets `highlighted`, which `Key.qml` never reads, so the shift key looks identical whether shift is off or on.
Fix: use an existing glyph (`caret-double-up` or `arrow-fat-line-up`). In `Key.qml`, show the pressed backdrop when `highlighted` (`visible: key.pressed || key.isSpecial || key.highlighted`, highlight colour when `highlighted`).
Effort: S.

**SS-27 · P1 · Fidelity / Similarity · `keyboard/UI/LanguageSelector.qml:15-79`**
Problem: the language picker ignores the design system completely:
- Colours are hex: `#2a2a2a` background, `#3a3a3a` cells, `#4a9eff` blue for the selected language (not the ambience highlight), `#444444` and `#ffffff`.
- Fonts are px: 14, 10 and 20 × scaleFactor.
- Languages are shown as flag emoji, but a flag is not a language (pt_BR shows 🇧🇷, ar_SA shows 🇸🇦).
- The title is untranslated.

Fix: rebuild it as a Silica list. Use `Silica.Theme` colours, with highlight for the current language. Show the native language name (`Qt.locale(id).nativeLanguageName`) in `fontSizeMedium` and drop the flags.
Effort: M.

**SS-28 · P2 · Fidelity (hard-coded px/colours) · `Key.qml:29-30,46-47,86-92,106-145`; `QwertyLayout.qml:171,204,237,311` (same in Number/Phone/Email/Url/Dynamic/Terminal); `MarathonKeyboard.qml:249,294`**
Problem:
- Key geometry is `60/45/70/80/50/40 * Constants.scaleFactor`.
- The preview and popup use `Qt.rgba(0,0,0,0.9)`.
- A 2 dp `#666666` rule sits between every key row. Sailfish's keyboard has no row rules.
- The keyboard background is `Qt.rgba(0.04,0.04,0.05,0.97)`, not ambience-tinted.

Fix: use `Theme.itemSizeSmall`/`paddingSmall` units. Use `Theme.highlightDimmerColor`/`overlayBackgroundColor` for popups and the background. Delete the row rules.
Effort: M.

**SS-29 · P2 · Type scale · keyboard**
Problem: the keyboard uses 8 distinct sizes: `fontSizeLarge` keys, `Small` function keys, `Tiny` alt hints, `Huge` preview, `Medium` predictions, plus LanguageSelector's 14/10/20 px. The playbook ceiling is 4-5.
Fix: after SS-27, cut to Large, Medium, Small and Tiny, with the preview at `Huge` as the one deliberate exception.
Effort: S.

**SS-30 · P2 · Fitts · `QwertyLayout.qml:325-370`; `MarathonKeyboard.qml:294`; `PredictionBar.qml:15`**
Problem: emoji, dismiss and "." are each 8 % of row width, about 55 px or 33 pt on the PinePhone. The prediction `Loader` is fixed at 40 dp while `PredictionBar.implicitHeight` is 48 dp, so the chips overhang into the first key row.
Fix: merge dismiss into a long-press on the "?123" key, or move it to the nav bar's keyboard button (it already toggles). That frees width for emoji and ".". Size the loader from `PredictionBar.implicitHeight`.
Effort: S.

**SS-31 · P2 · Accessible names · `keyboard/UI/Key.qml`**
Problem: keys have no `Accessible.role` or `name`. Icon keys (shift, backspace, enter, dismiss, emoji) are anonymous.
Fix: add `Accessible.role: Button` and `Accessible.name: iconName ? text : displayText`, mapping the `text` ids to human names.
Effort: S.

---

## Notification banner (`components/NotificationToast.qml`)

Good: it uses Silica tokens and type (`fontSizeSmall` title, `ExtraSmall` body, `iconSizeSmallPlus` glyph). The height is derived from content, the auto-hide pauses while the finger is down, the queue is serialised, and the banner sits below the status bar.

**SS-32 · P1 · Jakob / Hick · `NotificationToast.qml:182-204`**
Problem: tapping a banner does different things depending on the category. For messaging apps (a hard-coded list of ids plus `category.includes("message")`) a tap opens inline reply instead of the conversation, and with reply open there's no way to go to the app at all. Sailfish and every other platform open the source on a tap.
Fix: a tap always opens the app or deep link. Expose reply as a separate "Reply" action, either a pull-down on the banner or a small action button, for any notification that advertises the `inline-reply` capability.
Effort: M.

**SS-33 · P2 · Doherty (direct manipulation) · `NotificationToast.qml:169-173,208-213`**
Problem: the drag doesn't track the finger. Each move adds the cumulative `dragY * 0.5` to `toast.y`, so the banner runs away faster the longer you drag, and `Behavior on y` animates every assignment over 240 ms. Dismissal is swipe-up only, and the threshold is a raw `-30` px.
Fix: set `toast.y = baseY + Math.min(0, dragY)` with the Behavior disabled while pressed. Use a scaled threshold (`Theme.startDragDistance * 2`).
Effort: S.

**SS-34 · P2 · Peak-end · `NotificationToast.qml:125-154`**
Problem: the inline reply ignores the result of `InvokeReply` and dismisses straight away: no "Sent", and on failure the typed text is gone. "Reply..." and "Send" are untranslated. The field and button are fixed at 40/48/80 dp.
Fix: keep the text until `InvokeReply` returns OK, then show a brief "Sent" before dismissing. Use `Theme.itemSizeSmall` for the row.
Effort: S.

---

## Error toast (`components/ErrorToast.qml`)

**SS-35 · P1 · Fitts / modality · `ErrorToast.qml:42-45`**
Problem: a full-screen `MouseArea` sits under the card while the toast is showing (5 s). Any tap anywhere on the shell is eaten: it dismisses the toast and is lost. A non-modal notice becomes modal.
Fix: delete the full-screen MouseArea. Dismiss via the close button, a swipe, or the timeout.
Effort: S.

**SS-36 · P1 · Similarity (dismissal) · `ErrorToast.qml:61-76`**
Problem: swiping **down** dismisses it (`y > 50` with `maximumY: 100` raw px), the opposite of the notification banner, which swipes **up**. The resting `y` is already about 40 px, so roughly 10 px of downward drag dismisses. An upward drag snaps back.
Fix: use the same swipe-up-to-dismiss as SS-33 with the same scaled threshold. Better, make Error, Connection and Notification banners one component (they already share the `black 0.85` card and 1 px border).
Effort: S.

**SS-37 · P2 · Error copy · `MarathonShell.qml:~2058`; `ErrorToast.qml:17`**
Problem: the only caller is battery warnings, and the fallback title is a bare "Error". The component has no slot for a fix or action ("Plug in now" / "Turn on Power saver").
Fix: add an optional `actionText`/`action` callback rendered as a text button, and use it for "Turn on power saver" on low battery.
Effort: S.

---

## Connection toast (`components/ConnectionToast.qml`)

**SS-38 · P1 · Lying feedback · `ConnectionToast.qml:94-99`; `MarathonShell.qml:2041-2054`**
Problem: `onIsWifiOnChanged` shows "Connected to WiFi" when the radio turns on, before any association, usually with an empty `wifiNetwork`. `MarathonShell` separately shows "Connected to Wi-Fi" on `wifiConnectedChanged`. You get two toasts, one of them false, with two spellings. "Bluetooth enabled" and "Airplane mode enabled" also fire when the user has just tapped the QS tile, which already showed the result.
Fix: delete the `SystemStatusStore` handlers here. Keep only the `NetworkManagerCpp` connected/disconnected events, with the SSID ("Connected to %1"). Don't toast state the user changed by hand.
Effort: S.

**SS-39 · P2 · Similarity (dismissal) · `ConnectionToast.qml:229-262`**
Problem: it can't be dismissed by any gesture.
Fix: fold it into the shared banner from SS-36.
Effort: S.

---

## Volume / brightness HUD (`components/SystemHUD.qml`)

Good: it follows Sailfish (a strip at the top with a highlight bar), uses Theme tokens throughout and `tnum` for the percentage, and swaps to a muted glyph at 0. No P0 or P1 issues; the fade-out bug is in SS-04.

**SS-40 · P2 · Von Restorff · `SystemHUD.qml:63`**
Problem: when the ringer is silenced by DND or vibrate-only, the HUD still shows `speaker-high` with a value.
Fix: show `bell-slash` or `vibrate` plus a "Silent" label when `SystemControlStore.isDndMode`.
Effort: S.

---

## Power menu (`components/PowerMenu.qml`)

Good:
- Sleep is the single emphasised ring (a safe default).
- Restart and Power off go through a confirm step whose copy states the consequence ("You'll need to hold the power button…").
- Back and tap-outside cancel the pending step before closing the menu.
- The ring targets are `itemSizeLarge` (137 px) and labels are `fontSizeSmall`.

**SS-41 · P2 · Fitts (destructive placement) · `PowerMenu.qml:272-312`**
Problem: the confirm ring is centred horizontally, near where the middle "Restart" ring was a moment earlier. Only the vertical shift from the added description label separates them, so a double-tap on Restart can confirm a reboot. The ring's `iconSize: 24` is raw px.
Fix: put the confirm ring a full ring-height lower than the original row, or ignore taps for `Theme.minimumPressHighlightTime * 4` after entering `pending`. Use `iconSize: Theme.iconSizeMedium`.
Effort: S.

---

## Permission dialog (`components/PermissionDialog.qml`)

Good:
- It is a Sailfish-style full-screen Dialog: Deny top-left, Allow top-right in highlight, both full half-width header targets.
- The app icon and name are carried forward, each permission has its own row with a description, and the closing line says where to change it later.

**SS-42 · P2 · Error copy / Jakob · `PermissionDialog.qml:37-42,82-91`**
Problem: permission titles are raw ids, capitalised ("Sms", "Telephony", "System", "Storage"). The body sentence is built by English string concatenation ("X is requesting access to sms and telephony."), which can't be translated.
Fix: map each id to a translated title ("Text messages", "Phone calls", …). Build the sentence with `qsTr("%1 wants to use: %2")` plus a locale-aware list join.
Effort: S.

**SS-43 · P2 · Hygiene · `PermissionDialog.qml:8-23`**
Problem: the header comment describes a different layout (buttons at the bottom, 64×64 squircle, "no close X") from what is implemented. It will mislead the next edit.
Fix: replace it with a one-line description of the Sailfish Dialog layout.
Effort: S.

---

## Confirm dialog (`components/ui/ConfirmDialog.qml`, used for "Uninstall %1?" from `AppContextMenu.qml:67`)

**SS-44 · P1 · Hick / Von Restorff / Fitts (destructive) · `ConfirmDialog.qml:357-386,272-273`**
Problem:
- Two identical `Silica.Button`s sit side by side at equal width. Neither is primary, and the destructive one (Uninstall) looks like Cancel.
- The default label is a generic "Confirm".
- The look is a centred black card on a `#000000` backdrop, unlike every other shell dialog (ambience full-screen with corner actions), so it reads as foreign.

Fix: use the PermissionDialog/WiFi pattern (Cancel top-left, a verb top-right such as "Uninstall"). Or use a `RemorsePopup` for undoable removals, which is the Sailfish idiom. Require callers to pass a verb.
Effort: M.

---

## Share sheet (`components/ShareSheet.qml`)

**SS-45 · P1 · Fake control · `ShareSheet.qml:76-111`**
Problem: every target (Messages, Email, Notes, Copy Link) only logs and closes. `content` and `contentType` are stored and never used, and nothing in the repo calls `UIStore.openShareSheet`. Separately, `anchors.bottom` overrides `y`, so the slide-in Behavior never runs (`:40-45,137-142`). Not user-reachable today, but it's a trap for whoever wires it up.
Fix: delete it, or implement targets from a registry of apps declaring share MIME types (Sailfish `ShareAction` model), with "Copy" calling `ClipboardManagerCpp.copyToClipboard(content)`.
Effort: L to implement, S to delete.

---

## Clipboard history (`components/ClipboardManager.qml`)

**SS-46 · P1 · Fitts (destructive) / Jakob · `ClipboardManager.qml:186-204`**
Problem: "Clear" sits top-left, which is the slot where every other Sailfish dialog header puts Cancel. It wipes the whole history instantly, with no remorse or undo.
Fix: move Clear to a PullDownMenu item with `RemorsePopup` ("Clearing history"). Leave the top-left header slot empty or make it a Close.
Effort: S.

**SS-47 · P2 · Feedback / Postel · `ClipboardManager.qml:233-238,258-261,273-278`; `MarathonShell.qml:426-430`**
Problem:
- Copying an item just closes the sheet: no "Copied" confirmation.
- The per-item delete has no remorse.
- Timestamps are `"hh:mm AP"` regardless of locale or the 24 h setting, with no date for older items.
- The only way in is Ctrl+Shift+V on a hardware keyboard. There is no touch path, for example from the keyboard or a text field's long-press menu.

Fix: show a short "Copied" notice and use `RemorseItem` for delete. Use `Format.formatDate(…, Formatter.DurationElapsed)` or a locale time. Add a clipboard key to the symbols layout, or an entry in the text selection menu.
Effort: M.

---

## Wi-Fi password dialog (`components/WiFiPasswordDialog.qml`, OOBE only) and lock-screen network agent

Good:
- Sailfish Dialog layout (Cancel/Connect corners).
- The keyboard opens straight into the right field, and Return submits.
- Connect is disabled with an inline rule ("at least 8 characters") rather than an error after the fact.
- There is a `BusyIndicator` plus "Connecting to X…".
- NM failures are mapped to readable copy ("Incorrect password").
- The field gets `errorHighlight` and is not cleared on error.

**SS-48 · P1 · Postel (never clear user input) / Fitts · `WiFiPasswordDialog.qml:75-81,283-290`**
Problem: a tap anywhere on the empty ambience (for example just below the field while aiming for it) closes the dialog and wipes the typed password and SSID. The lock-screen agent does the same (`MarathonLockScreenNetworkAgent.qml:60-63`).
Fix: full-screen dialogs ignore taps outside. Leave via Cancel or Back only.
Effort: S.

**SS-49 · P1 · Doherty (more than 10 s needs cancel) · `WiFiPasswordDialog.qml:96,229-245`**
Problem: during "Connecting…" the Cancel corner is disabled, and there is no timeout. NM association plus DHCP regularly takes 10-30 s, and a stuck activation leaves the user stranded in OOBE.
Fix: keep Cancel enabled (deactivate the pending connection on NM). Add a 30 s timeout that calls `showError(qsTr("Couldn't connect. Check the password or move closer to the router."))`.
Effort: S.

**SS-50 · P2 · Postel / Similarity · `WiFiPasswordDialog.qml:118,251`; `MarathonLockScreenNetworkAgent.qml:95,166-171`; `MarathonShell.qml:2136-2146`**
Problem:
- The ≥8-character rule blocks WEP keys (5 or 13 characters).
- A hidden network can't be given a security type.
- The lock-screen agent does the same job with different rules (≥1 character, no busy state, "Sign in to WiFi" spelling).
- Nothing ever calls `lockScreenNetworkAgent.show()`, so it is dead UI.

Fix: accept 5/13/8-63 characters, or 64 hex digits, depending on `securityType`. Add a security picker in hidden mode. Make the agent reuse `WiFiPasswordDialog` instead of a second implementation, or delete it until it is wired up.
Effort: M.

---

## Incoming call (`components/IncomingCallOverlay.qml`)

Good:
- Answer and Decline are large glass rings (`itemSizeExtraLarge`) set `itemSizeLarge` apart.
- Answer is emphasised with highlight and label as well as colour, with no red/green-only signal.
- The caller name uses `fontSizeExtraLarge` Light, with the number formatted by `MPhoneNumber` underneath.

**SS-51 · P1 · Copy accuracy / security (verify) · `IncomingCallOverlay.qml:172-179,157-168`**
Problem: while locked, the copy says "Answering will unlock your device". `Answer` calls `UIStore.openApp("phone")` without going through the PIN. Either the copy is wrong or answering bypasses the lock. Both are bad: Sailfish and every mainstream OS answer over the lock screen and keep the device locked.
Fix: open the in-call UI as a lock-screen surface that leaves the session locked, and delete the sentence. Add a "Silence" action (or make the volume keys silence the ringer), which is missing today.
Effort: M.

---

## Alarm (`components/MarathonAlarmOverlay.qml`)

**SS-52 · P1 · Fitts (destructive easy) / Jakob · `MarathonAlarmOverlay.qml:81-104,146-163,124,175`**
Problem:
- Dismiss is the emphasised primary ring and Snooze is secondary.
- On top of that, a 100 px upward drag anywhere dismisses (raw px, not scaled). That is the same motion as the home gesture a half-awake user makes out of habit.
- Every mainstream alarm, Sailfish included, makes Snooze the big easy target and Dismiss the deliberate one.
- Snooze doesn't say how long.
- The time uses `fontSizeHuge * 1.5`, off the type scale.

Fix: emphasise Snooze, labelled "Snooze 10 min" from the alarm's setting. Make Dismiss a deliberate slide or hold on its own control, and remove the screen-wide swipe. Use `fontSizeHuge`, or the lock screen's clock style for consistency.
Effort: S.

---

## Cell broadcast (`components/MarathonCellBroadcastOverlay.qml`)

Good: it draws above the lock screen. Non-dismissable categories need a 3 s hold with a live countdown ("Hold to acknowledge — 2 s"), which is good progress feedback. Category is conveyed by title text, not just the red or amber strip.

**SS-53 · P1 · Broken modality · `MarathonCellBroadcastOverlay.qml:83-87`**
Problem: there is no input-swallowing `MouseArea`. Taps that miss the Acknowledge button fall through to whatever is underneath, such as lock-screen shortcuts or a running app, while an emergency alert is on screen.
Fix: add `MouseArea { anchors.fill: parent }` directly after the ambience background, as IncomingCallOverlay does.
Effort: S.

**SS-54 · P2 · Localisation / overflow / Similarity · `MarathonCellBroadcastOverlay.qml:43-58,134-154`**
Problem: the category titles are hard-coded English all-caps. Long ETWS or CMAS bodies have no `Flickable`, so they overflow off-screen. Acknowledge is a `Silica.Button` while every sibling overlay uses glass rings. There is a `"#F59E0B"` hex fallback.
Fix: use `qsTr` titles (sentence case, with weight for emphasis), put the body in a `SilicaFlickable`, and use one action style.
Effort: S.

---

## Screenshot preview (`components/ScreenshotPreview.qml`)

**SS-55 · P0 · Contrast (verify on device) · `ScreenshotPreview.qml:36-38,45`**
Problem: `Qt.rgba(15, 15, 15, 0.98)`, `Qt.rgba(255,255,255,0.15)` and `Qt.rgba(255,255,255,0.05)` pass 0-255 values to a 0-1 API. In Qt 6 they become extended-range or clamped white, so the card renders near-white behind `MColors.textPrimary` (white) text. "Screenshot saved" is unreadable.
Fix: use `Silica.Theme.rgba("black", 0.85)` and a `Theme.rgba(Theme.primaryColor, 0.1)` border, matching the other banners.
Effort: S.

**SS-56 · P1 · Broken gesture · `ScreenshotPreview.qml:81-98`**
Problem: swipe-right-to-dismiss calls `hide()` in `onPositionChanged`, but if the finger lifts inside the 160 dp card `onClicked` still fires, so a dismiss swipe also opens Gallery. The shell's keyboard-shortcut path also calls `screenshotFlash.trigger()` (`MarathonShell.qml:416,422`) on top of this component's own `flashAnimation`, which gives a double white flash.
Fix: track `dismissed` in the MouseArea and skip `onClicked` when set, or use a `DragHandler`. Use one flash, gated on reduce-motion.
Effort: S.

**SS-57 · P2 · Fidelity · `ScreenshotPreview.qml:31-77`**
Problem: geometry is hard-coded (`160 * scaleFactor`, `+16`, `8/6/20/2 * scaleFactor`) with `MTypography`/`MColors` instead of Silica. The thumbnail of a 1:2 screenshot is letterboxed into a 160×70 dp strip, which leaves it tiny. There are no Share or Delete actions.
Fix: make it a portrait thumbnail (`Theme.coverSizeSmall`-ish) using Silica tokens, and add Share/Delete as small glyph buttons once the share sheet (SS-45) is real.
Effort: M.
