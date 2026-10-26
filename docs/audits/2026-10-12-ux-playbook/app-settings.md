# Settings app — UX playbook audit (2026-10-12)

Scope: `apps/settings/**` (25 pages and dialogs, cover, `SettingsLogic.js`, `src/`), checked against the UX playbook build checklist. Sailfish/Jolla Settings is the Jakob's-law baseline and Keel Silica is the reference. Read-only audit, no device runs. Every claim below is traced through the app-runner IPC client (`tools/marathon-app-runner/ipc/shellipcclients.*`) and the shell service that consumes the setting.

## Summary

**The visual layer is in good shape. The biggest problem is settings that don't take effect.** The pages are among the most Silica-faithful in the repo:
- Every toggle is a glass-dot `TextSwitch` and every choice is a `ComboBox` or `ValueButton`.
- Every list row is `ListItem` at `Theme.itemSizeMedium`, so it passes Fitts's law.
- Spacing and fonts use Theme tokens everywhere. The only literals are a 1 px spacer and one scrim colour.
- Empty states use `ViewPlaceholder` with hint text.
- Destructive actions use `remorseDelete` or `RemorsePopup` (uninstall, remove account, reset tiles).
- Wi-Fi, Bluetooth and PIN flows have busy rows, and password fields have live character counts.

**Six controls show a state the system never applies (P0).** Screen timeout, status-bar clock position, Quick settings tiles, default apps, keyboard language and auto-capitalise, and the whole Mobile network page. Each one either writes to a store that nothing reads, or reads a service the app runner never exposes.

**The tests can't catch any of these.** They run against hand-written stubs that copy the pages' own assumptions.

The P1 issues cluster in three places:
- **Input lost on error (Postel):** Wi-Fi password, quick PIN.
- **Missing feedback (Doherty):** time zone change, add account, false "No networks found" right after Wi-Fi turns on.
- **Missing table-stakes Jolla controls:** forget a Wi-Fi network, unpair a Bluetooth device, hidden networks, automatic time, automatic locking.

| Severity | Count |
|---|---|
| P0 broken or lying | 6 |
| P1 clearly violates the playbook | 20 |
| P2 polish | 23 |

### Top 5

1. **ST-17:** "Turn screen off after" writes the inert `Display.screenTimeout` (DisplayManagerCpp). The idle blank and auto-lock timer read `SettingsManager.screenTimeout`, which never changes.
2. **ST-44:** The Quick settings page is dead. The shell's top menu hard-codes its tiles and never reads `enabledQuickSettingsTiles` or the tile order, and half of the page's tile IDs don't exist in the shell.
3. **ST-32:** Keyboard Language and Auto-capitalize never reach the keyboard. The IPC client has no such properties, so the store falls back to writing flat `QSettings` keys that the shell never reads.
4. **ST-15:** Mobile network always says "No modem found. Check that a SIM card is inserted…", even on an L5 with a working modem. `ModemManagerCpp` is never exposed to the app runner.
5. **ST-41 and ST-18:** Default apps and Status bar clock position persist values that no shell code reads.

---

## Main page (`pages/MainPage.qml`, `SettingsLogic.js`)

Good:
- Search sits at the top with keyword aliases, results show their section, and Enter opens the first hit.
- The empty state has a useful hint ("Try another word, like Wi-Fi, volume or PIN").
- Each row's summary carries state forward (Miller), for example "Brightness 60%" or "PIN set · Fingerprint".
- Airplane mode and Do not disturb sit at the top, as in Jolla.

**ST-01: Section labels don't describe their contents**
- **Severity:** P2
- **Law:** Miller (grouping), Similarity
- **Where:** `SettingsLogic.js:61-83`
- **Problem:**
  - Accounts sits under "Privacy".
  - Quick settings (a shell-chrome setting) sits under "Apps".
  - "Terminal", an app launch that leaves Settings, sits in System next to real pages.
- **Fix:**
  - Rename "Privacy" to "Security and accounts", or give Accounts its own section as Jolla does.
  - Move Quick settings to Device, next to Display.
  - Drop Terminal from Settings; it already sits in the app grid.
- **Effort:** S

**ST-02: Setting aliases open the page at the top**
- **Severity:** P2
- **Law:** Hick (scan cost)
- **Where:** `SettingsLogic.js:9-10`
- **Problem:** The `scale` and `screentimeout` routes and search hits open Display scrolled to the top. The user then has to hunt for the control they searched for.
- **Fix:** Pass a target `objectName` with the route, then `positionViewAt` that item and flash its highlight. This is the Jolla deep-link behaviour.
- **Effort:** M

