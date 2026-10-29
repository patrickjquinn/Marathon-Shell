import QtQuick
import QtTest
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import "../cover"

TestCase {
    name: "NotesCover"
    when: windowShown
    visible: true
    width: 540
    height: 960

    Component {
        id: cover
        NotesCover {}
    }
    SignalSpy {
        id: newSpy
        signalName: "newNoteRequested"
    }

    function test_showsLatestNote() {
        const c = createTemporaryObject(cover, this, {
            notes: [
                {
                    id: 2,
                    title: "Groceries",
                    content: "Groceries\nMilk\nBread"
                },
                {
                    id: 1,
                    title: "Ideas",
                    content: "Ideas"
                }
            ]
        });
        compare(findChild(c, "coverNoteTitle").text, "Groceries");
        compare(findChild(c, "coverNoteBody").text, "Milk\nBread");
        verify(!findChild(c, "coverPlaceholder").visible);
    }

    function test_legacyTitleKeptApart() {
        const c = createTemporaryObject(cover, this, {
            notes: [
                {
                    id: 1,
                    title: "Trip",
                    content: "Book ferry"
                }
            ]
        });
        compare(findChild(c, "coverNoteTitle").text, "Trip");
        compare(findChild(c, "coverNoteBody").text, "Book ferry");
    }

    function test_placeholderWhenEmpty() {
        const c = createTemporaryObject(cover, this, {
            notes: []
        });
        verify(findChild(c, "coverPlaceholder").visible);
    }

    function test_newNoteAction() {
        const c = createTemporaryObject(cover, this, {
            notes: []
        });
        newSpy.target = c;
        newSpy.clear();
        findChild(c, "newNoteAction").triggered();
        compare(newSpy.count, 1);
    }
}
