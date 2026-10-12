import QtQuick
import QtTest
import Sailfish.Silica 1.0
import Marathon.Silica 1.0

TestCase {
    id: testCase
    name: "Buttons"
    when: windowShown
    visible: true
    width: 540; height: 960

    SignalSpy { id: clickSpy; signalName: "clicked" }

    Component { id: button; Button { text: "Save" } }
    Component { id: iconButton; IconButton { icon.source: "image://theme/icon-m-delete" } }
    Component { id: namedIconButton; IconButton { icon.source: "image://theme/icon-m-delete"; Accessible.name: "Remove note" } }
    Component { id: valueButton; ValueButton { label: "Ringtone"; value: "Chime" } }
    Component { id: backgroundItem; BackgroundItem { width: 200; height: 80 } }
    Component { id: menuItem; MenuItem { text: "Delete" } }

    function activationKeys() {
        return [{ tag: "return", key: Qt.Key_Return }, { tag: "enter", key: Qt.Key_Enter }, { tag: "space", key: Qt.Key_Space }];
    }

    function focusedClicks(component, key) {
        const item = createTemporaryObject(component, testCase);
        clickSpy.target = item;
        clickSpy.clear();
        item.forceActiveFocus();
        verify(item.activeFocus);
        keyClick(key);
        return clickSpy.count;
    }

    function test_buttonRoleAndName() {
        const b = createTemporaryObject(button, testCase);
        compare(b.Accessible.role, Accessible.Button);
        compare(b.Accessible.name, "Save");
        verify(b.activeFocusOnTab);
    }
    function test_buttonKeys_data() { return activationKeys(); }
    function test_buttonKeys(data) { compare(focusedClicks(button, data.key), 1); }

    function test_buttonIgnoresOtherKeys() { compare(focusedClicks(button, Qt.Key_A), 0); }

    function test_iconButtonNameFallsBackToIconName() {
        const b = createTemporaryObject(iconButton, testCase);
        compare(b.Accessible.role, Accessible.Button);
        compare(b.Accessible.name, "delete");
    }
    function test_iconButtonNameCanBeSet() {
        compare(createTemporaryObject(namedIconButton, testCase).Accessible.name, "Remove note");
    }
    function test_iconButtonKeys_data() { return activationKeys(); }
    function test_iconButtonKeys(data) { compare(focusedClicks(iconButton, data.key), 1); }

    function test_valueButtonNameIncludesValue() {
        const b = createTemporaryObject(valueButton, testCase);
        compare(b.Accessible.role, Accessible.Button);
        compare(b.Accessible.name, "Ringtone: Chime");
    }
    function test_valueButtonKeys_data() { return activationKeys(); }
    function test_valueButtonKeys(data) { compare(focusedClicks(valueButton, data.key), 1); }

    function test_backgroundItemKeys_data() { return activationKeys(); }
    function test_backgroundItemKeys(data) { compare(focusedClicks(backgroundItem, data.key), 1); }

    function test_menuItemRoleAndName() {
        const m = createTemporaryObject(menuItem, testCase);
        compare(m.Accessible.role, Accessible.MenuItem);
        compare(m.Accessible.name, "Delete");
    }
    function test_menuItemKeys_data() { return activationKeys(); }
    function test_menuItemKeys(data) { compare(focusedClicks(menuItem, data.key), 1); }

    function test_pressActionClicks() {
        const b = createTemporaryObject(button, testCase);
        clickSpy.target = b;
        clickSpy.clear();
        b.Accessible.pressAction();
        compare(clickSpy.count, 1);
    }

    function test_focusFrameFollowsActiveFocus() {
        const b = createTemporaryObject(button, testCase);
        const frame = findChild(b, "focusFrame");
        verify(frame);
        verify(!frame.showing);
        b.forceActiveFocus();
        verify(frame.showing);
        compare(frame.border.color, Theme.highlightColor);
    }

    function test_disabledButtonIgnoresKeys() {
        const b = createTemporaryObject(button, testCase, { enabled: false });
        clickSpy.target = b;
        clickSpy.clear();
        b.forceActiveFocus();
        keyClick(Qt.Key_Return);
        compare(clickSpy.count, 0);
    }
}
