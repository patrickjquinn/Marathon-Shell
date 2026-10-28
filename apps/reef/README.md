<!--
SPDX-FileCopyrightText: 2026 Patrick Quinn
SPDX-License-Identifier: Apache-2.0
-->

# shipwright-reef (client application)

The Reef store client executable: a Qt6 app that loads the QML in `../ui/qml` and exposes the `Reef` singleton (`import Shipwright.Reef 1.0`), implemented in Rust with CXX-Qt 0.10 over `reef-backend` (`../backend`) and `reef-licence` (`../../licence`). The object's API is exactly the one documented in `../ui/README.md` ("Backend object API"). The list models also have a `count` property and a `get(row)` method.

This is a standalone Cargo workspace (its own `[workspace]` and `Cargo.lock`). The root workspace lists `reef/client/app` under `exclude`.

| File | What |
| --- | --- |
| `src/lib.rs` | The app (a shared library that is also executable, installed as `/usr/bin/shipwright-reef`; `tools/keel-launcher/link_sailfishapp.rs`). Starts `QGuiApplication` and loads `/usr/share/shipwright-reef/qml/shipwright-reef.qml`, or the file given by `--qml FILE` or `$REEF_QML` (as a `QUrl::fromLocalFile`, so any path works). Exits with status 1 if the QML fails to load. `--check-updates` runs the background check instead (no Qt). |
| `src/check.rs` | The background check: `shipwright-reef --check-updates`, see below. |
| `src/logging.rs` | A small `log` backend on stderr (journald on a phone); `REEF_LOG` sets the level. |
| `src/release_gate.rs` | Refuses to compile a release build (`--cfg release_build`) while a shipped default names a `.example` placeholder host or the licence server a staging host. |
| `src/bridge.rs` | The CXX-Qt bridge: the `Reef` singleton, and `ReefListModel` (a `QAbstractListModel` whose rows are replaced as a whole) behind `catalogueModel`, `installedModel` and `licenceModel`. |
| `src/rows.rs` | Pure conversions from backend types to model rows, the `packageDetails` map, and the `repoState`/`busyText`/`progress` strings. No Qt. |
| `src/jobs.rs` | Work that runs off the GUI thread: catalogue, token and revocation downloads (ureq with rustls, plus `file://`), the catalogue cache (written atomically), `ssu lr`, PackageKit transactions, repair commands, and the repository configuration (the installed `/usr/share/shipwright-reef/repo.conf`, so granularity and URL match what the installer registered). No Qt. |
| `src/settings.rs` | `refreshOnStart`, `backgroundCheckDays` and `licenceServer`, stored in `$XDG_CONFIG_HOME/shipwright-reef/settings.json`. |
| `cpp/factory.*` | C++ glue: creates the list models as QObject children of `Reef`, because Rust cannot `new` a CXX-Qt QObject. |
| `packaging/shipwright-reef.desktop` | Launcher: `Exec=/usr/bin/keel-shell -- /usr/bin/shipwright-reef`, `Sandboxing=Disabled`. The privileges entry is still `../packaging/privileges.d/`. |
| `packaging/systemd/shipwright-reef-check.{service,timer}` | The user timer (every 4 hours, persistent, randomised by up to 20 minutes) that runs the background check; the package's `%post` starts it in the running session. |
| `packaging/notifications/x-shipwright.reef.updates.conf` | Lipstick notification category of the update notification (popup, Events entry under Reef). |
| `packaging/dbus/org.shipwright.reef.ui.service` | Starts Reef when the notification's tap calls `org.shipwright.reef.ui.openUpdates` (the window's `DBusAdaptor`). |
| `tests/smoke-test.sh` | Headless smoke test (see below). |
| `tests/harness/smoke.qml.in` | The smoke test's QML driver. |

## Threading

Every invokable returns at once. Results come back through `queue_or_log` (a failed `queue`, which happens only while the object is being destroyed, is logged). If a worker thread cannot be created, the job ends at once with the error in `lastError`. `refresh()`, the start-up check, `install`/`update`/`updateAll`/`remove`, `repairRepository()` and `refreshLicences()` start a worker thread. That thread posts progress and results back to the GUI thread with CXX-Qt's `CxxQtThread::queue` (`impl cxx_qt::Threading for Reef`). Only one job runs at a time, and `busy` is true while it runs. A `refresh()` called during a job runs when that job ends. Any other operation called during a job fails at once, with `operationFinished(name, false, "Another operation is running.")`. PackageKit progress is forwarded only when it changes.

Things that run on the GUI thread, because they are only local file reads or writes: `packageDetails`, the licence calls (`checkLicenceToken`, `licenceTokenApp`, `addLicenceToken`, `removeLicence`), and settings writes.

At start-up the client shows the catalogue cached from the last refresh (`$XDG_CACHE_HOME/shipwright-reef/catalogue.json`). It then checks `ssu lr` and PackageKit install state in the background. The UI then calls `refresh()` if `refreshOnStart` is set.

