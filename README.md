# Keel

Keel lets Sailfish apps written for Silica run on Qt6 (see `docs/plan.md`,
"Keel"). It is Qt6 QML modules that apps import, plus the runtime that makes
a Qt6 app a Lipstick citizen the way a native Silica app is (ADR-0016):

- **Direct mode** (the default on Sailfish OS): the app's own windows are
  its Lipstick windows. Qt 6 talks to Lipstick through wl_shell and the Qt
  surface extension, the protocol path of native Qt 5 Silica apps, with
  Keel's own shell integration `keel-wl-shell` (`sailfishapp/waylandshell`);
  Keel tags the cover window `CATEGORY=cover`, gives app windows the
  properties Lipstick reads from a Silica window (`BACKGROUND_VISIBLE`, the
  cover link),
  follows Lipstick's orientation, activation, visibility and close, and
  reads the ambience from dconf. No extra process, no extra composition.
- **booster-keel** (`booster/`): a mapplauncherd booster that has Qt 6, the
  Wayland connection and a QML engine with Sailfish.Silica and Keel ready
  before an app is launched (`invoker --type=keel`), like
  `booster-silica-qt5` for native apps.
- **keel-shell** (`shell/`): the system-Qt5 nested compositor, now an opt-in
  fallback.

| Directory | What | Status |
| --- | --- | --- |
| `silica/` | `Sailfish.Silica 1.0` and `Keel 1.0` QML modules for Qt6 (QML, thin C++, CXX-Qt Rust) | v0.1: the v1 scope plus the corpus blockers of the 2026-10-01 measurement; see `silica/COMPATIBILITY.md` (95 implemented, 4 partial, 3 missing; most of it Silica's own BSD QML). Also a minimal `Sailfish.Share 1.0` (`ShareAction` copies to the clipboard). Host tests pass; aarch64 RPM: see "Device builds". |
| `shell/` | `keel-shell` (system Qt 5.6), the opt-in fallback window path | See `shell/README.md`. Built separately (Qt5). |
| `booster/` | `booster-keel`, the mapplauncherd booster for Keel apps (`shipwright-keel-booster`) | Host: builds against mapplauncherd from source, ctest `keel_booster_mode` passes. Device (Jolla Phone, 2026-10-09): sandboxed apps run in their per-app booster (booster-keel@<app>) and start in about half the time; see step 4 of "Building an app against Keel". |
| `testcompositor/`, `tests/direct/` | `keel-test-compositor`, a headless Lipstick stand-in (wl_shell + qt_surface_extension), and the direct-mode test | ctest `keel_direct_mode` passes (2026-10-01). |
| `nemo-compat/` | Qt6 builds of Nemo.DBus 2.0, Nemo.Notifications 1.0, Nemo.KeepAlive 1.1/1.2, Nemo.Configuration 1.0 plus `org.nemomobile.{dbus,notifications,keepalive,configuration}`; Keel's `org.nemomobile.lipstick 0.1` (`LauncherItem`); `Nemo.Policy`/`org.nemomobile.policy 1.0` (nemo-qml-plugin-policy on libresourceqt with Keel's QtDBus engine for the resource policy manager); no-op `Nemo.Ngf`/`org.nemomobile.ngf 1.0` (feedback events load, play nothing) | Upstream code with two Qt6 fixes; Nemo.Configuration uses Chum's mlite-qt6 (dconf) on the device and a JSON-file fallback on hosts; host tests pass; aarch64 RPM builds. |
| `sailfishapp/` | `libkeel-sailfishapp`: `SailfishApp::application/createView/pathTo/pathToMainQml/main` for Qt6, `sailfishapp.pc`; English plurals for `qsTr("%n file(s)", "", n)` when no catalog translates them (`(s)`, or `(singular|plural)`); Keel's launcher (`keellauncher.h`: direct mode, the booster hand-over) | Host tests pass; aarch64 RPM builds (0.1.0-2; 0.1.0-3 with the launcher not yet built in the SDK). |
| `qt5compat/` | Qt 5 QML API shims for unported apps, in Keel's own import directory (`/usr/lib64/keel/qt5compat`): `QtGraphicalEffects 1.x` (on Qt5Compat.GraphicalEffects), no-op `QtFeedback 5.0`, `RegExpValidator` and `VisualItemModel` under `QtQuick 2.0`..`2.14`, Qt 5 `MediaPlayer`/`VideoOutput`/`SoundEffect`/`Camera` under `QtMultimedia 5.x` | QML only; tests pass on Qt 6.4.2 and (before the `Camera` shim, which is tested on 6.4.2 only, without a camera) on 6.8.4 (qemu); aarch64 RPM builds. Reaches apps once keel-shell sets `QML_IMPORT_PATH` (one-line change, see `qt5compat/README.md`). Corpus tier B 7 -> 10 of 19; the `Camera` shim brought foilauth and yubikey to tier B in the seventh run. |
| `actions/` | Keel Actions (ADR-0018): the `Keel.Actions 1.0` QML module (`KeelAction`, `KeelParam`, `KeelResult`, `KeelEntity`, `KeelContext`, `KeelShortcut`) with the in-app runtime; the `keel` Rust crate (`#[keel::action]`, `#[keel::entity]`); the schema crate (validator, Reef review rules, plan validation) and the generator behind `keel actions` | Host tests pass (ctest `keel_actions_*`; `cargo test -p keel -p keel-actions-schema -p keel-actions-codegen`). The build step is `keel actions`. See "Keel Actions" below. |
| `rpm/` | `shipwright-keel-silica`, `-nemo-compat` (+ `-dbus`, `-configuration`), `-sailfishapp` (+ `-devel`), `-qt5compat` specs, `build-native.sh` | See "Device builds". |

Provenance: `silica/PROVENANCE.md`, `nemo-compat/PROVENANCE.md`.

## Building and testing on a host

Needs Qt 6.4 or newer (Core, Gui, Qml, Quick, DBus, QuickTest, Test, and
the private Gui headers, `qt6-base-private-dev`), CMake 3.19+, Ninja, Rust
(for the CXX-Qt part), `dbus-run-session` and `pkg-config`. The direct-mode
test also needs `libwayland-dev` (the test compositor) and Qt 6's Wayland
client (`qt6-wayland`); without the latter it reports "skipped". booster-keel
and its test are built when mapplauncherd's `libapplauncherd` is found:
`tools/perf/build-mapplauncherd.sh <prefix>`, then configure with
`PKG_CONFIG_PATH=<prefix>/lib/pkgconfig`.

```
cmake -S keel -B /tmp/claude-0/build-keel -G Ninja
cmake --build /tmp/claude-0/build-keel
ctest --test-dir /tmp/claude-0/build-keel --output-on-failure
```

`ctest` runs these tests and those of `platform/` (all 29 pass on Qt 6.4.2, 2026-10-01, with libapplauncherd from `tools/perf/build-mapplauncherd.sh`):

