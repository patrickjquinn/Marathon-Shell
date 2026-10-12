# Silica apps pilot Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Silica (Keel) Notes app runs on the PinePhone under Marathon, with Marathon's back gesture, accent and wallpaper.

**Architecture:** Keel's `Sailfish.Silica` is packaged as an Alpine apk from the public shipwright-open repo at a pinned commit. A small `SilicaApp.qml` (Silica `ApplicationWindow` plus the runner's `handleBack()`/`minimizeRequested()` contract and ambience wiring) is the app root. `apps/notes-silica` is the pilot, built only when Silica is available.

**Tech Stack:** Qt 6.11 QML, Keel (Rust/CXX-Qt 0.10 + QML), Alpine abuild in podman, qmltestrunner.

**Spec:** `docs/superpowers/specs/2026-10-11-silica-apps-pilot-design.md`

## Global Constraints

- Keel source: `https://github.com/patrickjquinn/shipwright-open/archive/<_commit>.tar.gz`, `_commit` pinned and sha512-checksummed.
- Build only Keel's `silica/` (Sailfish.Silica + Keel, Keel.SilicaCore, Keel.SilicaScreen). No nemo-compat, sailfishapp, platform, actions, booster, tests.
- `keel-silica` depends on `qt6-qtdeclarative~<exact x.y.z it was built with>`.
- Marathon builds without Keel present: `notes-silica` is skipped, nothing else changes.
- Licence texts: BSD-3-Clause (Silica QML) and MIT (Keel) ship in the apk.
- Follow `docs/CODING_RULES.md` A–G; no verbose comments.
- No commits or pushes unless the user asks. Checkpoints below say "stop: diff review" instead.
- Device: PinePhone `root@172.16.42.1`; restart via `systemctl restart greetd` only; never `pkill marathon-shell`; never drop_caches; deploy in chunks of at most 20 MB.
- Sudo only via `SUDO_ASKPASS=~/.marathon-secrets/askpass.sh sudo -A`.

## Review Focus

1. Wallpaper set to a `qrc:/wallpapers/...` value (the default) — app must show the same wallpaper from `/usr/share/marathon-shell/wallpapers/`, not Silica's harbour fallback. Test in Task 2.
2. Back gesture on the first page — must minimise, not do nothing and not close. Test in Task 2.
3. Corrupt or empty `notes-silica/data` — app must start with an empty list, not fail to load. Test in Task 3.
4. Storage permission not yet granted — saving must request it and save once granted, like `apps/notes`. Test in Task 3 (stubbed PermissionManager).
5. Keel absent at build time — the Marathon apk still builds and `notes-silica` is simply missing. Checked in Task 4.

---

## File map

- Create `packaging/packages/keel-silica/APKBUILD` — the Keel Silica apk.
- Create `scripts/qemu/lib/build-keel-silica-apk.sh` — builds it in podman (pattern: `build-marathon-mail-oauth-apk.sh`).
- Create `apps/notes-silica/manifest.json`, `CMakeLists.txt`, `NotesSilicaApp.qml`, `SilicaApp.qml`, `NotesStore.js`, `pages/NotesPage.qml`, `pages/NoteEditorPage.qml`, `assets/icon.svg`.
- Create `apps/notes-silica/tests/tst_silicaapp.qml`, `tests/tst_notesstore.qml`, `tests/run.sh`.
- Modify `apps/CMakeLists.txt` — conditional `add_subdirectory(notes-silica)`.
- Modify `packaging/packages/marathon-shell/APKBUILD` — `keel-silica` in makedepends and depends.
- Modify `scripts/qemu/lib/build-marathon-shell-apk.sh` — install `keel-silica-*.apk` from `/local-apks` like qmf.
- Modify spec §3: `SilicaApp` lives in the app for the pilot (not MarathonUI), so MarathonUI keeps building without Keel.

---

### Task 1: `keel-silica` apk

