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
        findChild(page, "bodyField").text = "A";
        tryCompare(store, "saves", 1, 3000);
        compare(store.notes.length, 1);
        compare(page.noteId, store.notes[0].id);

        findChild(page, "bodyField").text = "A\nmore";
        tryCompare(store, "saves", 2, 3000);
        compare(store.notes.length, 1);
        compare(store.notes[0].title, "A");
        compare(store.notes[0].content, "A\nmore");
    }

    function test_emptyNewNoteIsNotSaved() {
        const store = createTemporaryObject(storeStub, this);
        const page = createTemporaryObject(pageComponent, this, { store: store, noteId: -1 });
        findChild(page, "bodyField").text = "  \n ";
        page.commit();
        compare(store.saves, 0);
    }

    function test_openingDoesNotSave() {
        const store = createTemporaryObject(storeStub, this, { notes: [{ id: 3, title: "T", content: "B", timestamp: 1 }] });
        const page = createTemporaryObject(pageComponent, this, { store: store, noteId: 3 });
        compare(findChild(page, "bodyField").text, "T\nB");
        wait(1000);
        page.commit();
        compare(store.saves, 0);
    }

    function test_savingDoesNotRewriteTheField() {
        const store = createTemporaryObject(storeStub, this);
        const page = createTemporaryObject(pageComponent, this, { store: store, noteId: -1 });
        const body = findChild(page, "bodyField");
        body.text = "Hello ";
        page.commit();
        compare(store.notes[0].title, "Hello");
        compare(body.text, "Hello ");
    }

    function test_headerShowsDateNotTitle() {
        const store = createTemporaryObject(storeStub, this, { notes: [{ id: 3, title: "T", content: "T", timestamp: new Date(2025, 8, 7).getTime() }] });
        const page = createTemporaryObject(pageComponent, this, { store: store, noteId: 3 });
        compare(findChild(page, "header").title, "7 Sep 2025");
        verify(!findChild(page, "titleField"));
    }

    function test_editKeepsPin() {
        const store = createTemporaryObject(storeStub, this, { notes: [{ id: 3, title: "T", content: "", timestamp: 1, pinned: true }] });
        const page = createTemporaryObject(pageComponent, this, { store: store, noteId: 3 });
        findChild(page, "bodyField").text = "T\nx";
        page.commit();
        compare(store.notes[0].content, "T\nx");
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
