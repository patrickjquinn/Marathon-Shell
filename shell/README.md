# keel-shell

**keel-shell is now the opt-in fallback, not the default (ADR-0016).** Keel
apps render straight into Lipstick in *direct mode*: Qt 6's wl-shell
integration with the Qt surface extension, the protocol path of native Qt 5
apps, with Keel tagging the cover window `CATEGORY=cover` itself
(`keel/README.md`, "Runtime on the phone"). keel-shell stays built, tested
and packaged for a Lipstick where direct mode turns out not to work. An app
uses it when it is started as `keel-shell -- <app>` (keel-shell sets
`KEEL_SHELL=1`, which Keel obeys before anything else); in a desktop file:
`Exec=/usr/bin/keel-shell -- /usr/bin/<app>` with
`X-Nemo-Application-Type=no-invoker`.

keel-shell makes a Qt6 (Keel) app a first-class Lipstick citizen on Sailfish
OS. It is a nested Wayland compositor built against the **system Qt 5.6.3**
and runs as one process per app:

```
Lipstick (system Qt 5.6)
 ├─ app window                  ◄── keel-shell window #1 ◄── Qt6 main surface
 └─ cover window, CATEGORY=cover ◄── keel-shell window #2 ◄── Qt6 cover surface
                                      keel-shell (system Qt 5.6, QtCompositor)
                                      │ private Wayland socket (wl_shell)
                                      │ peer D-Bus (org.shipwright.keel.Shell1, org.container)
                                      ▼
                                    Qt6 app (Keel)
```