**Files:**
- Create: `packaging/packages/keel-silica/APKBUILD`
- Create: `scripts/qemu/lib/build-keel-silica-apk.sh`

**Interfaces:**
- Produces: `~/.cache/marathon-build/duranium/mkosi.packages/keel-silica-0.1.0-r0.apk` installing `/usr/lib/qt6/qml/Sailfish/Silica/qmldir`, `/usr/lib/qt6/qml/Sailfish/Silica/libsilicaplugin.so`, `/usr/lib/qt6/qml/Keel/qmldir`, `/usr/lib/qt6/qml/Keel/SilicaCore/qmldir`, `/usr/lib/qt6/qml/Keel/SilicaScreen/qmldir`.

- [ ] **Step 1: Find the versions to pin**

Run:
```bash
git ls-remote https://github.com/patrickjquinn/shipwright-open refs/heads/main
podman run --rm alpine:edge sh -c 'apk update -q; apk policy qt6-qtdeclarative | sed -n 2p'
```
Record the commit sha as `_commit` and the Qt version (e.g. `6.11.2`) as `_qtver`.

- [ ] **Step 2: Write the APKBUILD**

```sh
# Maintainer: Patrick Quinn <patrick.jm.quinn@gmail.com>
pkgname=keel-silica
pkgver=0.1.0
pkgrel=0
_commit=<sha from step 1>
_qtver=<qt version from step 1>
pkgdesc="Keel: Sailfish Silica QML components for Qt 6"
url="https://github.com/patrickjquinn/shipwright-open"
arch="aarch64"
license="MIT AND BSD-3-Clause"
depends="qt6-qtdeclarative~$_qtver"
makedepends="
	cargo
	cmake
	samurai
	qt6-qtbase-dev
	qt6-qtbase-private-dev
	qt6-qtdeclarative-dev
	qt6-qtdeclarative-private-dev
	"
source="$pkgname-$_commit.tar.gz::https://github.com/patrickjquinn/shipwright-open/archive/$_commit.tar.gz"
options="net !check"
builddir="$srcdir/shipwright-open-$_commit/keel"

prepare() {
	default_prepare
	cargo fetch --manifest-path silica/plugin/Cargo.toml --locked
}

build() {
	cmake -B build -G Ninja \
		-DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_INSTALL_PREFIX=/usr \
		-DKEEL_QML_INSTALL_DIR=/usr/lib/qt6/qml \
		-DKEEL_BUILD_NEMO_COMPAT=OFF \
		-DKEEL_BUILD_SAILFISHAPP=OFF \
		-DKEEL_BUILD_PLATFORM=OFF \
		-DKEEL_BUILD_ACTIONS=OFF \
		-DKEEL_BUILD_BOOSTER=OFF \
		-DBUILD_TESTING=OFF
	cmake --build build
}

package() {
	DESTDIR="$pkgdir" cmake --install build
	install -Dm644 LICENSE "$pkgdir"/usr/share/licenses/$pkgname/LICENSE
	install -Dm644 silica/upstream/sailfishsilica-qt5-1.2.156/LICENSE.BSD \
		"$pkgdir"/usr/share/licenses/$pkgname/LICENSE.BSD
}

sha512sums="SKIP"
```

`!check`: Keel's tests need a session bus and qmltestrunner; they run in Shipwright's CI, not here.

- [ ] **Step 3: Write the build script**

Copy `scripts/qemu/lib/build-marathon-mail-oauth-apk.sh`, then change: package name `keel-silica`; drop the shell-source mount and oauth env; `apk add` line becomes `abuild rsync curl ca-certificates git cargo cmake samurai qt6-qtbase-dev qt6-qtbase-private-dev qt6-qtdeclarative-dev qt6-qtdeclarative-private-dev`; run `abuild checksum` before `abuild -r` so `sha512sums` is filled in the container copy; copy the apk to `/out/`. Also copy the filled `sha512sums=` line back out to `/out/keel-silica.sha512` so it can be pasted into the APKBUILD.

