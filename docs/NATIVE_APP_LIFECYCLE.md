# Native app lifecycle

How Marathon drives native Wayland apps (GTK 3, GTK 4 / libadwaita, Qt / KDE,
browsers; usually Flatpaks) with the gesture bar and the lifecycle that
Marathon's own apps get over D-Bus. Marathon apps answer `Back` through
`org.marathonos.AppRunner.Lifecycle1`; a native app has no such channel, so
the shell uses what each toolkit already listens to.

Code: `shell/src/wayland/nativeback.h`, `WaylandCompositor::sendNativeBack`,
`crates/marathon-shell-native/src/cgroup.rs`, `tasks/lifecycle.rs` (`transition`),
`tasks/launch.rs` (`activate_running`).

## Back

### What each toolkit treats as back

| Toolkit | Back inputs it handles | Source |
|---|---|---|
| libadwaita `AdwNavigationView` (also inside `AdwNavigationSplitView` when collapsed) | **Escape** (unless `pop-on-escape` is false), **XF86Back**, Alt+Left, mouse back (button 8), swipe | [adw-navigation-view.c](https://gitlab.gnome.org/GNOME/libadwaita/-/blob/main/src/adw-navigation-view.c) (`gtk_widget_class_add_binding` for `GDK_KEY_Escape`/`GDK_KEY_Back`/Alt+Left; `back_forward_button_pressed_cb` for buttons 8/9); [docs](https://gnome.pages.gitlab.gnome.org/libadwaita/doc/main/class.NavigationView.html#shortcuts-and-gestures) |
| libadwaita `AdwDialog` (in-window sheet) | **Escape** | [adw-dialog.c](https://gitlab.gnome.org/GNOME/libadwaita/-/blob/main/src/adw-dialog.c) ("Esc to close") |
| GTK 4 `GtkPopover`, `GtkSearchBar` | Escape | GTK 4 |
| libhandy `HdyLeaflet` (GTK 3) | swipe only (`can-swipe-back`); no key or button binding | [hdy-leaflet.c](https://gitlab.gnome.org/GNOME/libhandy/-/blob/main/src/hdy-leaflet.c) |
| Kirigami `PageRow` | `StandardKey.Back` = **XF86Back** (all platforms) and Alt+Left (Linux); Escape only closes dialog layers | [PageRow.qml](https://invent.kde.org/frameworks/kirigami/-/blob/master/src/controls/PageRow.qml) `Shortcut { sequences: [StandardKey.Back] }`; [qplatformtheme.cpp](https://github.com/qt/qtbase/blob/6.10/src/gui/kernel/qplatformtheme.cpp) key bindings |
| Qt Quick Controls `Popup`/`Dialog`, Qt Widgets `QDialog` | Escape | Qt |
| Chromium / Firefox | XF86Back, Alt+Left, mouse back | |

Wayland mouse buttons are evdev codes: BTN_SIDE 0x113 (back, GDK button 8,
`Qt::BackButton`), BTN_EXTRA 0x114 (forward); QtWaylandCompositor maps
`Qt::ExtraButton1/2` to them ([qwaylandpointer.cpp](https://github.com/qt/qtwayland/blob/6.10/src/compositor/compositor_api/qwaylandpointer.cpp) `toWaylandButton`).

### What Marathon sends

1. **Transient UI first, through the protocol.** If the app has a mapped
   `xdg_popup` (menu, popover), the newest gets `popup_done`. Otherwise, if it
   has a mapped child `xdg_toplevel` (one with a parent: a GTK 3 or Qt dialog
   window), the newest gets `close`. Neither depends on which widget has
   keyboard focus.
2. **Otherwise one key, picked per toolkit** from the libraries mapped into
   the client (`/proc/<pid>/maps`, read once per window; works for Flatpaks,
   whose runtime libraries show at their sandbox paths):
   - GTK 4 / libadwaita and Keel-hosted apps: **Escape**. It pops an
     `AdwNavigationView` page *and* closes an `AdwDialog` sheet or a search
     bar, which XF86Back does not. An Escape nothing uses changes nothing:
     GTK 4 turns focus-visible back off on release when focus did not move.
   - GTK 3, Qt (Kirigami, Widgets, Quick), unknown (Electron, Firefox, SDL):
     **XF86Back**. GTK 3 and Qt do not navigate on Escape.
   - Qt's gtk3 platform theme maps libgtk-3 into Qt apps, so Qt is checked
     before GTK 3.

   The keyboard is used rather than the mouse back button: a button needs
   pointer focus, i.e. a `wl_pointer.enter` at some position (hover effects,
   and GTK's button-0 gestures at that spot), on a seat that is otherwise
   touch-only. XF86Back (keycode 166) and Escape are in the default xkb
   keymap the compositor serves. The compositor gives the app's window
   keyboard focus first if another client holds it.
3. **Forward** is XF86Forward (Alt+Right for Keel-hosted apps, as before).
   libadwaita pushes on it only if the app implements `get-next-page`.

### Unhandled detection

Wayland has no reply to a key. After sending back the compositor watches the
app for `MARATHON_NATIVE_BACK_MS` (default 350 ms). It counts as **handled**
on the first of:

- a commit to the window whose damage covers at least a tenth of it (a page
  transition, a sheet or a search bar going away); a spinner, a caret or a
  level meter stays below that (`NativeBack::visibleChange`);
- the window's title changing;
- any surface of the same client being created, mapping, unmapping or being
  destroyed (popup closed, dialog closed, the window itself closed).

Otherwise the compositor emits `nativeBackUnhandled(surfaceId)`; the
lifecycle turns it into `systemBackUnhandled` if that window still belongs to
the foreground app, and `MarathonShell.qml` backs out of the app exactly as
for a Marathon app's refusal.

Known limits: a window that repaints most of itself continuously (a video, a
game, a Qt Quick animation; Qt clients damage the whole buffer) always reads
as handled, so back never leaves it: the old behaviour, and home still works.
An in-window Qt Quick `Popup` (Kirigami.Dialog) closes on Escape, not on
XF86Back, so for Qt apps back skips it and goes to the page beneath.

## Lifecycle

### Where a native app's processes are

- `flatpak run` moves itself into a transient
  `app-flatpak-<id>-<instance>.scope` under the user manager before it
  spawns `xdg-dbus-proxy` and execs `bwrap`, so the whole instance, proxy
  included, is in that scope
  ([flatpak-run.c](https://github.com/flatpak/flatpak/blob/main/common/flatpak-run.c),
  `flatpak_run_in_transient_unit`).
- Desktop launchers use `app-<launcher>-<id>-<random>.scope`
  ([systemd.io/DESKTOP_ENVIRONMENTS](https://systemd.io/DESKTOP_ENVIRONMENTS/)).
- A native app the shell spawns directly starts in the shell's own
  `marathon-shell-*.scope`.

### What Marathon does

Native apps go through the same states as Marathon apps (Foreground,
BackgroundActive, BackgroundIdle, Frozen), the same 10 s idle-freeze
debounce, the same capability rule (an app holding `audio-playback` through
MPRIS stays BackgroundActive; a sandboxed player is matched by its MPRIS
`DesktopEntry`, since its bus connection is the proxy's) and the same
`oom_score_adj` ladder. The pid comes from the window's Wayland client.

- **App in an `app-*.scope`**: left there. Frozen and thawed with
  `org.freedesktop.systemd1.Manager.FreezeUnit/ThawUnit` on the session bus
  (the user manager), asynchronously
  ([org.freedesktop.systemd1](https://www.freedesktop.org/software/systemd/man/latest/org.freedesktop.systemd1.html)).
  The scope's cgroup belongs to the user manager, not to the subtree
  delegated to the shell ([CGROUP_DELEGATION](https://systemd.io/CGROUP_DELEGATION/)),
  so the shell does not write its `cgroup.freeze`, and does not move the
  app out of it: that left bwrap and the proxy running and emptied systemd's
  view of the instance. No `cpu.uclamp.min` boost for these.
- **App in the shell's scope**: moved into
  `marathon.slice/marathon-apps/marathon-app-<id>` and frozen there, like a
  runner.
- **Never the shell**: the shell's own cgroup and its ancestors never count
  as an app scope (a dev shell run from a terminal lives in the terminal's
  `app-*.scope`).
- **Thaw before input**: back and forward only go to the foreground app,
  which is never frozen; close, the memory-pressure kill and session stop
  thaw first. A frozen app's queued Wayland events and signals are delivered
  on thaw.

A frozen Flatpak's D-Bus proxy is frozen with it, so a call to the app waits
until it is thawed. The shell's own calls to apps (MPRIS) are asynchronous.

### xdg_toplevel `suspended`

xdg-shell v6 adds `suspended` (state 9); GTK 4 stops its frame clock on it
([gdktoplevel-wayland.c](https://gitlab.gnome.org/GNOME/gtk/-/blob/main/gdk/wayland/gdktoplevel-wayland.c)
`XDG_TOPLEVEL_STATE_SUSPENDED`). QtWaylandCompositor 6.11's public
`QWaylandXdgToplevel::State` stops at `ActivatedState`, and
`QWaylandXdgShell::initialize()` creates the `xdg_wm_base` global at
**version 1** ([qwaylandxdgshell.cpp](https://github.com/qt/qtwayland/blob/6.11/src/compositor/extensions/qwaylandxdgshell.cpp)
`d->init(compositor->display(), 1)`), so clients never bind v6 and the state
is not part of their protocol. `WaylandCompositor::sendSuspendedState` exists
but nothing calls it; using it properly needs the global advertised at v6
(a Qt patch or our own xdg_wm_base). Freezing does not depend on it, and
until an app is frozen the hidden-surface frame throttle already holds a
background window to about one frame a second.

## Activation

A running app with no window (closed to the background, e.g. a radio still
playing, or still starting) is asked for one with
`org.freedesktop.Application.Activate` on its desktop id, at the object path
the id maps to (`/de/haeckerfelix/Shortwave`), with auto-start off, after
waking it if frozen. Starting `flatpak run` again would cost a new sandbox
only for GApplication to hand off to the running instance and exit.
A `DBusActivatable=true` app must own that name
([Desktop Entry spec, D-Bus Activation](https://specifications.freedesktop.org/desktop-entry-spec/latest/dbus.html));
GApplication ([gapplicationimpl-dbus.c](https://gitlab.gnome.org/GNOME/glib/-/blob/main/gio/gapplicationimpl-dbus.c))
and KDBusService export the interface whether or not the desktop file says
so. Any error (no owner, no interface) falls back to starting the app as
before. `org.gtk.Actions` exports only `app.*` and `win.*` actions; a widget
action such as `navigation.pop` is not on the bus, so it is no route for back.
