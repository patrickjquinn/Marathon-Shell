<!--
SPDX-FileCopyrightText: 2026 Patrick Quinn
SPDX-License-Identifier: MIT
-->

# nemo-compat provenance

The Nemo QML plugins built here are open source. Keel builds the upstream code
for Qt6 rather than rewriting it (docs/plan.md, "Licensing and provenance":
contribute rather than duplicate). Upstream files keep their licence headers;
the full upstream licence texts are in `upstream-licenses/`.

| Directory | Upstream | Commit (fetched 2026-09-30) | Licence |
| --- | --- | --- | --- |
| `dbus/` (plugin: `plugin.cpp`, `declarativedbus*`) | github.com/sailfishos/nemo-qml-plugin-dbus `src/plugin/` | `df6e2415fe70e1844067f93b3216ca0442f17c8e` | LGPL-2.1-only |
| `dbus/nemo-dbus/` | same repository, `src/nemo-dbus/` | same | BSD-3-Clause |
| `notifications/` | github.com/sailfishos/nemo-qml-plugin-notifications `src/`, `src/plugin/plugin.cpp` | `e8df68e100c260078e7766d8fe45b40f4337f9a8` | BSD-3-Clause |
| `keepalive/` (except `compat/`) | github.com/sailfishos/nemo-keepalive `plugin/` and `lib/` | `c38d05b5ebc871dc36561abaf9bbf1dfb8438e83` | LGPL-2.1-only |
| `configuration/` (except `compat/`) | github.com/sailfishos/nemo-qml-plugin-configuration `src/` (fetched 2026-10-01) | `b8ff8957f7ed9d2e3fceffc782434f2609768686` | BSD-3-Clause (`LICENSE.BSD`) |
| `configuration/compat/mdconfgroup.h`, `mdconfitem.h` | github.com/sailfishos/mlite `src/` (fetched 2026-10-01) | `42c3b2102dadfc54a2cc7c87c6e4cfb28437c908` | LGPL-2.1-only |
| `ngf/client/`, `ngf/declarative/` | github.com/sailfishos/libngf-qt `src/include/`, `src/dbus/`, `declarative/src/` (fetched 2026-10-01) | `94caafdbc31341e9b9834199aedaa0c5f4a7bd44` | LGPL-2.1-only (`COPYING`) |
| `configuration/compat/mdconfgroup.cpp` | adapted from the same mlite commit, `src/mdconfgroup.cpp` | same | LGPL-2.1-only |
| `policy/plugin/` | github.com/sailfishos/nemo-qml-plugin-policy `src/`, tag `0.1.5` (fetched 2026-10-02) | `ad01a673e8b62dfe6da9e8ed9ca8103f5666bda6` | BSD-3-Clause (`LICENSE.BSD`) |
| `lipstick/upstream/` | github.com/sailfishos/lipstick `src/components/launcher{item,model,monitor,watchermodel,foldermodel,folderitem,dbus}.*`, `src/utilities/qobjectlistmodel.*`, `src/3rdparty/synchronizelists.h`, `src/lipstickglobal.h`, `src/lipstickdbus.h`, `src/logging.*` (fetched 2026-10-02) | `af4abc107119c9520b1e46549a103e684dc7ed2e` | LGPL-2.1-only (`upstream-licenses/lipstick.LICENSE.LGPL`); `synchronizelists.h` BSD-3-Clause |
| `lipstick/mlite/mdesktopentry*`, `mremoteaction*` | github.com/sailfishos/mlite `src/`, tag `0.5.5` (fetched 2026-10-02) | `42c3b2102dadfc54a2cc7c87c6e4cfb28437c908` | LGPL-2.1-only (`upstream-licenses/mlite.license.lgpl`) |
| `policy/libresourceqt/` | github.com/sailfishos/libresourceqt `libresourceqt/include/policy/`, `libresourceqt/src/` (all but the engine), tag `1.33.0` (fetched 2026-10-02) | `142b512f9de840bb7855415885cb6e8f1f09e08c` | LGPL-2.1-only (`COPYING`) |

Nemo.Configuration on the device: Chum's `chum:testing` for 5.2 ships
`mlite-qt6` 0.5.5 (with `-devel`, pkg-config `mlite6`) and its own
`nemo-qml-plugin-configuration-qt6` 0.2.10. Keel's spec builds the upstream
plugin unchanged against `mlite6` (`KEEL_REQUIRE_MLITE=ON`), so device
settings are real dconf keys shared with Silica apps and system settings;
the `-configuration` subpackage conflicts with Chum's plugin, which installs
the same `Nemo/Configuration/libnemoconfiguration.so`, and the main package
accepts either. Keel adds the legacy `org.nemomobile.configuration` qmldir.