It is a fork of [qt-runner](https://github.com/rinigus/qt-runner): same
compositor API, launcher behaviour and Maliit keyboard interface. It adds
[newcompositor](https://github.com/ArturGaspar/newcompositor)'s
one-Lipstick-window-per-toplevel model and a designated cover window. See
PROVENANCE.md for the exact commits and which files derive from which.

- **PROTOCOL.md** is the contract with Keel apps (environment, cover marker,
  D-Bus interface, ambience, keyboard). The Keel Silica engineer implements
  the client side from it.

## Status

| What | Status |
| --- | --- |
| Sailfish build (Qt 5.6.3, `SailfishOS-5.2.0.15-aarch64`) | Compiles and links for aarch64 with no warnings; RPM builds with `mb2`. Runs under qemu with Mesa llvmpipe: main and cover windows render, and the cover arrives with `CATEGORY=cover` (see "Running under qemu"). The earlier qemu abort was the missing OpenGL of `QT_QPA_PLATFORM=minimal`, not a keel-shell bug; keel-shell now exits with a clear error there. Not run on a device. |
| RPM | `mb2 build` gives `shipwright-keel-shell-0.1.0-1.aarch64.rpm`; rpmlint reports 0 errors and 3 warnings (unstripped binary, PIE suggested, licence tag not in rpmlint's list). The binary uses private QtCompositor API (RPM auto-requires `libQt5Compositor.so.5(Qt_5_PRIVATE_API)`), so rebuild it whenever `qt5-qtwayland-wayland_egl` changes. |
| Host build (Qt 5.15 backend) | Builds; 8 unit-test suites and the headless end-to-end test pass. |
| Behaviour on Lipstick | **Not verified.** See "Needs device verification". |

## Architecture

```
src/main.cpp                   CLI, wiring, SIGTERM handling
src/core/                      compositor-API-neutral, built for both backends
  windowmapper.*               surface → Lipstick window mapping (pure logic, unit-tested)
  coverpolicy.*                cover detection rule (unit-tested)
  lipstickwindow.*             CATEGORY property via QPlatformNativeInterface, alpha format
  graphics.*                   OpenGL check before showing windows; scene-graph error text
  backend.*                    shared outer-window behaviour: activation, orientation,
                               cover status, close handling
  shellstate.* shellservice.*  state forwarded to the app; peer D-Bus server
                               (private 0700 socket directory, no anonymous auth)
  containerstate.*             qt-runner's org.container interface (Maliit)
  ambience.*                   dconf dump/watch → env vars and AmbienceChanged
  launchconfig.* runner.*      argument parsing, app environment, child process
  logging.*                    logging category shipwright.keel.shell
src/backend/qt56/              Sailfish backend: Qt 5.6 QtCompositor (as qt-runner)
src/backend/qt515/             host backend: Qt 5.15 QtWaylandCompositor (as newcompositor)
```

**Compositor-API adapter.** Qt 5.6's QtCompositor (the pre-1.0 API:
`QWaylandQuickCompositor`, `QWaylandSurfaceItem`,
`createOutput(QWindow*, …)`) cannot be built on a stock distribution, and
Qt 5.15's QtWaylandCompositor does not exist on Sailfish. All placement
logic therefore lives in `core/`, behind a small `keel::Backend` class.
Each backend only turns its compositor's surfaces into
`keel::SurfaceInfo`, and turns the mapper's decisions back into windows and
views:

- `qt56` (device): one `QQuickWindow` plus one `QWaylandQuickOutput` for
  each Lipstick window. Each surface's `QWaylandSurfaceItem` is reparented
  into its window's content item, as qt-runner does. The surface is moved to
  that window's output with the private
  `QtWayland::Surface::addToOutput/removeFromOutput` calls, so its texture is
  updated in that window's scene graph. Frame callbacks are sent per window
  after rendering. This path handles EGL client buffers, like qt-runner.
- `qt515` (host): newcompositor's structure with a raster renderer, which
  handles `wl_shm` buffers only. That is enough for headless CI and for
  exercising the shared logic. It is not meant for the device.

**Window mapping** (`core/windowmapper.h`):

- The main Lipstick window exists from start-up, like qt-runner's, so the
  app appears in Lipstick at once. An output must exist before the first
  client surface, because the 5.6 compositor adds every surface to the
  primary output.
- The first non-cover toplevel is the main surface. Each further toplevel
  gets its own window, as in newcompositor.
- A toplevel matching the cover rule goes into a cover window, created when
  needed and tagged `CATEGORY=cover` before its first buffer.
- Transients, popups and subsurfaces go into their parent's window.
- A role change after mapping (a title that becomes the cover marker) moves
  the surface and its children to the right window.

**Lipstick category.** Lipstick reads `CATEGORY` from the
`qt_extended_surface` generic properties only when a surface is first mapped.
keel-shell therefore creates the platform window, calls
`QPlatformNativeInterface::setWindowProperty(handle, "CATEGORY", "cover")`
(Sailfish's client forwards this through
`QWaylandWindow::sendProperty` → wl_shell surface →
`QWaylandExtendedSurface::updateGenericProperty`), and only then shows the
window. The end-to-end test checks the Qt 5.15 client's version of this path
on the wire.

**Text input.** qt-runner does not forward the Sailfish keyboard through
Wayland. The app's Qt6 Maliit input context plugin talks to Maliit directly
and reads orientation and active state from qt-runner's peer bus (the
`org.container` interface in `FLATPAK_MALIIT_CONTAINER_DBUS`). keel-shell
serves the same interface, with orientation taken from the app's reported
content orientation, so the same plugin should work unchanged. It also
receives `keyboardRect` for `--follow-keyboard`. It does not bridge Wayland
text-input: the 5.6 compositor offers only the old `wl_text_input`, which
Qt6 does not speak. The Phase 0 gap is in PROTOCOL.md section 6.

**DPI.** Like qt-runner, keel-shell sets `QT_WAYLAND_FORCE_DPI` to the
primary screen's physical DPI (override with `--dpi`) and exposes it as
`Dpi`. Unlike qt-runner, it also sets `QT_ENABLE_HIGHDPI_SCALING=0` by
default: Qt6 would otherwise scale by dpi/96 (measured on the host: a
234 px cover came out 989 px wide at 401 dpi). Silica-style QML expects
device pixels times `Theme.pixelRatio`. Pass `--qt-scaling` to get Qt6's
scaling instead.

## Running an app

```
keel-shell [options] -- /usr/bin/myapp [app args…]
keel-shell --help
```

Without a program, keel-shell only serves its socket and prints the name,
as qt-runner does with no arguments.

To use keel-shell instead of direct mode, the desktop file pattern
(`packaging/keel-app.desktop.example`) is:

```
Exec=/usr/bin/keel-shell -- /usr/bin/org.example.weather
X-Nemo-Application-Type=no-invoker
```

Lipstick starts keel-shell, and keel-shell owns both Lipstick windows, so
the app window and the cover share one pid. SIGTERM (what Lipstick sends on
close) and the Lipstick window close request both reach the app as
`CloseRequested`, then as SIGTERM after a grace period. keel-shell exits with
the app's exit code.

Useful options: `--verbose` logs every mapping decision (it enables the
debug level of the `shipwright.keel.shell` logging category, as
`QT_LOGGING_RULES=shipwright.keel.shell.debug=true` also does); `--no-cover`
treats covers as ordinary windows; `--client-shell xdg-shell` is for host
testing; `--follow-keyboard`; `--env NAME=VALUE`. Setting
`KEEL_SHELL_REPORT=file.json` makes keel-shell write its window list
(role, CATEGORY, title) to that file whenever a window is shown or hidden.

## Building

**Sailfish (device):**

```
# In the Sailfish SDK container (target SailfishOS-5.2.0.15-aarch64). sb2 does
# not see /work, so build from a copy under the container home:
cp -r /work/keel/shell ~/keel-shell-src && mkdir ~/keel-shell-build && cd ~/keel-shell-build
sb2 -t SailfishOS-5.2.0.15-aarch64 -m sdk-install -R zypper --non-interactive in wayland-devel
mb2 -t SailfishOS-5.2.0.15-aarch64 build ~/keel-shell-src     # RPMS/shipwright-keel-shell-*.rpm
```

`rpm/shipwright-keel-shell.spec` has the same BuildRequires as qt-runner's
spec (`pkgconfig(Qt5Compositor) >= 5.6.0` and so on). It drops
sailfishapp, Silica and svg, which keel-shell does not use, and adds
`pkgconfig(wayland-server)`, which the private QtCompositor headers need.
`wayland-devel` is not preinstalled in the SDK target.

**Host (tests):**

```
cmake -S keel/shell -B target/keel-shell-host && cmake --build target/keel-shell-host -j
cd target/keel-shell-host && QT_QPA_PLATFORM=offscreen ctest --output-on-failure
```

This needs Qt 5.15 with QtWaylandCompositor and the Qt5 private headers
(`libqt5waylandcompositor5-dev`, `qtbase5-private-dev`), Qt6 Gui and DBus,
`qt6-wayland` (for the test client) and `wayland-scanner`. It does not need
weston or a GPU. `XDG_RUNTIME_DIR` must be short: the e2e test creates its
own directory under the system temp dir, because Unix socket paths are
limited to 108 bytes.

## Tests

| Test | What it covers |
| --- | --- |
| `tst_windowmapper` | Main, cover, secondary and child placement; a cover before main; a newer cover parking an older one and un-parking it; a late cover title moving a surface and its children; a main surface that turns into a cover; children mapped before their parent; signal order (window created before the surface is assigned). |
| `tst_coverpolicy` | Title marker exact, labelled and near-miss matches; app_id suffix; children are never covers; custom marker. |
| `tst_ambience` | GVariant text decoding, dconf dump parsing, env names, live `dconf watch` through a fake `dconf` script, a slow `dconf dump` not blocking the event loop, and a failed dump keeping its directory's previous values. |
| `tst_launchconfig` | CLI parsing (`--` and qt-runner style), app environment (qt-runner rules and the Keel variables), the qt5compat directory following the build's library directory, socket naming including the `/run/display` layout. |
| `tst_graphics` | Regression test for the qemu abort, on the `minimal` platform it happened on: the OpenGL check reports the missing OpenGL with the plugin's name, `start()` fails with that error and shows no window, the first fatal error is kept, and the scene-graph error text names the window. |
| `tst_orientation` | Angle convention matches `QScreen::angleBetween`; Maliit's table. |
| `tst_shellservice` | A real peer-to-peer D-Bus connection: the Keel interface (properties, methods, signals) and qt-runner's `org.container` exactly as the Maliit plugin uses it (and nothing else on it callable). Access control: the socket is a path in a fresh 0700 directory under `XDG_RUNTIME_DIR`, removed afterwards; SASL `ANONYMOUS` is refused and its call never arrives. As root (skipped otherwise), uid 65534 can neither connect to the private socket nor, on a world-accessible `--bus-address`, authenticate. |
| `tst_shellstate` | Keyboard height for `--follow-keyboard` in all four content orientations; negative keyboard rectangles from the peer are ignored. |
| `tst_e2e` | `fake-lipstick` (a headless Qt 5.15 compositor implementing `qt_surface_extension`) ← keel-shell ← a Qt6 client with a main and a cover window, for wl-shell, xdg-shell and a late cover title. It checks that Lipstick-side there are exactly two surfaces with content, exactly one with `CATEGORY=cover` received over `qt_extended_surface`, and that the cover window has the cover's size. It also checks keel-shell's report, the app's environment and D-Bus round trip, and that SIGTERM shuts both down cleanly. |

## Frame-time cost

Every app frame is composited twice: the app renders into its buffer, then
keel-shell draws that buffer as a texture into its own Lipstick window,
which Lipstick composites. This adds one full-screen textured quad per frame
on the GPU, one extra process (roughly a QtQuick app's RAM), and up to one
frame of latency, because the app's frame callback fires after keel-shell's
frame. qt-runner has exactly the same structure, so Phase 0 probe 2
(qt-runner-qt6 frame times) is a good proxy, and keel-shell should be
measured against it. There is no zero-copy path: 5.6 QtCompositor cannot
forward a client buffer to Lipstick as a subsurface.

## Direct mode replaced this plan (ADR-0016)

The section below was the plan for avoiding the nested compositor. It turned
out that no plugin of our own is needed: Qt 6.8's stock `wl-shell`
integration already creates a `qt_extended_surface` for every window and
forwards window properties through it (`QWaylandWlShellSurface::sendProperty`),
and a `QVariant` holding a `QString` serialises identically under Qt 5.6 and
Qt 6 stream versions, which `keel/testcompositor` decodes the way Lipstick
does (ctest `keel_direct_mode`). Keel's direct mode uses it. Points 3 and 4
below (what Lipstick accepts from a Qt 6 client: protocol versions, EGL
buffers through libhybris; the keyboard) remain the device questions. A
custom shell integration (`QWaylandShellIntegrationTemplate`, Qt 6.3+, for
example an xdg_toplevel with a qt_extended_surface) is still the next step
if wl-shell proves insufficient.

The original plan, for reference: a **Qt6 QtWaylandClient shell
integration plugin** loaded by the app (`QT_WAYLAND_SHELL_INTEGRATION=keel-lipstick`)
that talks to Lipstick directly:

1. Build a `QWaylandShellIntegrationPlugin` (Qt6 private API,
   `QtWaylandClient/private/qwaylandshellintegration_p.h`) that binds
   `wl_shell` and `qt_surface_extension` from Lipstick's registry. Generate
   client code for `surface-extension.xml` (already in
   `tests/e2e/fake-lipstick/`) with Qt6's `qtwaylandscanner`.
2. Create a `QWaylandShellSurface` subclass per window: `wl_shell_surface`
   set_toplevel/title/class, plus a `qt_extended_surface` for window
   properties. Keel sets `CATEGORY=cover` on its cover window through the
   same `setWindowProperty` path, serialised the way the Qt5 client does
   (`QDataStream << QVariant` with a Qt5-compatible stream version). Keel
   gets `onscreen_visibility`, `close` and content orientation natively.
3. Deal with what Lipstick's 5.4-era QtWayland accepts from a Qt6 client:
   the wl_compositor, wl_seat and wl_output versions, `wl_drm` or
   Sailfish's EGL buffer integration for Qt6's `wayland-egl`, and the
   absence of xdg-shell. This is the risky part, and exactly what qt-runner
   exists to avoid. Phase 0 should try a plain Qt6 window against Lipstick
   directly before committing to it.
4. The keyboard stays the same (Maliit plugin), minus the `org.container`
   state, which the plugin would take from the window instead.

Sketch of effort: 1–2 weeks for a plugin that shows windows with the right
category; unknown for EGL buffer compatibility. That unknown is what the
Gate 0 decision is about.

## Running under qemu

**The earlier abort.** Under qemu with `QT_QPA_PLATFORM=minimal`, keel-shell
aborted when it showed its main window. A core dump from qemu, read with the
target's own gdb (`sb2 -t … gdb keel-shell qemu_keel-shell_*.core`), shows
the faulting frame:

```
#3  QMessageLogger::fatal(char const*, ...) const            libQt5Core.so.5
#4  QSGRenderLoop::handleContextCreationFailure(QQuickWindow*, bool)  libQt5Quick.so.5
…
#14 QPlatformWindow::setVisible(bool)                        libQt5Gui.so.5
#15 keel::Backend::showOuterWindow (windowId=1)              src/core/backend.cpp:116
#16 keel::Backend56::start                                   src/backend/qt56/backend56.cpp:168
```

The log before it reads `This plugin does not support
createPlatformOpenGLContext!` and `Failed to create OpenGL context for format
…`. The `minimal` plugin has no OpenGL, and Qt Quick 5.6 has only the OpenGL
scene graph (no software renderer). When nothing handles
`QQuickWindow::sceneGraphError`, Qt calls `qFatal()`. The cause was the test
set-up, not keel-shell's code or qemu itself. keel-shell now checks that the
platform plugin offers OpenGL before it creates any window, and exits with 1
and this message:

```
keel-shell: error: the Qt platform plugin "minimal" has no OpenGL support. keel-shell draws its Lipstick windows with Qt Quick, which needs OpenGL ES (EGL); run it under a Wayland compositor with QT_QPA_PLATFORM=wayland-egl, as Lipstick provides
```

Every outer window also handles `sceneGraphError`, so a context that fails
later (a cover window, say) gives
`cannot render Lipstick window N (role): …`, stops the app and exits with 1.
Qt 5.6's render loops skip the frame once the signal is handled (checked
under qemu with the up-front check disabled: exit 1, no core).

**With OpenGL, it runs.** With Mesa llvmpipe in a throwaway target snapshot
(`mesa-llvmpipe-dri-swrast-driver`, not installed by default), keel-shell
runs under qemu against the host's `fake-lipstick`. It runs for 150 s with
no crash, then exits 0 on SIGTERM. The nested app was Qt 6's `qml` tool with
a main window and a `keel:cover` window. fake-lipstick received a 540x960
main surface and a 234x374 surface with `CATEGORY=cover`, both with content.
The set-up:

```
# host: fake-lipstick from the host build, socket on the /work mount
XDG_RUNTIME_DIR=$PWD/target/kshell-sock QT_QPA_PLATFORM=offscreen \
    <host-build>/tests/e2e/fake-lipstick --socket fake-lipstick-0 &   # then chmod 777 the socket
# SDK container: qemu-user directly (sb2 maps /work away), sysroot = the snapshot
T=/srv/mer/targets/SailfishOS-5.2.0.15-aarch64.<snapshot>
XKB_CONFIG_ROOT=$T/usr/share/X11/xkb WAYLAND_DISPLAY=/work/target/kshell-sock/fake-lipstick-0 \
QT_QPA_PLATFORM=wayland-egl LIBGL_ALWAYS_SOFTWARE=1 QT_LOGGING_TO_CONSOLE=1 \
    qemu-aarch64-static -L $T keel-shell --verbose --socket kshell-nested
```

Two harness traps. Sailfish's Qt logs to journald unless
`QT_LOGGING_TO_CONSOLE=1` is set, so the abort looks silent. And
`qemu -L` does not redirect xkbcommon's lookup of `/usr/share/X11/xkb`.
Without `XKB_CONFIG_ROOT`, Qt 5.6's Wayland client then passes a null XKB
context to `xkb_keymap_new_from_buffer` and segfaults in `xkb_context_ref`.
That bug is in Qt, not in keel-shell, and the phone has the xkb data.

## Needs device verification

Since ADR-0016 these checks matter only if direct mode fails on the phone,
and as the comparison `tools/phase0/keel-runtime-test.sh` makes (it runs the
same test app under keel-shell). None of the following has been tested on a
Jolla Phone or under Lipstick.
Under qemu, keel-shell ran only with Mesa llvmpipe, not with the phone's
libhybris EGL (see "Running under qemu"). Exact steps:

1. **Install and launch.** Build the RPM as above, install it
   (`pkcon install-local shipwright-keel-shell-*.rpm` as root, or
   `rpm -i --nodeps` for a quick probe), install Chum `chum:testing` Qt6
   (`qt6-qtbase`, `qt6-qtdeclarative`, `qt6-qtwayland`), then run
   `keel-shell --verbose -- /usr/bin/<qt6-test-app>` from an SSH session with
   the user's session environment (`XDG_RUNTIME_DIR=/run/user/100000`,
   `WAYLAND_DISPLAY=../../display/wayland-0`). Expect the log lines
   `outer window 1 (main) shown` and `map surface … -> window 1 (main)`. On
   the phone, expect the app to fill the screen. A Qt6 test app with a
   `keel:cover` window can be built from `tests/e2e/client/`; it uses
   QRasterWindow, so it works without a Qt6 EGL setup.
