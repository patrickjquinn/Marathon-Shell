# UX playbook audit: media and utility apps (A3)

Scope: `apps/camera`, `apps/clock`, `apps/music`, `apps/gallery`, `apps/calculator`, `apps/test`, `apps/template`.
This is a code-only audit at branch `feat/keel-framework-1a` (f995afaa). Nothing was run on a device. Findings marked "verify" come from reading the code and need a QEMU or device check.

Size baseline: Keel Theme bases at pixelRatio 1.0 are itemSizeExtraSmall 70, Small 80, Medium 100, Large 110, ExtraLarge 135, iconSizeMedium 64. On a 540-px-wide phone canvas, 70 units is roughly 7 mm, which is at least 44 pt. Every target below is checked against `Theme.itemSizeExtraSmall`.

## Summary

| Severity | Count |
| --- | --- |
| P0 broken | 2 |
| P1 clearly violates playbook | 19 |
| P2 polish | 32 |

The apps are Silica-faithful at the component level. There are almost no hard-coded pixels or colours: the only magic values are `Theme.rgba(primary, 0.1)` in two places and `3 * fontSizeHuge`. Every app uses pulley menus, ViewPlaceholder with hint text, ListItem with ContextMenu, and remorse on its main deletes. Almost every touch target is 80 units or larger.

The problems are in behaviour rather than visuals:

- Music is broken at runtime: a commit from today removed the import it needs to reach its library (A3-23), and it never claims background audio (A3-24).
- Most apps lose your work when closed (stopwatch, timer, music queue and position, calculator).
- Several end states are missing: no "alarm in 7 h" confirmation, no video thumbnail, recorded videos cannot be viewed anywhere.
- Some inputs are too narrow: timer presets only, a 26-city world clock, no copy or paste in Calculator.
- The Test Suite app ships on every user's home grid and can write fake data into their real contacts and messages.

---

## Camera

### CameraApp.qml / pages/CameraPage.qml

**A3-01 · P1 · Doherty threshold (launch)** · `apps/camera/CameraApp.qml:15`, `apps/camera/src/CameraController.cpp:54-55, 435-449`
- **Problem:** `CameraController` is a property of the ApplicationWindow. Its constructor runs `QMediaDevices::videoInputs()` and a sorted directory listing of `Pictures/Marathon`, both synchronously, before the first page exists. So the "Starting camera…" BusyLabel (`CameraPage.qml:429-439`) cannot appear until that work finishes. This is a likely contributor to the reported PinePhone splash of more than 7 s. The other likely contributor is the shared QML recompile on every launch.
- **Fix:** Let the page render first. Run device enumeration and the latest-photo scan after the first frame: `Qt.callLater` for enumeration, a worker for the directory scan, and read only the newest entry instead of sorting the whole folder. The existing BusyLabel then covers the wait. Measure on the PinePhone before and after.
- **Effort:** M

**A3-02 · P1 · Doherty / user control** · `apps/camera/CameraApp.qml:32-34`, `apps/camera/src/CameraController.cpp:165-175`
- **Problem:** The self-timer cannot be cancelled. Pressing the shutter during the countdown calls `captureWithTimer()` again, which restarts the countdown.
- **Fix:** While `timerActive` is true, the shutter cancels the timer (accessible name "Cancel timer") and shows a stop glyph, the same way recording does.
- **Effort:** S

**A3-03 · P1 · Peak-end (video success state)** · `apps/camera/src/CameraController.cpp:389-394, 438`
- **Problem:** `latestPhotoPath` is only updated from photo saves, and the startup scan filters `*.jpg/*.png`. After you stop a recording, the thumbnail does not change and nothing confirms the video was saved.
- **Fix:** On `RecorderState → Stopped`, take `actualLocation()`, emit a "media saved" signal, and show a poster frame (via the thumbnailer or MediaLibrary) in `CaptureThumbnail`.
- **Effort:** S–M

