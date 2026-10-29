import QtQuick
import QtTest
import Sailfish.Silica 1.0
import Marathon.Silica 1.0

TestCase {
    id: testCase
    name: "Text"
    when: windowShown
    visible: true
    width: 540
    height: 960

    Component {
        id: labelled
        TextField {
            width: 500
            label: "Name"
            placeholderText: "Your name"
        }
    }
    Component {
        id: placeholderOnly
        TextField {
            width: 500
            placeholderText: "Search"
        }
    }
    Component {
        id: area
        TextArea {
            width: 500
            label: "Body"
        }
    }
    Component {
        id: search
        SearchField {
            width: 500
            placeholderText: "Search notes"
        }
    }
    Component {
        id: form
        Column {
            width: 500
            property alias first: first
            property alias second: second
            TextField {
                id: first
                width: 500
                label: "First"
            }
            TextField {
                id: second
                width: 500
                label: "Second"
            }
        }
    }

    function test_names_data() {
        return [
            {
                tag: "label",
                c: labelled,
                name: "Name"
            },
            {
                tag: "placeholder",
                c: placeholderOnly,
                name: "Search"
            },
            {
                tag: "area",
                c: area,
                name: "Body"
            },
            {
                tag: "search",
                c: search,
                name: "Search notes"
            }
        ];
    }
    function test_names(data) {
        const t = createTemporaryObject(data.c, testCase);
        compare(t.Accessible.role, Accessible.EditableText);
        compare(t.Accessible.name, data.name);
        verify(t.activeFocusOnTab);
    }

    function test_tabMovesBetweenFields() {
        const f = createTemporaryObject(form, testCase);
        f.first.forceActiveFocus();
        verify(f.first.activeFocus);
        keyClick(Qt.Key_A);
        compare(f.first.text, "a");
        keyClick(Qt.Key_Tab);
        verify(f.second.activeFocus);
        keyClick(Qt.Key_B);
        compare(f.second.text, "b");
    }

    // A focused field shows Silica's own cursor and underline, no box.
    function test_noFocusFrameOnField() {
        const t = createTemporaryObject(labelled, testCase);
        t.forceActiveFocus();
        verify(t._editor.activeFocus);
        compare(findChild(t, "focusFrame"), null);
    }
}