Developer overrides, never set on a phone: `REEF_SYSROOT` (the root used to find `/etc/sailfish-release` and `repo.conf`), `REEF_URL_TEMPLATE` (the repository URL template, with `{release}` and `{arch}`), and `REEF_QML`.

## Background check

The "Check in the background" setting (never, every few hours, weekly) is read by `shipwright-reef --check-updates`, which `packaging/systemd/shipwright-reef-check.timer` (a systemd **user** timer) starts every 4 hours; the RPM's `%post` starts the timer in the running session, since its wants link only acts at the next login (until 11 October 2026 a phone that had not restarted since Reef arrived never checked). It runs without Qt: it reads the settings, and when a check is due (`check::due`: 4 hours or a week since `$XDG_CACHE_HOME/shipwright-reef/last-check`, with half an hour of slack; never for "Never") it runs the same refresh as the app (catalogue, cached for the next start; `ssu lr`; PackageKit's Reef updates; licence refreshes) and records the time. When an update has appeared that was not announced yet (`announced-updates` in the same folder, one `name version` a line), it posts one notification through `org.freedesktop.Notifications`, replacing its previous one: the apps by name ("Pilot update ready", "3 app updates ready" with the names), a popup (category `x-shipwright.reef.updates`), and a tap that opens Reef on its updates (`org.shipwright.reef.ui openUpdates`). The text is English, because this path has no Qt translations.

The RPM must ship the two units in `/usr/lib/systemd/user/` and enable the timer for every user (`/usr/lib/systemd/user/timers.target.wants/shipwright-reef-check.timer` symlink); see the report for the spec change.

## Release builds

**Licence server.** A fresh install's licence server (`settings::DEFAULT_LICENCE_SERVER`, the Settings page's "Licence server") is the production service, `https://licences.reefstore.app`, unless the build sets `REEF_LICENCE_SERVER`: a non-empty value replaces it, read with `option_env!` at compile time, so changing it rebuilds the crate. It must be an `https://` URL with a host and no whitespace, `?` or `#` (`settings::is_valid_licence_server`); anything else fails the build with "REEF_LICENCE_SERVER must be an https:// URL". A staging phone build points it at the staging service, for example `REEF_LICENCE_SERVER=https://licences-staging.reefstore.app`, together with that service's key in `SHIPWRIGHT_LICENCE_KEYS` (tools/build/native/README.md, "Licence keys"). `tools/build/native/native.sh` and `tools/build/sdk/sdk.sh` pass it into the build container, `tools/build/reef/lan-test-repo.sh --licence-server` sets it, and `services/cloudflare-staging.sh reef-packages` sets both to the staging licence service. A server saved in `settings.json` (once the user changes any setting) still wins over the built-in one.

`src/release_gate.rs` holds `const` assertions that only compile in when `--cfg release_build` is set: they fail while `settings::DEFAULT_LICENCE_SERVER` or `reef_backend::repo::DEFAULT_URL_TEMPLATE` contains `.example`, or while the licence server contains `staging` (a leftover `REEF_LICENCE_SERVER`). The shipped defaults are the production hosts (`https://licences.reefstore.app`, `https://reefstore.app/sailfishos/{release}/{arch}/`), so a release build passes. The RPM spec does not set `RUSTFLAGS="--cfg release_build"` yet: it would also refuse the staging licence keys that phone test builds use. Check: `cargo build --config 'build.rustflags=["--cfg","release_build"]'` builds, and with `REEF_LICENCE_SERVER=https://licences-staging.reefstore.app` it fails with "release build with a staging licence server".

## Build and test

Always use the shared build settings (see the house rules):

```
cd reef/client/app
export CARGO_INCREMENTAL=0 CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0 CARGO_TARGET_DIR=<repo>/target
cargo fmt --check
cargo clippy --locked --all-targets -- -D warnings
cargo test --locked
cargo build --locked
cmake -S ../../../keel -B <keel build> -G Ninja && cmake --build <keel build>
KEEL_QML_DIR=<keel build>/qml sh tests/smoke-test.sh
```

The build needs Qt 6 development files (`qmake6` on `PATH`, or `QMAKE=/usr/lib/qt6/bin/qmake`). It was built and tested on the host with Qt 6.4.2. The device has Chum Qt 6.8.4. The code uses only CXX-Qt 0.10 and Qt APIs that exist in both versions.

**Unit tests.** `rows.rs` covers catalogue rows (only packages tested on this release, sorted by category and then title), the message keys, install and update state, licensed flags, the installed-model filter, every `packageDetails` key, size text, PackageKit status text, progress, `repoState`, and licence rows for every status (active, grace, expired, revoked, invalid). `bridge.rs` checks that values become the `QVariant` types QML receives, and that the details map is keyed by role name. `jobs.rs` and `settings.rs` cover `file://` fetches, refresh without a release, a refresh that caches the catalogue atomically, licence refresh with no licences, and settings round-trip and normalisation. `check.rs` covers when a background check is due; `release_gate.rs` the placeholder detection.