**ST-03: Cover Bluetooth icon and action never change**
- **Severity:** P2
- **Law:** Similarity (states)
- **Where:** `cover/SettingsCover.qml:53,71`
- **Problem:** The Bluetooth state icon and cover action icon stay the same whether Bluetooth is on or off. The Wi-Fi line and action next to them do switch to an `-off` variant.
- **Fix:** Mirror the Wi-Fi pattern: use `icon-s-bluetooth`/off and `icon-cover-bluetooth`/off based on `Bluetooth.enabled`.
- **Effort:** S

## Wi-Fi (`WiFiPage.qml`, `WiFiDialog.qml`)

Good:
- Uses a PullDownMenu Scan action.
- Shows a "Connecting to X…" busy row.
- The connected network gets its own section.
- The password dialog counts characters ("At least 8 characters (3 more)").
- Open networks show a plain-language warning.

**ST-04: A failed connection clears the typed password**
- **Severity:** P1
- **Law:** Postel (never clear on error)
- **Where:** `WiFiPage.qml:27-33`, `WiFiDialog.qml:11`
- **Problem:** When a connection fails, the page pushes a brand-new `WiFiDialog`. The error label shows, but the password the user typed is gone, so a single typo forces a full retype.
- **Fix:** Keep the last attempt in `SettingsController` (`wifiDialogPassword`) and prefill it. Alternatively, keep the dialog open with a busy DialogHeader until the result arrives.
- **Effort:** S

**ST-05: Known networks always ask for the password again**
- **Severity:** P1
- **Law:** Tesler (remember last-used values)
- **Where:** `WiFiPage.qml:23-25`, backend `shell/src/managers/networkmanagercpp.cpp:659+`
- **Problem:**
  - Tapping a network you've already joined always asks for the password.
  - Every connect calls `AddAndActivateConnection` with a fresh UUID, so NetworkManager collects duplicate profiles.
  - There is no "Forget network" anywhere.
- **Fix:**
  - Expose a `known` flag on each entry in `availableNetworks`. Activate the existing profile without the dialog.
  - Add a ContextMenu with "Forget" (using `remorseDelete`) to known and connected networks.
- **Effort:** M/L

**ST-06: No way to join a hidden network**
- **Severity:** P1
- **Law:** Jakob
- **Where:** `WiFiPage.qml:59-66`
- **Problem:** Nothing lets the user join a hidden SSID. The PullDownMenu has only "Scan". Jolla has "Add network".
- **Fix:** Add a PullDownMenu "Add network" item that opens a Dialog with an SSID field, a Security ComboBox and a PasswordField.
- **Effort:** M

**ST-07: "No networks found" shows right after Wi-Fi turns on**
- **Severity:** P1
- **Law:** Doherty (false empty state)
- **Where:** `WiFiPage.qml:83-87`, `WiFiPage.qml:239-253`
- **Problem:**
  - `Network.toggleWifi()` is a D-Bus call, and `wifiEnabled` updates later through a signal. The `if (Network.wifiEnabled)` check reads the stale value, so turning Wi-Fi on never starts a scan.
  - With `scanning` false, the page immediately shows "No networks found. Move closer to a router…".
- **Fix:** Drop the inline check. Add `Connections { onWifiEnabledChanged: if (Network.wifiEnabled) page.scan() }`.
- **Effort:** S

**ST-08: No busy feedback during a rescan**
- **Severity:** P2
- **Law:** Doherty
- **Where:** `WiFiPage.qml:59`
- **Problem:** When networks are already listed, a rescan shows nothing apart from a disabled menu item. The busy row only appears while the list is empty.
- **Fix:** Set `PullDownMenu { busy: page.scanning }`. This is the Silica idiom.
- **Effort:** S

**ST-09: Every secured network gets the WPA-PSK dialog**
- **Severity:** P2
- **Law:** Postel
- **Where:** `WiFiDialog.qml:13,53`
- **Problem:** Every secured network gets the same "≥ 8 characters" PSK dialog. The backend hard-codes `key-mgmt=wpa-psk`, so WPA3-SAE, Enterprise (802.1X) and WEP networks accept input and then fail.
- **Fix:** Branch on `wifiDialogSecurity`. For unsupported types, show "Enterprise networks aren't supported yet" instead of a Connect button that can't work.
- **Effort:** M

