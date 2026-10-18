# Lessons from Jolla: Sailfish OS's shortcomings, checked against Marathon

Sources, read 2026-10-18:

- [Debating shortcomings of Sailfish OS](https://forum.sailfishos.org/t/debating-shortcomings-of-sailfish-os/33232/107): the whole thread, 99 posts.
- [Sanefish – what Jolla forgot](https://forum.sailfishos.org/t/release-sanefish-what-jolla-forgot/35167/23): the opening post (about 30 patches the community thinks Jolla should have shipped) and the replies.

Only the larger, recurring points are listed. "Marathon today" is checked against the code and the HackberryPi, not taken from memory.

## Where Sailfish failed, and where Marathon stands

| # | Jolla's failing (what users said) | Marathon today | Verdict |
|---|---|---|---|
| 1 | **No way to run the apps people need.** Banking and government-ID apps are missing, and Android support (AAS) is unreliable. Its apps ignore Sailfish gestures and have no back gesture. This was the most-raised reason people return to Android. | No Android runtime at all. Flatpaks and Marathon apps only. | **Biggest gap.** Decide the strategy now (below). |
| 2 | **Gestures fight each other and nobody can find them.** The top menu, scrolling, app close and edge swipes collide; one user put the tolerance at "0.001%". The Sanefish back zones also overlap the keyboard's edge keys. | One bottom pill (left back, up home/switcher, down Quick Settings) plus a left-edge Hub peek. The setup screens teach the gestures. | Mostly avoided. **Audit the left-edge peek against keyboard edge keys and horizontal in-app swipes**, and measure how forgiving the gestures are on the device. |
| 3 | **Five app stores** (Jolla Store, Chum, OpenRepos, Aurora, F-Droid), plus repo setup and malware risk. | One Store (Flathub plus Marathon packages), sandboxed installs, and sideload escalation blocked. | Avoided. Keep it to one Store. |
| 4 | **Covers are identical grey rectangles.** | The switcher shows live window thumbnails, two by two. | Avoided. |
| 5 | **A browser years behind** (old Gecko ESR) that "struggles on certain websites". | QtWebEngine (current Chromium) and Pacific (WPE). Today's V3D black-page bug was found by testing. | Avoided, but **keep the engines current**, and test the Browser on every GPU stack. |
| 6 | **"Incomplete and incredibly buggy"; built-in apps missing basics.** | 15 built-in apps with tests, now driveable end to end over MCP. Today's run still found bugs: Calculator precedence, Settings frozen after `app.show`, and the stale PID after an app exits. | **Run the MCP end-to-end pass on the device for every image** (keel-mcp makes this cheap), not by hand once a release. |
| 7 | **Recovery needs Telnet**, and the recovery menu can't be driven with the volume keys. | A/B updates fall back to the last good version on their own; this happened on the HackberryPi today. | Updates are covered. **There is no factory reset in Settings and no recovery UI.** Add "Erase all content" and a recovery boot entry. |
| 8 | **No real encryption** (LUKS and PIN missing or incomplete). | The QEMU image has LUKS2 root with an empty passphrase that unlocks itself, so it protects nothing. The Pi images: check. | **Gap.** Unlock the data partition with a key derived from the PIN (or a passphrase) at boot. Until then, don't claim data-at-rest protection. |
| 9 | **Notifications feel foreign.** | Redesigned today: Marathon-glass banners, and a Hub with day sections and app filters. | Addressed. |
| 10 | **No app search; no settings search.** | Global search and Settings search exist. | Avoided. |
| 11 | **Hidden affordances.** Pulley menus nobody discovers. | Marathon uses Silica's pulleys too. Some actions live only there; for example, "Check now" for updates is only in the pulley. | **Risk we share.** Every pulley action needs a visible route as well (an empty-state hint, a button, or an item in the page). |
| 12 | **The lock screen is fixed:** no flashlight, no widgets. | Phone and camera shortcuts, media controls, notifications. | Small gap. Consider a flashlight shortcut; skip widgets for now. |
| 13 | **Things the community patched in** (Sanefish): volume keys always control media, app lock, screen recorder, call recording, rotation suggestion, and text selection that doesn't overwrite the clipboard. | Volume is the Multimedia level (R38). No app lock, no screen recorder, no rotation suggestion. Call recording: check. | Pick the ones people use daily: **app lock and screen recorder** first. |
| 14 | **Developers have no examples, unclear store rules, and unstable SDK APIs; features ship as Patchmanager hacks.** | The Keel/Silica framework, `marathon-dev`, the design system, coding rules, Keel Actions, and Reef's review rules. | Mostly avoided. Keep the app template and docs current with every framework change. |
| 15 | **UI inconsistent because of AI-written code** (said of Sanefish). | Marathon is largely AI-assisted. Today the iOS-style glass was reversed because it broke the design system. | **A real risk for us.** Keep the guards: design-system tokens, CODING_RULES, screenshot review on the device, and push back on requests that break the system. |
| 16 | **No clear target market, an opaque roadmap, a hostile forum, thin marketing.** | Not a code problem. There is a roadmap tracker in-repo. | Publish the target and the roadmap. |

## What to do, in order

1. **Android apps (1).** Choose one approach and make it first-class, not best-effort:
   - Waydroid as a sandboxed runtime whose windows go through Marathon's compositor, with the pill's back gesture sent to Android as `KEYCODE_BACK`, notifications bridged into the Hub, and its apps listed in the launcher and Store;
   - or state plainly that Marathon is Flatpak/web only, and invest in PWAs through Pacific.

   Jolla's lesson is that doing it half-way costs the most trust.
2. **Erase and recover (7):** "Erase all content" in Settings, and a recovery boot entry the person can reach with buttons.
3. **Encryption bound to the PIN (8).**
4. **A device end-to-end pass for every image (6):** a keel-mcp script that calls every app's actions plus the shell's, and fails the release on an error. Today's manual run is the template (`mcpdrive.py`).
5. **Visible routes for pulley-only actions (11).**
6. **Gesture-conflict audit (2):** the left-edge peek against keyboard edge keys and in-app horizontal swipes, with forgiveness measured on the device.
7. **App lock and screen recorder (13).**