- [ ] **Step 4: Build it**

Run: `bash scripts/qemu/lib/build-keel-silica-apk.sh 2>&1 | tail -30`
Expected: `keel-silica-0.1.0-r0.apk` in `~/.cache/marathon-build/duranium/mkosi.packages/`. If CXX-Qt fails on musl, stop and report the error (spec risk 1); do not patch Keel here.

- [ ] **Step 5: Check the contents**

Run: `tar -tzf ~/.cache/marathon-build/duranium/mkosi.packages/keel-silica-0.1.0-r0.apk | grep -E "qml/(Sailfish/Silica|Keel)/(qmldir|lib.*\.so)$|licenses"`
Expected: the five qmldirs/plugins listed under Interfaces plus both licence files.

- [ ] **Step 6: Pin the checksum**

Replace `sha512sums="SKIP"` with the contents of `/out/keel-silica.sha512`.

- [ ] **Step 7: Stop: diff review**

---

### Task 2: `SilicaApp` root component

**Files:**
- Create: `apps/notes-silica/SilicaApp.qml`
- Create: `apps/notes-silica/tests/tst_silicaapp.qml`
- Create: `apps/notes-silica/tests/run.sh`

**Interfaces:**
- Produces: `SilicaApp` (Silica `ApplicationWindow`) with `property string appId`, `signal minimizeRequested()`, `function handleBack(): bool`, `function wallpaperUrl(path: string): string`.
- Consumes (runtime): `SettingsManagerCpp.wallpaperPath`, `MColors.accentBright` (`MarathonUI.Theme`), `Keel.Ambience.applyForwarded(lines)`.

- [ ] **Step 1: Write the test runner script**

`apps/notes-silica/tests/run.sh`:
```sh
#!/bin/sh
set -eu
here=$(cd "$(dirname "$0")" && pwd)
: "${KEEL_QML:?set KEEL_QML to a Keel build's qml dir}"
QT_QPA_PLATFORM=offscreen exec qmltestrunner -import "$KEEL_QML" \
	-import "$here/../../../build-ui" -input "$here"
```

- [ ] **Step 2: Write the failing tests**

`apps/notes-silica/tests/tst_silicaapp.qml`:
```qml
import QtQuick
import QtTest
import Sailfish.Silica 1.0
import "../"

TestCase {
    name: "SilicaApp"
    when: windowShown

    Component {
        id: appComponent
        SilicaApp {
            width: 540; height: 1140
            initialPage: Component { Page {} }
        }
    }
    Component { id: pageComponent; Page {} }
    SignalSpy { id: minimizeSpy; signalName: "minimizeRequested" }

    function test_backPopsPage() {
        const app = createTemporaryObject(appComponent, this);
        app.pageStack.push(pageComponent, {}, PageStackAction.Immediate);
        compare(app.pageStack.depth, 2);
        verify(app.handleBack());
        tryCompare(app.pageStack, "depth", 1);
    }

    function test_backOnFirstPageMinimises() {
        const app = createTemporaryObject(appComponent, this);
        minimizeSpy.target = app;
        minimizeSpy.clear();
        verify(app.handleBack());
        compare(minimizeSpy.count, 1);
        compare(app.pageStack.depth, 1);
    }

    function test_wallpaperUrl() {
        const app = createTemporaryObject(appComponent, this);
        compare(app.wallpaperUrl("qrc:/wallpapers/slate-aurora.svg"),
                "file:///usr/share/marathon-shell/wallpapers/slate-aurora.svg");
        compare(app.wallpaperUrl("file:///home/user/a.jpg"), "file:///home/user/a.jpg");
        compare(app.wallpaperUrl(""), "");
    }
}
```

- [ ] **Step 3: Run to see them fail**

Run: `KEEL_QML=~/Developer/Shipwright/build/keel/qml sh apps/notes-silica/tests/run.sh`
Expected: FAIL, `SilicaApp is not a type`.