**ST-10: Network subtitles are jargon and can't be translated**
- **Severity:** P2
- **Law:** Pragnanz, Similarity
- **Where:** `src/SettingsController.cpp:289-321`
- **Problem:**
  - Subtitles read like "WPA2 • 72% signal • 2.4 GHz": raw percentages and frequencies.
  - The strings are built in C++ with `QStringLiteral`, so they can't be translated.
  - They use "•" where the QML uses "·".
- **Fix:** Move the strings to QML `qsTr`. Show "Secured · Good signal" using `Logic.signalQuality`, and drop GHz.
- **Effort:** S

## Bluetooth (`BluetoothPage.qml`, `BluetoothPairDialog.qml`)

Good:
- The pairing dialog covers just-works, PIN, passkey and confirm-code modes, with clear help text.
- A "Pairing with X…" busy row shows while pairing.
- Paired and other devices sit in separate sections.

**ST-11: Paired devices can't be removed**
- **Severity:** P1
- **Law:** Jakob, Occam
- **Where:** `BluetoothPage.qml:135-140`
- **Problem:** There's no way to unpair or forget a device, even though `Bluetooth.unpairDevice()` exists in the client. The ContextMenu offers only Connect or Disconnect.
- **Fix:** Add a "Remove" MenuItem with `paired.remorseDelete(() => Bluetooth.unpairDevice(address))`.
- **Effort:** S

**ST-12: Opening the page doesn't start a scan**
- **Severity:** P1
- **Law:** Tesler, Doherty
- **Where:** `BluetoothPage.qml:145-164`, `src/SettingsController.cpp:794-807`
- **Problem:** A scan only starts when Bluetooth is switched on. If it was already on, "Other devices" says "No devices found" until the user finds the pull-down menu. Jolla scans while the page is open.
- **Fix:** Scan while the page is open: `onStatusChanged: status === PageStatus.Active && Bluetooth.enabled ? Bluetooth.startScan() : Bluetooth.stopScan()`.
- **Effort:** S

**ST-13: Connect and disconnect give no in-progress feedback**
- **Severity:** P2
- **Law:** Doherty, Pragnanz
- **Where:** `BluetoothPage.qml:134-141`, `BluetoothPage.qml:155`
- **Problem:**
  - Tapping a paired device to connect or disconnect gives no acknowledgement until the device state flips. With audio devices that takes 1–5 s.
  - Unpaired devices show "Signal -67 dBm", which is jargon.
- **Fix:**
  - Track a `pending` address and show "Connecting…" or "Disconnecting…" in the subtitle, with the row disabled.
  - Drop dBm and show "Tap to pair".
- **Effort:** S

**ST-14: PIN field rejects valid legacy PINs**
- **Severity:** P2
- **Law:** Postel
- **Where:** `BluetoothPairDialog.qml:77-83`
- **Problem:** The PIN field only accepts up to 6 digits. Legacy Bluetooth PINs can be up to 16 alphanumeric characters, so some old car kits and keyboards can't pair.
- **Fix:** Allow `[0-9A-Za-z]{0,16}` and keep the "usually 0000 or 1234" hint.
- **Effort:** S

## Mobile network (`CellularPage.qml`)

**ST-15: The page always says there's no modem**
- **Severity:** P0
- **Law:** Settings that lie
- **Where:** `CellularPage.qml:9-10`, `CellularPage.qml:69-85`
- **Problem:**
  - The page reads the `ModemManagerCpp` context property, which only the shell sets (`shell/main.cpp:694`). The app runner never sets it, and it isn't in `platformtypes.cpp`. The page also reads `modem.available`, but the shell's modem property is `modemAvailable`.
  - So on every device the page says "No modem found. Check that a SIM card is inserted and the modem is switched on." That sends L5 users with a working SIM to fault-find hardware.
  - The Mobile data switch can never be used.
- **Fix:**
  - Expose the modem through a Platform singleton (e.g. `Modem`) in the runner IPC, then bind to that.
  - Until then, change the copy to "Mobile network settings aren't available yet". Better, hide the main-page entry.
- **Effort:** M

**ST-16: Duplicate row and missing controls**
- **Severity:** P2
- **Law:** Occam, Jakob
- **Where:** `CellularPage.qml:43-67`
- **Problem:**
  - "SIM operator" shows the same `operatorName` as "Operator".
  - There's no Data roaming switch, preferred network type or APN entry, all of which are standard in Jolla's Mobile network page.
- **Fix:**
  - Drop the duplicate row.
  - Once ST-15 is fixed, add a "Data roaming" `TextSwitch` and a "Preferred network mode" `ComboBox`.