**A3-04 · P1 · Jakob (Jolla Camera) / peak-end** · `apps/camera/CameraApp.qml:52-54`, `apps/camera/pages/CameraPage.qml:381-391`
- **Problem:** Tapping the capture thumbnail calls `Navigation.launchApp("gallery")`, which opens Gallery's collection list. Your new photo is two taps away, and the camera is gone. In Jolla Camera, a swipe or tap shows the last capture, with Delete and Share in its pulley.
- **Fix:** Deep-link to the Gallery viewer for that path. The alternative is a local review page with a PullDownMenu containing Delete (RemorsePopup), Share and "Open in Gallery".
- **Effort:** M

**A3-05 · P1 · User direction (no pills or tinted fills) / Jakob** · `apps/camera/components/ModeSwitch.qml:7-17, 49-57`
- **Problem:** The photo/video switch is a segmented toggle: a pill-shaped `Rectangle` filled with `rgba(darkPrimary, opacityLow)`, with a `highlightBackgroundColor` disc behind the active mode. That combines a pill toggle and a tinted fill, both of which you rejected.
- **Fix:** Use two plain IconButtons with no container. Mark the current one with `icon.highlighted: true`, plus a small Label under it, so the state does not rely on colour alone.
- **Effort:** S

**A3-06 · P2 · Doherty (<100 ms visual acknowledgement)** · `apps/camera/pages/CameraPage.qml:63-69`
- **Problem:** The white flash runs on `photoSaved`, which fires after the JPEG is encoded and written. On slow hardware that is noticeably after the press. The haptic at press time (`:27-30`) is good.
- **Fix:** Expose `QImageCapture::imageCaptured` and run the flash on it. Keep `photoSaved` for updating the thumbnail.
- **Effort:** S

**A3-07 · P2 · Error copy** · `apps/camera/CameraApp.qml:20-22`, `apps/camera/src/CameraController.cpp:153-157`
- **Problem:** Every error raised while the camera is active shows "Check free storage and try again." That includes "Camera not ready", which you can trigger by tapping the shutter during the 150 ms flip.
- **Fix:** Disable the shutter while a flip is in progress, and map error kinds to the right copy.
- **Effort:** S

**A3-08 · P2 · Resumption / honesty** · `apps/camera/CameraApp.qml:71`, `apps/camera/manifest.json:16`
- **Problem:** Leaving the app calls `camera.stop()`, even in the middle of a recording. The manifest declares a `"recording"` background capability that is never claimed. The recording ends silently.
- **Fix:** Pick one:
  - Keep recording: hold `Lifecycle.beginBackgroundTask("recording", …)`, the same pattern as `ClockApp.qml:25-32`.
  - Stop cleanly and show "Video saved".
- **Effort:** S

**A3-09 · P2 · Reduced motion** · `apps/camera/pages/CameraPage.qml:92-111, 317-323, 424-426`
- **Problem:** The 3D viewfinder flip, the infinitely blinking recording dot and the flip-button rotation all ignore `Settings.reduceMotion`. No app in this audit scope reads that setting.
- **Fix:** When reduce motion is on, use duration 0 and show a steady dot.
- **Effort:** S

**A3-10 · P2 · Occam (remove-it test)** · `apps/camera/cover/CameraCover.qml:43-49`, `apps/camera/CameraApp.qml:80`
- **Problem:** The cover's camera action (`captureAction`) only activates the app, which tapping the cover already does. Its name suggests it takes a capture, but it does not.
- **Fix:** Either make it capture (activate, then shoot once the camera is active) or remove it.
- **Effort:** S

**A3-11 · P2 · Jakob** · `apps/camera/pages/CameraPage.qml:147-178`
- **Problem:** The rule-of-thirds grid is always drawn, with no way to turn it off. Jolla Camera offers this as a setting.
- **Fix:** Add a `TextSwitch` "Grid" to `SettingsPanel`, and persist it.
- **Effort:** S

