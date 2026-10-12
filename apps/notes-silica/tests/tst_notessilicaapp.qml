import QtQuick
import QtTest
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import ".."

TestCase {
    name: "NotesSilicaApp"
    when: windowShown

    Component {
        id: storeStub
        QtObject {
            property var value: "[]"
        }
    }
    Component {
        id: appComponent
        NotesSilicaApp { width: 540; height: 1140 }
    }

    function makeApp(stored) {
        const store = createTemporaryObject(storeStub, this);
        if (stored !== undefined)
            store.value = stored;
        const app = createTemporaryObject(appComponent, this, { store: store });
        return { app: app, store: store };
    }

    function test_corruptDataStartsEmpty() {
        compare(makeApp("{not json").app.notes.length, 0);
    }

    function test_loadsStoredNotes() {
        const t = makeApp(JSON.stringify([{ id: 3, title: "A", content: "", timestamp: 1 }]));
        compare(t.app.notes.length, 1);
        compare(t.app.notes[0].title, "A");
    }

    function test_saveWritesStore() {
        const t = makeApp();
        t.app.save([{ id: 1, title: "X", content: "", timestamp: 1 }]);
        compare(JSON.parse(t.store.value)[0].title, "X");
    }

    function test_storeIsAConfigurationValue() {
        const app = createTemporaryObject(appComponent, this);
        compare(app.store.key, "/apps/notes-silica/data");
    }
}
