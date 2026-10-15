import QtQuick
import QtTest
import Sailfish.Silica 1.0
import Marathon.Silica 1.0

TestCase {
    id: testCase
    name: "ComboBox"
    when: windowShown
    visible: true
    width: 540; height: 960

    Component {
        id: combo
        ComboBox {
            width: 540
            label: "Theme"
            currentIndex: 0
            menu: ContextMenu {
                MenuItem { text: "Light" }
                MenuItem { text: "Dark" }
                MenuItem { text: "Auto" }
            }
        }
    }

    Component {
        id: comboAtBottom
        SilicaFlickable {
            property alias combo: bottomCombo
            width: 540; height: 960
            contentHeight: column.height
            Column {
                id: column
                width: parent.width
                Item { width: 1; height: 900 }
                ComboBox {
                    id: bottomCombo
                    width: 540
                    label: "Encryption"
                    menu: ContextMenu {
                        MenuItem { text: "SSL" }
                        MenuItem { text: "STARTTLS" }
                        MenuItem { text: "None" }
                    }
                }
            }
        }
    }

    function test_menuNearTheBottomScrollsIntoView() {
        const f = createTemporaryObject(comboAtBottom, testCase);
        f.combo.forceActiveFocus();
        keyClick(Qt.Key_Return);
        const menu = f.combo.menu;
        tryVerify(() => menu.active && menu.height > 0 && !f.moving);
        tryVerify(() => menu.mapToItem(f, 0, menu.height).y <= f.height + 1, 2000, "menu runs off the bottom");
        verify(menu.mapToItem(f, 0, 0).y >= 0);
    }

    function test_roleNameValue() {
        const c = createTemporaryObject(combo, testCase);
        compare(c.Accessible.role, Accessible.ComboBox);
        compare(c.Accessible.name, "Theme: Light");
        verify(c.activeFocusOnTab);
    }

    function test_arrowsChooseWhileClosed() {
        const c = createTemporaryObject(combo, testCase);
        c.forceActiveFocus();
        keyClick(Qt.Key_Down);
        compare(c.currentIndex, 1);
        keyClick(Qt.Key_Down);
        keyClick(Qt.Key_Down);
        compare(c.currentIndex, 2);
        keyClick(Qt.Key_Up);
        compare(c.currentIndex, 1);
        compare(c.value, "Dark");
    }

    function test_enterOpensMenuAndSelects() {
        const c = createTemporaryObject(combo, testCase);
        c.forceActiveFocus();
        keyClick(Qt.Key_Return);
        tryVerify(function () { return c._controller.menuOpen; });
        keyClick(Qt.Key_Down);
        keyClick(Qt.Key_Down);
        keyClick(Qt.Key_Return);
        tryCompare(c, "currentIndex", 2);
        tryVerify(function () { return !c._controller.menuOpen; });
        verify(c.activeFocus);
    }

    function test_escapeClosesMenuWithoutChanging() {
        const c = createTemporaryObject(combo, testCase);
        c.forceActiveFocus();
        keyClick(Qt.Key_Space);
        tryVerify(function () { return c._controller.menuOpen; });
        keyClick(Qt.Key_Down);
        keyClick(Qt.Key_Escape);
        tryVerify(function () { return !c._controller.menuOpen; });
        compare(c.currentIndex, 0);
        verify(c.activeFocus);
    }
}