| ctest name | What | Test functions |
| --- | --- | --- |
| `keel_silica_qml` | qmltestrunner, offscreen: import, every type instantiating (including the types gained from Silica's BSD QML), PageStack (with and without headless immediate transitions), Dialog, pulleys with real drag gestures, Theme values and `rgba()`, TextField/TextArea input and text bindings, ComboBox, RemorsePopup timeout, ContextMenu, Screen, StandardPaths, LinkedLabel, ButtonLayout and other 0.1 additions, and a realistic sample app (`tests/qml/compatapp`) | 197 passed |
| `keel_silica_ambience_env` | Theme from keel-shell's `KEEL_AMBIENCE_*`/`KEEL_SILICA_*` and `KEEL_THEME_*` | 6 passed |
| `keel_silica_native_cargo_test` | Rust unit tests (ambience layering, palette, link detection for `LinkParser`) | 20 passed |
| `keel_silica_labelformat` | `Label` with `_defaultLabelFormat: Text.PlainText` (and plain-text labels) loads no images, local or remote | 5 passed |
| `keel_silica_screenshot_<scene>` | Each reference scene in `silica/tests/screenshots/scenes/` renders offscreen with `grabToImage()` (5 scenes; see "Look (tier C)") | passed |
| `keel_silica_shellcontract_shell` | The keel-shell contract against a fake `org.shipwright.keel.Shell1` peer server: cover window titled `keel:cover:<app>` **at show time**, top level, sized `Theme.coverSizeLarge`; CoverStatus → `Cover.status`; cover action tap; Orientation → rotation + `SetContentOrientation`; Active; `Activate()`; initial and changed ambience; `pixelRatio` scaling with `QT_ENABLE_HIGHDPI_SCALING=0`; CloseRequested → quit | 12 passed |
| `keel_silica_shellcontract_nodbus` | Same app with `KEEL_SHELL=1` but no `KEEL_SHELL_DBUS`: cover window still created, no connection, defaults | 12 passed |
| `keel_silica_shellcontract_noshell` | Plain desktop run: no cover window, Theme defaults, `activate()` raises the window | 12 passed |
| `keel_nemo_compat` | Private dbus-daemon with fake Notifications, MCE and echo services: typedCall/call/error callbacks, properties, signals, DBusAdaptor, service status, Notification publish/replace/close/clicked/actionInvoked/closed/notifications(), DisplayBlanking, KeepAlive, BackgroundJob, and every legacy URI | 24 passed |
| `keel_sailfishapp` | `application()`, `pathTo()`, `pathToMainQml()`, `createView()`, and `SailfishApp::main()` running a Silica app built the SDK-template way | 9 passed |
| `keel_sailfishapp_pkgconfig` | `pkg-config sailfishapp` resolves to the Keel library and header | passed |
| `keel_direct_mode` | Direct mode against `keel-test-compositor` (wl_shell + qt_surface_extension, as Lipstick): a Silica app built the SDK way (`tests/direct`) shows a full-screen wl_shell main window and a second surface carrying `CATEGORY=cover` (decodable by a Qt 5.6 compositor, sent before its first buffer), all from the app's own process with no keel-shell; the window properties Lipstick reads (`WINID`, `BACKGROUND_VISIBLE`, the cover link) and a cover that is not full screen; Lipstick hiding and showing the main window and the cover keeps their surfaces and redraws them (needs `keel-wl-shell`, so it runs on any Qt 6 with the Wayland client's private headers); output rotation gives a landscape buffer transform and rotates the page; activation, cover status, a press, Lipstick's close and SIGTERM; ambience from (fake) dconf | 36 checks |
| `keel_booster_mode` | The same, launched with `invoker --type=keel` through booster-keel: the app runs inside the booster's process (only when libapplauncherd is found) | 28 checks |

`keel/qt5compat` adds `keel_qt5compat_core`, `keel_qt5compat_graphicaleffects` (when Qt5Compat.GraphicalEffects is installed), `keel_qt5compat_silica_regression`, `keel_qt5compat_camera` (when Qt has the QtMultimedia QML module, or `-DKEEL_QT5COMPAT_TEST_CAMERA=ON`; needs a Multimedia backend, no camera) and the opt-in `keel_qt5compat_multimedia`; see `qt5compat/README.md`.

## Native code: CXX-Qt and where C++ remains