**Good:**
- The shutter is 135 units, bottom-centre, and plays a haptic on press.
- The thumbnail is 100 units and the flip, settings and mode buttons are 80, all with accessible names.
- The no-camera state is a ViewPlaceholder with a pull-down recovery ("Grant camera access" or "Try again").
- Settings live in a DockedPanel using TextSwitch, ComboBox and DetailItem, and Escape closes it.

---

## Clock

### AlarmsTab / AlarmDialog / AlarmDelegate

**A3-12 · P1 · Peak-end (success state)** · `apps/clock/ClockApp.qml:53-63`, `apps/clock/pages/AlarmDialog.qml:16`
- **Problem:** Saving or enabling an alarm gives no feedback. Jolla Clock shows "Alarm in 7 hours 20 minutes".
- **Fix:** After a successful `saveAlarm` or toggle-on, call `Logic.nextOccurrence(alarm, new Date())` and show `Notices.show(qsTr("Alarm in %1"))` with the remaining hours and minutes.
- **Effort:** S

**A3-16 · P2 · Bug (i18n round-trip)** · `apps/clock/ClockApp.qml:48, 56-57`
- **Problem:** `editAlarm` compares against the untranslated `"Alarm"`, but `saveAlarm` stores `qsTr("Alarm")`. In any non-English locale, the default label then appears as a literal custom label in the edit field.
- **Fix:** Store `""` for the default label and render `qsTr("Alarm")` only when displaying it.
- **Effort:** S

**Good:**
- This is Silica-exact: PullDownMenu "New alarm", ViewPlaceholder "No alarms / Pull down to add one", ListItem with ContextMenu Delete via `remorseDelete`, the glass-dot `Switch` with an accessible name, a `TimePicker` dialog with DialogHeader "Save", and weekday cells with CheckBox accessibility roles.

### StopwatchTab / TimerTab / models

**A3-13 · P1 · Ovsiankina (resumption)** · `apps/clock/ClockApp.qml:15-21`, `apps/clock/models/Stopwatch.qml`, `apps/clock/models/CountdownTimer.qml`
- **Problem:** The stopwatch and countdown are in-memory QtObjects. If you close the app, or it is killed by OOM or a crash, a running stopwatch or timer is lost silently. The timer only rings if the process is still alive (`onFinished → triggerAlarmNow`).
- **Fix:**
  - Persist `startedAt`, `before`, `laps` and `endsAt` with `ConfigurationValue`, and restore them on launch. Both models already use wall-clock time, so this is cheap.
  - Schedule the timer end as a one-shot system alarm at `endsAt`, and cancel it on pause or reset, so it rings even if the app is dead.
- **Effort:** M

**A3-14 · P1 · Postel / Tesler (input range)** · `apps/clock/pages/TimerTab.qml:67-88`
- **Problem:** The only way to set the timer is six preset buttons (1, 3, 5, 10, 15 and 30 min). You cannot set 2 min, 45 min or 1 h 30.
- **Fix:** Add a PullDownMenu "Set timer" that opens a Dialog with hour, minute and second pickers, and remember the last value. Keep the presets as quick picks.
- **Effort:** M

**A3-17 · P2 · Resumption / cover** · `apps/clock/cover/ClockCover.qml:14, 80-88`
- **Problem:** A paused timer disappears from the cover, because the cover shows the timer only while `running`. The cover also offers only Pause, with no Resume.
- **Fix:** Show the timer whenever `remaining > 0`, and make the cover action toggle between `icon-cover-pause` and `icon-cover-play`.
- **Effort:** S

**A3-18 · P2 · Serial position** · `apps/clock/pages/StopwatchTab.qml:52-74`, `apps/clock/models/Stopwatch.qml:41-44`
- **Problem:** Laps are listed oldest first and show cumulative times, so the newest lap drops below the fold and split times are not shown.
- **Fix:** Put the newest lap first and show its split, with the total as secondary text.
- **Effort:** S

