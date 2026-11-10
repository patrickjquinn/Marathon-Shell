<!--
SPDX-FileCopyrightText: 2026 Patrick Quinn
SPDX-License-Identifier: MIT
-->

# keel-shell ↔ Keel app contract (protocol version 1)

This is the contract between `keel-shell` (system Qt 5.6, one process per app)
and the Qt6 app it runs. The Keel Silica module (`keel/silica`) implements the
client side. Nothing here needs a custom Wayland protocol: the app uses
ordinary Qt6 windows plus one peer-to-peer D-Bus connection.

## 1. Detecting keel-shell

keel-shell sets these in the app's environment:

| Variable | Value | Notes |
| --- | --- | --- |
| `KEEL_SHELL` | `1` | Running under keel-shell. |
| `KEEL_SHELL_PROTOCOL` | `1` | This document's version. |
| `QML_IMPORT_PATH` | `<libdir>/keel/qt5compat[:<inherited>]` | Puts Keel's Qt 5 QML API shims (keel/qt5compat) first, ahead of any inherited path. `<libdir>` is fixed when keel-shell is built and matches `%{_libdir}`: `/usr/lib64` on aarch64, `/usr/lib` on 32-bit targets. |
| `KEEL_SHELL_DBUS` | D-Bus address | Peer-to-peer server, see section 4. Treat it as opaque and pass it to `connectToPeer` unchanged. By default it is `unix:path=$XDG_RUNTIME_DIR/keel-shell-XXXXXX/bus,guid=…`. |
| `KEEL_SHELL_COVER_TITLE` | `keel:cover` (default) | Title marker for the cover window, see section 3. Read it; do not hard-code it. |
| `KEEL_SHELL_COVER_ENABLED` | `1` or `0` | `0` when started with `--no-cover`: covers are shown as ordinary windows, so do not create one. |
| `KEEL_SHELL_DPI` | integer | Same value as `QT_WAYLAND_FORCE_DPI`. |
| `KEEL_AMBIENCE_*`, `KEEL_SILICA_*` | strings | Ambience snapshot at launch, see section 5. |
| `KEEL_AMBIENCE_KEYS` | `:`-separated dconf keys | Which dconf keys the `KEEL_*` variables came from. |
| `WAYLAND_DISPLAY` | private socket | Never Lipstick's socket. |
| `QT_QPA_PLATFORM` | `wayland` | |
| `QT_WAYLAND_SHELL_INTEGRATION` | `wl-shell` | Default: the 5.6 compositor on Sailfish only has `wl_shell`. `--client-shell` overrides it. |
| `QT_WAYLAND_FORCE_DPI` | physical DPI | As qt-runner does. |
| `QT_ENABLE_HIGHDPI_SCALING` | `0` | Unless it is already set or keel-shell was started with `--qt-scaling`. Qt6 would otherwise turn the forced DPI into a devicePixelRatio of dpi/96, about 4.8 on a phone. Silica QML uses device pixels times `Theme.pixelRatio`, so Keel runs unscaled. |
| `QT_WAYLAND_DISABLE_WINDOWDECORATION` | `1` | Unless it is already set. |
| `FLATPAK_MALIIT_CONTAINER_DBUS` | same as `KEEL_SHELL_DBUS` | For the Qt6 Maliit input context plugin (qt-runner compatibility), see section 6. |

keel-shell removes `QMLSCENE_DEVICE=customcontext` and
`QT_WAYLAND_RESIZE_AFTER_SWAP` from the environment, as qt-runner does.

## 2. Main window

The first top-level window the app shows that is not a cover becomes the
Lipstick app window. keel-shell shows that Lipstick window full screen as soon
as it starts, so the app appears in Lipstick immediately. The nested surface
is resized (`wl_shell_surface.configure`, or `xdg_toplevel` maximized) to the
Lipstick window's size, which is the full screen.

- Draw with a transparent background where the ambience should show through.
  The Lipstick window is translucent (alpha format, transparent clear colour).
  **[VERIFY]** on device.
- Keep the window in the device's native (portrait) geometry and rotate the
  content yourself, as Silica does (section 4.2).

Each further top-level window gets its own Lipstick window, as newcompositor
does. Transient windows and popups are drawn inside their parent's Lipstick
window at the offset the client requests.

## 3. Cover window

