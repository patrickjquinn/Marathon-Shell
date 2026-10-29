import QtQuick
import QtTest
import Sailfish.Silica 1.0
import Marathon.Silica 1.0

TestCase {
    id: testCase
    name: "Indicators"
    when: windowShown
    visible: true
    width: 540
    height: 960

    Component {
        id: indicator
        PageIndicator {
            count: 4
            currentIndex: 1
        }
    }
    Component {
        id: chip
        FilterChip {
            text: "Unread"
        }
    }
    SignalSpy {
        id: spy
        signalName: "clicked"
    }

    function test_pageIndicatorDescribesPosition() {
        const p = createTemporaryObject(indicator, testCase);
        compare(p.Accessible.role, Accessible.Indicator);
        compare(p.Accessible.name, "Page 2 of 4");
        verify(p.implicitWidth > 0 && p.implicitHeight > 0);
    }

    function test_pageIndicatorKeysAndTaps() {
        const p = createTemporaryObject(indicator, testCase, {
            interactive: true
        });
        verify(p.activeFocusOnTab);
        p.forceActiveFocus();
        keyClick(Qt.Key_Right);
        compare(p.currentIndex, 2);
        keyClick(Qt.Key_End);
        compare(p.currentIndex, 3);
        keyClick(Qt.Key_Right);
        compare(p.currentIndex, 3);
        keyClick(Qt.Key_Home);
        compare(p.currentIndex, 0);
        mouseClick(p, p.width - 2, p.height / 2);
        compare(p.currentIndex, 3);
    }

    function test_staticIndicatorIgnoresKeys() {
        const p = createTemporaryObject(indicator, testCase);
        verify(!p.activeFocusOnTab);
        p.forceActiveFocus();
        keyClick(Qt.Key_Right);
        compare(p.currentIndex, 1);
    }

    function test_dotsFollowCount() {
        const p = createTemporaryObject(indicator, testCase);
        const before = p.implicitWidth;
        p.count = 6;
        verify(p.implicitWidth > before);
    }

    function test_filterChipToggles() {
        const c = createTemporaryObject(chip, testCase);
        compare(c.Accessible.role, Accessible.CheckBox);
        compare(c.Accessible.name, "Unread");
        verify(c.Accessible.checkable);
        spy.target = c;
        spy.clear();
        c.forceActiveFocus();
        keyClick(Qt.Key_Space);
        verify(c.checked);
        compare(spy.count, 1);
        mouseClick(c);
        verify(!c.checked);
        compare(c.Accessible.checked, false);
    }

    function test_filterChipMeetsTargetSize() {
        const c = createTemporaryObject(chip, testCase);
        verify(c.height >= Theme.itemSizeExtraSmall);
    }

    function test_filterChipShowsStateWithAGlassDot() {
        const c = createTemporaryObject(chip, testCase);
        const dot = findChild(c, "chipIndicator");
        verify(dot.dimmed);
        c.checked = true;
        verify(!dot.dimmed);
        compare(c._backgroundColor.a, 0);
    }

    function test_filterChipFocusFrame() {
        const c = createTemporaryObject(chip, testCase);
        c.forceActiveFocus();
        verify(findChild(c, "focusFrame").showing);
    }
}