**A3-19 · P2 · Thumb zone** · `apps/clock/pages/StopwatchTab.qml:34-49`, `apps/clock/pages/TimerTab.qml:46-62`
- **Problem:** Start/Stop and Lap/Reset sit in the upper half, directly under the large time display.
- **Fix:** Anchor the button row to the bottom of the TabItem, with the time and laps above it.
- **Effort:** S

**A3-22 · P2 · Magic value** · `apps/clock/pages/TimerTab.qml:35`
- **Problem:** `backgroundColor: Theme.rgba(Theme.primaryColor, 0.1)` is a magic opacity.
- **Fix:** Use ProgressCircle's default background, or `Theme.opacityFaint`.
- **Effort:** S

### WorldClockTab / AddCityPage

**A3-15 · P1 · Postel / Tesler** · `apps/clock/ClockLogic.js:73-100`, `apps/clock/pages/AddCityPage.qml:33-36`
- **Problem:** The city list is 26 hard-coded entries, so Dublin, Lisbon, Cairo, Lagos, Jakarta and many others cannot be found. An empty search shows "No cities found" with no hint.
- **Fix:**
  - Build the list from tzdata (zone1970.tab, which includes country) through the `WorldClock` platform API, and search city and country names.
  - Add the hint "Try the country or a nearby city".
- **Effort:** M

**A3-20 · P2 · Pragnanz (type scale)** · `apps/clock/pages/WorldClockTab.qml:109, 132`, `apps/clock/components/AlarmDelegate.qml:60`
- **Problem:** Clock uses six font sizes: Huge, ExtraLarge, Large, default, Small and ExtraSmall. Secondary lines are ExtraSmall in World clock but Small in Alarms.
- **Fix:** Use Small for secondary lines in both tabs.
- **Effort:** S

**A3-21 · P2 · Output consistency** · `apps/clock/ClockLogic.js:123-127`
- **Problem:** The fallback for cities without a time zone always formats in 12 h with "AM/PM", ignoring the locale.
- **Fix:** Format with `Format.formatDate(…, Formatter.TimeValue)`.
- **Effort:** S

**Good:**
- City removal goes through remorse, and Move up/down sits in the context menu.
- The world-clock header shows the local time and date.
- The cover shows the next alarm, the timer or the stopwatch, with a context-appropriate action.
- A running countdown holds a background task, which is the pattern Music should copy (A3-24).

---

## Music

### MusicApp.qml / Player.qml

**A3-23 · P0 · Broken** · `apps/music/MusicApp.qml:15`, `tools/marathon-app-runner/main.cpp:1151-1153`
- **Problem:** Commit 68bd9a24 (today, "stop importing the shell module") removed `import MarathonOS.Shell`. In the runner, `MusicLibraryManager` is registered only as a singleton in that module, with no context property. Now `typeof MusicLibraryManager` evaluates to `"undefined"`, `library` is null, and every user sees "Music library unavailable" (`MainPage.qml:127, 130`). The unit tests stub the library, so they miss it. Verify on QEMU.
- **Fix:** Pick one:
  - Restore the import.
  - Have the runner also call `setContextProperty("MusicLibraryManager", …)` when storage is granted.

  Add a runner-level smoke test that checks `library !== null`.
- **Effort:** S

**A3-24 · P0 (verify) · Resumption / Jakob** · `apps/music/MusicApp.qml`, `apps/music/Player.qml`, `shell/src/services/backgroundtaskobserver.h:12-19`
- **Problem:** Music never claims background audio:
  - The shell grants `audio-playback` only through its MPRIS observer, but nothing in the repo publishes MPRIS for Music. The only MPRIS code is the shell's consumer, `mpris2controller.cpp`.
  - Music never calls `Lifecycle.beginBackgroundTask("audio-playback")`, although the manifest declares it.

  With the cgroup freezer, leaving Music should freeze playback. There are also no lock-screen or status-area media controls, which Jolla Media provides through MPRIS.
