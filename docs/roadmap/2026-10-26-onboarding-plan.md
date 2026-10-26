# Onboarding Implementation Plan

**Goal:** Replace the form-style first-run wizard with the six-beat,
learn-by-doing onboarding in the design, built from real Silica controls
and real shell components, ending with a gesture-driven hand-over to home.

**Architecture:** `MarathonOOBE.qml` becomes a coordinator that owns the
beat index, progress bar, back gesture, its `MarathonNavBar` (in a new
`setupMode`) and completion. Each beat is its own component under
`shell/qml/components/oobe/`. Previews embed `MarathonAppGrid`; the Hub
beat embeds `MarathonPeek`; the finish shrinks the coordinator's content
with a `MultiEffect` rounded mask.

**Tech Stack:** Qt 6.11 QML, Keel Sailfish Silica + Marathon.Silica,
QtQuick.Effects, Keel `Ambience`, Rust (ambience accents), qmltestrunner.

**Spec:** `docs/design/2026-10-26-onboarding-design.md`

## Global Constraints

- Beats, in order: Hello, Get online, Keep it private, Make it yours, Easy to read, Your Hub, then Off you go.
- Every control is a Keel Silica control (`Button`, `SecondaryButton`, `ListItem`, `Keypad`, `IconButton`, `Slider`, `TextSwitch`, `InteractionHintLabel`, `TouchInteractionHint`, `FirstTimeUseCounter`); imports `import Sailfish.Silica 1.0 as Silica` then `import Marathon.Silica 1.0 as Silica` (lint enforces the order).
- Every user-facing string `qsTr(...)` with a `//:` comment where the text alone is ambiguous. Copy is exactly the design's.
- Practice fallback: demo after 8 s or two failed tries; "Not now" after the demo.
- `reduceMotion`: hero motions become 200 ms cross-fades; the demo plays once.
- Passcode: 6 digits, enter then confirm, `Security.setQuickPINFirstRun`; not skippable.
- Fits 720×720 (HackberryPi, DPI profile 254) and 720×1440.
- Follow `docs/CODING_RULES.md`; terse comments; atomic commits; no AI trailers.

## Review Focus

- A person who never manages the edge swipe: the demo plays at 8 s, "Not now" appears, and setup can finish. Test in Task 5.
- Back gesture on the first beat, and on the passcode beat mid-entry: the first does nothing; the second returns to Get online and clears the digits. Test in Task 2 and Task 3.
- Setup restarted half-way (shell restart): it starts again from Hello with nothing half-applied except settings already saved (wallpaper, size, Wi-Fi). Test in Task 2.
- No Wi-Fi hardware or Wi-Fi off: Get online shows the Wi-Fi switch and "Not now" works. Test in Task 3.
- A finish flick released short of the threshold springs back and setup stays; a second, full flick completes it. Test in Task 6.

---

### Task 1: Wallpapers and the hint icon

