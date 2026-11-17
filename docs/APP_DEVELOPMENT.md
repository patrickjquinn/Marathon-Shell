# Writing a Marathon app

Marathon apps are QML on Keel: Sailfish Silica for Qt 6, with Marathon's own
controls on top. Each app runs in its own `marathon-app-runner` process and
talks to the system over D-Bus. This guide covers apps built in this
repository; `apps/template` is the smallest complete one and `apps/radio` a
full one (a D-Bus service, Keel actions, a shader, a cover).

House rules for all code here: [CODING_RULES.md](CODING_RULES.md).

## What you need

- Qt 6 with Qt Declarative and Qt Shader Tools (`qsb`, `qmlformat`,
  `qmltestrunner`).
- Keel's `Sailfish.Silica` QML modules for the tests: a Keel build or the
  keel-silica package. `KEEL_QML` names its `qml` directory.
- For trying an app on a phone: a development image built with your SSH key
  (`MARATHON_DEV_SSH_KEY`, see [BUILDING.md](BUILDING.md)).

## Create an app

```sh
scripts/new-app weather "Weather"
```

This copies `apps/template` to `apps/weather`, renames its files and
identifiers (`WeatherApp.qml`, `cover/WeatherCover.qml`, module
`MarathonApp.Weather`, settings under `/apps/weather/`) and adds
`add_subdirectory(weather)` to `apps/CMakeLists.txt`. The ID is lowercase
letters, digits and `-`; the name must start with a capital letter, since it
names the QML types.

## Layout

```
apps/weather/
  CMakeLists.txt        add_marathon_app(); install_keel_actions() if it has actions
  manifest.json
  WeatherApp.qml        entry point: ApplicationWindow with appId, initialPage, cover
  pages/                one Page per screen
  components/           the app's own items
  cover/WeatherCover.qml
  assets/icon.svg       and any images (installed with the app)
  shaders/              *.frag / *.vert and their baked .qsb
  tests/                run.sh and tst_*.qml (qmltestrunner)
```

