<!--
SPDX-FileCopyrightText: 2026 Patrick Quinn
SPDX-License-Identifier: MIT
-->

# Maliit input context for Keel

Qt 6 apps on Sailfish OS reach the keyboard (maliit-server) through
Chum's `qt6-sfos-maliit-platforminputcontext`, built from
[sailfishos-open/maliit-framework](https://github.com/sailfishos-open/maliit-framework)
(branch `qt6`, commit `f5aa5d6`, 10 October 2024). On the Jolla Phone it
had two faults, fixed in `patches/0001-keel-input-context.patch`:

- **Crash when the keyboard opens.** `MInputContext` leaves
  `containerConnectionInterface` (a Flatpak container connection)
  uninitialised unless `FLATPAK_MALIIT_CONTAINER_DBUS` is set, and
  `updateInputMethodArea()` dereferences it as soon as maliit-server
  reports the keyboard's area: every Keel app crashed when a text field
  took focus (Pacific's crash brought Lipstick down with it).
- **Text fields under the keyboard.** `keyboardRect()` returned an empty
  rectangle on the assumption that a compositor makes room. Keel apps run
  on Lipstick directly and, like Silica on Qt 5, lay out around
  `Qt.inputMethod.keyboardRectangle`, so the page never moved up.

`rpm/qt6-sfos-maliit-platforminputcontext.spec` builds only the platform
input context plugin, under Chum's package name with a higher release, so
Reef's repository replaces Chum's build. `rpm/prebuild.sh` fetches the
pinned source tarball and checks its SHA-256.

The fixes belong upstream; until then this package carries them.