- [ ] **Step 4: Write `SilicaApp.qml`**

```qml
import QtQuick
import Sailfish.Silica 1.0
import Keel 1.0
import MarathonUI.Theme

ApplicationWindow {
    id: app

    property string appId: ""

    signal minimizeRequested

    function handleBack() {
        if (pageStack.depth > 1) {
            pageStack.pop();
            return true;
        }
        minimizeRequested();
        return true;
    }

    function wallpaperUrl(path) {
        const prefix = "qrc:/wallpapers/";
        if (path.startsWith(prefix))
            return "file:///usr/share/marathon-shell/wallpapers/" + path.substring(prefix.length);
        return path;
    }

    function applyAmbience() {
        const wallpaper = typeof SettingsManagerCpp !== "undefined" ? wallpaperUrl(SettingsManagerCpp.wallpaperPath) : "";
        let lines = "highlightColor=" + MColors.accentBright;
        if (wallpaper !== "")
            lines += "\nbackgroundImage=" + wallpaper;
        Ambience.applyForwarded(lines);
    }

    Component.onCompleted: applyAmbience()

    Connections {
        target: typeof SettingsManagerCpp !== "undefined" ? SettingsManagerCpp : null
        ignoreUnknownSignals: true
        function onWallpaperPathChanged() {
            app.applyAmbience();
        }
    }
}
```

- [ ] **Step 5: Run the tests**

Run: `KEEL_QML=~/Developer/Shipwright/build/keel/qml sh apps/notes-silica/tests/run.sh`
Expected: 3 passed, 0 failed. If `MarathonUI.Theme` doesn't resolve, point the second `-import` at the directory that contains `MarathonUI/Theme/qmldir` in the host build (`find build* -path "*MarathonUI/Theme/qmldir"`).

- [ ] **Step 6: Stop: diff review**

---

### Task 3: Notes store and pages

**Files:**
- Create: `apps/notes-silica/NotesStore.js`
- Create: `apps/notes-silica/tests/tst_notesstore.qml`
- Create: `apps/notes-silica/NotesSilicaApp.qml`
- Create: `apps/notes-silica/pages/NotesPage.qml`
- Create: `apps/notes-silica/pages/NoteEditorPage.qml`
- Create: `apps/notes-silica/manifest.json`
- Create: `apps/notes-silica/assets/icon.svg` (copy of `apps/notes/assets/icon.svg`)

**Interfaces:**
- Consumes: `SilicaApp` (Task 2).
- Produces: `NotesStore.js` pure functions: `parse(json: string): Array`, `create(notes, title, content, now): Array`, `update(notes, id, title, content, now): Array`, `remove(notes, id): Array`. Note shape `{id: int, title: string, content: string, timestamp: int}` (same as `apps/notes`). Storage key `notes-silica/data`.

- [ ] **Step 1: Write the failing store tests**

`apps/notes-silica/tests/tst_notesstore.qml`:
```qml
import QtQuick
import QtTest
import "../NotesStore.js" as Store

TestCase {
    name: "NotesStore"

    function test_parseBad() {
        compare(Store.parse(""), []);
        compare(Store.parse("{oops"), []);
        compare(Store.parse("{\"a\":1}"), []);
    }
    function test_create() {
        const n = Store.create([], "", "body", 1000);
        compare(n.length, 1);
        compare(n[0].id, 1);
        compare(n[0].title, "Untitled");
        const m = Store.create(n, "B", "", 2000);
        compare(m[0].id, 2);
        compare(m[0].title, "B");
    }
    function test_updateAndRemove() {
        let n = Store.create([], "A", "", 1);
        n = Store.update(n, 1, "A2", "x", 5);
        compare(n[0].title, "A2");
        compare(n[0].timestamp, 5);
        compare(Store.update(n, 99, "z", "z", 6), n);
        compare(Store.remove(n, 1).length, 0);
    }
}
```

