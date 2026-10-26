# Keel as Marathon's UI framework

2026-10-11 · status: approved 2026-10-11 · sub-project 1 of 4

## Context

Decision (2026-10-11): **Keel, plus Marathon's extensions, becomes Marathon's
UI framework for the shell and every app.** MarathonUI is retired. Marathon
keeps its navigation and system model (gesture bar, back gesture, task
switcher, Hub, quick settings, lock flow); everything visual becomes
Sailfish (wallpaper-derived ambience, glass, Silica typography and
components, covers on switcher cards).

Programme:

1. **Framework** (this spec): Keel plus Marathon's extensions, wired into the
   runner and the shell.
2. Shell redesign on the framework (chrome, switcher with covers, Hub, quick
   settings, lock).
3. App migration in waves, simplest first.
4. Remove MarathonUI and the legacy app path. Nobody outside builds Marathon
   apps, so there is no compatibility layer: "MarathonUI" from here on means
   Keel plus these extensions.
5. Sailfish app support:
   - host the Keel protocol for C++ apps that use `SailfishApp::main()`,
     launched like native apps, and package Keel's `sailfishapp` shim;
   - Marathon backends for Pickers, Share, Accounts, Secrets and WebView;
   - install Sailfish RPMs and map Sailjail permissions onto Marathon's.

Native Linux and Flatpak apps keep their own launch path and are unaffected.
Forwarding the ambience through xdg-desktop-portal (color-scheme and accent)
is a small follow-up in sub-project 2.

References: "Sailfish OS app design second pass" and "UX Playbook for
Building UIs and Apps" (2026-10). The playbook's WCAG 2.2 AA rules
(labelled controls, full keyboard access, 44 px targets, visible focus) are
framework requirements.

**Constraint: Keel is not modified.** Keel is consumed as packaged
(keel-silica). Marathon's extensions live in this repository. Anything
generally useful is upstreamed to Keel later.

## The framework

```
  apps and shell QML
  ───────────────────────────────────────────────────────────────
  Marathon.Silica      a11y + keyboard on Silica controls,
                       plus components Silica lacks
  Marathon.Platform    Marathon services with no Sailfish API
  Sailfish.Silica      Keel (unmodified)
  Nemo.* (Keel)        Sailfish platform APIs, Marathon backends
  ───────────────────────────────────────────────────────────────
  marathon-app-runner = Keel host (protocol v1) · shell = ambience source
```

App code is Sailfish code plus the two Marathon modules. Where Sailfish has
an API (`Nemo.Notifications`, `Nemo.Configuration`, `Nemo.Ngf`), apps use
it, so they stay source-compatible with Sailfish. `Marathon.Platform` only
covers what Sailfish has no API for.

## Success criteria

1. Every app the runner starts is a Keel app with the host protocol. Apps not
   yet migrated carry `"toolkit": "marathonui"` in their manifest and run as
   today until sub-project 4.
2. The shell process loads Keel. Its ambience service drives both the shell's
   own `Keel.Ambience` and every app's, from the wallpaper. Changing the
   wallpaper re-themes the shell and running apps within a second.
3. Every interactive control in `Marathon.Silica` has an accessible role and
   name, a visible focus state, and works from a hardware keyboard.
4. `Marathon.Silica` provides each MarathonUI capability the apps and shell
   use that Silica lacks (table in §3).
5. `Marathon.Platform` replaces apps' direct use of `MarathonOS.Shell`.
6. `image://theme/icon-*` names used by Keel and our code resolve to
   Marathon icons.
7. The warm runner pre-loads the framework in the engine apps reuse; Silica
   app first frame stays within 10% of today's (about 1.7 s on the
   PinePhone).
8. notes-silica, rebuilt on the framework, passes the pilot device checks, a
   keyboard-only walkthrough and an accessibility-tree check.

## Design

### 1. The runner is a Keel host

Keel's host contract is `keel/shell/PROTOCOL.md` v1: environment variables
plus a peer-to-peer D-Bus server exposing `org.shipwright.keel.Shell1` at
`/org/shipwright/keel/Shell`. On Sailfish keel-shell is the host; on Marathon
`marathon-app-runner` is, for every app except legacy `marathonui` ones.

- **Environment:** the protocol's own variables only:
  - `KEEL_SHELL=1`
  - `KEEL_SHELL_PROTOCOL=1`
  - `KEEL_SHELL_DBUS`
  - `KEEL_SHELL_COVER_TITLE`
  - `KEEL_SHELL_COVER_ENABLED=0` until sub-project 2 enables covers
  - `KEEL_SHELL_DPI`
  - the `KEEL_AMBIENCE_*` snapshot

  In pool mode they are set at adoption, before app QML loads.