- **Fix:**
  - Hold a background task while `player.playing`, copying `ClockApp.qml:25-32`.
  - Publish MPRIS2 with a small adaptor (play/pause/next/metadata) so shell controls work.
- **Effort:** M

**A3-25 · P1 · Ovsiankina (resumption)** · `apps/music/Player.qml:11-14`
- **Problem:** The queue, index, position and shuffle/repeat settings are not persisted. Reopening Music starts empty, with no "continue" option.
- **Fix:** Save the queue paths, index, position and modes to `ConfigurationValue` on track change, pause and exit. Restore them paused, with the NowPlayingPanel shown.
- **Effort:** M

**A3-29 · P2 · Hidden mode** · `apps/music/pages/MainPage.qml:26-30`, `apps/music/pages/SongsPage.qml:34-38`
- **Problem:** "Shuffle all" sets `player.shuffle = true` and leaves it on. Tapping a song in an album later plays shuffled, and the only cue is on the Player page.
- **Fix:** Shuffle the queue order once, or turn shuffle off when the user taps a specific song.
- **Effort:** S

**A3-31 · P2 · Jakob** · `apps/music/Player.qml:41-43`
- **Problem:** Previous always jumps to the previous track. The platform convention is to restart the current track when the position is past 3 s. With shuffle on, Previous goes to index − 1 rather than the track that actually played before.
- **Fix:** Restart the track when past 3 s, and keep a play history for shuffle.
- **Effort:** S

**A3-32 · P2 · Failure state** · `apps/music/Player.qml:80-82`, `apps/music/MusicApp.qml:28-31`
- **Problem:** A failed track shows a notice and playback stops.
- **Fix:** Show the notice and then call `next()`.
- **Effort:** S

### pages/MainPage.qml (library)

**A3-26 · P1 · Doherty (>1 s and >10 s)** · `apps/music/MusicApp.qml:53-58`, `apps/music/pages/MainPage.qml:118-121`
- **Problem:** Tracks reload only on `scanComplete`, so a first scan of a large library is one long spinner with no progress. `MusicLibraryManager` already exposes `scanProgress` (`marathon-services/src/musiclibrarymanager.h:57`).
- **Fix:** Show "Looking for music… %1%" from `scanProgress`, and reload the track list in batches while the scan runs.
- **Effort:** S

**A3-27 · P1 · Doherty (launch)** · `marathon-services/src/musiclibrarymanager.cpp:109-110`, `apps/music/MusicApp.qml:49`, `apps/music/pages/MainPage.qml:56-57`
- **Problem:** Launch does all of this on the GUI thread before the first useful frame, which is a likely part of the PinePhone splash of more than 7 s:
  - The manager's constructor runs `initDatabase()` and `loadArtists()`.
  - `getAllTracks()` runs synchronously in `onCompleted`.
  - The category Repeater recomputes `Library.artists()` and `Library.albums()` over every track inside its model binding.
- **Fix:** Show the page first and fetch tracks asynchronously (QFuture, or after the first frame). Compute the counts once per reload in `MusicApp`. Measure gently, per the GPU-hang memory.
- **Effort:** M

**Good:**
- The empty state names the next action ("Copy audio files … into the Music folder").
- A missing-library state exists.
- Search is in the header, and categories are ListItems with counts.

### pages/PlayerPage.qml / NowPlayingPanel.qml

**A3-28 · P1 · User direction (no boxed generic icons or tinted fills)** · `apps/music/pages/PlayerPage.qml:30-43`
- **Problem:** The artwork is a rounded `Rectangle` filled with `rgba(highlightBackground, opacity)` and a generic `icon-l-music` glyph. That is exactly the boxed generic icon on a tinted fill that you rejected. The library extracts no artwork at all.
- **Fix:** Pull embedded or folder art through the thumbnailer into an `Image`. When there is no art, draw no box: let the large title and artist typography carry the page.
- **Effort:** M

