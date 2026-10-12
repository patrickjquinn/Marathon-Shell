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

    // A pill toggle on the right in place of Silica's glass dot on the left.
    function test_textSwitchIsAPillOnTheRight() {
        const s = createTemporaryObject(textSwitch, testCase);
        const pill = findChild(s, "toggle");
        verify(pill && pill.visible);
        verify(pill.x + pill.width <= s.width - Theme.horizontalPageMargin + 1);
        verify(pill.x > s.width / 2);
        const label = findChild(s, "toggleLabel") || s._label;
        compare(Math.round(label.mapToItem(s, 0, 0).x), Math.round(Theme.horizontalPageMargin));
        verify(label.x + label.width <= pill.x);
        verify(!findChild(s, "glass").visible);
    }

    function test_iconTextSwitchLeadsWithItsIcon() {
        const s = createTemporaryObject(iconTextSwitch, testCase);
        const pill = findChild(s, "toggle");
        verify(pill && pill.visible);
        verify(pill.x > s.width / 2);
        compare(Math.round(s.icon.x), Math.round(Theme.horizontalPageMargin));
        verify(s._label.mapToItem(s, 0, 0).x >= s.icon.x + s.icon.width);
        verify(s._label.mapToItem(s, 0, 0).x + s._label.width <= pill.x);
        verify(!findChild(s, "glass").visible);
    }

    function test_pillFollowsChecked() {
        const s = createTemporaryObject(textSwitch, testCase);
        const knob = findChild(s, "toggleKnob");
        const off = knob.x;
        s.checked = true;
        tryVerify(function () { return knob.x > off; });
    }

    function test_focusFrame() {
        const s = createTemporaryObject(textSwitch, testCase);
        verify(s.activeFocusOnTab);
        s.forceActiveFocus();
        verify(findChild(s, "focusFrame").showing);
    }
}