Hosts without `mlite6` (the development host, CI) compile
`configuration/compat/` instead: mlite's two public headers unchanged, an
`MDConfGroup` adapted from mlite (property binding, scopes and paths as
upstream; the DConfClient replaced by Keel's store), and Keel's own
`MDConfItem` and `KeelDConfStore`, which keep the keys in one JSON file
(`$XDG_CONFIG_HOME/keel/dconf.json`, or `KEEL_DCONF_FILE`) and pick up other
processes' writes through a file watch. That is a documented fallback, not
dconf: values do not reach other dconf users, and JSON loses the int/double
distinction of whole numbers unless the reader passes a type hint. An
unreadable file is never overwritten: the store logs it and renames it to
`dconf.json.corrupt` (or `.corrupt.<n>`) before its next write, and a write
that cannot be saved returns false and keeps the value in memory
(`tests/tst_dconfstore.cpp`).

Upstream already carries Qt 6 conditionals. Chum's `chum:testing` for 5.2
ships `nemo-qml-plugin-dbus-qt6` 2.1.39, built from the same repository; it
installs the same `Nemo/DBus/libnemodbus.so`, hence the `-dbus` subpackage
split in `keel/rpm/shipwright-keel-nemo-compat.spec`.

org.nemomobile.lipstick: lipstick's launcher types (`LauncherItem`,
`LauncherModel`, `LauncherWatcherModel`, `LauncherFolderModel`,
`LauncherFolderItem`, with `LauncherMonitor`, `LauncherDBus` and
`QObjectListModel` behind them) built for Qt 6 and registered as lipstick's
own plugin registers them (the two models start once QML has set their
properties, as lipstick's `LauncherModelType`/`LauncherFolderModelType`
do; `plugin.cpp` is Keel's). mlite's `MDesktopEntry` and `MRemoteAction`
(which upstream builds for Qt 6 too) are compiled in, so the plugin does not
need Chum's mlite-qt6 at run time. Without contentaction (Qt 5 only) the
items launch through GIO's `GDesktopAppInfo`, lipstick's own path when it is
built without contentaction. One Qt 6 change, marked in
`launcheritem.cpp`: `Qt::SkipEmptyParts`. The other types of lipstick's
plugin (compositor, windows, notification list, volume, USB mode, shutdown,
screenshots, keymap) live in the home screen's process and are not
provided. In an app process `LauncherDBus` registers lipstick's
`/LauncherModel` object on the app's own connection, where nobody calls it:
package-update progress (`isUpdating`) reaches lipstick, not apps.

Nemo.Policy: nemo-qml-plugin-policy's `Permissions` and `Resource` over
libresourceqt's `ResourcePolicy::ResourceSet` and resource classes (5.2
ships both as nemo-qml-plugin-policy-qt5 and libresourceqt-qt5 1.33),
compiled into one plugin. libresourceqt's `ResourceEngine` is the only part
not taken: upstream's goes through libresource (C) and libdbus-qeventloop,
neither of which has a Qt 6 or host build here. Keel's
`policy/engine/resource-engine.*` keeps its class interface (which
`resource-set.cpp` uses) and speaks the resource policy manager's D-Bus
protocol with QtDBus: the manager is `org.maemo.resource.manager` on the
system bus (Sailfish's ohmd), the messages and their argument lists, the
status reply, the manager's `grant` / `advice` / `release` / `unregister`
calls to `/org/maemo/resource/client<id>`, the resource and mode bits and
the application id (the process start time in hex) were taken from
libresource 0.25.2 (github.com/sailfishos/libresource, LGPL-2.1,
`src/dbus-msg.c`, `src/dbus-proto.*`, `src/res-msg.h`, `src/res-types.h`,
`src/res-msg.c`) as a protocol description; no libresource or
libresourceqt engine code is copied. How replies map to the ResourceSet's
signals (a grant of nothing answering an update, acquire or release, or
answering no request) follows libresourceqt's documented behaviour. When no
manager owns its name (development hosts, CI, a device without ohmd), the
engine answers each request itself and grants every resource, the old
stand-in's behaviour; a manager that appears later gets the set registered
and re-acquired. `tests/tst_policy.cpp` runs the QML types against a fake
manager on the private bus. Needs device verification: that ohmd grants a
sandboxed Keel app's set (Sailjail must let the app reach the manager, as it
does for Qt 5 apps through libresource), and that ohmd matches the
application id to the app's audio streams.