**A3-30 · P2 · Colour-only signal** · `apps/music/pages/PlayerPage.qml:81, 115`, `apps/music/pages/SongItem.qml:55`
- **Problem:** The shuffle and repeat-all states, and which song is playing, are shown only by highlight colour. This is the Silica convention, but it fails the playbook's colour-only rule.
- **Fix:** Add a small playing glyph on the current SongItem. Show "Shuffle · Repeat all" as PageHeader `description` text.
- **Effort:** S

**A3-34 · P2 · Fitts** · `apps/music/pages/PlayerPage.qml:95-102`
- **Problem:** The play/pause IconButton keeps Keel's fixed `itemSizeSmall` (80) box, but holds an `icon-l` (96) glyph. The glyph is bigger than its hit area.
- **Fix:** Set `width` and `height` to `Theme.itemSizeLarge` on that button.
- **Effort:** S

**Good:**
- The DockedPanel mini-player has 80-unit previous, play/pause and next controls, an accessible name on every button, and a slider that seeks on release.
- The cover offers play/pause and next, with a progress bar that updates only while the cover is visible.

### Playlists

**A3-33 · P2 · Destructive without remorse** · `apps/music/pages/SongItem.qml:46-50`
- **Problem:** "Remove from playlist" happens immediately, while deleting a playlist goes through remorse (`PlaylistsPage.qml:44-47`).
- **Fix:** Use `remorseDelete` here too.
- **Effort:** S

**Good:**
- "Added to %1" confirms an add.
- Playlist empty states use "Pull down to create one", and a playlist's own empty state explains how to add songs.

---

## Gallery

### GalleryPage / PhotoGridPage

**A3-35 · P1 · Dead end** · `apps/gallery/GalleryApp.qml:22`, `apps/gallery/pages/GalleryPage.qml:30-31`, `apps/gallery/pages/PhotoGridPage.qml:19-21`
- **Problem:** Gallery fetches videos only to count them in memories ("1 video"). The grids and the viewer show photos only, so the MP4s Camera writes cannot be opened in any app.
- **Fix:**
  - Include videos in the Photos grid, with a duration badge.
  - Add a "Videos" collection row.
  - Open videos in a player page, as Jolla Gallery does.
- **Effort:** M–L

**A3-36 · P2 · Same function, same look / Doherty** · `apps/gallery/pages/GalleryPage.qml:103-109`
- **Problem:** Scanning is shown as a text-only ViewPlaceholder ("Looking for photos"), while Music uses a BusyLabel for the same job. A rescan while photos are already listed shows nothing.
- **Fix:** Use `BusyLabel { running: store.scanning && list.count === 0 }`, matching Music.
- **Effort:** S

**A3-37 · P2 · Jakob** · `apps/gallery/pages/GalleryPage.qml:51-101`
- **Problem:** The main page lists collections as rows with small thumbnails. Jolla Gallery shows large image tiles for Photos, Videos and albums.
- **Fix:** Use a two-column grid of cover tiles with the title and count overlaid.
- **Effort:** M

**A3-38 · P2 · Tinted fill / magic value** · `apps/gallery/pages/GalleryPage.qml:73-77`
- **Problem:** The thumbnail loading placeholder is `Theme.rgba(primary, 0.1)`.
- **Fix:** Drop the placeholder (the Image fades in), or use `Theme.opacityFaint`.
- **Effort:** S

### PhotoViewerPage / PhotoDetailsPage / cover

**Good:**
- Delete goes through RemorsePopup and is the top pulley item, furthest from the finger, as in Jolla.
- Share appears only when the share service is available.
- The overlay shows "N of M" and toggles on tap.
- Left/Right/Escape keys work, and the page navigates horizontally so the pulley does not conflict.
- The details page uses DetailItems.
- An album page pops when its last photo is deleted.
- The empty state names the next action ("Take photos with Camera…").

