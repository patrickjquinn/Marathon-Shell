# Silica apps on Marathon — pilot

2026-10-11 · status: approved (source: shipwright-open, pinned)

## Goal

Marathon apps can be written with Sailfish Silica (via Keel) and look and feel
like Sailfish apps, while Marathon keeps its own system UX (gestures, Hub, task
switcher, lock screen, quick settings). The pilot proves this with one real app
on the PinePhone.

Success means all of these hold on the PinePhone:

1. A Silica Notes app launches from the Marathon launcher and draws its first
   frame no slower than the MarathonUI Notes (measured with
   `MARATHON_STARTUP_LOG`).
2. Pulley menu, context menu with remorse delete, page push/pop, TextField with
   the Marathon keyboard, Switch and Slider all work by touch.
3. Marathon's back gesture pops the Silica page stack, and on the first page
   minimises the app.
4. Highlight colour follows Marathon's accent; the background follows the
   Marathon wallpaper.
5. Freeze/thaw (cgroup freezer) and relaunch work as for any Marathon app.
6. Notes persist across relaunch through Marathon's per-app storage
   (`SettingsManagerCpp`), like the MarathonUI Notes.

Out of scope for the pilot: covers, orientation, Silica WebView/Pickers/Share/
Accounts, porting other apps, changing the shell's own look.

## Spike evidence (host, Qt 6.11.2)

A throwaway Silica app ran unmodified in `marathon-app-runner`: Silica's
`ApplicationWindow` is an `Item`, so the runner's `QQuickView` loads it. Silica
rendering (ambience, glass, typography, page stack, pulley indicator) was
correct, and `KEEL_THEME_HIGHLIGHT_COLOR` recoloured it to Marathon teal. An SVG
wallpaper did not show as the background. Touch was not tested.

## Design

### 1. `keel-silica` package (Alpine aarch64)

New `packaging/packages/keel-silica/APKBUILD`, modelled on
`marathon-mail-oauth` (cargo in abuild, `options="net"` for `cargo fetch`).

- Builds Keel's `silica/` subtree: `Sailfish.Silica 1.0` and the `Keel 1.0`
  modules it imports (`Keel.SilicaCore`, `Keel.SilicaScreen`), nothing else.
  No nemo-compat, sailfishapp, platform or actions.
- Installs under `/usr/lib/qt6/qml/`.
- `depends` pins `qt6-qtdeclarative` to the exact version built against
  (Keel links `QtQuickPrivate`/`QtGuiPrivate`).
- Source: the public `github.com/patrickjquinn/shipwright-open` archive at a
  pinned commit (`_commit` in the APKBUILD, checksummed). Keel is developed
  in Shipwright and exported there; bumping Keel is a `_commit` change.
- Licensing: Silica QML is BSD-3-Clause, Keel is MIT; both are compatible with
  Marathon's Apache-2.0. The package carries both licence texts.

### 2. Runner support

None needed. The runner already loads a plain QML entry file and already calls
the root's `handleBack()`. Keel's ambience is set at runtime from QML
(`Keel.Ambience.applyForwarded`), and Silica blurs and dims the wallpaper
itself (raster or SVG).

### 3. `SilicaApp.qml` (in the pilot app)

Silica `ApplicationWindow` plus the contract the runner expects:

- `function handleBack()`: pops the page stack when `depth > 1`, else emits
  `minimizeRequested()`; returns true.
- `signal minimizeRequested()` (the runner's lifecycle object connects to it).
- Ambience: highlight from `MColors.accentBright`, background from
  `SettingsManagerCpp.wallpaperPath` (`qrc:/wallpapers/X` mapped to
  `/usr/share/marathon-shell/wallpapers/X`), reapplied when the wallpaper
  changes.

It lives in `apps/notes-silica/` for the pilot so MarathonUI keeps building
without Keel; it moves to a MarathonUI module if more Silica apps follow.

### 4. Pilot app: `apps/notes-silica`

A separate app (`id: notes-silica`) so both Notes can be compared side by
side. Same data format as `apps/notes` (JSON array in `SettingsManagerCpp`),
stored under its own key `notes-silica/data`, because settings keys are
scoped to the caller's app id. Pages: list (pulley: New note; context menu:
Delete with remorse; search), editor (TextArea, title field), and nothing
else.

`notes-silica` is not added to the pinned home grid; it is reached from the
app drawer.

### 5. Testing

- Host: `marathon-app-runner --app-id notes-silica` offscreen with
  screenshots, as in the spike, in CI-free manual runs.
- Device: deploy `keel-silica` and the app, drive with `marathon-touchctl`,
  capture with `snap`, and compare launch timing against `notes`.

## Risks

- **Rust/CXX-Qt on musl.** Not yet built for Alpine. Mitigation: build it
  first, before any other pilot work; stop if it fails in ways that need Keel
  changes.
- **Silica uses Sailfish's units.** Theme sizes assume Sailfish's pixel ratio;
  PinePhone at 720x1440 may need `KEEL_THEME_PIXEL_RATIO`. Checked on device.
- **Keel's Qt private API use.** Pinned exactly; every Qt bump rebuilds
  `keel-silica`.
- **Phone stability.** The PinePhone has been dropping off USB under heavy
  writes; deploys go in small chunks.
