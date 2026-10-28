# Reef as Marathon's store (Bandit)

**Goal:** Reef replaces the Marathon store: Flathub, F-Droid (Android through Deckard) and Reef's own catalogue in one app that installs, updates and removes through `marathon-store-handler`.

**Decided (owner, 2026-10-28):** Reef replaces `apps/store` in images. The owner publishes the Marathon catalogue at `reefstore.app/marathon/<arch>/catalogue.json`; Reef shows it alongside Flathub and F-Droid from day one.

**Architecture:** Reef's Rust bridge stays the only client of the handler, as the old store's QML was: it fires `marathon-store://<verb>/<arg>` (xdg-open) and reads the handler's files in `$XDG_RUNTIME_DIR/marathon-store-state` (`installed.json`, `phone-apps.json`, `android-device.json`, `settings.json`, `install-progress-<app>.json`). Every row carries a source: `reef`, `flathub` or `fdroid`; a Reef catalogue package names what installs it (a Flathub ref or an Android package), so Reef never needs a package manager of its own.

## Tasks

1. **Sources in `reef-backend`.** `Package` gains `source` (`flathub:<ref>` / `android:<package>`) for Reef catalogue entries; Flathub rows from the handler's phone-fit list and AppStream, F-Droid rows from the handler's compact catalogue. One entry list; ranking and search unchanged. Tests: parse a catalogue entry with each source; a Reef entry and a Flathub row for the same ref show once (Reef's wins).
2. **Install state from the handler.** `installed.json` and updates feed `store::entries`; per-app progress (`pending`, `installing`, percent, `failed` + error, `removing`, `cancelling`) becomes row roles. Bridge invokables `install(name)`, `update(name)`, `uninstall(name)`, `cancel(name)`, `updateAll()`, `open(name)`.
3. **UI.** Install/Open/Update/Remove/Cancel with progress on the package page and rows; the Installed page lists installed apps and updates with Update all; source shown on the package page; F-Droid sync and the Android page's facts (permissions, anti-features) on Android rows; sideloading an APK (`apk-inspect`, `apk-install`); the handler's settings (auto-update) on the settings page.
4. **Packaging.** Images ship `shipwright-reef` as the store (home grid, `marathon-store://` links, Keel actions for Pilot: search, install, open, updates) and no longer `apps/store`; the handler and its timers stay.
5. **Catalogue spec for the owner.** `docs/reef/marathon-catalogue.md`: URL, fields, the `source` field, icons/screenshots, licence models.
6. **Device verification (HackberryPi).** Browse each source; install, open, update and remove a Flathub app and an F-Droid app; a failed install shows why; Pilot "install X" through Keel; cold start time of the store.

Delete `apps/store` once task 6 passes.