2. **Cover accepted by Lipstick.** With the test client running, go to the
   home screen. Expect an app cover showing the client's cover window (the
   test client paints it blue) in the app grid. Check
   `journalctl --user -u lipstick` for errors. If the grid shows no cover,
   run with `--no-cover`, then compare with a Silica app. To confirm the
   category arrived, use `WAYLAND_DEBUG=1 keel-shell …`: expect
   `qt_extended_surface@…update_generic_property("CATEGORY", …)` before the
   cover surface's first `wl_surface.commit`.
3. **Cover actions.** Add a `CoverAction`-like area in the client's cover
   window that logs taps. Tap it in the app grid and expect the log line.
   Also check that `CoverStatus` flips to 1 when the grid is visible and
   back to 0 when it is not (log it from the client).
4. **Virtual keyboard.** Install `qt6-sfos-maliit-platforminputcontext` (if
   it exists for 5.2) and run a Qt6 app with a TextField under keel-shell.
   Tapping the field should open the keyboard, and typed text should appear;
   check orientation in landscape too. Compare with qt-runner-qt6 on the
   Xperia (5.1), where it is packaged. If the keyboard opens but covers the
   field, try `--follow-keyboard`.
5. **Translucent ambience wallpaper.** Run a client that clears to
   transparent. The ambience wallpaper should show behind it, as behind
   Silica apps. If the window is black, check whether the Qt 5.6 client got
   an alpha EGL config (`QSG_INFO=1 keel-shell …` prints the surface format).
