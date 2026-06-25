# Marathon Shell — r230 UX audit (2026-06-25, autonomous)

Driven via marathon-dev launch / screenshot — no touch synthesis, 13 of 14
apps captured cleanly. Mail launched but rendered Messages (Mail process
either crashed silently or the entry-point routing reverted to the
fallback handler).

## Confirmed (re-tested live)
- **#406 Phone title heavy + unlabeled actions** — title at y≈170 ≈64 px tall vs 16 px tab labels; X icon role ambiguous.
- **#408 Settings brightness 0%** — actually a sandbox-isolation symptom (see #421); Settings reads its own empty SystemControlStore singleton. Wi-Fi, BT, Display, Sound all show defaults because the app process has no IPC bridge to the shell's stores.
- **#412 Browser cold-start dead-air** — splash without progress, no chrome.
- **#417 Camera bare empty state** — "Camera unavailable" text only, no tab bar, no troubleshooting CTA.
- **#418 Maps stuck on splash** — same dead-air pattern as Browser.
- **#421 Apps cannot reach shell singletons** — broader pattern; brightness/sound/Wi-Fi/BT all read defaults in Settings.
- **#426 Calculator ~700 px wasted above result** — yes; scientific row chips also touch with no breathing room.

## New findings landed this turn

### Music (fixed)
- "PLAYING FROM" eyebrow at y≈63 was overlapping the status-bar clock. Cause: column `anchors.topMargin: 8` against an app that fills the full canvas (no safe-area inset from app side). Fix: `anchors.topMargin: Constants.safeAreaTop + 8` in `apps/music/MusicApp.qml`.

### Clock (open)
- World Clocks rows collapsed: offset (`-4h`) sits *above* city name on its own visual row; time and "THU" suffix on a second sub-row. Looks like a CSS-grid collapse where intended `[offset · city] [time · day]` shows as `[offset]\n[city] [time]\n[day]`.
- Analog clock face minute-hand overlaps centered "THU/PM" label — hand drawn on top of text.

### Calendar (open)
- M-T-W-T-F-S-S weekday letters render in same grey as next-month days — weekday header indistinguishable from "trailing days" content.
- "THURSDAY, JUNE 25" subhead followed by ~600 px empty space — needs MEmptyState or upcoming-events list (same pattern as Hub / Phone Recents fixes from earlier in session).

### Notes (open)
- Both a "TODAY" section header AND an "No Notes Yet" empty state visible simultaneously — redundant. Either hide the section when empty, or drop the empty-state.

### Store (open)
- Single Editors' Pick card then ~870 px black to tab bar. Missing category rows / loading skeleton.
- Hero card teal decorative arc bleeds past the card edge at x≈570-720.

### Settings (open, blocked on #421)
- 0% values across the board because the Settings app is sandboxed and its `SystemControlStore` singleton is a fresh empty instance, NOT a proxy to the shell's. Needs `apps/settings` to read via `org.marathonos.Shell.Display1.GetState()`, `Network1.GetState()`, etc., instead of `SystemControlStore.brightness`.
- Bottom Battery row clipped through-icon — content area not respecting the navBar safe area.

## Mail (P0 — captured rendering Messages)
Mail launches via `marathon-dev launch mail` but the resulting screen IS
the Messages app (title bar "Messages", Pinned/All/Archive tabs).
Either:
1. Mail crashes immediately and the compositor falls back to whatever was last shown, or
2. The `mail` app-id is mis-routed and actually launches Messages.

Needs `journalctl _PID=$(pidof marathon-shell-bin) -f` while invoking
`marathon-dev launch mail` to capture the crash output.
