import QtQuick
import QtTest
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import ".."

TestCase {
    name: "NotesApp"
    when: windowShown

    Component {
        id: valueStub
        QtObject {
            property var value
        }
    }
    Component {
        id: legacyStub
        QtObject {
            property string data: "[]"
            property int reads: 0
            function get(key, fallback) {
                reads++;
                return key === "notes/data" ? data : fallback;
            }
        }
    }
    Component {
        id: permissionsStub
        QtObject {
            property bool granted: true
            function hasPermission(appId, permission) {
                return granted && appId === "notes" && permission === "storage";
            }
        }
    }
    Component {
        id: appComponent
        NotesApp {
            width: 540
            height: 1140
        }
    }

    function makeApp(stored, legacyData, granted, imported) {
        const store = createTemporaryObject(valueStub, this, {
            value: stored === undefined ? "[]" : stored
        });
        const flag = createTemporaryObject(valueStub, this, {
            value: imported === true
        });
        const legacy = createTemporaryObject(legacyStub, this, {
            data: legacyData || "[]"
        });
        const permissions = createTemporaryObject(permissionsStub, this, {
            granted: granted !== false
        });
        const app = createTemporaryObject(appComponent, this, {
            store: store,
            imported: flag,
            legacySettings: legacy,
            permissions: permissions
        });
        return {
            app: app,
            store: store,
            flag: flag,
            legacy: legacy
        };
    }

    function test_corruptDataStartsEmpty() {
        compare(makeApp("{not json").app.notes.length, 0);
    }

    function test_loadsStoredNotes() {
        const t = makeApp(JSON.stringify([
            {
                id: 3,
                title: "A",
                content: "",
                timestamp: 1
            }
        ]), undefined, true, true);
        compare(t.app.notes.length, 1);
        compare(t.app.notes[0].title, "A");
    }

    function test_saveWritesStore() {
        const t = makeApp();
        t.app.save([
            {
                id: 1,
                title: "X",
                content: "",
                timestamp: 1
            }
        ]);
        compare(JSON.parse(t.store.value)[0].title, "X");
        compare(t.app.notes[0].title, "X");
    }

    function test_storesAreConfigurationValues() {
        const app = createTemporaryObject(appComponent, this, {
            legacySettings: null
        });
        compare(app.store.key, "/apps/notes/data");
        compare(app.imported.key, "/apps/notes/legacyImported");
    }

    function test_importsLegacyNotesOnce() {
        const old = JSON.stringify([
            {
                id: 1,
                title: "Old",
                content: "kept",
                timestamp: 5,
                pinned: true
            }
        ]);
        const t = makeApp("[]", old);
        compare(t.app.notes.length, 1);
        compare(t.app.notes[0].title, "Old");
        verify(t.app.notes[0].pinned);
        verify(t.flag.value);
        t.app.importLegacy();
        compare(t.legacy.reads, 1);
        compare(t.app.notes.length, 1);
    }

    function test_importKeepsNotesWrittenBeforeIt() {
        const now = JSON.stringify([
            {
                id: 1,
                title: "New",
                content: "",
                timestamp: 9
            }
        ]);
        const old = JSON.stringify([
            {
                id: 1,
                title: "Old",
                content: "",
                timestamp: 5
            }
        ]);
        const t = makeApp(now, old);
        compare(t.app.notes.map(n => n.title), ["New", "Old"]);
        compare(t.app.notes.map(n => n.id), [1, 2]);
    }

    function test_noImportWithoutStorageGrant() {
        const t = makeApp("[]", JSON.stringify([
            {
                id: 1,
                title: "Old",
                content: "",
                timestamp: 5
            }
        ]), false);
        compare(t.legacy.reads, 0);
        compare(t.app.notes.length, 0);
        verify(!t.flag.value);
    }

    function test_emptyLegacyStoreMarksImported() {
        const t = makeApp("[]", "[]");
        compare(t.legacy.reads, 1);
        verify(t.flag.value);
        compare(t.store.value, "[]");
    }

    function test_alreadyImportedSkipsLegacy() {
        const t = makeApp("[]", JSON.stringify([
            {
                id: 1,
                title: "Old",
                content: "",
                timestamp: 5
            }
        ]), true, true);
        compare(t.legacy.reads, 0);
        compare(t.app.notes.length, 0);
    }

    function test_aShareBecomesANoteAndOpens() {
        const t = makeApp("[]", "[]", true, true);
        t.app.receiveShare([
            {
                name: "Marathon",
                data: "https://marathonos.org"
            }
        ]);
        compare(t.app.notes.length, 1);
        compare(t.app.notes[0].title, "Marathon");
        tryCompare(t.app.pageStack, "depth", 2);
        compare(t.app.pageStack.currentPage.noteId, t.app.notes[0].id);
    }
}