**Files:**
- Create: `shell/resources/wallpapers/moos-sunset.jpg`, `oeschinensee-night.jpg`, `sylvester-dawn.jpg` (copy from `/tmp/claude-1000/-home-patrickquinn-Developer-Marathon-Shell/5d652fe6-cba5-4042-ac15-511e33033fff/scratchpad/walls-dl/out/`)
- Modify: `shell/resources/wallpapers/CREDITS`, `shell/CMakeLists.txt` (the `shell_wallpapers` resource list), the image's wallpaper install list if separate (check `packaging/` and `/usr/share/marathon-shell/wallpapers` handling)
- Modify: `crates/marathon-shell-native/src/ambience.rs` `BUILT_IN` (three rows: names "Moos Sunset", "Oeschinensee Night", "Lake Sylvester Dawn", with measured accents)
- Create: `marathon-icon-theme/svg/graphics-edge-swipe-arrow.svg` (+ the theme's index/icon-map entry; `tests/lint/check-icon-map.sh` must pass)

- [ ] **Step 1:** Measure each accent with the crate's own `seed`/`highlight` (a throwaway test printing them); record the hex values; delete the throwaway.
- [ ] **Step 2:** Add files, CREDITS entries (title, author, Commons URL, licence, "scaled and re-encoded"), resource entries, `BUILT_IN` rows. Extend the ambience test that checks built-ins: each new file name resolves to its accent through `built_in()`.
- [ ] **Step 3:** Draw `graphics-edge-swipe-arrow.svg` in the theme's style (a right-pointing chevron trail from the edge, white fill, same viewBox convention as neighbours) and register it.
- [ ] **Step 4:** Run `cargo test -p marathon-shell-native ambience`, `bash tests/lint/check-icon-map.sh` — PASS. Commit "Add three photographic wallpapers with distinct accents" and "Add the edge-swipe hint graphic".

### Task 2: Coordinator, setup mode, progress and Hello

**Files:**
- Modify: `shell/qml/components/MarathonOOBE.qml` (becomes the coordinator)
- Modify: `shell/qml/components/MarathonNavBar.qml` (`property bool setupMode: false`; when true, the locked-session gates on swipe up and tap are bypassed and `gestureProgress` keeps reporting)
- Create: `shell/qml/components/oobe/OobeProgress.qml`, `OobeHello.qml`, `OobeAccessibilitySheet.qml`, `OobeLanguageSheet.qml`
- Modify: `shell/CMakeLists.txt` QML_FILES
- Test: `tests/ui/tst_oobeflow.qml` (+ stubs in `tests/ui/stubs/` as needed)

**Interfaces:**
- Consumes: `SettingsManagerCpp.language`, `SettingsManagerCpp.availableLanguages` (localisation Task 1), `SettingsManagerCpp.reduceMotion`, `userScaleFactor`.
- Produces: coordinator `property int beat` (0 Hello … 6 Your Hub, 7 Off you go), `function advance()`, `function back()`, signal `setupComplete`; each beat component exposes `signal done()` and optional `function handleBack(): bool` (true = consumed internally).

- [ ] **Step 1: Write failing tests** `tst_oobeflow.qml`: starts on Hello with no progress bar; swipe up on the nav bar (setupMode) advances to Get online; tap on the pill and Enter also advance; back on Hello stays; progress shows 1 of 5 on Get online; Accessibility opens a sheet whose Reduce motion switch writes `reduceMotion`; Language lists `availableLanguages` native names, marks preview ones "Preview", writes `language` on tap; a freshly created OOBE always starts at beat 0.
- [ ] **Step 2: Run** `qmltest.sh tst_oobeflow.qml` — FAIL.
- [ ] **Step 3: Implement** the coordinator, `setupMode`, progress, Hello (greetings list from the shipped languages: en "Hello", de "Hallo", fr "Bonjour", es "Hola", ga "Dia dhuit"; 2.5 s cross-fade; wallpaper glow) and both sheets.
- [ ] **Step 4: Run** `qmltest.sh tst_oobeflow.qml tst_navbar.qml` — PASS (navbar suite unchanged). Commit "Start setup with Hello and the setup-mode nav bar".

### Task 3: Get online and Keep it private

**Files:**
- Create: `shell/qml/components/oobe/OobeOnline.qml`, `OobePasscode.qml` (logic moved from the old pages)
- Modify: `tests/ui/tst_oobewifi.qml`, `tests/ui/tst_oobepasscode.qml` (retarget); delete `tests/ui/tst_oobetimezone.qml` (step removed)

- [ ] **Step 1: Retarget the tests**: wifi — networks as ListItems, connected first and highlighted, "Not now" advances without connecting, Wi-Fi off shows the switch; passcode — Keypad digits fill dots, delete removes, mismatch shows "Passcodes don't match. Try again." and clears confirm, match calls `Security.setQuickPINFirstRun` and advances, back mid-entry returns to Get online with digits cleared, physical keys work.
- [ ] **Step 2: Run** — FAIL; **implement** the two beats; **run** `qmltest.sh tst_oobewifi.qml tst_oobepasscode.qml` — PASS.
- [ ] **Step 3: Commit** "Move Wi-Fi and the passcode into the new setup beats".

### Task 4: Make it yours and Easy to read

**Files:**
- Create: `shell/qml/components/oobe/OobeLook.qml`, `OobeSize.qml`, `oobe/WallpaperReveal.qml` (circle reveal)
- Test: `tests/ui/tst_oobelook.qml`

- [ ] **Step 1: Write failing tests**: thumbnails list the built-in wallpapers (from the same source Settings' Ambience page uses); tapping one sets the wallpaper via the normal settings path and starts the reveal centred on that thumbnail; the preview contains a `MarathonAppGrid`; the size Slider (75–150, step 5, value text "N%") writes `userScaleFactor` and the preview grid's columns follow.
- [ ] **Step 2: Run** — FAIL; **implement** (reveal ≈450 ms OutCubic; cross-fade under reduceMotion); **run** `qmltest.sh tst_oobelook.qml` — PASS.
- [ ] **Step 3: Commit** "Choose wallpaper and size on the real home grid during setup".

### Task 5: Your Hub practice

**Files:**
- Create: `shell/qml/components/oobe/OobeHub.qml`, `oobe/PracticeCoach.qml` (8 s / two-tries fallback, demo, "Not now")
- Test: `tests/ui/tst_oobehub.qml`

- [ ] **Step 1: Write failing tests**: entering posts one "Welcome to Marathon" notification (app "Marathon"); an edge drag to the icon stop completes the beat ("That's it") and advances after 1.5 s; no attempt for 8 s starts the TouchInteractionHint demo; two short drags also start it; after the demo "Not now" is visible and advances; under reduceMotion the demo doesn't loop; re-entering doesn't post a second notification.
- [ ] **Step 2: Run** — FAIL; **implement**; **run** `qmltest.sh tst_oobehub.qml tst_peek.qml` — PASS.
- [ ] **Step 3: Commit** "Practise the Hub peek during setup".

### Task 6: Off you go

**Files:**
- Create: `shell/qml/components/oobe/OobeFinish.qml`
- Modify: `MarathonOOBE.qml` (shrink/round its content with `MultiEffect` mask driven by the nav bar's `gestureProgress`), `shell/qml/components/MarathonAppGrid.qml` (one-shot `playEntrance()` stagger, 30 ms per icon), `shell/qml/MarathonShell.qml` (call it on setup completion)
- Test: extend `tests/ui/tst_oobeflow.qml`

- [ ] **Step 1: Write failing tests**: on the finish beat a flick past the threshold emits `setupComplete` and sets `firstRunComplete`; a drag released short springs back (scale returns to 1) and does not complete; the content scale tracks progress down to 0.45.
- [ ] **Step 2: Run** — FAIL; **implement**; **run** `qmltest.sh tst_oobeflow.qml` — PASS.
- [ ] **Step 3: Commit** "Leave setup with the flick up into the home screen".

### Task 7: After-setup hints

**Files:**
- Create: `shell/qml/components/FirstUseHints.qml` (in `MarathonShell.qml`)
- Test: `tests/ui/tst_firstusehints.qml`

- [ ] **Step 1: Write failing tests**: the first app opened after setup shows "Drag the bar left to go back" once; the first return home shows "Pull the bar down for quick settings" once; neither shows again (FirstTimeUseCounter limit 1); neither shows during setup.
- [ ] **Step 2: Run** — FAIL; **implement**; **run** — PASS. Commit "Teach back and quick settings the first time they're useful".

### Task 8: On the device

- [ ] **Step 1:** Build and install on the HackberryPi; turn first run back on (`firstRunComplete=false` in `~/.config/marathon-os/Marathon Shell.conf`, greetd stopped while editing, a backup kept); drive every beat with `/root/replay.py` touches; screenshot each (`kill -USR1`), and compare with the round-2 mockup boards; fix differences that hurt the design.
- [ ] **Step 2:** Run it once in German and once in the pseudo-language; fix clipping.
- [ ] **Step 3:** Restore the settings file and the PIN 027602; full lint; touched suites; bump pkgrel; push; `gh run list`.