---

## Calculator

### pages/CalculatorPage.qml / Calculator.qml

**A3-39 · P1 · Feedback / visibility of state** · `apps/calculator/pages/CalculatorPage.qml:155-172`, `apps/calculator/cover/CalculatorCover.qml:21-23`
- **Problem:** After you press +, the page shows only the first operand and the previous calculation. The pending `currentOperator` appears only on the cover, so you cannot see whether the operator registered.
- **Fix:** While an operator is pending, bind the expression label to `fmt(currentValue) + " " + currentOperator`, the same binding the cover uses. Also draw the active operator key highlighted.
- **Effort:** S

**A3-40 · P1 · Postel** · `apps/calculator/pages/CalculatorPage.qml:173-187`
- **Problem:** You cannot copy a result or paste a number.
- **Fix:** Long-press the display to open a ContextMenu with Copy and Paste, using `Clipboard.text`. Normalise pasted text: trim it, strip spaces and thousands separators, and accept either `,` or `.` as the decimal mark.
- **Effort:** S

**A3-41 · P2 · Output correctness and locale** · `apps/calculator/Calculator.qml:27-33`
- **Problem:** `fmt()` hard-codes `,` for grouping and `.` for decimals. `toFixed(8)` turns 1e-9 into "0" and shows 1e21 as "1e+21".
- **Fix:** Format with locale-aware output (`Number.toLocaleString(Qt.locale(), …)`), with about 12 significant digits and an exponent for extreme values.
- **Effort:** S

**A3-42 · P2 · Jakob** · `apps/calculator/Calculator.qml:235`
- **Problem:** `%` always divides by 100, so `50 + 10 % =` gives 50.1. iOS, Android and Jolla give 55.
- **Fix:** When an operator is pending, compute % as `currentValue × x / 100`.
- **Effort:** S

**A3-43 · P2 · Resumption** · `apps/calculator/pages/CalculatorPage.qml:13`, `apps/calculator/Calculator.qml:13`
- **Problem:** The basic/scientific mode resets to scientific on every launch, and the history is lost when the app closes.
- **Fix:** Persist both with `ConfigurationValue`.
- **Effort:** S

**A3-44 · P2 · Pragnanz (grid alignment)** · `apps/calculator/pages/CalculatorPage.qml:202-205`
- **Problem:** Eleven function keys in a six-column grid leave a ragged last row.
- **Fix:** Use 12 keys (add `1/x` or `xʸ`), or use 4 columns × 3 rows.
- **Effort:** S

**A3-45 · P2 · User direction (no tinted fills)** · `apps/calculator/pages/CalcKey.qml:38-44`
- **Problem:** The `=` key draws a tinted rounded fill. Its highlight-coloured text already gives the emphasis.
- **Fix:** Remove the fill and rely on highlight colour plus `font.bold`.
- **Effort:** S

**Good:**
- Digit keys are 110 units tall by about 129 wide, and function keys are 80 tall. All keys meet the size target.
- Pressing a key plays a haptic and highlights the key immediately.
- The keyboard is fully mapped, including comma for the decimal mark and Escape to clear.
- Every symbol key has an accessible name.
- Undo is in the pulley, and divide-by-zero shows "Can't divide by 0".
- The history pane has an empty state.

---

## Test Suite (apps/test)

**A3-46 · P1 · Should not be on the home grid** · `apps/CMakeLists.txt:233`, `shell/qml/models/FilteredAppModel.qml:55-70`
- **Problem:** The test app is built into every image, and the home grid appends every app that is not pinned, so users see it. From there, one tap can:
  - add "John Doe" to the user's real address book, again on every tap (`pages/TelephonyTestsPage.qml:46-50`)
  - inject fake SMS
  - toggle airplane mode
  - blank the screen, which leaves the in-app "Wake" button unreachable (`pages/SystemTestsPage.qml:152-158`)