- **Effort:** S

## Display (`DisplayPage.qml`)

Good:
- Labelled sections: Screen, Interface.
- The brightness slider applies live while dragging.
- ComboBoxes describe each option.
- Brightness 0% is safe: the backend remaps it so the panel stays lit.

**ST-17: Screen timeout writes a setting nothing reads**
- **Severity:** P0
- **Law:** Settings that lie
- **Where:** `DisplayPage.qml:72-85`
- **Problem:**
  - The ComboBox reads and writes `Display.screenTimeout`, which goes to DisplayManagerCpp (`shellservices.cpp:796-800`). That value is only stored (`displaymanagercpp.cpp:572-581`) and drives nothing.
  - The idle blank and auto-lock timers read `SettingsManagerCpp.screenTimeout` (`shell/qml/MarathonShell.qml:721`, `MarathonLockScreen.qml:21`).
  - Sync only runs from SettingsManager to Display (`displaypolicycontroller.cpp:15-20`), never back. So the combo shows "5 minutes" while the screen still blanks at the old value.
- **Fix:** Bind and write `Settings.screenTimeout`, which is in milliseconds and already on `SettingsClient`. Drop the `/1000`.
- **Effort:** S

**ST-18: Status bar clock position does nothing**
- **Severity:** P0
- **Law:** Dead control
- **Where:** `DisplayPage.qml:128-148`
- **Problem:** `statusBarClockPosition` persists, but nothing in `shell/qml` reads it (`grep` finds no consumer outside SettingsManager and the IPC layer). The control and its notch-specific descriptions are fiction.
- **Fix:** Implement the position in `MarathonStatusBar.qml`, or remove the ComboBox and its keyword.
- **Effort:** S (remove) / M (implement)

**ST-19: Interface size change gives no hint**
- **Severity:** P2
- **Law:** Doherty, Peak-end
- **Where:** `DisplayPage.qml:107-127`
- **Problem:** Apps get `MARATHON_USER_SCALE` at launch (runner `main.cpp:1048`). Changing the size resizes the shell, but Settings and other open apps keep their old size, with no hint.
- **Fix:** Add a description such as "Open apps resize when you reopen them", or reload the window scale live.
- **Effort:** S

**ST-20: Timeout option labels can't be translated**
- **Severity:** P2
- **Law:** Postel (strict output)
- **Where:** `DisplayPage.qml:76-85`
- **Problem:** The menu items show English strings ("30 seconds") that double as the lookup keys for `Settings.screenTimeoutValue()`. Translating the labels would break the lookup.
- **Fix:** Use a local `[{ms, title: qsTr(...)}]` model, like `Logic.scales`.
- **Effort:** S

## Sounds (`SoundPage.qml`, `SoundPickerPage.qml`)

Good:
- Tones use `ValueButton` and open a picker, as in Jolla.
- The picker previews each sound when tapped.
- The per-app volume section only appears when the backend supports it, and has its own empty state.

**ST-21: "Muted" in the summary, but no mute control**
- **Severity:** P1
- **Law:** Similarity, Settings that lie
- **Where:** `SoundPage.qml:32-46`, `MainPage.qml:26`
- **Problem:** The main page summary can say "Muted", but Sounds has no mute or silent control. Its slider shows a volume as if sound were on.
- **Fix:**
  - Add a "Silent" `TextSwitch` that calls `Audio.setMuted`, matching the shell's "Silent" tile.
  - Set the slider's `valueText` to "Muted" while muted.
- **Effort:** S

**ST-22: No vibration switch**
- **Severity:** P2
- **Law:** Jakob
- **Where:** `SoundPage.qml`
- **Problem:** There's no vibration switch, although `Settings.vibrationEnabled` exists and gates keyboard haptics (`shell/qml/components/VirtualKeyboard.qml:75`). Today it can only be changed from the top-menu tile.
- **Fix:** Add a "Vibration" `TextSwitch` under a "Feedback" SectionHeader.
- **Effort:** S

**ST-23: Per-app sliders only apply on release**
- **Severity:** P2
- **Law:** Doherty (<100 ms)
- **Where:** `SoundPage.qml:105`
- **Problem:** Per-app volume sliders only apply on release. The main Volume slider applies live, so the same control behaves two ways.
- **Fix:** Apply on `onValueChanged` while `down`, as the main slider does.
- **Effort:** S

