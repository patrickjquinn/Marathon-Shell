<!--
SPDX-FileCopyrightText: 2026 Patrick Quinn
SPDX-License-Identifier: Apache-2.0
-->

# Reef (store app)

Reef is Marathon's app store. This is its client: a Keel app that loads the QML in `ui/` and exposes the `Reef` singleton (`import Shipwright.Reef 1.0`), implemented in Rust with CXX-Qt 0.10 over `reef-backend` and `reef-licence` (`crates/`). The object's API is the one in `UI.md` ("Backend object API"). The shell starts it under marathon-keel-host (`X-Marathon-KeelHost=true` in `shipwright-reef.desktop`).

It came from Shipwright's Reef for Sailfish OS. What stayed there: the RPM installer and spec, ssu repository pinning, PackageKit installs, the signed `repomd.xml` check, the background update check and its Lipstick notification, and every server (licence services, developer portal, reefstore.app and its publishing tools).

**What works now.** Browsing: the catalogue (`<store>/catalogue.json`, cached for the next start), its icons and screenshots, featured apps, collections, categories, ranked search and each app's page. Licences: adding a token, refreshing it from the licence service, and buying through a claim code. **What does not, yet.** Installing, updating and removing apps: the Install button is disabled with a note saying so, and the Installed page stays empty. Reef has no catalogue for Marathon published yet, so the store says that it has none (`jobs::DEFAULT_STORE_URL`, `https://reefstore.app/marathon/<arch>/`).

This is a Cargo workspace of its own (its own `[workspace]` and `Cargo.lock`): it links Keel's SailfishApp from keel-silica-dev, which the shell's build and CI do not install, so `crates/` cannot hold it.

| File | What |
| --- | --- |
| `src/lib.rs` | The app (a shared library that is also executable, installed as `/usr/bin/shipwright-reef`; `tools/keel-launcher/link_sailfishapp.rs`). Loads `/usr/share/shipwright-reef/qml/shipwright-reef.qml`, or `--qml FILE` / `$REEF_QML`. |
| `src/bridge.rs` | The CXX-Qt bridge: the `Reef` singleton, and `ReefListModel` behind its models. |
| `src/rows.rs` | Pure conversions from backend types to model rows, the `packageDetails` map and the keyed messages. No Qt. |
| `src/jobs.rs` | Work off the GUI thread: catalogue, asset, token and revocation downloads (ureq with rustls, plus `file://`), the catalogue cache (written atomically), and where the store is (`store_url`). |
| `src/settings.rs` | `refreshOnStart` and `licenceServer`, in `$XDG_CONFIG_HOME/shipwright-reef/settings.json`. |
| `src/logging.rs` | A `log` backend on stderr; `REEF_LOG` sets the level. |
| `src/release_gate.rs` | Refuses a release build (`--cfg release_build`) while a shipped default names a `.example` host or the licence server a staging one. |
| `cpp/` | The window (Keel's SailfishApp view) and the list models' factory. |

Developer overrides, never set on a phone: `REEF_STORE_URL` (the store directory, `{arch}` replaced) and `REEF_QML`.

## Build and test

```
cd apps/reef
export QMAKE=/usr/lib/qt6/bin/qmake KEEL_SAILFISHAPP_INCLUDEDIR=<keel-silica-dev>/usr/include/keel/sailfishapp KEEL_SAILFISHAPP_LIBDIR=<keel-silica-dev>/usr/lib
cargo fmt --check
cargo clippy --locked --all-targets -- -D warnings
cargo test --locked
```

The package (`packaging/packages/shipwright-reef`) builds with `PILOT_PKGS=shipwright-reef scripts/qemu/lib/build-pilot-apk.sh`, and `scripts/build-image.sh` builds it for every image.

**Licence server.** A fresh install's licence server (`settings::DEFAULT_LICENCE_SERVER`) is `https://licences.reefstore.app`, unless the build sets `REEF_LICENCE_SERVER`. Licence keys come from `SHIPWRIGHT_LICENCE_KEYS` at build time (`crates/reef-backend`); without them no token verifies, and nothing else changes.
