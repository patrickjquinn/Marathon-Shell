import QtQuick
import QtTest
import Sailfish.Silica 1.0
import Marathon.Silica 1.0

TestCase {
    id: testCase
    name: "Switches"
    when: windowShown
    visible: true
    width: 540; height: 960

    Component { id: textSwitch; TextSwitch { text: "Wi-Fi"; description: "Connect automatically" } }
    Component { id: plainSwitch; Switch { icon.source: "image://theme/icon-m-wlan" } }
    Component { id: iconTextSwitch; IconTextSwitch { text: "Bluetooth"; icon.source: "image://theme/icon-m-bluetooth" } }
    Component { id: manualSwitch; TextSwitch { text: "Manual"; automaticCheck: false } }

    function switches() {
        return [{ tag: "TextSwitch", c: textSwitch, name: "Wi-Fi" },
                { tag: "Switch", c: plainSwitch, name: "wlan" },
                { tag: "IconTextSwitch", c: iconTextSwitch, name: "Bluetooth" }];
    }

    function test_roleNameAndState_data() { return switches(); }
    function test_roleNameAndState(data) {
        const s = createTemporaryObject(data.c, testCase);
        compare(s.Accessible.role, Accessible.CheckBox);
        compare(s.Accessible.name, data.name);
        verify(s.Accessible.checkable);
        compare(s.Accessible.checked, false);
        s.checked = true;
        compare(s.Accessible.checked, true);
    }

    function test_spaceToggles_data() { return switches(); }
    function test_spaceToggles(data) {
        const s = createTemporaryObject(data.c, testCase);
        s.forceActiveFocus();
        keyClick(Qt.Key_Space);
        compare(s.checked, true);
        keyClick(Qt.Key_Space);
        compare(s.checked, false);
    }

    function test_descriptionIsExposed() {
        compare(createTemporaryObject(textSwitch, testCase).Accessible.description, "Connect automatically");
    }

    function test_toggleActionRespectsAutomaticCheck() {
        const s = createTemporaryObject(manualSwitch, testCase);
        s.Accessible.toggleAction();
        compare(s.checked, false);
    }

    function test_focusFrame() {
        const s = createTemporaryObject(textSwitch, testCase);
        verify(s.activeFocusOnTab);
        s.forceActiveFocus();
        verify(findChild(s, "focusFrame").showing);
    }
}