- [ ] **Step 2: Run to see it fail**

Run: `KEEL_QML=~/Developer/Shipwright/build/keel/qml sh apps/notes-silica/tests/run.sh`
Expected: FAIL loading `NotesStore.js`.

- [ ] **Step 3: Write `NotesStore.js`**

```js
.pragma library

function parse(json) {
    try {
        const v = JSON.parse(json);
        return Array.isArray(v) ? v : [];
    } catch (e) {
        return [];
    }
}

function nextId(notes) {
    return notes.reduce((m, n) => Math.max(m, n.id), 0) + 1;
}

function create(notes, title, content, now) {
    const note = { id: nextId(notes), title: title || "Untitled", content: content || "", timestamp: now };
    return [note].concat(notes);
}

function update(notes, id, title, content, now) {
    if (!notes.some(n => n.id === id))
        return notes;
    return notes.map(n => n.id === id ? { id: id, title: title || "Untitled", content: content, timestamp: now } : n);
}

function remove(notes, id) {
    return notes.filter(n => n.id !== id);
}
```

- [ ] **Step 4: Run the tests**

Run: `KEEL_QML=~/Developer/Shipwright/build/keel/qml sh apps/notes-silica/tests/run.sh`
Expected: all SilicaApp and NotesStore tests pass.

- [ ] **Step 5: Write the app root and pages**

`apps/notes-silica/NotesSilicaApp.qml`:
```qml
import QtQuick
import Sailfish.Silica 1.0
import "NotesStore.js" as Store
import "pages"

SilicaApp {
    id: app
    appId: "notes-silica"

    property var notes: []
    property bool savePending: false

    function load() {
        notes = Store.parse(SettingsManagerCpp.get("notes-silica/data", "[]"));
    }

    function save(next) {
        notes = next;
        if (typeof PermissionManager !== "undefined" && !PermissionManager.hasPermission(appId, "storage")) {
            savePending = true;
            PermissionManager.requestPermission(appId, "storage");
            return;
        }
        SettingsManagerCpp.set("notes-silica/data", JSON.stringify(notes));
        savePending = false;
    }

    Connections {
        target: typeof PermissionManager !== "undefined" ? PermissionManager : null
        ignoreUnknownSignals: true
        function onPermissionGranted(id, permission) {
            if (id === app.appId && permission === "storage" && app.savePending)
                app.save(app.notes);
        }
    }

    Component.onCompleted: load()

    initialPage: Component {
        NotesPage { store: app }
    }
}
```

Before writing `onPermissionGranted`, check the real signal name and arguments in `tools/marathon-app-runner/ipc/shellipcclients.h` (`class PermissionClient`) and how `apps/notes/NotesApp.qml` reacts to a grant; use the same.

`apps/notes-silica/pages/NotesPage.qml`:
```qml
import QtQuick
import Sailfish.Silica 1.0
import "../NotesStore.js" as Store

Page {
    id: page
    property var store

    SilicaListView {
        anchors.fill: parent
        header: PageHeader { title: qsTr("Notes") }
        model: page.store.notes

        PullDownMenu {
            MenuItem {
                text: qsTr("New note")
                onClicked: pageStack.push(Qt.resolvedUrl("NoteEditorPage.qml"), { store: page.store, noteId: -1 })
            }
        }

        ViewPlaceholder {
            enabled: page.store.notes.length === 0
            text: qsTr("No notes")
            hintText: qsTr("Pull down to add one")
        }

        delegate: ListItem {
            id: item
            required property var modelData
            contentHeight: Theme.itemSizeMedium
            menu: ContextMenu {
                MenuItem {
                    text: qsTr("Delete")
                    onClicked: item.remorseDelete(function () {
                        page.store.save(Store.remove(page.store.notes, item.modelData.id));
                    })
                }
            }
            onClicked: pageStack.push(Qt.resolvedUrl("NoteEditorPage.qml"), { store: page.store, noteId: item.modelData.id })

            Column {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                anchors.verticalCenter: parent.verticalCenter
                Label {
                    width: parent.width
                    text: item.modelData.title
                    truncationMode: TruncationMode.Fade
                    color: item.highlighted ? Theme.highlightColor : Theme.primaryColor
                }
                Label {
                    width: parent.width
                    text: item.modelData.content
                    font.pixelSize: Theme.fontSizeExtraSmall
                    truncationMode: TruncationMode.Fade
                    color: item.highlighted ? Theme.secondaryHighlightColor : Theme.secondaryColor
                }
            }
        }
        VerticalScrollDecorator {}
    }
}
```

