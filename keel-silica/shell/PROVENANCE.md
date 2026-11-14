<!--
SPDX-FileCopyrightText: 2026 Patrick Quinn
SPDX-License-Identifier: MIT
-->

# keel-shell provenance

## Upstreams

| Upstream | URL | Commit studied / derived from | Licence |
| --- | --- | --- | --- |
| qt-runner (rinigus) | https://github.com/rinigus/qt-runner | `4da48c6f9626b1cc2c7186b602c35f7dd73aa554` (2025-10-23) | BSD-3-Clause (`upstream-licenses/qt-runner.LICENSE`). Its sources carry copyright lines for Elros (2017–2020), Rinigus (2020–2023) and Digia Plc (2012); it is based on the QtWayland 5.4 `qml-compositor` example and on qxcompositor. |
| newcompositor (Artur Gaspar) | https://github.com/ArturGaspar/newcompositor (source link from https://openrepos.net/content/artur/newcompositor) | `75ab5acd7df2adb0ab7e26880573a12965e91d95` (2024-06-20) | BSD-3-Clause, Copyright (c) 2023 Artur Gaspar (`upstream-licenses/newcompositor.LICENSE`). Its compositor files carry The Qt Company's BSD example header (2017). |
| Sailfish qtwayland | https://github.com/sailfishos/qtwayland | `f377218d71c1c2de7b0cf71f0acd551309d8e86b` | Consulted for the Qt 5.6.3 QtCompositor API and the client's property path. The only file copied is `src/extensions/surface-extension.xml` (BSD, The Qt Company 2015), used by the test compositor. |
| Lipstick | https://github.com/sailfishos/lipstick | `af4abc107119c9520b1e46549a103e684dc7ed2e` | Consulted only, nothing copied (LGPL-2.1). It shows that the category is read from the `CATEGORY` window property when a surface is first mapped (`surfaceCategory()`, `createView()` in `src/compositor/lipstickcompositor.cpp`). |
| maliit-framework (sailfishos-flatpak fork) | https://github.com/sailfishos-flatpak/maliit-framework | `c1ce5ed850597cf7b0a1ea22cd6450bf4217092e` | Consulted only, nothing copied (LGPL-2.1). It is the client of the `org.container` interface that keel-shell reproduces (`input-context/minputcontext.cpp`). |

The Sailfish SDK target `SailfishOS-5.2.0.15-aarch64` provides
`qt5-qtwayland-wayland_egl-devel` 5.6.3+git6-1.11.2.jolla. The same API and
private headers were used for the device build.

## Which upstream keel-shell is forked from

The **device backend** (`src/backend/qt56/`) follows **qt-runner**'s choice of
compositor API: the Qt 5.6 `QtCompositor` module (`QT += compositor`), whose
pre-1.0 API is the one Lipstick itself is built on. This lets keel-shell
link against the system Qt 5.6 like any Sailfish app, and its Lipstick-facing
windows use the Sailfish Qt 5.6 Wayland client, the same client every Silica
app uses. newcompositor uses Qt 5.15's QtWaylandCompositor from Chum's
`opt-qt5`. That would add an opt-qt5 dependency (its availability for 5.2
was not checked), and its client needed an `LD_PRELOAD` hack against
Lipstick (`hacks/hacks.cpp`).

newcompositor's **design** is the model for multi-window: one Lipstick window
and one compositor output per nested toplevel, children drawn in their
parent's window, close requests forwarded. That design is reimplemented on
the 5.6 API, with surfaces moved between outputs through the private
`QtWayland::Surface::addToOutput/removeFromOutput` calls. The **host
backend** (`src/backend/qt515/`) follows newcompositor's Qt 5.15 code
structure (Compositor, View, Window) so the shared logic can be tested
without a device.

## File-by-file

| File | Origin | Licence |
| --- | --- | --- |
| `src/backend/qt56/backend56.{h,cpp}` | Derived from qt-runner `src/qmlcompositor.{h,cpp}` and `qml/WindowContainer.qml` (compositor construction, `addDefaultShell`, `createOutput`, surface-item handling, frame callbacks, touch and focus). Multi-window, output moves and cover tagging are new. | BSD-3-Clause (upstream header kept) |
| `src/backend/qt515/backend515.{h,cpp}` | Derived from newcompositor `src/compositor.cpp`, `src/view.cpp` and `src/window.cpp` (shell hookup, xdg and wl_shell role handling, input forwarding, output mode handling). Raster renderer and mapper delegation are new; Xwayland code removed. | BSD-3-Clause (upstream header kept) |
| `src/core/containerstate.{h,cpp}` | Derived from qt-runner and newcompositor `src/dbuscontainerstate.{h,cpp}`: the same `org.container` D-Bus interface for Maliit. | BSD-3-Clause |
| `src/core/runner.{h,cpp}` | Derived from qt-runner `src/runner.{h,cpp}`: child process start, stdout/stderr forwarding, crash detection. | BSD-3-Clause |
| `src/core/orientation.cpp` | New, except `maliitAngle()`, which reproduces qt-runner's `orientationAngle()` table (itself from Maliit's `minputcontext.cpp`). | Proprietary AND BSD-3-Clause |
| `src/core/launchconfig.cpp` | New. The environment rules (`WAYLAND_DISPLAY`, `QT_WAYLAND_FORCE_DPI`, `FLATPAK_MALIIT_CONTAINER_DBUS`, dropping `QMLSCENE_DEVICE=customcontext` and `QT_WAYLAND_RESIZE_AFTER_SWAP`, a socket next to `../../display`) re-implement qt-runner's `runner.cpp`/`main.cpp` behaviour; no code copied. | MIT |
| `tests/e2e/fake-lipstick/surface-extension.xml` | Copied from Sailfish qtwayland (see above), SPDX comment added. | BSD-3-Clause |
| Everything else under `keel/shell/` | New. | MIT |

Because derived files are BSD-3-Clause, the upstream licence texts ship in
the RPM (`/usr/share/licenses/shipwright-keel-shell/`). If Keel later moves
to MIT or Apache-2.0 (docs/plan.md, "Licence boundaries"), the BSD files
stay BSD, which is compatible with either. No GPL or LGPL code is included.

## Not used

- qxcompositor (elros34), qt-runner's own ancestor, was not consulted directly.
- No Jolla proprietary source or binaries were consulted.