**ST-24: Picker gaps and mismatched header case**
- **Severity:** P2
- **Law:** Peak-end, Similarity
- **Where:** `SoundPickerPage.qml:16-19`, `SoundPickerPage.qml:28`, `src/SettingsController.cpp:355-366`
- **Problem:**
  - The preview keeps playing after the user leaves the page.
  - There's no "None" (silent) option for notification or ringtone.
  - The header comes from C++ in Title Case ("Notification Sound"), while the button that opened it says "Notification sound".
- **Fix:**
  - Stop the preview `onStatusChanged` when the page deactivates.
  - Add a "None" row.
  - Make the header `qsTr` in sentence case.
- **Effort:** S

## Notifications (`NotificationsPage.qml`)

Good: Per-app switches are actually honoured by the shell (`notificationservicecpp.cpp:64`), and the lock-screen switch is wired (`MarathonLockScreen.qml:76`).

**ST-25: Per-app list is long and unexplained**
- **Severity:** P2
- **Law:** Hick, Miller
- **Where:** `NotificationsPage.qml:49-68`
- **Problem:**
  - The "Apps" list includes every installed app, including ones that never notify.
  - There's no search and no explanation of what turning an app off does.
  - When the list is empty, the header just disappears.
- **Fix:**
  - Add a SectionHeader description label: "Turn off to hide an app's notifications".
  - Sort apps that have notified first.
  - Add a SearchField once the list passes about 15 apps.
- **Effort:** S/M

## Date and time (`DateTimePage.qml`, `TimeZonePage.qml`)

Good:
- The 24-hour switch previews the live time as its description, which is a nice touch.
- The time zone picker has search, UTC offsets and a helpful empty hint.

**ST-26: Only the 24-hour switch and time zone are settable**
- **Severity:** P1
- **Law:** Tesler, Jakob
- **Where:** `DateTimePage.qml:35-48`
- **Problem:**
  - There's no "Automatic time" (NTP) switch and no automatic time zone.
  - The date and time can't be set by hand. Keel has `DatePickerDialog` and `TimePickerDialog`.
  - There's no date format setting, although `Settings.dateFormat` exists on `SettingsClient`.
  - Jolla's page has all of these.
- **Fix:** Add a "Time" section:
  - An "Automatic update" `TextSwitch` using timedate1 `SetNTP`.
  - Time and Date `ValueButton`s that open the pickers, disabled while automatic update is on.
  - A "Date format" `ComboBox`.
- **Effort:** M

**ST-27: A failed time zone change is silent**
- **Severity:** P1
- **Law:** Doherty, Peak-end
- **Where:** `TimeZonePage.qml:50-53`, `shell/src/managers/settingsmanager.cpp:622-644`
- **Problem:** Choosing a zone pops the page immediately, but `SetTimezone` is an async timedate1 call. If it fails (for example a polkit denial), the only trace is a `qWarning`, and the Date and time page silently keeps the old zone.
- **Fix:** Emit a `timeZoneChangeFailed(reason)` signal and forward it over IPC. Show "Couldn't change the time zone" with `Notices.show`.
- **Effort:** S/M

## Battery (`BatteryPage.qml`)

**ST-28: Two controls for the same setting**
- **Severity:** P1
- **Law:** Occam, Similarity
- **Where:** `BatteryPage.qml:48-77`
- **Problem:**
  - The "Power saver mode" switch and the "Power profile" ComboBox both drive the CPU governor.
  - If the user picks Performance while saver is on, the switch stays on.
  - Saver also quietly cuts the idle timeout to 30 s (`powermanagercpp.cpp:365-371`), and no copy says so.
- **Fix:**
  - Keep one control: a "Power profile" ComboBox with Power saver as one option, or Jolla's "Battery saving mode" with an activation-threshold Slider.
  - State the side effect in the description: "Also turns the screen off sooner".
- **Effort:** M

**ST-29: Battery level shows "-1%" with no battery**
- **Severity:** P1
- **Law:** Settings that lie
- **Where:** `BatteryPage.qml:33`, `AboutPage.qml:104`
- **Problem:** Both pages render "-1%" when there's no battery (QEMU dev sim, boards on bench power). The main page already guards against this with `Logic.batterySummary`.
- **Fix:** Use `Logic.batterySummary`, or show "No battery" when `batteryLevel < 0`, and hide the saver controls.
- **Effort:** S

**ST-30: Status text is Title Case and can't be translated**
- **Severity:** P2
- **Law:** Similarity
- **Where:** `src/SettingsController.cpp:270-287`
- **Problem:** The status text is untranslatable C++ in Title Case ("Plugged In, Not Charging"), while every QML string is in sentence case.
- **Fix:** Move it to QML `qsTr` in sentence case.
- **Effort:** S