`apps/notes-silica/pages/NoteEditorPage.qml`:
```qml
import QtQuick
import Sailfish.Silica 1.0
import "../NotesStore.js" as Store

Page {
    id: page
    property var store
    property int noteId: -1

    readonly property var note: store.notes.find(n => n.id === noteId)

    function commit() {
        const title = titleField.text.trim();
        const body = bodyArea.text;
        if (noteId < 0) {
            if (title === "" && body.trim() === "")
                return;
            store.save(Store.create(store.notes, title, body, Date.now()));
        } else if (!note || title !== note.title || body !== note.content) {
            store.save(Store.update(store.notes, noteId, title, body, Date.now()));
        }
    }

    onStatusChanged: if (status === PageStatus.Deactivating) commit()

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height

        Column {
            id: column
            width: parent.width
            PageHeader { title: page.noteId < 0 ? qsTr("New note") : qsTr("Edit note") }
            TextField {
                id: titleField
                width: parent.width
                label: qsTr("Title")
                placeholderText: qsTr("Title")
                text: page.note ? page.note.title : ""
                EnterKey.iconSource: "image://theme/icon-m-enter-next"
                EnterKey.onClicked: bodyArea.focus = true
            }
            TextArea {
                id: bodyArea
                width: parent.width
                placeholderText: qsTr("Note")
                text: page.note ? page.note.content : ""
            }
        }
        VerticalScrollDecorator {}
    }
}
```

`apps/notes-silica/manifest.json`:
```json
{
  "id": "notes-silica",
  "name": "Notes (Silica)",
  "version": "0.1.0",
  "entryPoint": "NotesSilicaApp.qml",
  "icon": "assets/icon.svg",
  "author": "Marathon OS",
  "permissions": ["storage"],
  "minShellVersion": "1.0.0",
  "categories": ["Productivity"],
  "handlesUriSchemes": [],
  "defaultFor": [],
  "searchKeywords": ["notes", "silica"],
  "deepLinks": {}
}
```

- [ ] **Step 6: Run it on the host**

Copy `apps/notes-silica` to `<scratch>/home/.local/share/marathon-apps/notes-silica`, then:
```bash
HOME=<scratch>/home QML_IMPORT_PATH=$HOME/Developer/Shipwright/build/keel/qml QT_QPA_PLATFORM=offscreen \
  timeout 20 build/tools/marathon-app-runner/marathon-app-runner --app-id notes-silica 2>&1 | grep -iE "error|warn|qml" | grep -viE "dbus|activatable"
```
Expected: no QML errors. For screenshots, temporarily add the spike's `grabToImage` timer in the scratch copy only.

- [ ] **Step 7: Stop: diff review**

---

### Task 4: Build and packaging wiring

**Files:**
- Create: `apps/notes-silica/CMakeLists.txt`
- Modify: `apps/CMakeLists.txt` (after `add_subdirectory(notes)`)
- Modify: `packaging/packages/marathon-shell/APKBUILD` (`depends`, `makedepends`; bump `pkgrel`)
- Modify: `scripts/qemu/lib/build-marathon-shell-apk.sh` (next to the qmf `/local-apks` install)

**Interfaces:**
- Consumes: `keel-silica` apk (Task 1), app files (Tasks 2–3).
- Produces: `/usr/share/marathon-apps/notes-silica/` in the marathon-shell apk.