Nemo.Ngf on the device: libngf-qt's QML plugin (`NonGraphicalFeedback`,
`NgfProperty`) with its `Ngf::Client` compiled into the plugin library, as
the nemo-dbus helpers are. The upstream code already carries the Qt 6
conditionals and is built unchanged. It calls ngfd on the system bus
(`com.nokia.NonGraphicFeedback1.Backend`, object
`/com/nokia/NonGraphicFeedback1`: `Play(s, a{sv}) -> u`, `Pause(u, b)`,
`Stop(u)`, signal `Status(u, u)`), the same protocol the Qt 5 plugin uses;
ngfd itself is not Qt. `tests/tst_nemocompat.cpp` runs it against a fake
ngfd on the private test bus. Chum ships no Qt 6 build of libngf-qt, so
there is no package conflict. Until 2026-10-01 Keel had a silent QML
stand-in here; it is gone.

## Keel changes to upstream files

Each changed file says so under its licence header.

1. `dbus/nemo-dbus/dbus.cpp`, `demarshallDBusArgument()`: under Qt 6,
   `QVariant::typeId()` always equals `userType()`, so upstream's "already a
   built-in type" test matched everything and `QDBusVariant` / `QDBusArgument`
   values reached QML unconverted (for example `DBusInterface.getProperty()`
   returned an empty `QDBusVariant`). Keel tests `type < QMetaType::User`.
   To be offered upstream (this likely affects Chum's package too).
2. `dbus/declarativedbusadaptor.cpp`, `Properties.Get`: the reply now wraps
   the value in a `QDBusVariant`, as the D-Bus specification requires (`v`);
   upstream sent the bare value, which QtDBus clients reject ("got s,
   expected v"). To be offered upstream.
3. `keepalive/plugin.cpp`: also registers the legacy `org.nemomobile.keepalive`
   URI (1.0 with `KeepAlive` and `DisplayBlanking` as singletons, as the old
   import was used; 1.1 as `Nemo.KeepAlive` 1.1).
4. `configuration/compat/mdconfgroup.cpp` (from mlite): see above; the
   configuration plugin's own files are unchanged apart from SPDX headers.
5. `policy/plugin/permissions.*`: `QQmlListProperty` count and index are
   `qsizetype` in Qt 6.
6. `policy/plugin/resource.cpp`: `m_resource` was left uninitialised and is
   read by `updateAcquired()` for a resource that never joined the set (one
   with `required: false`); it starts as null.
7. `policy/libresourceqt/src/resource-set.cpp`: two debug format arguments
   cast from `qsizetype` to `int`.

No other upstream file is modified (SPDX header lines were added to the
copied files). `nemo-dbus/README`, the `.pro` files and
upstream's `plugins.qmltypes` (Qt5 `qmlplugindump` output) were not copied.

## Keel's own files

Shipwright-licensed, written for Keel:

- `CMakeLists.txt`, `qmldir/*`: build and module layout. The legacy URI
  directories contain only a `qmldir` whose `plugin` line points at the
  library in the `Nemo/...` directory; the upstream plugins accept both URIs.
- `keepalive/compat/iphbd/libiphb.h`, `keepalive/compat/iphb_fallback.cpp`: a
  timer stand-in for libiphb on hosts without DSME, written against the
  function names and signatures of libiphb's public header. Device builds link
  the real libiphb (`KEEL_REQUIRE_IPHB=ON` in the spec). A wait fires after
  `mintime`, or after `maxtime` when `mintime` is 0, never at once
  (`tests/tst_iphbfallback.cpp`).
- `keepalive/compat/mce/*.h`: the six MCE D-Bus names and display state
  strings nemo-keepalive uses, for hosts without `mce-headers`. The values are
  MCE's public D-Bus API. Device builds use `mce-headers`.
- `tests/*`: fake Notifications / MCE / echo services and the test suite.
- `configuration/compat/keeldconfstore.*`, `mdconfitem.cpp`,
  `mlite-global.h`, `MDConfGroup`, `MDConfItem`: the host fallback store
  described above, written for Keel against mlite's public API.
- `lipstick/plugin.cpp`, `lipstick/mlite/mlite-global.h`,
  `lipstick/mlite/logging.*`: Keel's plugin for lipstick's launcher types
  and stand-ins for mlite's export macro and logging category. Until
  2026-10-02 `lipstick/` held Keel's own read-only `LauncherItem`; it is
  gone.
- `policy/engine/*`: the resource policy engine described above. Until
  2026-10-02 `policy/` held a grant-always QML stand-in; it is gone.
