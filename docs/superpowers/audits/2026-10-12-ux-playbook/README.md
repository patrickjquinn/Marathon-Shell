# UX playbook audit, 2026-10-12

Every shell surface and app was checked against the UX playbook (21 laws plus the build checklist). Sailfish conventions and Marathon's pill-gesture model count as the platform conventions. Findings come from reading the code and from PinePhone screenshots of r395.

| Report | Scope | P0 | P1 | P2 |
| --- | --- | --- | --- | --- |
| [shell-entry.md](shell-entry.md) | Lock, PIN, first-run setup, home, search, switcher, Hub | 3 | 15 | 36 |
| [shell-system.md](shell-system.md) | QS, status/nav bar, keyboard, toasts, HUD, dialogs, overlays | 4 | 22 | 31 |
| [app-settings.md](app-settings.md) | Settings | 6 | 20 | 23 |
| [apps-store-browser-maps-terminal.md](apps-store-browser-maps-terminal.md) | Store, Browser, Maps, Terminal | 0 | 13 | 29 |
| [apps-comms-productivity.md](apps-comms-productivity.md) | Email, Messages, Phone, Notes, Calendar | 0 | 17 | 27 |
| [apps-media-utility.md](apps-media-utility.md) | Camera, Clock, Music, Gallery, Calculator, Test Suite, template | 2 | 19 | 32 |
| **Total** | | **15** | **106** | **178** |

## P0: broken or lying

| ID | Problem |
| --- | --- |
| SE-49 | Tapping a Hub notification does nothing; the signal isn't connected and sends id 0. |
| SE-15 | A 4- or 5-digit quick PIN can't be entered; the pad submits only at 6 digits and has no OK key. |
| SE-32 | The home pager and the grid count apps-per-page differently, so apps are unreachable at 150 % and a blank page appears at 110 %. |
| SS-24 | Keyboard accents can't be typed; the popup closes on release. |
| SS-05 | The QS Hotspot starts an open-secret AP (`marathon2025`) the user never sees, and lights up even when it fails. |
| SS-06 / ST-44 | Settings › Quick settings changes nothing; the shell hard-codes its tiles and the IDs don't match. |
| SS-55 | The screenshot preview card uses `Qt.rgba(15, 15, 15)`, which renders as white. |
| ST-17 | Screen timeout writes a store the idle timers don't read. |
| ST-32 | Keyboard language and auto-capitalise never reach the keyboard. |
| ST-15 | Mobile network always says "No modem found"; the modem isn't exposed to apps. |
| ST-41 | Default apps are saved but never read. |
| ST-18 | Status-bar clock position is saved but never read. |
| A3-23 | Music can't reach its library. **Fixed in 665f6445** (restored the shell module import). |
| A3-24 | Music probably stops when backgrounded (no MPRIS, so no background-audio grant). Verify on device. |

## Cross-cutting themes

1. **Settings that lie.** Pages write keys with no consumer. Add a contract test that every key Settings writes is a real IPC property the shell reads (ST-49).
2. **Lost input and state.** Wi-Fi and PIN dialogs clear fields on error; stopwatch, timer, Music queue, Calculator and Mail drafts are lost on close.
3. **Silent waits.** QS radio toggles, mail send/sync, account sign-in, Store installs and time-zone changes give no progress, outcome or cancel.
4. **Dead ends.** Mail folders, attachments, Camera's thumbnail, Phone's "Send message", the Store offline, Maps' futile "Try again".
5. **Gesture teaching and consistency.** First-run setup doesn't teach the pill gestures, and toast dismissal differs on every surface.
6. **Rejected styles still present.** Maps' FilterChip, Camera's mode pill, the Music artwork box, Messages' tinted bubbles, the teal press halo on home icons.
7. **Test Suite on every home grid.** Should be developer-only (A3-46).

## Suggested order

P0s first (most are small), then themes 1–3, which cover most P1s, then the per-surface P1s by traffic (lock/home/Hub/QS, then Phone, Messages, Settings, Camera), then P2 polish.
