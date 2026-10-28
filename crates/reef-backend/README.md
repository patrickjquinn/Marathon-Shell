<!--
SPDX-FileCopyrightText: 2026 Patrick Quinn
SPDX-License-Identifier: Apache-2.0
-->

# reef-backend

The Rust half of the Reef store client (`apps/reef`). The QML UI talks to a single CXX-Qt object (`apps/reef/src/bridge.rs`), and that object is a thin shell over this crate. This crate does no networking of its own: the app downloads the catalogue, tokens and revocation list and passes the bytes in. That keeps an HTTP stack out of the crate and every rule unit-testable.

| Module | What it does |
| --- | --- |
| `catalogue` | The `catalogue.json` model, schema 1, published per arch. `visible()` hides packages whose `requires_cpu` (or every build of a `variants` group) this phone's processor lacks, and sorts the rest by category and then title. The catalogue is not signed, so `parse` refuses a licence `app_id` that is not a safe file name and a non-`https://` purchase URL, and drops a non-`https://` homepage or source. |
| `index` | The store index (catalogue v2): one index with what lists, rows and search need, and a details file per app checked against the index's SHA-256. Nothing reads an index yet: its signature has no check on Marathon. |
| `licences` | `LicenceStore`: one verified token file per app (mode 600, written atomically). Every app id is checked with `handoff::valid_app_id` before it becomes a path. The revocation list and its signature are one file (`revocations.signed`). A stored subscription token is never replaced by one for the same licence that expires sooner. `EMBEDDED_KEYS` comes from `SHIPWRIGHT_LICENCE_KEYS` at build time (below) and is empty without it; an empty key set rejects every token. |
| `claim_codes` | How a licence bought on the web reaches the phone: `new_claim()` (128 bits from `getrandom`), `purchase_url_with_claim`, and `PendingClaims` (one file per code in `claims/` beside the licence directory, at most 20, dropped after 30 days). The app redeems them during a licence refresh (`GET /v1/claims/{code}`). |
| `licenced` | The licence hand-off service: `GetLicence(app_id)` on the session bus returns the token `LicenceStore` holds for that app. Run by the D-Bus-activated binary `shipwright-reef-licenced` (`src/bin`, activation file in `data/`), which exits after `SHIPWRIGHT_REEF_LICENCED_IDLE_SECS` (default 30) idle seconds. Not installed on Marathon yet: apps reach the session bus only through the shell's admission, which has no rule for it. |
| `store` | `entries()`: catalogue rows joined with what is installed and what has an update, for the UI. |

## Build and test

```
cd crates
cargo test -p reef-backend       # unit tests + the licence hand-off's D-Bus tests
cargo clippy -p reef-backend --all-targets -- -D warnings
cargo run -p reef-backend --example validate-catalogue -- catalogue.json aarch64
```

`tests/licenced_dbus.rs` starts a private `dbus-daemon` for the hand-off: the service in-process, no service, and the real binary started by D-Bus activation from the activation file. Without `dbus-daemon` it is skipped, unless `MARATHON_TEST_STRICT` is set.

**Licence keys.** `build.rs` fills `licences::EMBEDDED_KEYS` from the build-time variable `SHIPWRIGHT_LICENCE_KEYS`, `kid:base64url` entries separated by commas. A malformed value fails the build, unset means no trusted key, and a release build (`--cfg release_build`) refuses key ids starting with `staging` or `test`. `reef_licence::build` does the parsing.