Every `.qml` and `.js` file outside `tests/` goes into the app's QML module
(the `file(GLOB_RECURSE ...)` in the template's CMakeLists.txt). Other files
the QML loads by URL go in `RESOURCES`, as `apps/radio/CMakeLists.txt` does
for `assets/land.png`. Native code, when an app needs it, goes in `SOURCES`
of `add_marathon_app` (types registered with `QML_ELEMENT`); keep it to what
QML cannot do (CODING_RULES C10).

## manifest.json

The schema is `schemas/marathon-app-manifest-v1.schema.json`; the rules it
cannot express are in [APP_MANIFEST_SCHEMA.md](APP_MANIFEST_SCHEMA.md).

| Field | |
| --- | --- |
| `id` | The app id: install directory, Wayland app_id, `appId` in QML, settings prefix `/apps/<id>/`, D-Bus name `org.marathonos.<id>`. Single words are reserved for Marathon's own apps; an app shipped outside Marathon uses a reverse-DNS id. |
| `name` | Shown on the home grid and in search. |
| `entryPoint` | The root QML file, e.g. `WeatherApp.qml`. |
| `icon` | `assets/icon.svg`. |
| `permissions` | What the app may use. See below. |
| `permissionReasons` | Why the app needs each sensitive permission, in words shown to the user. |
| `categories` | Any of `Communication`, `Productivity`, `Entertainment`, `Utility`, `System`. |
| `searchKeywords` | Words that should find the app in search, besides its name. |
| `testedOn` | Window widths and input modes (`touch`, `keyboard`, `pointer`) the tests cover. |
| `dataLifecycle` | Whether the app's data stays after an uninstall (`appData`: `remove` or `keep`). |

Permission names, from `schemas/marathon-permissions-v1.json`:

| Permission | Sensitive | |
| --- | --- | --- |
| `network` | | Internet and local network |
| `notifications` | | Show notifications |
| `alarms` | | Set alarms and timers |
| `sensors` | | Motion and light sensors |
| `location` | yes | Where the device is |
| `camera` | yes | Photos and video |
| `microphone` | yes | Record audio |
| `contacts` | yes | Read and change contacts |
| `calendar` | yes | Read and change calendar events |
| `storage` | yes | Photos, music, videos, documents, downloads |
| `telephony` | yes | Calls and call history |
| `sms` | yes | Send and read SMS |
| `bluetooth` | yes | Bluetooth devices |
| `secret-service` | yes | The keyring (also needs `dataLifecycle.secrets`) |
| `system` | restricted | Device settings; Marathon's own system apps only |
| `terminal` | restricted | Full system access; Marathon's own system apps only |

Check a manifest with `marathon-dev lint` (`--system-app` for Marathon's own
apps, which may use single-word ids):

```sh
cd crates && cargo run -q -p marathon-apps --bin marathon-dev -- lint --system-app ../apps/weather
```

## UI: Keel and Silica

Every QML file imports Silica and then Marathon's controls, in this order
(`tests/lint/check-silica-imports.sh` checks it):

```qml
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
```

- The root is `ApplicationWindow` with `appId`, `initialPage` and `cover`.
  It handles back (pops a page, else minimises).
- Screens are `Page`s; scrolling content is `SilicaListView` /
  `SilicaFlickable` with a `PageHeader` as the header.
- Actions go in a `PullDownMenu` (or `PushUpMenu`), not toolbars or floating
  buttons. Rows are `ListItem`, with a `ContextMenu` for per-row actions.
- Deletes use remorse (`ListItem.remorseDelete`, `RemorsePopup`), not a
  confirmation dialog. Empty lists show a `ViewPlaceholder`.
- Sizes, colours and fonts come from `Theme`: `Theme.horizontalPageMargin`,
  `Theme.paddingLarge`, `Theme.itemSizeMedium`, `Theme.fontSizeMedium`,
  `Theme.primaryColor`, `Theme.highlightColor`. No hex colours or pixel sizes.
- The cover (`CoverBackground`) shows a few lines of state at most and one
  or two `CoverAction`s. See `apps/template/cover/` and `apps/notes/cover/`.
- App state: `Nemo.Configuration`'s `ConfigurationValue { key: "/apps/<id>/..." }`.
  Notifications: `Nemo.Notifications`. Platform services (contacts, location,
  network, alarms and more): `import Marathon.Platform 1.0`.
- Custom interactive items set `Accessible.role` and `Accessible.name` and
  take keyboard focus.

`apps/template/pages/MainPage.qml` shows most of this in one page.
[KEEL_APP_MIGRATION.md](KEEL_APP_MIGRATION.md) has the full rules and a
table of Silica equivalents; [UI_DESIGN_SYSTEM.md](UI_DESIGN_SYSTEM.md) is the
shell's design language, which apps should sit in.

## Talking to a system service

Services are D-Bus daemons on the session bus (Marathon's own are in
`crates/`, added with `marathon_daemon()` in `crates/CMakeLists.txt`). Wrap
one in a single QML file that exposes its state as properties and its methods
as functions, as `apps/radio/RadioService.qml` does with `Nemo.DBus 2.0`'s
`DBusInterface`:

```qml
import QtQuick
import Nemo.DBus 2.0

Item {
    id: radio

    property var state: ({})
    readonly property bool playing: state.playing === true

    function refresh() {
        bus.call("GetState", [], s => radio.state = s);
    }

    // Arguments of other D-Bus types than the defaults go through typedCall.
    function tune(khz) {
        bus.typedCall("Tune", [{ "type": "i", "value": khz }]);
    }

    // Answers arrive later, so a method that returns something takes a
    // callback; the error callback keeps the caller from waiting forever.
    function search(text, done) {
        bus.typedCall("Search", [{ "type": "s", "value": text }], done, () => done([]));
    }

    DBusInterface {
        id: bus

        // The StateChanged signal: a function named after it, lower camel case.
        function stateChanged(s) {
            radio.state = s;
        }

        service: "org.marathonos.Radio"
        path: "/org/marathonos/Radio"
        iface: "org.marathonos.Radio1"
        signalsEnabled: true
        Component.onCompleted: radio.refresh()
    }
}
```

Create it once in the root file and hand it to pages and the cover
(`RadioService { id: radioService }`, then `radio: radioService`).

Gotcha: inside `DBusInterface`, `service`, `path` and `iface` are its own
properties. Code there that means an outer item with the id `service` gets
the bus name string instead, so don't give the wrapper that id (Radio's is
`radio`, the interface `bus`).

Daemons that hold the user's data ask the shell whether the calling app holds
a permission (`Permissions1.Admit`); MediaLibrary, for one, wants `storage`.
List what your app needs in the manifest.

## Keel actions for Pilot

Actions let Pilot and other assistants use the app ("play Radio Nova",
"find jazz stations"). Declare them with `Keel.Actions 1.0`, one `KeelAction`
per action, in a file such as `RadioActions.qml` (see
`apps/radio/RadioActions.qml` and `apps/music/MusicActions.qml`):

```qml
import QtQuick
import Keel.Actions 1.0

Item {
    id: root

    property var radio

    KeelAction {
        name: "radio.stop"
        title: qsTr("Stop the radio")
        description: "Stop the radio, if it is playing."
        idempotent: true
        onInvoked: (args, call) => {
            root.radio.stop();
            call.reply(null);
        }
    }
}
```

`description` is what the model reads: say what the action does, what its
parameters mean and what it returns. Parameters are `KeelParam`s with types
and limits; results are a `KeelResult`. Answer with `call.reply(value)` or
`call.fail("NotAvailable", "why")`. Create the actions item in the root file
(`RadioActions { radio: radioService }`).

Regenerate the manifest whenever a declaration changes, from `crates/`:

```sh
cd crates && cargo run -q -p keel-actions-codegen --bin keel-actions -- \
    --qml ../apps/radio/RadioActions.qml --app-id org.marathonos.radio \
    --out ../apps/radio/keel-actions.json
```

With `--check` it compares instead of writing and fails when the file is
stale. Commit `keel-actions.json` and install it from the app's
CMakeLists.txt:

```cmake
install_keel_actions(${APP_NAME} keel-actions.json)
```

That installs it as `share/keel/actions/org.marathonos.<id>.json` with a
D-Bus activation file, so a call can start the app. The runner turns actions
on only when that file is there as the app starts; `scripts/app-push`
installs it too.

## Shaders

Write GLSL 440 in `shaders/*.frag` (and `*.vert`), in the form Qt Quick's
`ShaderEffect` expects (see `apps/radio/shaders/globe.frag`). Bake them:

```sh
scripts/bake-shaders apps/radio/shaders
```

This writes `globe.frag.qsb` next to the source, for GLSL ES 100 and 300 (the
phones' GPUs) and GLSL 120/150 (desktop GL). Commit both files: device builds
have no `qsb`. `add_marathon_app` puts every `shaders/*.qsb` into the module,
so refer to it by a URL relative to the QML file:

```qml
ShaderEffect {
    fragmentShader: Qt.resolvedUrl("../shaders/globe.frag.qsb")
}
```

Gate an animation that drives a shader on visibility (CODING_RULES C8).

## App icon

Icons are drawn by `scripts/build-app-icons.py` on one shared frame; the
spec is `docs/design/app-icon-spec.md`. The square corners name the category
(`COMMS`, `PLACES`, `MEDIA`, `TIME`, `TOOLS`); hues are in
`docs/design/colour-palette.md`. To add one, write a draw function next to
the others and an entry in `ICONS`:

```python
    "weather": ("Weather: a cloud", 210.0, TIME, weather),
```

Then run it with picosvg, naming the app (or nothing, for every app):

```sh
python3 -m venv /tmp/v && /tmp/v/bin/pip install picosvg
/tmp/v/bin/python3 scripts/build-app-icons.py weather
```

It writes `apps/weather/assets/icon.svg`.

## On a phone

`scripts/app-push` copies an app's QML, scripts, assets and baked shaders to
a development phone and restarts the app. The runner loads the entry QML
from the app's directory, so a QML change shows in seconds, without a
package build.

```sh
scripts/app-push radio              # push apps/radio and restart it
scripts/app-push --restore radio    # remove the pushed files; the installed build runs again
```

`MARATHON_DEVICE` is the phone as ssh reaches it (default `root@172.16.42.1`,
the USB network); `MARATHON_SSH_OPTS` adds ssh options:

```sh
MARATHON_DEVICE=root@192.168.1.40 MARATHON_SSH_OPTS="-i $HOME/.ssh/id_ed25519" scripts/app-push radio
```

It needs a writable root, as development images have. It also installs the
app's `keel-actions.json` (`--restore` puts the packaged one back). Native
code (`SOURCES`) and daemons are not pushed: those need a package build. The shell reads its list of apps when it starts, so an
app the phone has never had needs an installed build, or a shell restart
after the first push, before app-push can launch it.

## Tests

Each app has a qmltestrunner suite in `tests/`:

```sh
KEEL_QML=<Keel qml dir> sh apps/weather/tests/run.sh
```

The template's `tests/tst_templateapp.qml` shows the pattern: create the
window with stub state, wait for the page, drive it through `objectName`s,
check the result. Replace D-Bus wrappers and `ConfigurationValue`s with
plain `QtObject` stubs (the template's `valueStub`); shared stubs go in
`tests/stubs/`. Add `apps/<app>/tests` to the Qml suites in
`tests/CMakeLists.txt` so ctest runs it.

## Formatting and lint

CI formats QML with Qt 6's `qmlformat -i` and fails on any change. Call the
Qt 6 one by its path: an old `qmlformat` 1.0 may be first on `PATH`, and it
sorts imports, which breaks the Silica import order.

```sh
find apps/weather -name '*.qml' -exec /usr/lib64/qt6/bin/qmlformat -i {} +   # Fedora
find apps/weather -name '*.qml' -exec /usr/lib/qt6/bin/qmlformat -i {} +     # Arch, Debian
sh tests/lint/check-silica-imports.sh
```

Shell scripts pass `shellcheck`.

## Before you ship

- [ ] `manifest.json`: description, permissions (with reasons for the
      sensitive ones), categories, searchKeywords; `marathon-dev lint` passes.
- [ ] An `ICONS` entry in `scripts/build-app-icons.py`; `assets/icon.svg` regenerated.
- [ ] Every string the user sees is in `qsTr()`.
- [ ] Theme sizes and colours only; pulley menus for actions; remorse for
      deletes; a `ViewPlaceholder` for every empty list; a cover.
- [ ] Back works on every page; the app lays out at each width in `testedOn`.
- [ ] Shaders baked and the `.qsb` committed.
- [ ] `keel-actions.json` regenerated (`--check` passes) and installed with
      `install_keel_actions`.
- [ ] Tests pass and are listed in `tests/CMakeLists.txt`.
- [ ] Qt 6 `qmlformat` changes nothing; `check-silica-imports.sh` passes.
- [ ] Tried on a phone from every way in: home grid, search, Pilot,
      notifications, the cover.
