import QtQuick
import QtTest
import Sailfish.Silica 1.0
import Marathon.Silica 1.0

TestCase {
    id: testCase
    name: "Slider"
    when: windowShown
    visible: true
    width: 540
    height: 960

    Component {
        id: stepped
        Slider {
            width: 500
            label: "Volume"
            minimumValue: 0
            maximumValue: 10
            stepSize: 1
            value: 5
        }
    }
    Component {
        id: continuous
        Slider {
            width: 500
            label: "Brightness"
            minimumValue: 0
            maximumValue: 1
            value: 0.5
        }
    }

    function test_roleNameAndValue() {
        const s = createTemporaryObject(stepped, testCase);
        compare(s.Accessible.role, Accessible.Slider);
        compare(s.Accessible.name, "Volume");
        verify(s.activeFocusOnTab);
    }

    function test_arrowsStep() {
        const s = createTemporaryObject(stepped, testCase);
        s.forceActiveFocus();
        keyClick(Qt.Key_Right);
        compare(s.value, 6);
        keyClick(Qt.Key_Left);
        keyClick(Qt.Key_Left);
        compare(s.value, 4);
    }

    function test_pageKeysMoveTenPercent() {
        const s = createTemporaryObject(continuous, testCase);
        s.forceActiveFocus();
        keyClick(Qt.Key_PageUp);
        fuzzyCompare(s.value, 0.6, 1e-9);
        keyClick(Qt.Key_PageDown);
        keyClick(Qt.Key_PageDown);
        fuzzyCompare(s.value, 0.4, 1e-9);
    }

    function test_clampedToRange() {
        const s = createTemporaryObject(stepped, testCase, {
            value: 10
        });
        s.forceActiveFocus();
        keyClick(Qt.Key_Right);
        compare(s.value, 10);
        keyClick(Qt.Key_Home);
        compare(s.value, 0);
        keyClick(Qt.Key_Left);
        compare(s.value, 0);
        keyClick(Qt.Key_End);
        compare(s.value, 10);
    }

    function test_increaseAction() {
        const s = createTemporaryObject(stepped, testCase);
        s.Accessible.increaseAction();
        compare(s.value, 6);
        s.Accessible.decreaseAction();
        compare(s.value, 5);
    }
}
