# Moving platform code to Rust

Keel already builds part of itself in Rust (`keel/silica/plugin`: a CXX-Qt static library that CMake builds with cargo and links into the `Keel` plugin). Marathon has one Rust program, `tools/marathon-mail-oauth`, built as its own APK. This plan moves more of Marathon's platform code to Rust, one component at a time, where Rust gets us something real: a maintained crate in place of a shell-out, logic we can unit-test, or memory safety at a trust boundary.

## Rules

- Use the cargo CLI: `cargo new`, `cargo add`, `cargo test`, `cargo clippy`. Don't write dependency versions into `Cargo.toml` by hand, and don't hand-roll anything a maintained crate already does.
- Lints match Shipwright: clippy pedantic (minus `must_use_candidate`, `missing_errors_doc` and `module_name_repetitions`), plus the restriction lints Keel's plugin uses (`unwrap_used`, `expect_used`, `panic` and the rest). Code must be clippy-clean with `-D warnings`.
- Every migrated component gets Rust unit tests, and ctest runs them. The existing C++ and QML tests are the behaviour contract and must stay green.
- Don't migrate QML UI. Don't rewrite large shell subsystems.
- A crate's licence must be compatible with Apache-2.0. This rules out sequoia-openpgp (LGPL-2.0+), because we link statically.

## Layout

- **`crates/`** is one Cargo workspace, with its own `Cargo.toml`, `Cargo.lock` and lint table. It is not at the repo root, so `tools/marathon-mail-oauth` keeps building on its own and its APK doesn't change.
- **One static library per linked binary.** Two Rust static libraries in one link both carry `std`, and the link fails on duplicate symbols. So each C++ library that needs Rust gets a single `*-native` crate holding all of that library's Rust modules. This is the same approach Keel takes with `keel_silica_native`. Shared logic can go in plain `rlib` crates, which several native crates or CLIs can use.
- **The C++ boundary uses `cxx`** when no QObject crosses it: plain functions, enums and structs. That's the case for everything in wave 1. CXX-Qt, as Keel uses it, is for when Rust owns a QObject. `cxx` is the layer CXX-Qt is built on, and it doesn't need Qt at build time.
- **CMake drives cargo the way Keel does.** `crates/CMakeLists.txt` runs `cargo build --locked` as a custom target and exposes each native crate as an INTERFACE library. That library carries the static archive, the cxx include directory and a dependency on the cargo target. With `BUILD_TESTING` on, it also registers `cargo test --workspace --locked` with ctest.
- **The cargo target directory** is the `MARATHON_CARGO_TARGET_DIR` cache variable. It defaults to `$CARGO_TARGET_DIR` when that is set, and to `<build>/cargo` otherwise. Development builds point it at tmpfs.
- **The consuming library links the archive with `--exclude-libs`.** The Rust runtime then stays private to that `.so`, so it can't clash with Keel's copy in the same process.
- **Packaging:** marathon-shell's APKBUILD gains `cargo` in makedepends, and `prepare()` runs `cargo fetch --locked`, with `options="net"`. This follows the keel-silica and marathon-mail-oauth APKBUILDs, so no vendoring is needed. The APK build container (`scripts/qemu/lib/build-marathon-shell-apk.sh`) installs `cargo`.

## Inventory

The table rates each candidate on five things:
- **Bugs:** known or likely defects.
- **Safety:** what's at stake at the boundary.
- **Test:** how much logic could be unit-tested once it's in Rust.
- **Self:** how cleanly the component is separated from the rest (CLI, D-Bus, or a narrow C++ interface).
- **Perf.**