- **Peer bus:** a `QDBusServer` on a private socket under `$XDG_RUNTIME_DIR`:

  | Member | Marathon source |
  | --- | --- |
  | `Ambience` / `AmbienceChanged` | shell ambience service (§2), relayed |
  | `Active` / `ActiveChanged` | runner window `activeChanged` |
  | `Orientation` / `OrientationChanged` | shell orientation (0 until rotation exists) |
  | `CoverStatus` | 0 until sub-project 2 |
  | `CloseRequested` | runner close path |
  | `Activate()` | `Navigation1.LaunchApp(appId)` |
  | `Ping()` | `"marathon"` |

- **Back:** unchanged. The runner calls `handleBack()` on the root.
  `SilicaApp` keeps only that and moves into `Marathon.Silica` as
  `ApplicationWindow` (shadowing Silica's).
- **The shell draws the ambience behind Keel apps.** Found while checking
  the client: under a host, Keel's `ApplicationWindow` leaves its background
  transparent (`Shell.phone`), as on Sailfish where Lipstick draws the
  ambience. Marathon's app window therefore draws the same dimmed, blurred
  wallpaper behind Keel apps, flattened into one layer. Frame time must stay
  within 10% of drawing no background (PinePhone).
- **Risk check first:** read Keel's `Shell` client for everything it does
  when `Shell.connected`, and run notes-silica against the protocol before
  building on it.

### 2. Ambience service (shell)

`AmbienceService` in the shell. It feeds the shell's own engine directly
(`Ambience.applyForwarded`) and is exported as
`org.marathonos.Shell.Ambience1` (public read) for runners to relay.

- **Derivation from `SettingsManager.wallpaperPath`:**
  1. Downscale to 64 px.
  2. The most saturated well-populated hue bucket is the base colour.
  3. Mean luminance above 0.6 gives `DarkOnLight`, otherwise `LightOnDark`.
  4. The highlight comes from Keel's palette rule (`highlightFromColor`), so
     the colours match Keel's.
- **Output:** Keel's key names (`highlightColor`, `colorScheme`,
  `wallpaper`), debounced to 250 ms.
- **Tests:** unit tests of the derivation on fixed dark, light, monochrome
  and saturated images.

### 3. `Marathon.Silica` (new, `marathon-silica/`)

A QML module imported after `Sailfish.Silica 1.0`. It depends only on
Silica, so it could also run on Sailfish.

**3a. Accessible, keyboard-operable controls.** Each type derives from
Silica's type of the same name and adds:
- `Accessible.role` and `Accessible.name`, plus `checked` and
  description where they apply, and the press/toggle actions;
- `activeFocusOnTab`;
- a focus ring in the ambience's highlight;
- keys:

| Type | Keys |
| --- | --- |
| Button, IconButton, ValueButton, MenuItem, BackgroundItem, ListItem | Enter/Space activate; Menu or Shift+F10 opens a ListItem's menu |
| Switch, TextSwitch, IconTextSwitch | Space toggles |
| Slider | Left/Right step; PageUp/PageDown 10% |
| ComboBox | Enter opens; arrows choose |
| PullDownMenu, PushUpMenu | Menu or Ctrl+M opens; arrows; Enter selects; Esc closes |
| Dialog | Enter accepts when `canAccept`; Esc rejects |
| RemorseItem, RemorsePopup | Esc cancels |
| SilicaListView, SilicaFlickable | arrows move focus; Home/End |
| PageHeader, SectionHeader | role Heading |
| TextField, TextArea, SearchField | name from `label`/`placeholderText`; Enter follows `EnterKey` |

**3b. Components Silica lacks.** From the MarathonUI usage in apps and the
shell today:

| MarathonUI (uses) | Framework answer |
| --- | --- |
| MApp (19), MPage (4), MStackView (5) | ApplicationWindow, Page, PageStack |
| MTopBar (19), MTopHairline (18) | PageHeader |
| MSection (27), MSectionHeader (1) | SectionHeader in a Column |
| MSettingsListItem (22) | ListItem, ValueButton, TextSwitch, DetailItem |
| MButton (42), MIconButton (14), MCircularIconButton (4) | Button, IconButton |
| MLabel (18), MText (1) | Label |
| MEmptyState (23) | ViewPlaceholder |
| MConfirmDialog (10) | Dialog; RemorseItem/RemorsePopup for destructive actions |
| MActivityIndicator (10) | BusyIndicator, BusyLabel |
| MSnackbar (9) | Notices.show |
| MSearchField (9), MTextField (7), MTextInput (3), MTextArea (1), MFormField (1) | SearchField, TextField, TextArea |
| MToggle (4), MSlider (3), MQSSlider (1) | Switch, TextSwitch, Slider |
| MSheet (4), MModal (2) | DockedPanel, Dialog |
| MScrollView (1) | SilicaFlickable |
| Icon (84) | Silica Icon with the Marathon icon theme (§5) |
| **MTabBar (11)** | **new: `TabBar` / `TabView`** (Keel has private ones; ours is public) |
| **MPageIndicator (1)** | **new: `PageIndicator`** |
| **MFilterChip (1)** | **new: `FilterChip`** |
| MCard (17), MFloatingActionButton (7) | not recreated: Sailfish idiom is lists and the pulley menu; redesigned per app in sub-project 3 |
| MAppIcon, MMarathonMark, MNowBar, MHaloedDisplay, MEntrance, wallpapers | shell-only; rebuilt in sub-project 2 |

New components follow the Sailfish design doc: Theme sizes, colours and
margins only.

### 4. `Marathon.Platform` (new, same directory)

Rule: use the Sailfish API where one exists, with a Marathon backend;
otherwise `Marathon.Platform`.

| Need (today in MarathonOS.Shell) | Framework |
| --- | --- |
| Notifications | `Nemo.Notifications` (Keel) → the shell's existing `org.freedesktop.Notifications` |
| App settings storage (`SettingsManagerCpp.get/set`) | `Nemo.Configuration` (Keel's per-app store) |
| Haptics (HapticService, 192 uses) | `Nemo.Ngf` events. Keel's Ngf is a no-op, so Marathon supplies an Ngf backend over the shell's Haptic1. (Upstream candidate.) |
| Permissions, launch route, lifecycle | `Marathon.Platform.Permissions`, `.App` (route, params, minimise) |
| Location, Sensors, Alarms, Contacts, Telephony, SMS, CallHistory, MediaLibrary, Music | `Marathon.Platform` types wrapping today's runner clients, renamed and without the `*Cpp` suffixes |
| System control (Network, Bluetooth, Display, Power, Audio, Security, Updates, Dav) | `Marathon.Platform.System`, available only to apps with the `system` permission (Settings) |

The runner registers these in place of today's `MarathonOS.Shell`
registrations. Legacy apps keep the old names until sub-project 4.

### 5. Marathon icon theme

Keel's provider searches
`/usr/share/themes/sailfish-default/silica/z<ratio>/icons-monochrome/`. A
`marathon-icon-theme` package installs icons there:
- monochrome white glyphs rendered from Phosphor (MIT) for z1.0 to z2.0;
- a checked-in name map from Sailfish icon names to Phosphor glyphs;
- a build check that fails on any `image://theme/icon-*` name used by Keel's
  Silica QML or our QML that has no mapping.

### 6. Runner and pool

- The warm runner pre-compiles the framework (Silica, `Marathon.Silica`,
  `Marathon.Platform`) in the engine the app reuses, plus MarathonUI while
  legacy apps exist.
- `notes-silica` moves onto the framework and drops its local `SilicaApp`.

## Testing

- **Host:**
  - qmltestrunner suites for `Marathon.Silica`: per type, role and name, and
    keys via `keyClick`;
  - QtTest for the ambience derivation and the runner's protocol server
    (a fake client on `KEEL_SHELL_DBUS`);
  - `Marathon.Platform` registration;
  - the icon map check.
- **Device (PinePhone):**
  - the pilot checks;
  - a wallpaper change re-themes the shell and notes-silica;
  - a keyboard-only walkthrough;
  - the accessibility tree via AT-SPI;
  - launch timing within criterion 7.

## Risks

- **Keel's client may expect keel-shell behaviour beyond PROTOCOL.md.**
  Checked first.
- **Shadowing relies on import order.** Tests import in the order apps do.
  A lint rule flags app files importing `Sailfish.Silica` without
  `Marathon.Silica`.
- **Silica's internal use of its own controls** (for example the MenuItems
  it builds inside its components) gets no shadowing. Fill the gap where an
  app-facing API exists; the rest goes on the upstream list.
- **Shell in-process Keel:** the compositor process loads about 16 MB of
  Keel plugins and Keel's singletons. Measure shell start time and memory
  on the PinePhone before sub-project 2 builds on it.
- **Icons:** Phosphor is MIT; Jolla's icons are never used.
