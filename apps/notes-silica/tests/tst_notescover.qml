import QtQuick
import QtTest
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import "../cover"

TestCase {
    name: "NotesCover"
    when: windowShown
    visible: true
    width: 540; height: 960

    Component { id: cover; NotesCover {} }
    SignalSpy { id: newSpy; signalName: "newNoteRequested" }

    function test_listsLatestTitles() {
        const c = createTemporaryObject(cover, this, { notes: [{ id: 2, title: "Groceries" }, { id: 1, title: "Ideas" }] });
        const labels = findChild(c, "coverNotes");
        compare(labels.count, 2);
        verify(!findChild(c, "coverPlaceholder").enabled);
    }

    function test_atMostThree() {
        const c = createTemporaryObject(cover, this, { notes: [{ id: 4, title: "a" }, { id: 3, title: "b" }, { id: 2, title: "c" }, { id: 1, title: "d" }] });
        compare(findChild(c, "coverNotes").count, 3);
    }

    function test_placeholderWhenEmpty() {
        const c = createTemporaryObject(cover, this, { notes: [] });
        verify(findChild(c, "coverPlaceholder").enabled);
    }

    function test_newNoteAction() {
        const c = createTemporaryObject(cover, this, { notes: [] });
        newSpy.target = c;
        newSpy.clear();
        findChild(c, "newNoteAction").triggered();
        compare(newSpy.count, 1);
    }
}