## Storage (`StoragePage.qml`)

Good: A clean ProgressBar plus DetailItems.

**ST-31: Totals only**
- **Severity:** P2
- **Law:** Pareto, Peak-end
- **Where:** `StoragePage.qml:25-47`
- **Problem:** The page shows totals only. There's no breakdown (apps, media, cache) and no action, so a full disk is a dead end.
- **Fix:** Add a "Usage" SectionHeader with per-category DetailItems, plus a link to Installed apps.
- **Effort:** M

## Keyboard (`KeyboardPage.qml`, `src/KeyboardSettingsStore.cpp`)

**ST-32: Language and Auto-capitalize never reach the keyboard**
- **Severity:** P0
- **Law:** Settings that lie
- **Where:** `KeyboardPage.qml:22-61`, `src/KeyboardSettingsStore.cpp:91-100`
- **Problem:**
  - `SettingsClient` has no `keyboardLanguage` or `keyboardAutoCapitalize` property (`shellipcclients.h:330-338`).
  - So `writeSettingValue()` falls back to the generic `Set`. That writes flat `QSettings` keys (`keyboardLanguage`, `keyboardAutoCapitalize`), but the shell reads `keyboard/language` and `keyboard/autoCapitalize` (`settingsmanager.cpp:336,341`) and never emits a change.
  - Reads come back as the default, so the combo and switch also show the wrong current value.
  - Auto-correct, predictions and haptics work because they have real properties.
- **Fix:** Add both properties to `SettingsClient`, plus the `emitProp`/`Set` cases in `shellservices.cpp`.
- **Effort:** S

**ST-33: Key vibration has no description and depends on a hidden switch**
- **Severity:** P2
- **Law:** Similarity
- **Where:** `KeyboardPage.qml:70-76`
- **Problem:**
  - "Vibrate on key press" is the only TextSwitch with no description.
  - It does nothing while global vibration is off (`VirtualKeyboard.qml:75`), and nothing tells the user.
- **Fix:**
  - Add a description.
  - Disable the switch with the description "Turn on vibration in Sounds" when `!Settings.vibrationEnabled`.
- **Effort:** S

## Security (`SecurityPage.qml`, `QuickPinDialog.qml`, `RemovePinDialog.qml`)

Good:
- The PIN dialog validates as you type ("The PINs don't match", digits only).
- Removing the PIN requires the password, which serves as confirmation.
- A busy row shows while the password is checked.
- "How it works" copy explains the PIN model.

**ST-34: The quick PIN dialog closes before the password is checked**
- **Severity:** P1
- **Law:** Postel (keep data on error), Peak-end
- **Where:** `SecurityPage.qml:24-27`, `SecurityPage.qml:42-47`
- **Problem:** The dialog closes on accept, and only then is the system password verified. A wrong password shows a Notice, and the user has to retype the new PIN, the confirmation and the password.
- **Fix:** Verify before closing. Set `canAccept` false while pending, keep the dialog open with a busy DialogHeader, and on failure set `errorHighlight` on the password field only. Alternatively, reopen the dialog with the PIN fields prefilled.
- **Effort:** M

**ST-35: No automatic locking control**
- **Severity:** P1
- **Law:** Jakob, Tesler
- **Where:** `SecurityPage.qml:81-98`
- **Problem:**
  - There's no "Automatic locking" control, although `Settings.autoLock` and `autoLockTimeout` exist on the client and the shell honours `autoLock` (`MarathonShell.qml:738`).
  - "Lock method" is a read-only DetailItem with the jargon label "System Password (PAM)".
- **Fix:** Add a "Device lock" section with an "Automatic locking" ComboBox (Off, 5 min, 30 min, … as in Jolla), and drop the PAM label.
- **Effort:** M

**ST-36: Fingerprint "Not enrolled" is a dead end**
- **Severity:** P2
- **Law:** Peak-end, Remove-it test
- **Where:** `SecurityPage.qml:120-124`
- **Problem:** The row says "Fingerprint: Not enrolled" and offers no way to enrol. It shows even on devices with no reader (fprintd absent), such as the L5.
- **Fix:** Hide the row when there's no reader. When a reader exists, make it an action that starts enrolment.
- **Effort:** S

