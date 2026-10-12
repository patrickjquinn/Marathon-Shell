import QtQuick
import QtTest
import Sailfish.Silica 1.0
import Marathon.Silica 1.0

TestCase {
    id: testCase
    name: "Menus"
    when: windowShown
    visible: true
    width: 540; height: 960

    property var log: []

    Component {
        id: pulleyPage
        SilicaFlickable {
            width: 540; height: 960
            contentHeight: 2000
            PullDownMenu {
                MenuItem { text: "Settings"; onClicked: testCase.log.push("settings") }
                MenuItem { text: "New note"; onClicked: testCase.log.push("new") }
            }
            PushUpMenu {
                MenuItem { text: "Back to top"; onClicked: testCase.log.push("top") }
            }
        }
    }

    Component {
        id: listWithMenu
        SilicaListView {
            width: 540; height: 960
            model: 5
            PullDownMenu {
                MenuItem { text: "New"; onClicked: testCase.log.push("new") }
            }
            delegate: ListItem {
                id: delegate
                required property int index
                Accessible.name: "Note " + index
                menu: ContextMenu {
                    MenuItem { text: "Delete"; onClicked: testCase.log.push("delete " + delegate.index) }
                    MenuItem { text: "Share"; onClicked: testCase.log.push("share " + delegate.index) }
                }
                onClicked: testCase.log.push("open " + index)
            }
        }
    }

    function init() { log = []; }

    function pulley(flick) {
        return flick.pullDownMenu;
    }

    function test_pullDownOpensFromKeyboard_data() {
        return [{ tag: "ctrl+m", key: Qt.Key_M, mod: Qt.ControlModifier }, { tag: "menu", key: Qt.Key_Menu, mod: Qt.NoModifier }];
    }
    function test_pullDownOpensFromKeyboard(data) {
        const f = createTemporaryObject(pulleyPage, testCase);
        f.forceActiveFocus();
        keyClick(data.key, data.mod);
        tryVerify(function () { return f.pullDownMenu.active; });
        compare(f.pullDownMenu.Accessible.role, Accessible.PopupMenu);
    }

    function test_pullDownArrowsAndEnterSelect() {
        const f = createTemporaryObject(pulleyPage, testCase);
        f.forceActiveFocus();
        keyClick(Qt.Key_M, Qt.ControlModifier);
        tryVerify(function () { return f.pullDownMenu.active; });
        keyClick(Qt.Key_Down);
        compare(f.pullDownMenu.menuItem.text, "Settings");
        keyClick(Qt.Key_Down);
        compare(f.pullDownMenu.menuItem.text, "New note");
        keyClick(Qt.Key_Return);
        tryCompare(testCase, "log", ["new"]);
        tryVerify(function () { return !f.pullDownMenu.active; });
        verify(f.activeFocus);
    }

    function test_pullDownEscapeCloses() {
        const f = createTemporaryObject(pulleyPage, testCase);
        f.forceActiveFocus();
        keyClick(Qt.Key_M, Qt.ControlModifier);
        tryVerify(function () { return f.pullDownMenu.active; });
        keyClick(Qt.Key_Escape);
        tryVerify(function () { return !f.pullDownMenu.active; });
        compare(log, []);
        verify(f.activeFocus);
    }

    function test_pushUpOpensFromKeyboardAtEnd() {
        const f = createTemporaryObject(pulleyPage, testCase);
        f.forceActiveFocus();
        keyClick(Qt.Key_End);
        tryVerify(function () { return f.atYEnd; });
        keyClick(Qt.Key_M, Qt.ControlModifier);
        tryVerify(function () { return f.pushUpMenu.active; });
        keyClick(Qt.Key_Up);
        keyClick(Qt.Key_Return);
        tryCompare(testCase, "log", ["top"]);
    }

    function test_listItemMenuKey_data() {
        return [{ tag: "menu", key: Qt.Key_Menu, mod: Qt.NoModifier }, { tag: "shift+f10", key: Qt.Key_F10, mod: Qt.ShiftModifier }];
    }
    function test_listItemMenuKey(data) {
        const v = createTemporaryObject(listWithMenu, testCase);
        v.forceActiveFocus();
        keyClick(Qt.Key_Down);
        const item = v.currentItem;
        compare(v.currentIndex, 1);
        verify(item.activeFocus);
        keyClick(data.key, data.mod);
        tryVerify(function () { return item.menuOpen; });
        keyClick(Qt.Key_Down);
        keyClick(Qt.Key_Down);
        keyClick(Qt.Key_Return);
        tryCompare(testCase, "log", ["share 1"]);
        tryVerify(function () { return !item.menuOpen; });
        verify(item.activeFocus);
    }

    function test_contextMenuEscape() {
        const v = createTemporaryObject(listWithMenu, testCase);
        v.forceActiveFocus();
        const item = v.currentItem;
        keyClick(Qt.Key_Menu);
        tryVerify(function () { return item.menuOpen; });
        keyClick(Qt.Key_Escape);
        tryVerify(function () { return !item.menuOpen; });
        compare(log, []);
        verify(item.activeFocus);
    }

    function test_contextMenuClosesWhenFocusLeaves() {
        const v = createTemporaryObject(listWithMenu, testCase);
        v.forceActiveFocus();
        const item = v.currentItem;
        keyClick(Qt.Key_Menu);
        tryVerify(function () { return item.menuOpen; });
        v.itemAtIndex(3).forceActiveFocus();
        tryVerify(function () { return !item.menuOpen; });
    }

    function test_ctrlMOnListItemOpensPulley() {
        const v = createTemporaryObject(listWithMenu, testCase);
        v.forceActiveFocus();
        const item = v.currentItem;
        verify(item.activeFocus);
        keyClick(Qt.Key_M, Qt.ControlModifier);
        tryVerify(function () { return v.pullDownMenu.active; });
        verify(!item.menuOpen);
    }

    function test_listItemEnterClicks() {
        const v = createTemporaryObject(listWithMenu, testCase);
        v.forceActiveFocus();
        keyClick(Qt.Key_Down);
        keyClick(Qt.Key_Down);
        keyClick(Qt.Key_Return);
        compare(log, ["open 2"]);
        compare(v.currentItem.Accessible.role, Accessible.ListItem);
        compare(v.currentItem.Accessible.name, "Note 2");
    }
}