| Component | Where | Bugs | Safety | Test | Self | Perf | Verdict |
|---|---|---|---|---|---|---|---|
| Package signature verification | `marathon-core/src/marathonappverifier.cpp` | High: shells out to `gpg`, which isn't in the image, so every signed package fails with `GPGNotAvailable` on the phone | High: the trust gate for sideloaded apps | High | Narrow: three paths in, one verdict out | – | **Wave 1** |
| Package archive create/extract | `marathon-core/src/marathonapppackager.cpp` | High: shells out to `zip`, `unzip` and `zipinfo`, none of which is in the image. The symlink check parses `zipinfo` text and is skipped whenever `zipinfo` is missing | High: untrusted archives get written to disk | High | Narrow: two paths in, an error out | Small | **Wave 1** |
| Store URL handler | `scripts/store/marathon-store-handler` (bash, plus `marathon-store-refresh-state`, which calls python3 to escape JSON) | Medium: progress comes from scraping flatpak's TTY output through `script(1)`, and the JSON is assembled with `printf` | Medium: the arguments are URLs from an app sandbox | High: URL and ref validation, progress parsing, error extraction, state JSON | CLI boundary | – | **Wave 2.** The image installs these scripts from the duranium pipeline (`marathon-extras`, patches 0003, 0021 and 0024), so moving them into the shell APK needs a coordinated pipeline patch. `libflatpak` bindings would remove the TTY scraping, but the dev host has no `flatpak-devel`, so that path can't be tested here yet |
| Desktop-file parsing and icon lookup | `shell/src/components/desktopfileparser.cpp` | Medium: a hand-rolled INI parser with no locale keys, escapes or field codes beyond a regex | Low | High (`freedesktop-desktop-entry`, `freedesktop-icons`) | Medium: returns `QVariantMap` to QML, so it needs a CXX-Qt or value bridge into the shell binary | Medium: it scans every launch | Wave 2 |
| Notification store | `shell/src/dbus/notificationdatabase.cpp` | Low | Low | Medium | Narrow | – | Later. QtSql works, and the gain is small |
| Alarm scheduling | `shell/src/managers/alarmmanagercpp.cpp` | Medium: time arithmetic across DST and repeats | Low | High: pure next-fire computation | Narrow if only the scheduling maths moves | – | Wave 2: move just the next-fire computation, using `chrono` / `jiff` |
| Music library scanner | `marathon-services/src/musiclibrarymanager.cpp` | Medium | Low | Medium (`lofty` for tags) | Medium | Medium | Wave 3 |
| Store refresh, flatpak listing | `shell/src/services/flatpakmanager.cpp` | Low | Low | Low | Narrow | – | Goes with the store handler |
| App runner, sandbox (bwrap argv) | `tools/marathon-app-runner`, `tools/marathon-sandbox` | Medium: argv assembly bugs have happened (r336) | High | High | Medium | – | Wave 3: move the argv builder only |
| Compositor, launch service, shell IPC | `shell/src/wayland`, `applaunchservice`, `shellservices` | – | – | – | Large and Qt-bound | – | Not planned |

## Wave 1

Both components go in `crates/marathon-core-native`, which is linked into `libMarathonCore.so`, and each is its own commit.

**1. Signature verification**

`marathon_core_native::verify` uses rPGP (`pgp`, MIT OR Apache-2.0) to load the trusted keys from `trusted-keys/*.asc|*.gpg`, armoured or binary, and to check the detached `SIGNATURE.txt` against `manifest.json`. It returns `Valid`, `InvalidSignature`, `UntrustedKey`, `NoTrustedKeys` or `Failed` (unreadable files, a bad key). The C++ `MarathonAppVerifier` keeps everything else: its QObject API and signals, the strict-mode policy and the syslog audit lines.

Two behaviour changes:
- **No more `gpg` at runtime.** This fixes signed installs on the phone.
- **Dev mode with no trusted keys** used to verify against the user's own gpg keyring. A signed package in that state is now treated the same as an unsigned one: accepted with the same audit warning. Strict mode is unchanged and still refuses.

`signManifest`, the developer-side signing in `marathon-dev`, still uses the developer's own gpg key and agent.

**2. Archives**

`marathon_core_native::archive` uses the `zip` crate:
- **Create:** a deflated archive of the app directory. Symlinks are followed, as `zip -r` did, and Unix permission bits are kept.
- **Extract:** any symlink entry, or any entry whose name escapes the destination, is refused before anything is written. Then the crate's own `extract` runs.

That replaces `zip`, `unzip` and the `zipinfo` parsing. The post-extraction symlink scan goes too, because nothing can create a symlink any more. The C++ `MarathonAppPackager` keeps manifest validation, progress signals and the move into place.

**Verification**

- `cargo test` and `cargo clippy -- -D warnings` pass in `crates/`.
- ctest runs `Rust_Crates`.
- `Core_AppVerifier`, `Core_AppPackager` and `Core_InstallerSecurity` stay green: the verifier test still generates its keys with gpg and now checks them through Rust.
- The shell, app runner and `marathon-dev` still link against MarathonCore.

## Later waves

These get a short design note each, in this directory, when they start.

- **Store handler as a Rust CLI.** Use `libflatpak` transactions once there's a host with `flatpak-devel` to test on. Add a pipeline patch that drops the bash copies from `marathon-extras`.
- **Desktop-file parsing**, through `freedesktop-desktop-entry` and `freedesktop-icons`, bridged with CXX-Qt into the shell.
- **The alarm next-fire computation.**
