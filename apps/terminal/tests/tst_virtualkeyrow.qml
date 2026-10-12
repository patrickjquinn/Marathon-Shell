import QtQuick
import QtTest
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import "../components"

TestCase {
    id: test

    name: "VirtualKeyRow"
    when: windowShown
    visible: true
    width: 540; height: 200

    Component {
        id: rowComponent
        VirtualKeyRow { width: 540 }
    }
    SignalSpy { id: keySpy; signalName: "keyTriggered" }

    function makeRow() {
        const row = createTemporaryObject(rowComponent, test);
        keySpy.target = row;
        keySpy.clear();
        return row;
    }

    function key(row, name) {
        return findChild(row, "key_" + name);
    }

    function test_hasTheTerminalKeys() {
        const row = makeRow();
        for (const name of ["Esc", "Tab", "Ctrl", "Alt", "|", "~", "left", "down", "up", "right"])
            verify(key(row, name), name);
        compare(key(row, "Esc").Accessible.name, "Escape");
        compare(key(row, "up").Accessible.name, "Up");
    }

    function test_tapSendsKey() {
        const row = makeRow();
        mouseClick(key(row, "Esc"));
        compare(keySpy.count, 1);
        compare(keySpy.signalArguments[0][0], Qt.Key_Escape);
        mouseClick(key(row, "|"));
        compare(keySpy.signalArguments[1][1], "|");
    }

    function test_holdSendsAlternate() {
        const row = makeRow();
        mousePress(key(row, "|"));
        tryCompare(keySpy, "count", 1, 3000);
        mouseRelease(key(row, "|"));
        compare(keySpy.signalArguments[0][0], 0);
        compare(keySpy.signalArguments[0][1], "\\");
    }

    function test_ctrlArmsForOneKey() {
        const row = makeRow();
        mouseClick(key(row, "Ctrl"));
        compare(row.ctrlState, VirtualKeyRow.Armed);
        verify(key(row, "Ctrl").Accessible.checked);
        mouseClick(key(row, "Tab"));
        compare(keySpy.signalArguments[0][2], Qt.ControlModifier);
        compare(row.ctrlState, VirtualKeyRow.Idle);
    }

    function test_tapAgainDisarms() {
        const row = makeRow();
        mouseClick(key(row, "Alt"));
        mouseClick(key(row, "Alt"));
        compare(row.altState, VirtualKeyRow.Idle);
    }

    function test_holdLocks() {
        const row = makeRow();
        mousePress(key(row, "Ctrl"));
        tryCompare(row, "ctrlState", VirtualKeyRow.Locked, 3000);
        mouseRelease(key(row, "Ctrl"));
        verify(key(row, "Ctrl").highlighted);
        mouseClick(key(row, "up"));
        mouseClick(key(row, "down"));
        compare(keySpy.signalArguments[1][2], Qt.ControlModifier);
        compare(row.ctrlState, VirtualKeyRow.Locked);
        mouseClick(key(row, "Ctrl"));
        compare(row.ctrlState, VirtualKeyRow.Idle);
    }

    function test_modifiersCombine() {
        const row = makeRow();
        mouseClick(key(row, "Ctrl"));
        mouseClick(key(row, "Alt"));
        compare(row.modifiers, Qt.ControlModifier | Qt.AltModifier);
        row.consumeArmed();
        compare(row.modifiers, 0);
    }
}
