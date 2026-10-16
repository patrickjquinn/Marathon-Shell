# Native app theming: GTK, libadwaita and KDE apps

GTK 3, GTK 4/libadwaita and KDE/Qt apps, in a Flatpak or not, take
Marathon's ambience (scheme, accent, wallpaper-tinted colours) through
their toolkits' own channels. The main channel is xdg-desktop-portal's
Settings interface, which apps can read from inside the sandbox. Where
the portal can't carry something, a file is written to the place the
toolkit already reads it from, and a Flatpak override makes that file
visible to the app.

| Piece | Where |
|---|---|
| Portal backend (`org.freedesktop.impl.portal.Settings`) | `shell/src/dbus/portalsettings.*` |
| Ambience to colours (pure, tested, WCAG AA) | `shell/src/services/toolkittheme.*` |
| GTK file writer (never replaces a user's own file) | `shell/src/services/toolkitthemewriter.*` |
| Default-ambience GTK 3 themes, `Marathon.colors` | `shell/toolkit-themes/` (golden files, `test_shell_toolkittheme`) |
| Portal routing | `packaging/packages/marathon-base-config/marathon-portals.conf` |
| Flatpak override | `packaging/packages/postmarketos-ui-marathon/marathon-flatpak-*` |

## What each toolkit reads (verified in upstream source)

**GTK 3** (`gdk/wayland/gdkscreen-wayland.c`, gtk-3-24). Inside a sandbox
(`gdk_should_use_portal()`), GTK 3 calls `ReadAll(["org.gnome.*"])` and
listens for `SettingChanged`. It reads these keys:

- `org.gnome.desktop.interface`: `gtk-theme`, `gtk-key-theme`,
  `icon-theme`, `cursor-theme`, `cursor-size`, `font-name`,
  `cursor-blink*`, `gtk-im-module`, `enable-animations`,
  `gtk-enable-primary-paste`, `overlay-scrolling`, `font-antialiasing`,
  `font-hinting`, `font-rgba-order`, `text-scaling-factor`.
- `org.gnome.desktop.wm.preferences`: `button-layout` and the titlebar
  actions.
- `org.gnome.settings-daemon.plugins.xsettings`: `antialiasing`,
  `hinting`, `rgba-order`.
- Also `org.gnome.desktop.{sound,privacy,a11y,peripherals.mouse}` and
  `org.gnome.fontconfig serial`.

GTK 3 doesn't read `org.freedesktop.appearance`. Dark mode is only a
theme name, such as `Adwaita-dark`. When `gtk-theme` changes, GTK 3
reloads the theme live.

**GTK 4** (`gdk/wayland/gdksettings-wayland.c`, main/4.22). Same table as
GTK 3, plus `font-rendering`, `a11y.interface keyboard-focus-visible-timeout`
and `show-status-shapes`. GTK 4 also reads `org.freedesktop.appearance`
`color-scheme`, `contrast`, `reduced-motion` and `accent-color`, which
drive CSS `prefers-color-scheme` and the accent (GTK 4.20+). The user
stylesheet `$XDG_CONFIG_HOME/gtk-4.0/gtk.css` is loaded **once** at
startup (`settings_init_style`, no file monitor). Its
`@media (prefers-color-scheme)` blocks are re-evaluated live because the
provider's `prefers-color-scheme` is bound to the setting.

**libadwaita** (`adw-settings-impl-portal.c`). Reads `color-scheme`,
`contrast` and `accent-color` `(ddd)` from `org.freedesktop.appearance`,
falling back to `org.gnome.desktop.a11y.interface high-contrast` and
`org.gnome.desktop.interface accent-color`. When GSettings is absent (as
in a Flatpak) it also reads `org.gnome.desktop.interface`
`document-font-name` and `monospace-font-name`. All of these update live.
libadwaita ignores `gtk-theme`. It snaps the portal accent to the nearest
of its nine named accents (`adw_accent_color_nearest_from_rgba`, an
Oklch hue split). An exact accent is only possible through `gtk.css`.

**KDE** (plasma-integration `khintssettings.cpp`, `kfontsettingsdata.cpp`).
When `KSandbox::isInside()`, `KHintsSettings` calls
`ReadAll(["org.kde.kdeglobals.*"])` and builds the palette with
`KColorScheme::createApplicationPalette` from the
`org.kde.kdeglobals.Colors:*` groups. It reads `widgetStyle`,
`Icons/Theme` and toolbar style from the same map. On `SettingChanged`:

- `General/ColorScheme`: re-reads everything and repaints, live.
- `KDE/widgetStyle`, `Icons/Theme`, `Toolbar style/ToolButtonStyle`:
  applied live.

It ignores changes to individual colour keys. Fonts are read per key
with `Read("org.kde.kdeglobals.General", "font")` and friends, and update
live on `General/font`.

xdg-desktop-portal-kde (`settings.cpp`) serves every kdeglobals group as
`org.kde.kdeglobals.<Group>`, each value as `KConfigGroup::readEntry`'s
**string**: colours `"r,g,b"`, fonts in `QFont::toString` form. On a
palette change it signals only `General/ColorScheme`. Marathon mirrors
both behaviours.

Qt picks a platform theme from `QT_QPA_PLATFORMTHEME`, then
`xdgdesktopportal` (in a sandbox), then `XDG_CURRENT_DESKTOP`
(`qgenericunixthemes.cpp`, `qguiapplication.cpp`). On Marathon
(`XDG_CURRENT_DESKTOP=marathon`), KDE's plugin (key `kde`) would never
load. The override therefore sets `QT_QPA_PLATFORMTHEME=kde`. Apps
without the plugin fall through to `xdgdesktopportal` as before.

KDE runtime check (host, `org.fedoraproject.KDE6Platform` f44): it ships
`KDEPlasmaPlatformTheme6.so`, `breeze6.so` and the `breeze` icons. Its
metadata already grants `xdg-config/kdeglobals:ro`.

**xdg-desktop-portal** (`src/settings.c`). It queries every backend
listed for Settings. Since 1.19.1, `ReadAll` merges results **per key,
with the first backend winning**. `Read` returns the first backend that
answers. With `org.freedesktop.impl.portal.Settings=marathon;gtk`,
Marathon's keys shadow xdg-desktop-portal-gtk's GSettings values, and the
GTK backend still answers every key Marathon doesn't serve. Before
1.19.1, results were concatenated. GTK applies duplicates in order, so
the GTK backend would win. **Requires xdg-desktop-portal ≥ 1.19.1**
(unchecked on the image).

**Flatpak** (`common/flatpak-context.c`, `flatpak-run.c`, `flatpak-dir.c`):

- `--filesystem=xdg-config/X` exposes the host path and also bind-mounts
  it at the app's own `$XDG_CONFIG_HOME/X` (`~/.var/app/ID/config/X`),
  so `xdg-config/gtk-4.0` makes `~/.config/gtk-4.0/gtk.css` the app's
  user stylesheet. Checked on the host with Blanket and VLC through
  `/proc/self/mountinfo`. The same holds for `xdg-data/X` and
  `$XDG_DATA_HOME/X`, so `xdg-data/themes` is where GTK 3 looks for user
  themes. The directory is bound **only if it exists when the app
  starts**. The shell creates both on its first ambience.
- Host `/usr/share/icons` and the fonts are always visible
  (`/run/host/share/icons`, `/run/host/fonts`). `/usr/share/themes` is
  not, and `/usr` can't be exposed. Flatpak's GTK 3 theme extensions
  (`org.gtk.Gtk3theme.*`, `download-if=active-gtk-theme`) only exist for
  themes published on a remote.
- Overrides live in `<installation>/overrides/global` (all apps) or
  `overrides/<app-id>`, in metadata keyfile format. The **system**
  overrides apply only to system-installed apps. The **user** overrides
  apply to every app the user runs. The Store installs `--user`, so both
  are linked.

## What Marathon serves

From the ambience (`/desktop/jolla/theme/color/highlight`, `color_scheme`):

- `org.freedesktop.appearance`: `color-scheme` (u), `accent-color`
  (ddd), the exact highlight.
- `org.gnome.desktop.interface`:
  - `color-scheme`: `prefer-dark`, `prefer-light` or `default`.
  - `gtk-theme`: `Marathon`/`Marathon-dark` once the shell has written
    them to `$XDG_DATA_HOME/themes`, else `Adwaita`/`Adwaita-dark`
    (built into every libgtk-3).
  - `icon-theme`: `Adwaita`. Marathon ships no freedesktop icon theme;
    its icon theme is a Silica theme.
  - `font-name`: `Source Sans 3 11`, Marathon's UI face.
  - `monospace-font-name`: `JetBrains Mono 10`.
  - `cursor-size`: 24.
  - `enable-animations`: true.
  - `accent-color`: the GNOME 47 name libadwaita's own hue split gives.
- `org.kde.kdeglobals.*`:
  - `Colors:Window/View/Button/Selection/Tooltip/Complementary/Header`:
    all twelve roles.
  - `WM`: colours and `activeFont`.
  - `General`: `ColorScheme=Marathon` and fonts.
  - `KDE`: `widgetStyle=Breeze`.
  - `Icons`: `Theme=breeze`, which the KDE runtime ships.

Colour derivation (`ToolkitTheme::palette`):

- Backgrounds are HSL tones of the highlight's hue at
  `min(0.22, 0.35 × saturation)`. Dark lightness runs 0.09–0.18 and light
  runs 0.91–0.99.
- Text, links and the negative/neutral/positive colours are moved in
  lightness until they reach at least 4.5:1 on every background. The test
  sweeps 384 highlights in both schemes.
- Text on the accent is black or white, whichever contrasts more. That is
  always at least 4.58:1.
- Complementary stays dark, as Breeze's does.

Files the shell writes on each ambience change, with `QSaveFile`. A file
is replaced only if it is absent or its first line is the Marathon
marker, so a user's own file is never replaced:

- `~/.config/gtk-4.0/gtk.css`: libadwaita's named colours as
  `@define-color` (≤1.5) and `:root` variables (1.6+). The current
  scheme's palette is at top level, so GTK below 4.20 gets it. Both
  palettes are also in `@media (prefers-color-scheme: dark|light)`
  blocks.
- `~/.local/share/themes/Marathon{,-dark}/gtk-3.0/gtk.css`: Adwaita's
  built-in `gtk-contained{,-dark}.css` plus Marathon's `@define-color`
  palette. Adwaita GTK 3 hard-codes its colours, so a handful of widget
  rules (window, headerbar, views, buttons, selection, links, sliders)
  use the named colours.

The GTK 3 and GTK 4 output was parsed by GTK 3.24.32 and GTK 4.22.5 in
the GNOME 50 runtime with zero errors. The D-Bus wire types (`u`,
`(ddd)`, `s`, `i`, `b`, `a{sa{sv}}`) and the signals were checked with
`gdbus` on a private bus.

## The Flatpak override

`/usr/share/marathon/flatpak-overrides` is linked by tmpfiles `L` to
`/var/lib/flatpak/overrides/global` and by user-tmpfiles to
`~/.local/share/flatpak/overrides/global`. `L` leaves an existing
override alone. `flatpak override --user` later replaces the link with
a merged file.

```ini
[Context]
filesystems=xdg-config/gtk-4.0:ro;xdg-data/themes:ro;

[Environment]
QT_QPA_PLATFORMTHEME=kde
```

- `xdg-config/gtk-4.0:ro`: libadwaita/GTK 4 read the ambience's colours
  from `gtk-4.0/gtk.css`. Read-only; the directory holds only GTK 4's
  user CSS and `settings.ini`.
- `xdg-data/themes:ro`: GTK 3 resolves `gtk-theme=Marathon[-dark]` from
  `$XDG_DATA_HOME/themes`. Read-only; exposes the user's themes, nothing
  else.
- `QT_QPA_PLATFORMTHEME=kde`: needed for the KDE platform theme, which is
  what reads `org.kde.kdeglobals.*`.

Not granted: `xdg-config/gtk-3.0`, since GTK 3 colours travel in the
theme. `xdg-config/kdeglobals` isn't granted either: the portal carries
it, and the KDE runtime grants it itself.

## Live versus restart

| Change | GTK 3 | libadwaita / GTK 4 | KDE (KDE runtime) |
|---|---|---|---|
| Light/dark flip | live (`gtk-theme` swap reloads the theme, written first) | live (portal `color-scheme`; `@media` picks the right palette on GTK ≥ 4.20) | live (`General/ColorScheme` → palette reload) |
| Accent | at restart (in the theme files) | live, snapped to a named accent; the exact accent from `gtk.css` at restart | live |
| Wallpaper-tinted backgrounds | at restart, or at the next scheme flip | at restart | live |
| Fonts, icons, style | live | live | live |

## Not done natively, or not done

- **libadwaita colours beyond the accent** have no portal key. They come
  from `gtk.css`, which GTK reads once, so they change at restart. The
  exact accent in `gtk.css` also overrides libadwaita's live named
  accent until then.
- **Plain GTK 4 apps** (no libadwaita) use GTK's Default theme. Its
  colours are compiled in, and nothing here recolours it beyond
  scheme and accent.
- **Native (non-Flatpak) GTK apps** read GSettings (dconf), not the
  portal, unless `GTK_USE_PORTAL=1` (GTK 3) or `GDK_DEBUG=portals`
  (GTK 4). `WaylandCompositor::launchApp` sets `GTK_USE_PORTAL=0` for
  native launches. Changing that is in `shell/src/wayland`, which is out
  of scope here. Native libadwaita does use the portal, and native GTK
  reads `~/.config/gtk-4.0/gtk.css` directly.
- **Native KDE apps** read `~/.config/kdeglobals`, which Marathon doesn't
  write. `Marathon.colors` is installed to `share/color-schemes` for them
  to select.
- **Not verified on a device:** the per-key merge needs
  xdg-desktop-portal ≥ 1.19.1 on the image. The user-tmpfiles link needs
  the user manager's `systemd-tmpfiles-setup.service`.

## Sources

- GTK 3 portal settings: https://gitlab.gnome.org/GNOME/gtk/-/blob/gtk-3-24/gdk/wayland/gdkscreen-wayland.c
- GTK 4 portal settings: https://gitlab.gnome.org/GNOME/gtk/-/blob/main/gdk/wayland/gdksettings-wayland.c
- GTK 4 user CSS: https://gitlab.gnome.org/GNOME/gtk/-/blob/main/gtk/gtksettings.c (`settings_init_style`)
- GTK 3 built-in Adwaita resources: https://gitlab.gnome.org/GNOME/gtk/-/blob/gtk-3-24/gtk/gen-gtk-gresources-xml.py
- libadwaita portal: https://gitlab.gnome.org/GNOME/libadwaita/-/blob/main/src/adw-settings-impl-portal.c
- libadwaita accents: https://gitlab.gnome.org/GNOME/libadwaita/-/blob/main/src/adw-accent-color.c
- libadwaita colours: https://gitlab.gnome.org/GNOME/libadwaita/-/blob/main/src/stylesheet/_colors.scss
- xdg-desktop-portal-kde: https://invent.kde.org/plasma/xdg-desktop-portal-kde/-/blob/master/src/settings.cpp
- plasma-integration: https://invent.kde.org/plasma/plasma-integration/-/tree/master/qt6/src/platformtheme
- Qt theme selection: https://github.com/qt/qtbase/blob/6.8/src/gui/kernel/qguiapplication.cpp, https://github.com/qt/qtbase/blob/6.8/src/gui/platform/unix/qgenericunixthemes.cpp
- xdg-desktop-portal merge (1.19.1+): https://github.com/flatpak/xdg-desktop-portal/blob/1.20.0/src/settings.c
- Flatpak filesystem binds and overrides: https://github.com/flatpak/flatpak/blob/main/common/flatpak-context.c, https://github.com/flatpak/flatpak/blob/main/common/flatpak-dir.c, https://github.com/flatpak/flatpak/blob/main/common/flatpak-run.c