- **Fix:** Build it only in developer images (a CMake option), or hide it unless developer mode is on (for example, a default `hiddenApps` entry or a manifest flag).
- **Effort:** S

**A3-47 · P1 · Fake signal** · `apps/test/TestApp.qml:27-41`
- **Problem:** `run()` counts anything that is not `false` as a pass. A void call passes whether or not anything happened (for example `haptic()`, `Location.stop()`, `scheduleWake`), so "N passed" in the header proves nothing.
- **Fix:** Have checks return an explicit boolean from something verifiable. Count calls that only trigger an effect separately, as "triggered".
- **Effort:** S

**A3-48 · P2 · Feedback** · `apps/test/components/TestItem.qml`
- **Problem:** Tapping a row gives no result on the row itself. Only the header counter changes.
- **Fix:** Show the last outcome as secondary text on the row, as words ("Passed" or "Failed"), not colour alone.
- **Effort:** S

**A3-49 · P2 · Naming / manifest** · `apps/test/manifest.json:2, 9`, `apps/test/pages/MainPage.qml:17`
- **Problem:** The app is called "Test Suite" in the manifest and "Service tests" in its page header. The manifest also uses a non-standard `category` field.
- **Fix:** Use one name, and the standard `categories` array.
- **Effort:** S

Not deleted, noted only: `apps/test/TestCounters.qml` is unused, and `components/Actions.qml` is an empty Column wrapper.

---

## Template (apps/template)

Patterns in the template spread to every new app, so P1 here means "fix before it is copied again".

**A3-50 · P1 · Propagating bug** · `apps/template/pages/MainPage.qml:47`, `apps/template/TemplateApp.qml:29-31`
- **Problem:** The remorse delete captures the item's index and removes by that index when the remorse window ends. If the list changes during the window (a cover "add", or a second pending delete), the wrong item is removed.
- **Fix:** Store items as `{id, text}` and delete by id.
- **Effort:** S

**A3-51 · P2 · Fake affordance** · `apps/template/pages/MainPage.qml:36-59`
- **Problem:** The ListItem has no `onClicked`. Rows highlight when pressed but do nothing, which teaches new apps to ship dead rows.
- **Fix:** Push a minimal detail or edit page, or show only the menu on press-and-hold.
- **Effort:** S

**A3-52 · P2 · Manifest schema drift** · `apps/template/manifest.json:8`
- **Problem:** The template uses `"category": "utilities"`. The shipped apps use `"categories": [...]`, `searchKeywords`, `protected` and `minShellVersion`. The test app copied the same drift.
- **Fix:** Use the schema from `apps/camera/manifest.json`.
- **Effort:** S

**A3-53 · P2 · Missing playbook states** · `apps/template/*`
- **Problem:** The template does not demonstrate a loading state (BusyLabel past 1 s), an error Notice, or a Dialog with a success notice. New apps start without these.
- **Fix:** Add one minimal example of each, a few lines apiece.
- **Effort:** S

**Good:**
- Theme-only sizes.
- A pull-down primary action.
- A ViewPlaceholder with a next action.
- A ContextMenu with `remorseDelete`.
- Persisted state through `Nemo.Configuration`.
- A cover action and a test suite.

---

## Cross-app notes

- **Reduced motion:** none of these apps reads `Settings.reduceMotion` (see A3-09). Camera is the only one with significant motion.
- **Same function, same look:** busy states differ (Music uses BusyLabel, Gallery uses placeholder text; A3-36). Remorse is used consistently except for "Remove from playlist" (A3-33).
- **Resumption:** this is the systemic gap. Stopwatch, timer, music queue and calculator all lose their state when the app closes (A3-13, A3-25, A3-43).
- **Launch performance:** Camera (A3-01) and Music (A3-27) both do synchronous work on the GUI thread before the first frame. The other likely factor is the known QML recompile on every launch. Measure gently.
