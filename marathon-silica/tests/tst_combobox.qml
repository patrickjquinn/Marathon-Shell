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