Following the plan's policy, the logic in Keel's native part is Rust via
CXX-Qt 0.10.0 (pinned; `silica/plugin`, its own Cargo workspace excluded from
the root one): the `Keel.Ambience` QObject, the ambience layering (keel-shell
environment, `AmbienceChanged`, `KEEL_THEME_*` overrides), the palette
derivation behind `Theme.highlightFromColor()` and friends, and `LinkParser`
(the link detection of Silica's BSD `LinkedLabel`).

Thin C++ remains where the Qt object model needs it or where there is no
logic to move:

- the two QML plugin classes and the `theme` image provider (plugin glue);
- `EnterKey` and `ButtonLayout` (attached-property types; CXX-Qt 0.10 cannot
  declare `QML_ATTACHED`, and ButtonLayout is a `QQuickItem`), `Clipboard` and
  `StandardPaths` (a few lines over `QClipboard` / `QStandardPaths`);
- `Screen` (a C++ singleton, because a QML singleton loses to Qt Quick's
  `Screen` in name lookup; see COMPATIBILITY.md);
- the native types of `Sailfish.Silica.private` that Silica's BSD QML needs
  (`plugin/cpp/private/`: page stack gesture area, pulley menu logic,
  `AnimatedLoader`, `InverseMouseArea`, `DragFilter`, `GlassItem`,
  `Palette`, text-editor helpers, the `qsTrId` fallback translator; see
  `silica/PROVENANCE.md`). They are `QQuickItem`s, attached types, event
  filters or incubator users, which CXX-Qt 0.10 cannot express;
- `Keel.Shell`: in direct mode, Qt window and screen plumbing (the cover's
  window property through the platform native interface, orientation,
  activation, SIGTERM) and the dconf reader (`dconfambience.cpp`, ported
  from keel-shell); under keel-shell, its QtDBus peer connection, property
  mirroring and signal forwarding. CXX-Qt has no binding for QWindow's
  platform side or QtDBus, and a Rust D-Bus stack (zbus) in every app process
  for six signals was not worth it.

## Building an app against Keel

Starting a new app: `keel new` and `keel run` (`tools/keel-dev`) generate a
working Rust + Silica app on Keel and run it in a desktop window; see
`docs/developers/getting-started.md`.

Keel targets source compatibility: a Silica app's QML stays as it is; the
native part is rebuilt against Qt6.

1. QML: keep `import Sailfish.Silica 1.0`. Nemo imports (`Nemo.DBus`,
   `Nemo.Notifications`, `Nemo.KeepAlive`, `Nemo.Configuration` and their
   `org.nemomobile.*` forms) work unchanged. Check the app with `keel-compat` and
   `silica/COMPATIBILITY.md`.
2. C++: keep `#include <sailfishapp.h>` and `SailfishApp::main()` or
   `application()`/`createView()`/`pathTo()`. Build with Qt6:
   - qmake (Qt6's `qmake6`): `PKGCONFIG += sailfishapp` with
     `PKG_CONFIG_PATH=/usr/lib64/keel/pkgconfig`, or `PKGCONFIG += keel-sailfishapp`;
   - CMake: `find_package(KeelSailfishApp)` and link `Keel::SailfishApp`, or
     `pkg_check_modules(SAILFISHAPP REQUIRED IMPORTED_TARGET keel-sailfishapp)`.
   `CONFIG += sailfishapp` (the Qt5 SDK feature file) is not provided; add
   the pkg-config line instead.
3. Spec: `BuildRequires: shipwright-keel-sailfishapp-devel, qt6-qtbase-devel,
   qt6-qtdeclarative-devel`; `Requires: shipwright-keel-silica,
   shipwright-keel-sailfishapp` (plus `shipwright-keel-nemo-compat` if it
   uses Nemo imports); `Requires: shipwright-keel-booster`,
   `Recommends: shipwright-keel-shell`. Data files still go to `/usr/share/<appname>/`.
   Link the binary as a PIE that exports `main` (`-fPIE -pie -rdynamic`, as
   for any mapplauncherd-boosted app). Rust apps: see "Runtime on the phone".
4. Desktop file. A sandboxed app (an `[X-Sailjail]` section) starts in its
   own booster inside its sandbox, as Jolla's camera and email do:

   ```
   Exec=/usr/bin/invoker --type=keel -A -- /usr/bin/harbour-example
   ```

   with no `X-Nemo-Application-Type`, and the package installs
   `/usr/lib/systemd/user/user-session.target.d/50-harbour-example.conf`
   (`[Unit]` `Wants=booster-keel@harbour-example.service`) and `Requires:
   shipwright-keel-booster`. `-A` names the booster after the binary;
   booster-keel@ runs it under the Sailjail profile of the desktop file of the
   same name. Measured on the Jolla Phone (2026-10-09): Shoal Migrate's first
   frame 282 to 320 ms after launch, against 613 to 633 ms unboosted; each
   per-app booster keeps about 55 MB resident. With
   `X-Nemo-Application-Type=keel` instead, Lipstick (libcontentaction) runs
   `invoker --type=keel --id=<app> --single-instance <Exec>`; `--id` forces
   the sandbox, which the shared booster-keel.service is not in, so a
   sandboxed app starts unboosted (verified on the phone); an unsandboxed app
   (`Sandboxing=Disabled`) does run in booster-keel.service. Either way the
   app is in direct mode. To use keel-shell instead (the fallback):
   `Exec=/usr/bin/keel-shell -- /usr/bin/harbour-example` with
   `X-Nemo-Application-Type=no-invoker`.

On a desktop (no `/etc/sailfish-release`, no `KEEL_DIRECT=1`) the app runs as
an ordinary Qt6 window with the default dark ambience;
`KEEL_THEME_PIXEL_RATIO=2` and other `KEEL_THEME_*` variables emulate a
phone.

## Keel Actions: what an app can do, for Pilot and any MCP client

Keel Actions (`actions/`, ADR-0018, `docs/specs/pilot.md` section 9) give
every Keel app an MCP surface. An app declares typed **actions**,
**entities** (objects it owns, addressed as `keel://<app-id>/<type>/<id>`),
a **context** (what the current page shows) and **shortcuts** (suggested
sequences of actions), next to the code that implements them. The app ID is
`<OrganizationName>.<ApplicationName>` from the desktop file's
`[X-Sailjail]` section; it is also the app's D-Bus name.

QML (`import Keel.Actions 1.0`, a module of its own so that `Keel 1.0` stays
with `silica/`):

```qml
import Keel.Actions 1.0

KeelAction {
    name: "notes.create"                  // domain.verb
    title: qsTr("Create note")
    description: "Create a new note with an optional title and a body."
    parameters: [
        KeelParam { name: "title"; type: "string"; maxLength: 200 },
        KeelParam { name: "body"; type: "string"; required: true; maxLength: 20000 }
    ]
    returns: KeelResult { type: "object"; fields: ["id"] }
    onInvoked: (args, call) => call.reply({ id: notesModel.create(args.title, args.body) })
}

KeelEntity {
    type: "note"; title: "Note"
    description: "A note: a title and a body of text."
    KeelParam { name: "created"; type: "string"; format: "date-time"; maxLength: 32; summarisable: true; indexable: true }
    KeelParam { name: "body"; type: "string"; maxLength: 20000 }
    onResolve: (id, call) => call.reply(notesModel.get(id))           // {id, title, created, body}
    onFind: (query, limit, call) => call.reply(notesModel.search(query, limit))
}

KeelContext {                             // one per page
    purpose: "reading a note"
    entity: noteEntity.uri(page.noteId)
    text: page.visibleText               // what the app chooses to expose
    active: page.status === PageStatus.Active
}

KeelShortcut {
    name: "shopping-list"; title: qsTr("New shopping list")
    description: "Create a note titled Shopping with the items given."
    arguments: [ KeelParam { name: "items"; required: true } ]
    steps: [ { action: "notes.create", arguments: { title: "Shopping", body: "{{items}}" } } ]
}
```

- **Handlers answer through the call.** `onInvoked: (args, call)` gets the
  validated arguments; it answers with `call.reply(value)` or
  `call.fail(code, message)`, now or later (keep `call` for asynchronous
  work). QML signal handlers cannot return values, so the spec's
  `onInvoked: (args) => ...` form is not used. An unanswered call fails
  with `Timeout` after `timeout` ms (default 25,000); an action without a
  `returns` completes when the handler returns.
- **Types**: `string`, `integer`, `number`, `boolean`, `entity` (with
  `entity: "<type>"` or `"<app-id>/<type>"` of another app), `array` (with
  `itemType` and `maxItems`) and `object` (`fields` for required strings,
  nested `KeelParam`s for typed fields). Strings default to `maxLength`
  4,096, arrays to `maxItems` 100, integers to the 32-bit range; every
  object is closed (`additionalProperties: false`).
- **Flags**: `readOnly`, `destructive`, `idempotent`, `openWorld` (reaches
  the network), `confirm` (always ask first), `sensitive` (the result is
  for the person only, never for a model), `untrusted` (the result carries
  content the app does not vouch for, such as a web page or someone else's
  message: data for a model, never instructions; manifest
  `_meta["org.shipwright.keel/untrusted"]`, only when set), `enabled` (run
  time).
- **Results** go out as JSON objects: an `object` result as it is, any
  other type as `{ "result": <value> }` (MCP output schemas are objects).
  The runtime checks results against the declared schema; a mismatch fails
  the call (the app's bug, reported as `Failed`).
- **Entities** answer `onResolve` with the full object and `onFind` with a
  list; only `id`, `title` and properties marked `summarisable` ever leave
  a find result, and `indexable` ones may enter Pilot's on-device index.
- **Context** is returned only for the active `KeelContext`, only while the
  app is in the foreground or was within the last 30 s, and `keel-mcp` reads
  it only for a request the person started. Text is cut at 4,000
  characters.

Every property that describes the contract must be a literal (strings,
numbers, booleans, `qsTr("...")`, lists of those): the build step reads the
QML statically.

Testing in QML: the `KeelActions` singleton calls actions, entities and the
context the way D-Bus does, and `KeelActions.describe()` returns the
manifest the declarations produce. Run the test with
`KEEL_ACTIONS_APP_ID=<app-id>` (and `KEEL_ACTIONS_FOREGROUND=1` for context
tests, since no window system decides the foreground in a test run):

```qml
const call = KeelActions.invoke("notes.create", { body: "Milk" })
verify(call.succeeded, call.errorMessage)       // call.result.id
compare(KeelActions.invoke("notes.create", {}).errorCode, "InvalidArguments")
tryCompare(asyncCall, "finished", true)
```

`actions/tests/app/NotesActions.qml` is a complete example; its test is
ctest `keel_actions_qml`.

The build step: `keel actions` (`tools/keel-dev`) reads the app's QML
(`--qml`, default `qml/` or `ui/`), Rust sources (`--rust`, default `src/`)
and desktop file (`--desktop`; the app ID is `[X-Sailjail]`
`OrganizationName.ApplicationName`, the executable `Exec`) and writes into
`--out` (default `target/keel-actions`):

| File | Install to | What |
| --- | --- | --- |
| `actions.json` | `/usr/share/keel/actions/<app-id>.json` | the manifest: MCP tools (`<app-id>/<action>`, schemas, hints, `_meta`), entity types with their `<app-id>/<type>.find` tools, the context resource, shortcuts as prompts |
| `<app-id>.actions.xml` | `/usr/share/dbus-1/interfaces/` | `org.shipwright.Keel.Actions` (`actions/dbus/`) annotated with the app's actions |
| `<app-id>.service` | `/usr/share/dbus-1/services/` | session-bus activation through Sailjail, with `--keel-actions` |
| `<app-id>.sailjail` | the desktop file | the `ExecDBus=` line for `[X-Sailjail]` |
| `keel_actions.c` | compiled in (C/C++ apps) | `keel_actions_manifest()`; Rust apps call `keel::manifest!()` |

`--tests DIR` also writes per-action test stubs (`tst_keel_actions.qml`,
`keel_actions_tests.rs`) when they are missing: a schema round trip and an
invocation per action, a find per entity type. `--check` writes nothing
and fails when the output is stale or the desktop file lacks `ExecDBus`;
`--review FILE` applies Reef's rules to a manifest. Errors name the file
and line: a non-literal contract property, an unknown property or type, an
undeclared step action or `{{argument}}`, a review rule. From `build.rs`:
`keel_actions_codegen::Config { qml, rust, desktop, .. }.build_script()`
(into `$OUT_DIR`), then `keel::manifest!()` in the crate; from CMake:
`keel_add_actions()` in `actions/cmake/KeelActions.cmake`. The generator
and the runtime build the same schemas (ctest
`keel_actions_describe_golden` compares them), and the generator's own
output is pinned by golden files (`actions/codegen/tests/golden`,
`UPDATE_GOLDEN=1 cargo test -p keel-actions-codegen` to rewrite).

At run time the `Keel.Actions` plugin is the app's runtime. When it loads
it looks for the compiled-in manifest (`keel_actions_manifest`, from
`keel::manifest!()` or `keel_actions.c`) and the `keel` crate's native
table in every loaded object (booster-keel loads apps `RTLD_LOCAL`), or
reads `KEEL_ACTIONS_MANIFEST`, and then serves
`org.shipwright.Keel.Actions` on the app ID at
`/org/shipwright/Keel/Actions` (`actions/dbus/`): `Describe`, `Invoke`,
`GetEntity`, `FindEntities` and `GetContext`, with JSON in and out,
arguments and results validated against the manifest, delayed replies for
asynchronous answers, and errors
`org.shipwright.Keel.Actions.Error.<code>`. A QML declaration takes a
call first, then a Rust function; a call for a declared action whose QML
has not loaded yet waits up to 10 s. Started with `--keel-actions` (the
generated `.service` file), `Keel::headless()` (`sailfishapp/`) is true:
`Keel::showMainWindow()` shows nothing, apps that show their view
themselves check it first, and the runtime quits the process after 30 s
without calls (`KEEL_ACTIONS_IDLE_MS`). ctest `keel_actions_dbus` runs the
round trip on a private bus with activation and idle exit;
`keel_actions_dbus_native` does it for Rust actions in a library loaded
`RTLD_LOCAL` (`actions/tests/native`, whose `build.rs` runs the generator).

**keel-mcp** (`actions/mcp`, `cargo build -p keel-mcp`) serves every app's
actions as one MCP server, with rmcp 3.5: MCP 2026-07-28 (requests carry
`_meta` and need no `initialize`) and, through `initialize`, 2025-11-25
and earlier. `keel-mcp --stdio` serves a client that spawns it;
`keel-mcp --socket [PATH]` listens on `$XDG_RUNTIME_DIR/keel-mcp.sock`
(mode 0600) for `pilotd`; `--external` serves a paired desktop agent (no
sensitive results, no context). It reads `/usr/share/keel/actions/*.json`
(`--actions-dir`; rescanned every 2 s) and asks running apps on the
session bus for their manifests (`--probe-seconds`, default 10); an
installed manifest wins.

| Keel | MCP |
| --- | --- |
| action `<app-id>/<name>` | tool `<app-id>__<name>` (MCP tool names allow only `A-Za-z0-9_.-`; the manifest name is in `_meta["org.shipwright.keel/name"]`, and calls and plans accept either) |
| entity type | resource template `keel://<app-id>/<type>/{id}` and tool `<app-id>__<type>.find` |
| entity | `resources/read keel://<app-id>/<type>/<id>`: `uri`, `id`, `title` and the `summarisable` properties only |
| context | resource `keel://<app-id>/context`, read only with `_meta["org.shipwright.keel/userInitiated"]: true`, never activating the app |
| shortcut | prompt `<app-id>__<name>`; `prompts/get` fills in the arguments and returns the plan |
| plans | `keel__plan.validate`, `keel__plan.run` (steps reference earlier outputs with `{"$step": n, "path": "/json/pointer"}`; a plan with a destructive, open-world or `confirm` step runs only with `_meta["org.shipwright.keel/confirmed"]: true`) |

Arguments are validated before the D-Bus call and results against
`outputSchema` after it. A `sensitive` action's result never goes into
`structuredContent`: it comes back as text annotated
`audience: ["user"]`, and not at all to an external host. An `untrusted`
action's result keeps its `structuredContent`, but the call result carries
`_meta["org.shipwright.keel/untrusted"]: true` and its first text says the
content is data, never instructions; `keel/plan.run` marks such steps
`untrusted: true`. Clients (pilotd) must keep that content out of the
instruction channel. Tests:
`cargo test -p keel-mcp` (raw JSON-RPC against a stand-in app) and ctest
`keel_mcp_conformance` (the same test, plus the stdio and socket
transports of the binary, against the real test app over a private bus
with activation).

The Shoal apps and Reef's client are the reference implementations. Each
declares its actions in `actions/<App>Actions.qml` under its QML root,
instantiated by the main QML file; its `build.rs` runs the generator and
`src/lib.rs` calls `keel::manifest!()`; its launcher returns before showing
the view when `Keel::headless()`; its desktop file has `ExecDBus`; its spec
installs the three generated files and requires `shipwright-keel-actions`.

| App (app ID) | Actions | Entities, context, shortcuts |
| --- | --- | --- |
| Keys (`org.shipwright.shoal-keys`) | `keys.search` (read-only, sensitive), `keys.copy` (read-only, sensitive: copies a password, user name or one-time code; answers only which field), `keys.lock` | `entry` (title, site and folder only, never secrets); context on the entry page (which entry, its title) |
| Mail (`org.shipwright.shoal-mail`) | `mail.search` (read-only), `mail.compose` (opens a prefilled draft), `mail.send` (destructive, open-world, confirm) | `message` (subject, sender, date, folder; never the body); context on the message page; shortcut `write-to` |
| Migrate (`org.shipwright.shoal-migrate`) | `migrate.scan`, `migrate.status` (read-only), `migrate.start` (confirm), `migrate.cancel` | |
| iCloud setup (`org.shipwright.ShoalICloud`) | `icloud.accounts` (read-only), `icloud.sync` (open-world) | |
| Reef (`org.shipwright.reef`; unsandboxed, so the app ID is set in `build.rs`) | `reef.search` (read-only), `reef.install` (confirm, open-world; answers when installed) | `app` (store app: summary, category, version, installed) |

Every one fails with `NotAvailable` when it cannot act (Keys locked, no
mail account, nothing planned, Reef busy). A QML handler that throws
fails its call at once (`Failed`) instead of timing out.

Rust (the `keel` crate, `actions/rust/keel`):

```rust
#[keel::action(
    name = "notes.search",
    description = "Search notes by text. Returns up to `limit` matches.",
    read_only = true
)]
async fn search(#[keel(max_length = 256)] query: String, limit: Option<u32>) -> keel::Result<Vec<NoteRef>> { ... }

#[keel::entity(type = "note", title = "Note")]
#[derive(serde::Serialize)]
struct Note { id: String, title: String, #[keel(summarisable)] created: String }
impl keel::EntitySource for Note { /* get(id), find(query, limit) */ }
```

The macros register the functions; the `Keel.Actions` runtime in the app
calls them after validating the arguments (synchronous ones on the GUI
thread, `async` ones on a worker thread). `cargo test` can call them with
`keel::invoke(name, json)` (see `actions/rust/keel/tests/actions.rs`).

## Runtime on the phone: direct mode, booster-keel, keel-shell

ADR-0016 has the decision and its sources.

**Direct mode.** `SailfishApp::application()` (and `Keel::application()`
for apps whose `main` is not SailfishApp's) calls `Keel::prepareEnvironment()`
(`sailfishapp/include/keellauncher.h`) before the `QGuiApplication` exists.
On Sailfish OS (`/etc/sailfish-release`), unless `KEEL_DIRECT=0` or
`KEEL_SHELL=1`, or anywhere with `KEEL_DIRECT=1`, it sets, when not already
set on purpose: `QT_QPA_PLATFORM=wayland-egl` (also replacing the session's
Qt 5 value `wayland`), `QT_WAYLAND_SHELL_INTEGRATION="keel-wl-shell;wl-shell"`,
`QT_WAYLAND_DISABLE_WINDOWDECORATION=1`, `QT_ENABLE_HIGHDPI_SCALING=0`; it
removes `QMLSCENE_DEVICE=customcontext` and `QT_WAYLAND_RESIZE_AFTER_SWAP`
(Qt 5 session settings), puts `<libdir>/keel/qt5compat` first on
`QML_IMPORT_PATH`, and sets `KEEL_DIRECT=1`. Keel's `Shell` singleton then
does what keel-shell did, against Lipstick itself:

| What | How (direct mode) | Lipstick side |
| --- | --- | --- |
| Main window | The `QQuickView`, shown full screen (`Keel::showMainWindow`), with `WINID`, `BACKGROUND_VISIBLE` (Lipstick draws the dimmed ambience behind it), `SAILFISH_HAVE_COVER` and `SAILFISH_COVER_WINDOW` (`"__winref:<cover WINID>"`), as Silica's Qt 5 window sets them | `wl_shell` surface, `set_fullscreen`; `qt_extended_surface` generic properties (Qt 5.6 `QDataStream` format) |
| Shown and hidden | `keel-wl-shell` (`sailfishapp/waylandshell`): Lipstick's `onscreen_visibility` Hidden makes a window not exposed (Qt Quick stops rendering it) and keeps its surface; any other value exposes it again. Qt 6's own wl-shell hid the `QWindow`, which destroyed its surface: the app lost its window on display off and in the switcher | `qt_extended_surface.onscreen_visibility` (display off, switcher; covers: Minimized when shown in the switcher) |
| Cover | Second top-level window (title `keel:cover:<app>`), `Shell.prepareCoverWindow()` creates it and sets the window property `CATEGORY=cover` before it is shown | `qt_extended_surface.update_generic_property("CATEGORY", QString "cover")`, before the first buffer; Lipstick reads it when the window is first mapped (`lipstickcompositor.cpp`) |
| Device orientation | `QScreen::orientation()` → `Shell.orientation` (0, 90, 180, 270 for Portrait, Landscape, PortraitInverted, LandscapeInverted) | `wl_output` transform (`setScreenOrientation`) |
| Content orientation | `Shell.setContentOrientation()` → `QWindow::reportContentOrientationChange()` on every app window except the cover | `wl_surface.set_buffer_transform` (Qt 5.6 and Qt 6 use the same table) |
| Activation | `QGuiApplication::applicationState()` → `Shell.active`; `activate()` = `raise()` + `requestActivate()` | keyboard focus; `qt_extended_surface.raise` |
| Cover status | Active while the app is inactive and the cover window is visible, exposed and not hidden or minimised | `qt_extended_surface.onscreen_visibility`, frame callbacks |
| Close | The main window's close event, and SIGTERM, → `Shell.closeRequested` (ApplicationWindow quits; the app is ended 3 s later if it does not) | `qt_extended_surface.close`; `terminateProcess()` SIGTERM |
| Ambience | keys under `/desktop/jolla/theme/` and `/desktop/sailfish/silica/` read at start and watched after, through libdconf (`keel/silica/plugin/cpp/keeldconf.h`; Sailjail's private-bin leaves sandboxed apps no `dconf` program; the program is the fallback on hosts without the library) → `Keel.Ambience` (same key format as keel-shell's) | dconf |

**booster-keel** (`booster/`, `shipwright-keel-booster`): mapplauncherd
forks it in the user session (`booster-keel.service`, started like
`booster-silica-qt5.service` through the silica-session booster;
`booster-keel@.service` is the per-app sandboxed variant). Before any
launch it calls `Keel::Booster::createApplication()` (direct mode, so the
Wayland connection to Lipstick is open), creates a `QQuickView`, and
compiles and instantiates `/usr/share/booster-keel/preload.qml` in its
engine. On `invoker --type=keel <app>` mapplauncherd sets the app's
environment, `dlopen()`s the app binary, the booster adopts the app's
arguments, name and translations (`Keel::Booster::adoptArguments()`), and
mapplauncherd calls the app's `main`. `SailfishApp::application()` returns the
booster's application and `SailfishApp::createView()` its view, whose engine
already has Silica's types compiled.

Boostable binaries: C++ apps are PIEs exporting `main` (as for
booster-silica-qt5; a C++ app whose own code has `thread_local` variables
has the Rust problem below and must be linked the Rust way or launched
unboosted). Rust apps cannot be plain PIEs: Rust's standard library uses
thread-locals, and the linker turns their accesses in an executable into
fixed offsets that are wrong once the binary is loaded into another process
(seen on the host as a crash in `std::thread::spawn`). So
`tools/keel-launcher/link_sailfishapp.rs` (and the `keel new` template's
`build.rs`) link Rust app binaries as executable shared objects: `-shared`,
the C runtime's `Scrt1.o`, a `.interp` section and a version script that
exports only `main`. They run directly and load into the booster. Their
`main` takes the application and the command line from Keel's launcher
(`keel_application()`, `launch_args()`; `tools/keel-launcher/launcher.rs`),
because under the booster Rust's `std::env::args()` holds the booster's
arguments.

**keel-shell** (`shell/`) is unchanged and remains available: an app
started with `keel-shell -- <app>` runs nested exactly as before
(`shell/PROTOCOL.md`); `KEEL_SHELL=1` wins over direct mode.

### Start-up and rendering

What Keel sets, or relies on, for start-up and latency, and why:

| Setting | Where | Effect |
| --- | --- | --- |
| Direct mode (no nested compositor) | `keellauncher.cpp` | One process and one composition pass per frame, as for native apps; no second Qt in memory |
| booster-keel | `booster/` | Qt 6, the Wayland and EGL connection, Sailfish.Silica's and Keel's plugins, type registration and the common Silica types are ready before the launch; the binary's relocations are resolved before the fork (`-z now`), so they are shared, not per-app private pages |
| Threaded render loop | Qt's default on wayland-egl (`QSG_INFO=1` shows "threaded render loop") | Rendering and animations run off the GUI thread, so a busy GUI thread does not drop frames; left at Qt's choice, checked on the phone |
| Double buffering, swap interval 1 | `QSurfaceFormat::setDefaultFormat` in direct mode | No third queued buffer between an input and the frame that shows it |
| Alpha on every Quick window | `QQuickWindow::setDefaultAlphaBuffer(true)` in direct mode (as booster-silica-qt5) | App and cover windows share one EGL config; Lipstick composes the ambience behind translucent Silica pages |
| No client-side decorations | `QT_WAYLAND_DISABLE_WINDOWDECORATION=1` | wl_shell has no server-side decorations; Qt would otherwise draw (and repaint) a frame |
| Precompiled QML | `qt_add_qml_module` (qmlcachegen) for all of Sailfish.Silica (109 files), Sailfish.Silica.private (67), Background (2) and Share (1): compiled units are linked into the plugins and the installed `qmldir` says `prefer :/qt/qml/...`; the RPM ships no `.qml` sources for them | No QML parsing or compilation of Keel's own types at start-up. Not compiled: keel/qt5compat's shims and nemo-compat's two Policy files (plain `.qml` files; Qt caches them on first use under `~/.cache`), and each app's own QML from `/usr/share/<app>/qml` (Qt's disk cache after the first start; apps may compile theirs with qmlcachegen) |

Host measurements of all this, with the method and the device method:
`tools/perf/README.md`.

## Device builds (Sailfish SDK, `SailfishOS-5.2.0.15-aarch64`)

The target needs Chum's `chum:testing` repository for Qt6 6.8.4
(`qt6-qtbase-devel`, `qt6-qtdeclarative-devel`; package names checked with
`sb2 -t SailfishOS-5.2.0.15-aarch64 -m sdk-install -R zypper se qt6` on
2026-09-30). Build from a scratch copy in the container, with your own mb2
snapshot:

```
# nemo-compat and sailfishapp: plain CMake in the target
mb2 -t SailfishOS-5.2.0.15-aarch64 --snapshot=keel -s keel/rpm/shipwright-keel-nemo-compat.spec build
mb2 -t SailfishOS-5.2.0.15-aarch64 --snapshot=keel -s keel/rpm/shipwright-keel-sailfishapp.spec build

# booster-keel and the device test apps: after sailfishapp (they need
# shipwright-keel-sailfishapp-devel in the target; the booster also the
# SDK's mapplauncherd-devel). Not built in the SDK yet.
mb2 -t SailfishOS-5.2.0.15-aarch64 --snapshot=keel -s keel/rpm/shipwright-keel-booster.spec build
mb2 -t SailfishOS-5.2.0.15-aarch64 --snapshot=keel -s keel/rpm/shipwright-keel-runtime-test.spec build

# silica: cross-compile the CXX-Qt part first (the SDK's Rust is 1.75,
# CXX-Qt 0.10 needs 1.85), then package
keel/rpm/build-native.sh /home/mersdk/keel/native
mb2 -t SailfishOS-5.2.0.15-aarch64 --snapshot=keel -s keel/rpm/shipwright-keel-silica.spec \
    build -- --define "keel_native_dir /home/mersdk/keel/native"
```

`build-native.sh` runs `tools/build/sdk/cargo-sailfish.sh` with a generated
`qmake` stand-in (the target qmake6's answers, paths mapped into the
sysroot) and wrappers that run the target's aarch64 `moc` through sb2
(qemu). It then copies the cxx-qt headers into the staged tree, so the
cargo directory can be deleted. Inside `mb2`, Qt's own moc, rcc,
qmlcachegen and qmltyperegistrar also run as aarch64 binaries under qemu.

Two SDK quirks the spec works around or that cost time:

- Under sb2, the target's `qmlcachegen` writes its `.cpp` outputs with
  mode 000 (QSaveFile cannot stat its file descriptor: sb2 logs "Path not
  found for FD ... statx()"). The silica spec makes them readable and
  resumes the build; any Qt6 project using `qt_add_qml_module` in the SDK
  will hit this.
- The CXX-Qt cross-build took 54 minutes on a loaded machine (load average
  about 25 on 4 cores) and 13 minutes on a quieter one; most of it is
  `cxx-qt-lib`'s C++ and its moc runs under qemu.

### Status of device builds (2026-10-01, `SailfishOS-5.2.0.15-aarch64`, Chum Qt 6.8.4)

| Package | Result |
| --- | --- |
| `shipwright-keel-silica` | Builds (with `build-native.sh` first). rpmlint: 0 errors; warnings: unstripped plugins, licence tag. Requires up to `GLIBC_2.39` (target has 2.41). |
| `shipwright-keel-nemo-compat`, `-dbus`, `-configuration` | Build (0.1.0-2 rebuilt 2026-10-01 with Nemo.Configuration against Chum's `mlite-qt6-devel`, lipstick and policy); link the target's real libiphb and use mce-headers. rpmlint: warnings: unstripped plugins, licence tags, duplicate policy QML files under both URIs; errors (not fatal under Sailfish's rpmlint config): mlite's verbatim LGPL text has the old FSF address. The 0.1.0-2 silica package (new QML and `format.cpp`/`urlresolver.cpp`) was not rebuilt for the device. |
| `shipwright-keel-sailfishapp`, `-devel` | Build. rpmlint: `shlib-policy-name-error` (the library package is not named `libkeel-sailfishapp1`), unstripped library, licence tag. |

Run under qemu in the target (`sb2 -t SailfishOS-5.2.0.15-aarch64.keel`,
the target's own Qt 6.8.4 `qmltestrunner`, offscreen) against the aarch64
build: the whole `keel_silica_qml` suite (175 passed) and
`keel_silica_ambience_env` (6 passed, which exercises the cross-built Rust
part), and an import smoke test of every Nemo URI from the extracted
nemo-compat RPMs (3 passed). Running under qemu is not running on a device.

## Needs device verification

Nothing here has run on a Jolla Phone. Steps, on a phone with developer mode,
Chum `chum:testing` Qt6 (`qt6-qtbase`, `qt6-qtbase-gui`,
`qt6-qtdeclarative`, `qt6-qtwayland`, `qt6-sfos-maliit-platforminputcontext`)
and the Keel RPMs (`shipwright-keel-silica`, `-sailfishapp`, `-booster`,
`-shell`, `-runtime-test`) installed. Steps 0a to 0c, and the measurements,
are automated by `tools/phase0/keel-runtime-test.sh`
(`tools/phase0/keel-runtime-test.md`); run it first and paste its results
file back.

0. **Direct mode and the booster (ADR-0016).**
   a. *Qt 6 renders straight into Lipstick.* Run
      `/usr/bin/harbour-keeldirect` from an SSH session with the session's
      `WAYLAND_DISPLAY`/`XDG_RUNTIME_DIR` (the kit does this): the page must
      appear full screen. `QSG_INFO=1` must report the OpenGL ES backend on
      the phone's GPU (not llvmpipe) and the threaded render loop.
      `WAYLAND_DEBUG=client` must show `wl_shell` and
      `qt_surface_extension` globals, one `get_shell_surface` per window and
      `update_generic_property("CATEGORY", ...)` for the cover. Record
      whether Lipstick also lists `xdg_wm_base`. If nothing appears, try
      `QT_QPA_PLATFORM=wayland`, then keel-shell.
   b. *Lipstick takes the cover.* Go to the home screen: the app grid shows
      the cover ("Direct"), not a thumbnail of the page; the app logs
      `KEELTEST coverStatus=active`, then `inactive` when it is opened
      again. A `CoverAction` triggers when tapped. Closing the app from its
      cover ends it (`closeRequested` in its log).
   c. *Orientation, keyboard, ambience.* Rotating the phone turns the page
      (`deviceOrientation=2` for landscape) and the keyboard opens in the
      new orientation; the text field opens the Sailfish keyboard; Theme's
      highlight colour equals `dconf read /desktop/jolla/theme/color/highlight`
      and follows an ambience change within a second.
   d. *Launcher path.* Tap the "Keel direct test" icon: Lipstick runs
      `invoker --type=keel`; with `booster-keel.service` active
      (`systemctl --user status booster-keel`) the app's process is the
      booster (`readlink /proc/<pid>/exe` is
      `/usr/libexec/mapplauncherd/booster-keel`); stop the service and tap
      again: the app still starts (invoker's generic fallback).
   e. *Sandboxed apps.* Verified 2026-10-09: with
      `X-Nemo-Application-Type=keel` a sandboxed app started unboosted
      (`invoker --type=keel --id=... --single-instance`, then Sailjail; no
      booster). With `Exec=/usr/bin/invoker --type=keel -A -- /usr/bin/<app>`
      and booster-keel@<app> running (started with the session by the app's
      package) the app's process is the per-app booster's, inside the
      sandbox; with that booster stopped, `invoker -A` starts nothing, so the
      app's package requires shipwright-keel-booster.
   f. *Rust apps boosted.* `invoker --type=keel /usr/bin/shipwright-shoal-keys`
      must start and run normally (the binary is an executable shared
      object, see "Runtime on the phone"); `/usr/bin/shipwright-shoal-keys
      --version` must work too.
1. **Module loads on Qt 6.8.4.** `QML_IMPORT_TRACE=1 KEEL_DIRECT=1
   /usr/bin/harbour-keeldirect` (or any Keel app); a file that imports
   `Sailfish.Silica 1.0` and `Nemo.DBus 2.0` must load without import
   errors. (Only Qt 6.4 has been tested on a host; Keel uses no API newer
   than 6.4.)
2. **Cover under keel-shell (the fallback).** `keel-shell --verbose --
   /usr/bin/harbour-keeldirect`: the app grid must show the cover, `keel-shell
   --verbose` logs the `cover window` mapping, and `Cover.status` becomes
   Active. Tap a cover action: it must trigger.
3. **Ambience.** `dconf dump /desktop/jolla/theme/` and
   `dconf dump /desktop/sailfish/silica/`; record the key names in
   `silica/PROVENANCE.md` and compare with the mapping in
   `silica/plugin/src/config.rs` (`color/highlight`, `color/primary`,
   `color/secondary`, `color/highlightBackground`, `color_scheme`,
   `theme_pixel_ratio`, wallpaper). Switch ambience in Settings while the app
   runs: `Theme.highlightColor` must follow within a second. In direct mode
   Keel runs `dconf` itself: check it may (Sailjail profiles of sandboxed
   apps) and that `ps` shows one `dconf watch /desktop/` per app.
4. **Scale.** Compare `Theme.pixelRatio`, `Theme.paddingLarge`,
   `Theme.itemSizeSmall`, `Theme.fontSizeMedium` and
   `Theme.horizontalPageMargin` with a Qt5 Silica app printing the same
   values; list differences in `silica/COMPATIBILITY.md`.
5. **Orientation.** Rotate the phone in an app that allows all
   orientations: content rotates, the keyboard follows (direct mode:
   `wl_surface.set_buffer_transform`; keel-shell: `SetContentOrientation`).
   Under keel-shell also check the direction: keel-shell reports
   `QScreen::angleBetween(primary, orientation)` (270 for
   `Qt::LandscapeOrientation`), which Keel maps to `LandscapeInverted`;
   direct mode maps `Qt::LandscapeOrientation` to `Orientation.Landscape`.
6. **Keyboard.** Tap a TextField: the Sailfish keyboard must appear (needs
   `qt6-sfos-maliit-platforminputcontext`), and EnterKey text/icon should
   show on its enter key.
7. **Look (tier C).** The reference page set is
   `silica/tests/screenshots/scenes/` (Page with PageHeader; SilicaListView
   of ListItems with the pulley menu open; Dialog with TextFields, a
   TextSwitch and a Button; controls; a cover). The host renders are in
   `silica/tests/screenshots/before/` (Keel 0.1) and `after/` (Silica's BSD
   QML on Keel), made with `silica/tests/screenshots/render.sh <keel build>`
   (offscreen software scene graph: no shader effects there).
   a. On the phone, run each scene under Keel (direct mode; the `qml` tool
      does not go through Keel's launcher, so set its variables:
      `KEEL_DIRECT=1 QT_QPA_PLATFORM=wayland-egl QT_WAYLAND_SHELL_INTEGRATION=wl-shell
      QT_WAYLAND_DISABLE_WINDOWDECORATION=1 /usr/lib64/qt6/bin/qml <scene>.qml`, or under
      keel-shell: `keel-shell -- /usr/lib64/qt6/bin/qml <scene>.qml`) and take a
      screenshot (Volume up and Volume down together, or
      `dbus-send --session --print-reply --dest=org.nemomobile.lipstick
      /org/nemomobile/lipstick/screenshot
      org.nemomobile.lipstick.saveScreenshot string:/home/defaultuser/Pictures/keel-<scene>.png`).
      For `list-pulley`, drag the list down until the menu shows; for the
      cover, minimise the app.
   b. Run the same file on the phone's own Qt 5 Silica (the scenes import
      only `QtQuick 2.0` and `Sailfish.Silica 1.0`): copy it to
      `/usr/share/keelref/qml/keelref.qml` and start
      `invoker --type=silica-qt5 /usr/bin/sailfish-qml keelref`; take the
      same screenshots.
   c. Compare each pair at full size: page header font, size and margins;
      list item height and press highlight; pulley menu (gradient background,
      highlight bar under the selected item, item colours, the menu's
      dimming of the page); dialog header (Cancel / accept text, sizes);
      text field underline, label and placeholder; switch glow; button
      shape; cover layout. Then check the GPU effects that the host cannot
      render: the pulley and context menu layers, a long `Label` with
      `truncationMode: TruncationMode.Fade` (fades out at the edge), a
      `ProgressCircle` and a `TimePicker` (ring drawn). The app's log must
      have no `ShaderEffect` or `.qsb` warnings (Keel's compiled shaders
      are in `qrc:/qt/qml/Sailfish/Silica/shaders/`).
   d. Repeat (a) to (c) in a light ambience and in landscape. Record every
      difference in `silica/COMPATIBILITY.md`.
8. **Nemo.** A notification from `Notification.publish()` must appear in the
   Events view and its default action must call back. `DisplayBlanking {
   preventBlanking: true }` must keep the display on; `BackgroundJob` must
   fire while the display is off (real libiphb wakeups).
9. **SailfishApp.** A harbour app rebuilt against `keel-sailfishapp` finds its
   files in `/usr/share/<appname>` and loads its translations.
10. **Nemo.Configuration.** With `shipwright-keel-nemo-compat-configuration`
    (or Chum's `nemo-qml-plugin-configuration-qt6`): a `ConfigurationValue {
    key: "/apps/keeltest/x" }` set from a Keel app must show in `dconf read
    /apps/keeltest/x`, and `dconf write /apps/keeltest/x 5` must update the
    app's value and a `ConfigurationGroup` property of the same key while it
    runs. Also `import org.nemomobile.configuration 1.0`.
11. **Lipstick, policy, share.** `org.nemomobile.lipstick` `LauncherItem {
    filePath: "/usr/share/applications/jolla-clock.desktop" }`: `title`,
    `iconId` and `isValid` correct; `launchApplication()` starts the app
    (Keel launches the `Exec` line itself; check sailjailed apps start).
    A camera page using `Nemo.Policy` `Permissions` (foilauth's scan page)
    must be granted the camera by ohmd (Keel's engine registers the set with
    the resource policy manager; `Permissions.acquired` turns true).
    `ShareAction.trigger()` opens the system share dialog (pick Bluetooth,
    email, another app); an app with a `ShareProvider` and `X-Share-Methods`
    in its desktop entry receives shares from Gallery.
    `NonGraphicalFeedback { event: "chat_fg" }.play()` (communi) loads and
    is silent; decide whether to play events through ngfd's D-Bus API.
12. **App icon paths.** A cover with `CoverPlaceholder { icon.source:
    "/usr/share/icons/hicolor/86x86/apps/<app>.png" }` shows the icon.
13. **Silica strings and shaders.** With the phone set to a language other
    than English, Silica's own texts in a Keel app (DialogHeader "Cancel" /
    "Accept", remorse "Undo", date and time pickers) must be translated:
    Keel loads the phone's `/usr/share/translations/sailfishsilica-qt5_<locale>.qm`
    at run time and falls back to engineering English. Also check that
    `QSG_INFO=1` reports the OpenGL ES RHI backend and that the compiled
    shaders (`silica/qml/shaders/*.qsb`, GLSL ES 100 and 300 es) load without
    warnings; they have only been compiled, not run, on the host.
8. **Keel Actions activation (ADR-0018).** Install an app with actions
   (its `/usr/share/dbus-1/services/<app-id>.service` and the `ExecDBus=`
   line in its desktop file), close it, then
   `gdbus call --session -d <app-id> -o /org/shipwright/Keel/Actions -m org.shipwright.Keel.Actions.Describe`.
   Expected: Sailjail starts the app with its permissions and without a
   window (`--keel-actions`), the call answers, and the process exits after
   30 s. Check whether Sailjail honours `ExecDBus` or needs the `.service`
   `Exec` line as generated (`/usr/bin/sailjail -p <desktop> ...`). Then
   launch the app from the home screen while the headless instance runs:
   note whether `invoker --single-instance` raises a window, starts a second
   process (which must then lose the bus name and quit) or does nothing.