**ST-37: Status section exposes internal counters**
- **Severity:** P2
- **Law:** Hick, Remove-it test
- **Where:** `SecurityPage.qml:125-134`, `src/SettingsController.cpp:323-338`
- **Problem:** "Failed attempts: 0" and "Account: Active" are internal counters shown permanently. Their strings are C++ and Title Case.
- **Fix:** Show lockout state only while locked out.
- **Effort:** S

## Accounts (`AccountsPage.qml`, `AddAccountDialog.qml`)

Good:
- Removing an account uses `remorseDelete`.
- The empty state explains the pull-down.
- The footer copy is honest about Google OAuth not being supported.

**ST-38: Adding an account gives no feedback**
- **Severity:** P1
- **Law:** Doherty, Peak-end, Postel
- **Where:** `AccountsPage.qml:13-20`
- **Problem:** "Add" closes the dialog and calls `dav.addAccount()`. The returned ID is ignored, and an empty ID (failure) is silent. There's no "Checking…" state and no success confirmation, and a bad password only shows up later as "Last error".
- **Fix:** Add a busy state ("Checking account…"). On failure, show a Notice and reopen the dialog with its fields preserved. On success, run a first sync and show a "Syncing…" subtitle on the new row.
- **Effort:** M

**ST-39: Server URL isn't normalised; rows can't be toggled**
- **Severity:** P2
- **Law:** Postel, Tesler
- **Where:** `AddAccountDialog.qml:13`, `AccountsPage.qml:95-101`
- **Problem:**
  - The server URL isn't trimmed or normalised: a bare `cloud.example.com` and trailing spaces pass through as typed.
  - An account row's menu only offers Remove, although `enableAccount()` exists.
- **Fix:**
  - Trim the URL and prepend `https://` when the scheme is missing.
  - Add a "Disable sync" or "Enable sync" MenuItem.
- **Effort:** S

## Apps

### Installed apps (`AppManagerPage.qml`)

Good: Uninstall goes through `remorseDelete`, and Notices report success or failure by name.

**ST-40: Fabricated version and silent rows**
- **Severity:** P2
- **Law:** Settings that lie (minor), Doherty
- **Where:** `AppManagerPage.qml:58-61`, `AppManagerPage.qml:109`
- **Problem:**
  - Apps with no version show a made-up "Version 1.0.0".
  - Tapping a system app does nothing at all.
  - There's no "Uninstalling…" state between the remorse timer ending and the Notice.
  - There's no search in a list of 30+ apps.
- **Fix:**
  - Omit the version when it's unknown.
  - Give system apps a details page or no press highlight.
  - Show a busy subtitle while uninstalling.
  - Add a SearchField header.
- **Effort:** S

### Default apps (`DefaultAppsPage.qml`, `AppPickerPage.qml`)

**ST-41: Default apps does nothing**
- **Severity:** P0
- **Law:** Dead control
- **Where:** `DefaultAppsPage.qml:23-44`, `AppPickerPage.qml:35-38`
- **Problem:** `defaultApps` is saved, but nothing outside SettingsManager and the IPC layer reads it. URL routing, top-menu shortcuts (`app:camera`) and phone/SMS intents all use hard-coded app IDs. All nine handler pickers are fiction.
- **Fix:** Wire `Navigation.navigate` and the shell handlers to `SettingsManager.defaultApps`, or remove the page, its route and its search keywords until they're wired.
- **Effort:** M/L (wire) / S (remove)

### Hidden apps (`HiddenAppsPage.qml`)

**ST-42: Switch meaning is unclear and the list isn't searchable**
- **Severity:** P2
- **Law:** Similarity, Hick
- **Where:** `HiddenAppsPage.qml:22-30`
- **Problem:**
  - The switch reads "on = hidden", the reverse of Notifications where "on = allowed", and rows have no description.
  - The full app list has no search.
  - Settings can hide itself.
- **Fix:**
  - Add a page description: "Switched on apps are hidden".
  - Add a SearchField header.
  - Protect `settings` from being hidden.
- **Effort:** S

### App grid (`AppLayoutPage.qml`)

**ST-43: "Hide desktop apps" only applies after a shell restart**
- **Severity:** P1
- **Law:** Settings that lie (until restart)
- **Where:** `AppLayoutPage.qml:50-57`
- **Problem:** The shell reads `filterMobileFriendlyApps` once at startup and bakes it into the app-scan lambdas (`shell/main.cpp:1223-1293`). The switch flips, but the grid doesn't change until the shell restarts, and nothing says so.
- **Fix:** Rescan when `filterMobileFriendlyAppsChanged` fires in `main.cpp`.
- **Effort:** S/M

### Quick settings (`QuickSettingsPage.qml`)