- [ ] **Step 1: App CMake**

Read how `add_marathon_app` installs apps (`apps/CMakeLists.txt`). `notes-silica` is loaded from its entry file (the runner supports a plain `entryPoint` file), so install the directory as-is rather than compiling a module:
```cmake
install(DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/
    DESTINATION ${MARATHON_APPS_DIR}/notes-silica
    PATTERN "CMakeLists.txt" EXCLUDE
    PATTERN "tests" EXCLUDE)
```

- [ ] **Step 2: Conditional subdirectory**

In `apps/CMakeLists.txt`:
```cmake
find_path(SAILFISH_SILICA_QMLDIR Sailfish/Silica/qmldir PATHS ${QT6_INSTALL_PREFIX}/${QT6_INSTALL_QML} /usr/lib/qt6/qml /usr/lib64/qt6/qml)
if(SAILFISH_SILICA_QMLDIR)
  add_subdirectory(notes-silica)
else()
  message(STATUS "Sailfish.Silica not found - notes-silica will not be built")
endif()
```

- [ ] **Step 3: Check both configurations on the host**

Run a fresh configure of `apps/` into a scratch build dir twice: once as-is (host has no Silica in `/usr/lib64/qt6/qml`, so expect the "not built" message and a clean build), and once with `-DSAILFISH_SILICA_QMLDIR=$HOME/Developer/Shipwright/build/keel/qml` (expect `notes-silica` in `cmake --install --prefix <scratch>` output). Remove the scratch build dirs afterwards (disk is tight).

- [ ] **Step 4: Packaging**

`packaging/packages/marathon-shell/APKBUILD`: add `keel-silica` to `depends` and `makedepends`; bump `pkgrel`. `scripts/qemu/lib/build-marathon-shell-apk.sh`: after the qmf install, the same pattern for `keel-silica-*.apk` from `/local-apks` with `--allow-untrusted`, warning if absent.

- [ ] **Step 5: Build the apk**

Run: `bash scripts/qemu/lib/build-marathon-shell-apk.sh 2>&1 | tail -20` (do not run the lint probe concurrently).
Expected: new marathon-shell apk containing `usr/share/marathon-apps/notes-silica/manifest.json`.

- [ ] **Step 6: Stop: diff review**

---

### Task 5: Device verification (PinePhone)

**Files:** none (results go in the session report).

- [ ] **Step 1: Deploy in chunks**

Wait for `ip -br addr | grep 172.16.42.2`. Install `keel-silica` via `apk add --allow-untrusted` after copying the apk. Deploy the marathon-shell `usr/` tree split into ≤20 MB tars, checking `uptime` and `dmesg | tail` between chunks. Then `rm -rf /home/user/.cache/marathon-qml && systemctl restart greetd`. Check the wallpaper directory exists: `ls /usr/share/marathon-shell/wallpapers/`.

- [ ] **Step 2: Success criteria (spec §Goal)**

1. Launch Notes and Notes (Silica) three times each with `MARATHON_STARTUP_LOG=1`; compare median first-frame.
2. Drive with `marathon-touchctl`: pulley → New note, type title with the Marathon keyboard, back; long-press → Delete → wait for remorse; Switch/Slider are not in the app, so check them with the spike app copied to `/home/user/.local/share/marathon-apps/`.
3. Back gesture on the editor returns to the list; on the list it minimises.
4. Snap: highlight is teal; background is the dimmed Marathon wallpaper.
5. Background the app, wait for freeze, resume; kill via the task switcher and relaunch.
6. Notes created in step 2 are still there after relaunch.

Capture each with `snap`. If `Theme` sizes are wrong at 720×1440, try `KEEL_THEME_PIXEL_RATIO` in the app env and report the value that matches.

- [ ] **Step 3: Report**

Results per criterion with screenshots and timings; anything failed goes back to the user before fixing.