**Contract:** the cover is a separate top-level `QWindow` (Keel's `CoverWindow`)
whose **title** is the marker, set **before** `show()`:

```cpp
// Keel Silica, when ApplicationWindow creates its cover:
const QByteArray marker = qgetenv("KEEL_SHELL_COVER_TITLE");   // "keel:cover"
if (qgetenv("KEEL_SHELL") == "1" && qgetenv("KEEL_SHELL_COVER_ENABLED") != "0") {
    coverWindow->setTitle(QString::fromUtf8(marker));          // or marker + ":" + app name
    coverWindow->resize(coverSize);                            // Theme.coverSizeLarge
    coverWindow->show();
}
```

keel-shell treats a nested top-level as the cover if either of these is true:

1. Its title equals the marker, or starts with the marker followed by `:`.
   So `keel:cover` and `keel:cover:Weather` match; `keel:covered` does not.
   Matching is case-sensitive.
2. Its app_id or wl_shell class ends with `.keel-cover`, for example
   `org.example.weather.keel-cover`. This is a fallback for clients that can
   set a per-window app_id. Qt6 sets the same app_id on every window, from
   `QGuiApplication::desktopFileName()`, so Keel uses the title.

Why the title: Qt6 sends it through both `wl_shell_surface.set_title` and
`xdg_toplevel.set_title`, before the first buffer is committed. It needs no
private Qt API and no new Wayland protocol, and Lipstick never sees it: the
Lipstick-facing windows belong to keel-shell, which gives them its own titles.

What keel-shell does with the cover:

- It creates a second Lipstick window, tags it `CATEGORY=cover`, and maps the
  cover surface into it. The tag is sent as a `qt_extended_surface` generic
  property before the window's first buffer, because Lipstick reads the
  category only when the surface is first mapped.
- The Lipstick cover window takes the cover surface's size. The app chooses
  the cover size; keel-shell never configures (resizes) a cover.
- Touches on the cover in the Lipstick window are forwarded to the cover
  surface as ordinary Wayland touch or pointer events, so cover actions that
  are part of the cover's QML get them. **[VERIFY]** that Lipstick delivers
  cover-action taps to a cover window this way.
- `CoverStatus` (section 4) is 1 while the Lipstick cover window is exposed
  and 0 otherwise. **[VERIFY]** that exposure tracks what the user sees in
  the app grid.
- If a newer cover surface appears, it replaces the older one. The older one
  is parked (not shown) and comes back if the newer one goes away.
- If the title becomes the marker after the window is mapped, the surface is
  moved from its secondary window into the cover window. This works but
  costs a Lipstick window create and destroy, and the surface keeps the size
  it was configured to as a secondary window. Set the title before `show()`.

Do not give the cover window a transient parent; transients never count as
covers.

## 4. Peer D-Bus: `org.shipwright.keel.Shell1`

Connect with
`QDBusConnection::connectToPeer(qgetenv("KEEL_SHELL_DBUS"), "keel-shell")`.
It is a private peer-to-peer connection, not the session bus, so there is
no service name; use an empty service in calls.

Access control. Every keel-shell listens on its own filesystem socket,
`bus` in a new directory `keel-shell-XXXXXX` (mode 0700, created with
`mkdtemp`) under `$XDG_RUNTIME_DIR`, or under the system temp directory when
`XDG_RUNTIME_DIR` is unset. It never uses an abstract socket, which any
process in the same network namespace could reach. Only processes of the
same uid (and root) can open the socket. Anonymous authentication is
refused, so libdbus authenticates each peer by its kernel credentials
(`EXTERNAL`) and admits only keel-shell's own uid. The app inherits the
directory from keel-shell, so a sandbox that keel-shell runs in covers the
app as well. `--bus-address` overrides the address; anonymous
authentication stays off. The directory is removed when keel-shell exits.
Clients need no change: the address comes from the environment as before.

Object path `/org/shipwright/keel/Shell`, interface
`org.shipwright.keel.Shell1`:

| Member | Type | Meaning |
| --- | --- | --- |
| property `ProtocolVersion` | `i` | `1` |
| property `Orientation` | `i` | Device orientation in degrees (0, 90, 180, 270), equal to `QScreen::angleBetween(primaryOrientation, orientation)` in keel-shell. |
| property `ContentOrientation` | `i` | The last value the app set, same convention. |
| property `Active` | `b` | A non-cover keel-shell window is the active Lipstick window. |
| property `CoverStatus` | `i` | 0 inactive, 1 active (cover window exposed). |
| property `Ambience` | `a{sv}` | Full dconf key → value map, see section 5. |
| property `Dpi` | `i` | DPI forwarded to Qt. |
| method `Ping()` → `s` | | Returns `"keel-shell"`. |
| method `GetAmbience()` → `a{sv}` | | Same as the property; convenient from QML/JS bindings. |
| method `Activate()` | | Raise and activate the main Lipstick window (e.g. from a notification action). |
| method `SetContentOrientation(i degrees)` | | The app has rotated its content. keel-shell reports this to Lipstick (`QWindow::reportContentOrientationChange` on its non-cover windows) and to the keyboard. |
| signal `OrientationChanged(i)` | | |
| signal `ContentOrientationChanged(i)` | | |
| signal `ActiveChanged(b)` | | |
| signal `CoverStatusChanged(i)` | | |
| signal `AmbienceChanged(a{sv})` | | Whole new map, debounced (250 ms). |
| signal `DpiChanged(i)` | | |
| signal `CloseRequested()` | | Lipstick closed the app (window close or SIGTERM to keel-shell). Save state and quit. keel-shell sends SIGTERM to the app after the grace period (`--close-grace`, default 3000 ms; 1000 ms when the close came as SIGTERM), then SIGKILL 5 s later. |

### 4.1 Activation

`Active` becomes true when Lipstick activates the main (or a secondary)
keel-shell window. keel-shell also gives the matching nested surface Wayland
keyboard focus, so Qt6's own `QWindow::isActive()` and
`QGuiApplication::applicationState()` follow. Use `Active` for Silica's
`Qt.application.state` semantics. The cover window never counts as active.

### 4.2 Orientation

Silica rotates content inside a portrait window, and Keel does the same:

1. Listen to `OrientationChanged(angle)`.
2. If the page allows that orientation, rotate the QML content to it.
3. Call `SetContentOrientation(angle)` when the rotation is done.

keel-shell never rotates or resizes the app's surface for orientation.

## 5. Ambience

At launch, keel-shell runs `dconf dump` on:

| dconf directory | Environment prefix |
| --- | --- |
| `/desktop/jolla/theme/` | `KEEL_AMBIENCE_` |
| `/desktop/sailfish/silica/` | `KEEL_SILICA_` |

Each key becomes `<prefix><RELATIVE_KEY_UPPERCASED>`; characters other than
A–Z and 0–9 become `_`. For example `/desktop/jolla/theme/color/highlight`
becomes `KEEL_AMBIENCE_COLOR_HIGHLIGHT`. Values are decoded from GVariant text:
strings without quotes, booleans as `true`/`false`, numbers in decimal.
Arrays and dictionaries are passed through as GVariant text.

The Sailfish OS documentation says the active ambience lives under
`/desktop/jolla/theme` (Develop > Ambience > Storage of Settings). It does not
document the individual key names, so keel-shell forwards every key it finds
instead of choosing some. Keel's `Theme` should map the ones it needs, such
as `color/highlight`, `color/primary`, `color/secondary`,
`color/highlightBackground`, `color_scheme` and the wallpaper path, and fall
back to defaults for anything missing. **[VERIFY]** the key names with
`dconf dump /desktop/jolla/theme/` on the Jolla Phone and record them in
Keel.

For live changes, keel-shell runs `dconf watch` on the same directories. When
anything changes it dumps them again and, if the result differs, emits
`AmbienceChanged` with the whole map (keys are full dconf paths). An
ambience switch rewrites many keys at once; these are collapsed into one
signal.

## 6. Virtual keyboard (Maliit)

keel-shell handles the keyboard the same way qt-runner does: it does not
bridge Wayland text-input. The Qt6 app loads the Sailfish Maliit input
context plugin (`qt6-sfos-maliit-platforminputcontext`, the plugin qt-runner-qt6
depends on). That plugin talks to the Maliit server on the session bus
itself and uses `FLATPAK_MALIIT_CONTAINER_DBUS` for the container state.
keel-shell serves that interface unchanged:

- object `/`, interface `org.container` (the plugin addresses it as
  `org.flatpak.sailfish.container`; on a peer-to-peer connection the service
  name is ignored)
- properties `activeState` (int) and `orientation` (int; Maliit's angle for the
  current **content** orientation, qt-runner's table)
- signals `activeStateChanged(bool)` and `orientationChanged(int)`
- method `keyboardRect(bool active, int x, int y, int w, int h)`, which the
  plugin calls to report the keyboard area, in the screen's native
  (portrait) coordinates. It is the only callable method on `/`. A
  rectangle with a negative width or height is ignored.

With `--follow-keyboard`, keel-shell shrinks the main surface by the
keyboard height (qt-runner's "follow keyboard" mode): the rectangle's height
while the content is portrait, its width while the content is landscape
(both backends use `ShellState::keyboardHeight`). The surface keeps at least
1 px. Keel apps normally
leave this off and lay out around `Qt.inputMethod.keyboardRectangle`, as
Silica does.

Gap for Phase 0: whether the Qt6 Maliit plugin is available for Sailfish 5.2
(Chum `chum:testing` has Qt6 6.8.4; the plugin package was not checked), and
whether it works with keel-shell as it does with qt-runner-qt6.
**[VERIFY]**