**ST-44: The whole page does nothing**
- **Severity:** P0
- **Law:** Dead control
- **Where:** `QuickSettingsPage.qml:39-48`, `SettingsLogic.js:172-192`
- **Problem:**
  - `shell/qml/components/MarathonQuickSettings.qml:116-145` hard-codes its tiles and never reads `enabledQuickSettingsTiles` or `quickSettingsTileOrder`.
  - The page's tile IDs don't match the shell's: `flight` vs `airplane`, `notifications` vs `dnd`, `battery` vs `lowpower`.
  - It lists `screenshot`, `settings` and `lock`, which aren't tiles at all.
  - Every switch and "Reset to defaults" is fiction.
- **Fix:** Make the shell filter and order `tiles` by `enabledQuickSettingsTiles`, using the shell's IDs, and generate `Logic.tiles` from the same list. Otherwise remove the page.
- **Effort:** M

## System

### Software updates (`UpdatesPage.qml`)

Good: `PullDownMenu busy` while checking, and a clear status headline.

**ST-45: "Update available" is a dead end**
- **Severity:** P1
- **Law:** Peak-end, Hick (one primary action)
- **Where:** `UpdatesPage.qml:22-27`, `UpdatesPage.qml:49`
- **Problem:** "Update X is available" offers no install path. The only action is a pull-down "View release", which opens a browser, and there are no instructions.
- **Fix:** When an update is available, add the next step inline: an "Install" action, or "How to update" with steps. Show "Last error" in plain language.
- **Effort:** M

### About device (`AboutPage.qml`, `DeviceNameDialog.qml`)

**ST-46: "Build" and "OS version" mislabel what they show**
- **Severity:** P1
- **Law:** Settings that lie (mislabelled)
- **Where:** `AboutPage.qml:64-71`, `src/SettingsController.cpp:740-741`
- **Problem:**
  - "Build" shows `QSysInfo::buildAbi()` (for example `arm64-little_endian-lp64`), not a build.
  - "OS version" is the host distro's pretty name.
  - The Marathon version (`Updates.currentVersion`) isn't shown at all.
- **Fix:** Show "Marathon OS version" from `Updates.currentVersion` and an "OS base" row, and drop the ABI or relabel it "Architecture".
- **Effort:** S

**ST-47: Device name isn't used anywhere**
- **Severity:** P1
- **Law:** Dead control
- **Where:** `AboutPage.qml:54-58`, `shell/src/managers/settingsmanager.cpp:477-483`
- **Problem:** The device name is stored only in `QSettings`. No consumer exists: it isn't the hostname or the Bluetooth adapter alias, which is what users expect it to name.
- **Fix:** Apply it to BlueZ `Adapter1.Alias` and hostnamed `SetPrettyHostname`. Sanitise and limit the length (63) in the dialog, with inline error copy.
- **Effort:** M

### Legal (`PrivacyPage.qml`, `TermsPage.qml`)

**ST-48: Privacy policy promises a screen that doesn't exist**
- **Severity:** P1
- **Law:** Settings that lie (copy)
- **Where:** `PrivacyPage.qml:7`
- **Problem:** The policy says "You can change permissions per app in Settings", but there's no per-app permission UI anywhere in Settings.
- **Fix:** Add an app details page (permissions and notifications), reached from Installed apps, or correct the copy.
- **Effort:** S (copy) / L (feature)

## Tests (`apps/settings/tests`)

**ST-49: Stubs can't catch settings that don't take effect**
- **Severity:** P1
- **Law:** Goal-driven verification
- **Where:** `tests/stubs/Marathon/Platform/*.qml`, `tests/stubs/MarathonApp/Settings/*.qml`
- **What's covered:** 55 test functions across Logic, the main page, connectivity, devices, system, apps and the cover. Each one checks that a page writes the property its stub defines.
- **Problem:** The stubs are hand-written to match the pages, for example `Display.screenTimeout` and `KeyboardSettingsStore.currentLanguage`. So every P0 above passes: no test checks that a written key exists on the real `SettingsClient` or `DisplayClient`, or that anything in the shell consumes it. Remove-account and uninstall remorse are tested; the Wi-Fi retry path and the PIN wrong-password path are not.
- **Fix:** Add a C++ contract test that walks every property the Settings QML writes:
  - assert that it's a `Q_PROPERTY` on the runner IPC client;
  - assert that it has an `emitProp`/`Set` case in `shellservices.cpp`;
  - keep an allowlist of the shell consumer for each key.
- **Effort:** M