6. **Orientation.** Rotate the phone. `OrientationChanged` should reach the
   app (log it). After the app calls `SetContentOrientation`, the status bar
   and keyboard should follow. Check that the keyboard comes up in the
   rotated orientation.
7. **Activation and close.** Switch between apps: `Active` should toggle.
   Close from the switcher: the app should get `CloseRequested` and exit,
   and keel-shell should exit with the app's code. Check that no keel-shell
   process is left behind (`pgrep keel-shell`).
8. **Frame times.** Run the Phase 0 60-item list flick in a Qt6 app under
   keel-shell and under qt-runner-qt6 (on 5.1), with
   `QSG_RENDER_TIMING=1` in both keel-shell and the app. Record the
   frame-time distributions side by side. Expect parity with qt-runner;
   anything worse is a keel-shell bug.
9. **Sailjail.** Launch through the desktop file with a `[X-Sailjail]`
   section. The app must reach keel-shell's peer bus (default address
   `unix:path=$XDG_RUNTIME_DIR/keel-shell-XXXXXX/bus`, a filesystem socket
   that keel-shell creates inside the sandbox it runs in) and the Wayland
   socket under `/run/display`. Check with `--verbose` that the log's
   `KEEL_SHELL_DBUS=` names a path inside the sandbox's `XDG_RUNTIME_DIR`,
   and that `Ping` succeeds from the app (Keel's `Shell.connected`). Also
   check that sailjail does not put the app in a user namespace of its own
   that maps it to another uid than keel-shell: libdbus would then refuse it
   (anonymous authentication is off). If the sandbox blocks either socket,
   pass `--bus-address unix:path=<directory the app can reach>/bus` and/or
   `--socket <name in XDG_RUNTIME_DIR>`.
10. **Ambience keys.** Run `dconf dump /desktop/jolla/theme/` and
    `dconf dump /desktop/sailfish/silica/` on the phone and record the key
    names for Keel's `Theme`. Switch ambience: `AmbienceChanged` should
    fire once, with the new colours.
11. **OpenGL start-up.** On the phone, keel-shell must not print
    `has no OpenGL support` or `cannot render Lipstick window`. Either one
    means the libhybris EGL or the `wayland-egl` platform failed: check
    `QT_QPA_PLATFORM` in the session environment and run with `QSG_INFO=1`,
    which prints `GL_RENDERER`. Expect the phone's GPU there, not llvmpipe.
12. **Multi-window texture moves.** A late cover title moves a surface
    between two `QQuickWindow`s, and so between GL contexts. Check that this
    does not crash or leave a stale texture. If it misbehaves, Keel must set
    the cover title before `show()`, which PROTOCOL.md asks for anyway.
