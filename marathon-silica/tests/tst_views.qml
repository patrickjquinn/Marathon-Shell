import QtQuick
import QtTest
import Sailfish.Silica 1.0
import Marathon.Silica 1.0

TestCase {
    id: testCase
    name: "Views"
    when: windowShown
    visible: true
    width: 540; height: 960

    Component {
        id: list
        SilicaListView {
            width: 540; height: 960
            model: 30
            delegate: ListItem { required property int index; Label { text: "Row " + parent.index } }
        }
    }
    Component {
        id: searchList
        SilicaListView {
            id: v
            property string query: ""
            readonly property Item field: headerItem
            width: 540; height: 960
            model: ["apple", "apricot", "banana", "blueberry"].filter(w => w.indexOf(query) >= 0)
            header: SearchField { width: 540; onTextChanged: v.query = text }
            delegate: ListItem { required property string modelData; Label { text: parent.modelData } }
        }
    }

    function test_headerFieldKeepsFocusWhileFiltering() {
        const v = createTemporaryObject(searchList, testCase);
        v.field.forceActiveFocus();
        keyClick(Qt.Key_A);
        keyClick(Qt.Key_P);
        compare(v.field.text, "ap");
        compare(v.count, 2);
        verify(v.field.activeFocus);
        keyClick(Qt.Key_Down);
        verify(v.currentItem.activeFocus);
    }

    Component {
        id: searchGrid
        SilicaGridView {
            id: g
            property string query: ""
            readonly property Item field: headerItem
            width: 540; height: 960
            cellWidth: 270; cellHeight: 180
            model: ["apple", "apricot", "banana", "blueberry"].filter(w => w.indexOf(query) >= 0)
            header: SearchField { width: 540; onTextChanged: g.query = text }
            delegate: BackgroundItem { required property string modelData; width: 270; height: 180; Label { text: parent.modelData } }
        }
    }

    function test_gridHeaderFieldKeepsFocusWhileFiltering() {
        const g = createTemporaryObject(searchGrid, testCase);
        g.field.forceActiveFocus();
        keyClick(Qt.Key_B);
        keyClick(Qt.Key_Backspace);
        keyClick(Qt.Key_A);
        compare(g.field.text, "a");
        compare(g.count, 3);
        verify(g.field.activeFocus);
        keyClick(Qt.Key_Down);
        verify(g.currentItem.activeFocus);
    }

    Component {
        id: flick
        SilicaFlickable { width: 540; height: 960; contentHeight: 3000 }
    }

    function test_listArrowsMoveFocus() {
        const v = createTemporaryObject(list, testCase);
        compare(v.Accessible.role, Accessible.List);
        v.forceActiveFocus();
        keyClick(Qt.Key_Down);
        keyClick(Qt.Key_Down);
        compare(v.currentIndex, 2);
        verify(v.currentItem.activeFocus);
        keyClick(Qt.Key_Up);
        compare(v.currentIndex, 1);
    }

    function test_listHomeEnd() {
        const v = createTemporaryObject(list, testCase);
        v.forceActiveFocus();
        keyClick(Qt.Key_End);
        compare(v.currentIndex, 29);
        tryVerify(function () { return v.atYEnd; });
        keyClick(Qt.Key_Home);
        compare(v.currentIndex, 0);
        tryVerify(function () { return v.atYBeginning; });
    }

    Component {
        id: form
        Item {
            width: 540; height: 960
            property alias flick: flick
            property alias field: field
            property alias before: before
            Button { id: before; text: "Before" }
            SilicaFlickable {
                id: flick
                y: 100; width: 540; height: 800; contentHeight: 3000
                TextField { id: field; width: 500; label: "Title" }
            }
        }
    }

    function test_flickableWithControlsIsNotATabStop() {
        const f = createTemporaryObject(form, testCase);
        tryVerify(function () { return !f.flick.activeFocusOnTab; });
        f.before.forceActiveFocus();
        keyClick(Qt.Key_Tab);
        verify(f.field.activeFocus);
        keyClick(Qt.Key_PageDown);
        tryVerify(function () { return f.flick.contentY > 0; });
    }

    function test_flickableArrowsScroll() {
        const f = createTemporaryObject(flick, testCase);
        f.forceActiveFocus();
        keyClick(Qt.Key_Down);
        tryVerify(function () { return f.contentY > 0; });
        keyClick(Qt.Key_End);
        tryVerify(function () { return f.atYEnd; });
        keyClick(Qt.Key_Home);
        tryVerify(function () { return f.atYBeginning; });
    }

    function test_flickablePageDown() {
        const f = createTemporaryObject(flick, testCase);
        f.forceActiveFocus();
        keyClick(Qt.Key_PageDown);
        tryVerify(function () { return f.contentY >= f.height * 0.8; });
    }
}
