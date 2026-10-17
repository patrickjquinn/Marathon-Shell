# OEM test app run — HackberryPi CM5, shell r455–r458, 2026-10-17

Every function in apps/test driven on the device with screenshots and the journal. Status as of the end of the run; fixes land under the R-items in docs/roadmap/TRACKER.md.

| # | Area | Finding | Status |
|---|---|---|---|
| F1 | Calls | Answer: overlay unloaded mid-handler (invalid context, hide not a function); Phone never opened | verified fixed r459 |
| F2 | Calls | Decline: same invalid-context error | verified fixed r459 |
| F3 | Calls | callaudiod exits on devices with no earpiece; shell's SelectMode/EnableSpeaker calls wait for D-Bus timeout | → R09 audio agent |
| F4 | Permissions | Launch prompt lists 5 of 8 manifest permissions (no contacts/location/notifications); contacts later denied silently without a prompt | open |
| F5 | Calls | Declining a call while unlocked brings up the lock screen | verified fixed r459 (7f2b266b) |
| F6 | Calls | A declined call raises a "Missed Call" notification | verified fixed r459 — no Missed Call for a decline |
| F7 | Permissions | "system" requested by test app is denied (restricted to system apps) — expected, but the prompt still lists it | check |
| F8 | Notifications | "With icon" shows the default bell, not the app's custom icon | open |
| F9 | Compositor | journal spam: "Failed to move cursor on screen UNKNOWN1: -14" (hardware cursor ioctl) | open |
| F10 | Notifications | A notification arriving while a banner is on screen is sometimes never bannered (Important/Interactive dropped when sent back-to-back) | open |
| F11 | Notifications | Actions (reply/dismiss/snooze) never shown — not in the banner, not in the Hub; app passes plain string ids | open |
| F12 | Notifications | Clear all: Nemo.Notifications Notification.close() sends no CloseNotification on the bus (Keel nemo-compat, read-only here, or runner id handling) | open — report |
| F14 | Keyboard | Autocorrect drops the typed capital: "Teh" + space → "the" (should be "The"), Notes on device | verified fixed r461 — OSK in Notes: "teh" → "The", "hello" stays lowercase |
| F15 | Keyboard | On device (Notes, text-input v2) every word after a space is capitalised ("Teh Hello Ello Tero"); host tests pass — likely the surrounding-text update arriving after the keyboard decides | verified fixed r461 — quick double space ". " + shift, slow double space leaves shift off, caps lock "THE" |
| F16 | OTA | systemd-sysupdate/sysupdated log "Failed to resolve $BOOT" / "Failed to enumerate components" at every shell start on a non-A/B image; Settings should show unsupported quietly | check |
| F18 | Power | "Power save" only flips a UI state: the shell runs `tee` into cpufreq scaling_governor as user → Permission denied every time; use power-profiles-daemon (org.freedesktop.UPower.PowerProfiles) | open |
| F19 | Display | "Auto-brightness: On" on a device with no light sensor (no IIO devices) — a setting that does nothing | open → R35 |
| F20 | Display | Increase from 78% leaves the 10-level backlight at 8/10 (88% truncated, not rounded) | open → R35 |
| F21 | Display | After an app's Display1.SetScreenState(false) then (true): CRTC back on, but the shell still treats the screen as off and drops all touches (shell + apps) until the power key is pressed — user sees a lit, frozen screen | open → R35 |
| F22 | Permissions | Test app (system permission denied) could still call Display1.SetScreenState; root busctl got Access denied for GetState | open → R28 |
| F23 | Sensors | Flashlight shows a working Toggle on a device with no torch; it silently stays Off — should report "not available" | open (minor) |
| F24 | Location | Test app Stop leaves "Active: Yes" (shared LocationManager kept alive by the shell) — confusing, maybe per-client state | open (minor) |
| F25 | Audio | marathon-audiod SetVolume on the Bluetooth A2DP sink (node 54, device 59) returns OK and audiod then reports the new level, but WirePlumber/wpctl show the sink unchanged; reading (wpctl→audiod) works. QS slider therefore moves without changing the volume | verified fixed r461 — SetVolume/SetMuted reach the BT sink, wpctl changes reach audiod, QS slider moves the sink |
| F26 | Audio | Test app audio profiles: Silent/Vibrate/Normal leave "Current: unknown" and Silent does not mute the sink (no [MUTED] in wpctl) — mute likely the same broken write path as F25; profile name not exposed to apps | verified fixed r461 — label shows silent/vibrate/normal; Silent and Vibrate mute, Normal unmutes |
| F27 | Alarms | Dismissing an alarm that fired while the phone was unlocked leaves the phone locked (same pattern as F5 for calls) | verified fixed r459 — same screen-on cause as F5 |
| F28 | Lock | Receiving an SMS while unlocked (test app Multiple SMS) immediately shows the lock screen — with F5/F27 points to the event-wake path re-showing the lock screen when already awake | verified fixed r459 |
| F29 | Calls | simulateCallStateChange: "Active call" shows no in-call indicator, "Ringing" shows no overlay; "End call" locks the phone (F5 family) | open → R32 |
| F30 | Screenshot | Test app "Take screenshot" calls ScreenshotService, which is not exposed to apps → throws, nothing captured. Apps should go through xdg-desktop-portal Screenshot (consent), which the shell's portal backend could implement | open |

| F31 | Alarms | "Current alarms 1" still counted after the one-off test alarm was dismissed | open (minor) |
| F32 | Audio | Dragging the QS volume slider also raises the volume OSD, drawn over the QS header with the date showing through | open (polish) |
| F33 | Audio | Volume OSD and QS slider round differently for the same level (13% vs 14) | open (polish) |

## Worked as intended

- Simulated incoming call screen (number formatting, contact lookup path), SMS banners and lock-screen entries
- Notifications: simple, high-priority (heads-up), all four categories with their icons, a burst of 10, tap-to-open (after 646141ad/10fa7a98)
- Alarms: trigger, create (+1 min, fired on time), hold-to-dismiss, snooze (refired after 10 min)
- Media: ringtone, notification and alarm sounds reach the Bluetooth speaker through PipeWire and stop cleanly
- System: battery/charging state matches UPower; Wi-Fi scan; brightness 50/100/decrease reach the backlight
- Sensors: light/proximity correctly unavailable; location active through the GeoClue agent (BeaconDB, 25 km)
- Gestures: short pull from the pill opens quick settings; the back indicator glow takes taps (r457)
- Sandbox: per-app security-context socket bound over marathon-wayland-0 in the runner (r457)
