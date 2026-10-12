import QtQuick
import QtTest
import Sailfish.Silica 1.0
import Keel 1.0
import "../pages"

TestCase {
    name: "NoteEditorPage"
    when: windowShown

    Component {
        id: storeStub
        QtObject {
            property var notes: []
            property int saves: 0
            function save(next) { notes = next; saves++; }
        }
    }
    Component {
        id: pageComponent
        NoteEditorPage { width: 540; height: 1140 }
    }

    function test_typingSavesWithoutLeavingPage() {
        const store = createTemporaryObject(storeStub, this);
        const page = createTemporaryObject(pageComponent, this, { store: store, noteId: -1 });
        findChild(page, "titleField").text = "A";
        tryCompare(store, "saves", 1, 3000);
        compare(store.notes.length, 1);
        compare(page.noteId, store.notes[0].id);

        findChild(page, "bodyField").text = "more";
        tryCompare(store, "saves", 2, 3000);
        compare(store.notes.length, 1);
        compare(store.notes[0].content, "more");
    }
}