**Smoke test** (`tests/smoke-test.sh [binary]`). It builds three noarch RPMs and generates `catalogue.json` for them with `tools/build/reef/gen-catalogue.py` into a `file://` repository. It then runs the real binary with `QT_QPA_PLATFORM=offscreen`, the real UI, and `QML_IMPORT_PATH` pointing at a Keel build (`KEEL_QML_DIR`), so unknown Silica properties or types fail the test. `ssu` and `pkcon` are stubs. The system bus points at a missing socket, so PackageKit is unreachable, and the resulting error appears in `lastError`. The script makes two runs:

- **pinned.** Checks the release, arch, alias, `repoState` and URL. Checks that `catalogueModel` has 2 of the 3 packages (one is tested only on 5.2.0.18) with the right roles, that `packageDetails` is complete and empty for a hidden package, that `repairCommands()` is empty, and that the licence calls reject a garbage token. Checks that settings are normalised and saved, and that the catalogue is cached. Starts an install, which fails (no PackageKit), and checks the package page shows the error and `lastError` has it. Checks that the cover and every page (Package, Installed, Licences, Settings, AddLicenceDialog) instantiate against the real object (created directly, not through the page stack, so the check does not depend on Keel's transition timing). Last, Buy: `buyUrl()` is empty for a free package and adds a 32-hex `claim=` code for the paid one, `checkPurchases()` then starts a licence refresh that asks the (unreachable) service for the code without showing it in `lastError`, and the script checks the pending claim file is kept, mode 600 in a 700 directory. Fails on any QML warning.
- **drifted.** The same checks with `ssu` reporting 5.2.0.15. `repairCommands()` shows four commands. `repairRepository()` returns at once with `busy` set. When `operationFinished` fires, `repoState` must be `pinned`. The script then checks that exactly `ssu rr`, `ssu ar <url>`, `ssu ur` and `pkcon -p repo-set-data shipwright-reef refresh-now true` ran.

- **background check.** `--check-updates` with no settings file (every few hours by default) caches the catalogue and records the check; with the setting at "Never" it does nothing and says so.

## Needs device verification

The list below was written before the phone arrived. Since 5 October Reef has been built for aarch64 (natively, `tools/build/native/native.sh`) and run on the Jolla Phone in direct mode, not under keel-shell, on Sailfish OS 5.2.0.18 only; nothing is recorded on 5.2.0.15 (`d9f22adb`). What the commits record as seen on the phone:

- Reef and an app installed on a phone with nothing of Shipwright's, following reefstore.app/install; the faults found there (pages with a remorse failing to open, apps doing nothing when tapped until their booster ran) were fixed (`89680b57`).
- Installs from Reef through PackageKit: the progress the phone sent is what the steady progress bar is built on (`85fabfa1`); an installed app at the repository's version showed Install, fixed (`c0560227`).
- Removing an app with its add-ons through `Store::remove` (Pilot and its gesture patch together) (`5ddc0b33`).
- Reef verifying the repository's signed `repomd.xml` itself before installs and updates, because ssu sets `gpgcheck=0` on Sailfish (`14c5bcf1`).
- The screenshot viewer, portrait and landscape (`fc0e6b6a`).

Not recorded on the phone: the `privileged` group check in item 2, an update from Reef, HTTPS behind an intercepting proxy (item 4), drift and repair after an OS update (item 5), and item 6.

1. **Cross build.** `tools/build/sdk/cargo-sailfish.sh build --release --locked --manifest-path reef/client/app/Cargo.toml`, with the result in `target/aarch64-unknown-linux-gnu/release/libshipwright_reef.so` (the app is a shared library that is also executable, see `tools/keel-launcher/link_sailfishapp.rs`). The spec expects it there and installs it as `/usr/bin/shipwright-reef`. cxx-qt-build runs the target's `qmake -query`, `moc` and `qmlcachegen`. How to wrap those for the SDK is still open (`tools/phase0/probe-display.md`, route S, step 3). Chum Qt6 6.8.4 devel packages are already in the `SailfishOS-5.2.0.15-aarch64` target. The fallback is a native build on the phone (route N).
2. **Launch through keel-shell.** Install the RPM, then tap Reef in the app grid. The app and its cover should appear. Check `grep Groups /proc/$(pgrep -f /usr/bin/shipwright-reef)/status` for the `privileged` gid. The privileges entry names `/usr/bin/shipwright-reef`, but Lipstick launches `/usr/bin/keel-shell`. If the group is missing, the entry has to match what Lipstick actually starts: try the desktop file form, or a helper (`reef/helper`).
3. **PackageKit from the app.** Refresh, then install, update and remove a test package from Reef. Progress (`busyText`, percent) should update while the transaction runs, and the UI must stay responsive: pull-down menus should still open during a download.
4. **HTTPS from the phone.** The catalogue downloads through ureq, rustls and bundled webpki roots. Check that it works on the phone's network. Behind an intercepting proxy it will fail, because the system CA store is not used.
5. **Drift and repair.** Covered by `../backend/README.md` item 7. After an OS update the RPM trigger should already have re-pinned the repository (see `../../rpm/`). The in-app Repair is the second line of defence.
6. **Cover action and dialogs under keel-shell.** See `../ui/README.md`, "Needs device verification".
