<!--
SPDX-FileCopyrightText: 2026 Patrick Quinn
SPDX-License-Identifier: MIT
-->

# keel-launcher: how the Qt 6 apps get their window

Keel's `ApplicationWindow` is an `Item`, not a window
(`keel/silica/qml/ApplicationWindow.qml`). An app that loads it as the root
of a `QQmlApplicationEngine` shows no main window. On a desktop nothing
appears. On a phone only the cover would be mapped and the app would have no
Lipstick app window. The apps therefore start the way a Sailfish SDK app
does: `SailfishApp::application()` and `SailfishApp::createView()` from Keel's
SailfishApp library (`keel/sailfishapp`). `createView()` returns a
`QQuickView` that sizes the root item to itself. This is the same shape
`keel new` generates (`tools/keel-dev/templates/app/cpp/launcher.cpp`).

Apps: `reef/client/app`, `shoal/keys/app`, `shoal/mail/app`,
`shoal/migrate/app`, `shoal/bridge-icloud/app`.

| Piece | Where |
| --- | --- |
| `keel_show_main_view(qmlPath)` | Each app's `cpp/launcher.{h,cpp}`. The files are identical apart from the include prefix. It loads the file into the view: full screen on a phone (Keel's direct mode or keel-shell, `Keel::windowMode()`), otherwise a phone-sized window, and it honours `keel run`'s `KEEL_RUN_SIZE`, `KEEL_RUN_ORIENTATION` and `KEEL_RUN_SCREENSHOT`. A load error prints the QML errors and returns false. The Rust `main` then exits with status 1. A root that is not an `Item` (a smoke-test harness `QtObject`) is created in the view's engine and not shown. |
| `keel_application()`, `keel_launch_arguments()` | Same files: `Keel::application()` and `Keel::launchArguments()` (`keel/sailfishapp/include/keellauncher.h`). The application is booster-keel's when the app is boosted, otherwise created on the first call (direct mode on Sailfish OS, ADR-0016). |
| Rust side | Each app's `src/bridge.rs` declares the three functions and includes `launcher.rs` from here: `launch_args()` (use it, not `std::env::args()`, which holds the booster's arguments when boosted) and `keel_application()`. `launcher.rs` also has `keel_main(run)`, which the C `main` in the app's `src/lib.rs` calls: it ignores SIGPIPE and turns a panic into exit status 101, as Rust's start code for a binary would. `run` parses `launch_args()`, takes the application from `keel_application()` and calls `keel_show_main_view` instead of `QQmlApplicationEngine::load`. |
| Linking | `link_sailfishapp.rs` here, pulled into each app's `build.rs` with `include!`. Its header lists where the library comes from. Each app is a library crate built only as a `cdylib` (`[lib] crate-type = ["cdylib"]`; an `rlib` next to it would turn off release LTO), and `executable_cdylib()` makes that shared library executable too (`Scrt1.o`, a `.interp` section): the RPM installs `target/<triple>/release/lib<crate>.so` as `/usr/bin/<app>`, and booster-keel `dlopen()`s the same file and calls its `main`. A Rust binary cannot be boosted: rustc compiles it with local-exec TLS, which a shared object cannot hold (a release build fails to link with `-shared`) and which would break in the booster. On a host, `cargo build` gives `target/debug/lib<crate>.so`; run it directly (under the app's name, as the smoke tests do with a symlink: Keel names the application after `argv[0]`) or with `keel run`. There is no `cargo run`. |
| Compiled QML | `precompile_qml.rs` here, `include!`d the same way: after the app's CxxQtBuilder has built, `precompile_app_qml(src, "/usr/share/<app>/qml", &[])` compiles the app's QML and JavaScript with qmlcachegen and links the units into the app, by the paths the package installs the files at (the engine never compiles them, and never reads the files). `precompile_app_qml_typed` compiles more of it to C++: against Keel's types (`KEEL_QML_IMPORT_PATH`, which `cxxqt-sailfish.sh` sets in native builds from `keel/tools/qml-sdk.sh`) and with the app's directory imports resolved. Pacific uses it and installs its QML files empty (`shoal/pacific/rpm/shipwright-pacific.spec`, which then requires the exact Qt Declarative release). The build script's output says how much became C++. |
| Regression test | `tools/window-probe/`. Each app's smoke test runs the real app library with the real main QML and fails unless a visible top-level window whose title does not start with `keel:cover` appears. |

## Where libkeel-sailfishapp comes from

First match wins:

1. `KEEL_SAILFISHAPP_INCLUDEDIR` and `KEEL_SAILFISHAPP_LIBDIR`.
2. A Keel CMake build in `KEEL_BUILD_DIR`.
3. On hosts only: `~/.cache/keel-dev/keel-build`, then `pkg-config keel-sailfishapp`.
4. Otherwise `keel/sailfishapp/src/sailfishapp.cpp` from this repository is
   compiled into the build-script output directory. It uses cc's compiler for
   the target and the Qt that `qmake` reports.

Case 4 is what CI and the Sailfish SDK build use. Neither needs a Keel
package installed at build time. In the SDK, `cxxqt-sailfish.sh` sets the
cross compiler and a `qmake` stand-in for the target's Qt. That copy is only
linked against. On the phone, the binary loads
`/usr/lib64/libkeel-sailfishapp.so.1` from `shipwright-keel-sailfishapp`,
built from the same source. That package is in each spec's `Requires`.
