import QtQuick
import QtTest
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import "../pages"

TestCase {
    id: testCase
    name: "NoteEditorPage"
    when: windowShown
    visible: true
    width: 540; height: 1140

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
    Component {
        id: appComponent
        ApplicationWindow {
            width: 540; height: 1140
            initialPage: Component { Page {} }
        }
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

    function test_emptyNewNoteIsNotSaved() {
        const store = createTemporaryObject(storeStub, this);
        const page = createTemporaryObject(pageComponent, this, { store: store, noteId: -1 });
        findChild(page, "titleField").text = "  ";
        page.commit();
        compare(store.saves, 0);
    }

    function test_openingDoesNotSave() {
        const store = createTemporaryObject(storeStub, this, { notes: [{ id: 3, title: "T", content: "B", timestamp: 1 }] });
        const page = createTemporaryObject(pageComponent, this, { store: store, noteId: 3 });
        compare(findChild(page, "titleField").text, "T");
        compare(findChild(page, "bodyField").text, "B");
        wait(1000);
        page.commit();
        compare(store.saves, 0);
    }

    function test_savingDoesNotRewriteTheField() {
        const store = createTemporaryObject(storeStub, this);
        const page = createTemporaryObject(pageComponent, this, { store: store, noteId: -1 });
        const title = findChild(page, "titleField");
        title.text = "Hello ";
        page.commit();
        compare(store.notes[0].title, "Hello");
        compare(title.text, "Hello ");
    }

    function test_editKeepsPin() {
        const store = createTemporaryObject(storeStub, this, { notes: [{ id: 3, title: "T", content: "", timestamp: 1, pinned: true }] });
        const page = createTemporaryObject(pageComponent, this, { store: store, noteId: 3 });
        findChild(page, "bodyField").text = "x";
        page.commit();
        compare(store.notes[0].content, "x");
        verify(store.notes[0].pinned);
    }

    function test_pulleyPinToggles() {
        const store = createTemporaryObject(storeStub, this, { notes: [{ id: 3, title: "T", content: "", timestamp: 1 }] });
        const page = createTemporaryObject(pageComponent, this, { store: store, noteId: 3 });
        findChild(page, "pinNoteItem").clicked(null);
        verify(store.notes[0].pinned);
        findChild(page, "pinNoteItem").clicked(null);
        verify(!store.notes[0].pinned);
    }

    function test_deleteWithRemorsePops() {
        const store = createTemporaryObject(storeStub, this, { notes: [{ id: 3, title: "T", content: "", timestamp: 1 }, { id: 4, title: "U", content: "", timestamp: 2 }] });
        const app = createTemporaryObject(appComponent, testCase);
        tryVerify(() => app.pageStack.currentPage !== null);
        app.pageStack.push(pageComponent, { store: store, noteId: 3 }, PageStackAction.Immediate);
        const page = app.pageStack.currentPage;
        findChild(page, "bodyField").text = "edited";
        page.deleteNote();
        compare(store.notes.length, 2);
        tryCompare(app.pageStack, "depth", 1, 10000);
        compare(store.notes.map(n => n.id), [4]);
    }
}
