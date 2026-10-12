import QtQuick
import QtQuick.Window
import QtTest
import Sailfish.Silica 1.0 as Silica
import MarathonOS.Shell
import "../../shell/qml/components"

TestCase {
    name: "NavBar"
    when: windowShown

    Window {
        width: 720
        height: 400
        visible: true

        MarathonNavBar {
            id: nav
            y: 300
            width: 720
            height: 96
            shortSwipeThreshold: 40
            longSwipeThreshold: 200
        }
    }

    SignalSpy { id: homeSpy; target: nav; signalName: "shortSwipeUp" }
    SignalSpy { id: searchSpy; target: nav; signalName: "toggleSearch" }
    SignalSpy { id: keyboardSpy; target: nav; signalName: "toggleKeyboard" }
    SignalSpy { id: leftSpy; target: nav; signalName: "swipeLeft" }
    SignalSpy { id: rightSpy; target: nav; signalName: "swipeRight" }

    function init() {
        UIStore.closeQuickSettings();
        nav.isAppOpen = false;
        homeSpy.clear();
        searchSpy.clear();
        keyboardSpy.clear();
        leftSpy.clear();
        rightSpy.clear();
    }

    function drag(x, y, dx, dy) {
        mousePress(nav, x, y);
        const steps = 8;
        for (let i = 1; i <= steps; ++i)
            mouseMove(nav, x + dx * i / steps, y + dy * i / steps, 16);
        mouseRelease(nav, x + dx, y + dy);
    }

    function test_pullDownOpensQuickSettings() {
        drag(nav.width / 2, nav.height / 2, 0, 40);
        verify(UIStore.quickSettingsOpen);
    }

    function test_pullDownAtTheEdgeOpensQuickSettings() {
        drag(nav.width - 10, 10, 0, 40);
        verify(UIStore.quickSettingsOpen);
    }

    function test_swipeUpNearEitherEdgeGoesHome() {
        drag(10, nav.height - 5, 0, -80);
        drag(nav.width - 10, nav.height - 5, 0, -80);
        compare(homeSpy.count, 2);
        compare(searchSpy.count, 0);
        compare(keyboardSpy.count, 0);
    }

    function test_buttonsMeetTheTouchTarget() {
        for (const name of ["searchButton", "keyboardButton"]) {
            const b = findChild(nav, name);
            verify(b, name);
            verify(b.width >= Silica.Theme.itemSizeExtraSmall, name + " width " + b.width);
            verify(b.height >= Math.min(nav.height, Silica.Theme.itemSizeExtraSmall), name + " height " + b.height);
        }
    }

    function test_tapButtons() {
        const s = findChild(nav, "searchButton");
        const k = findChild(nav, "keyboardButton");
        // Near the hit area's outer corner, past the glyph.
        mouseClick(s, s.width - 2, 2);
        mouseClick(k, 2, k.height - 2);
        compare(searchSpy.count, 1);
        compare(keyboardSpy.count, 1);
    }

    function test_swipeStartingOnAButtonStillNavigates() {
        const k = findChild(nav, "keyboardButton");
        const p = k.mapToItem(nav, k.width / 2, k.height / 2);
        drag(p.x, p.y, -200, 0);
        compare(leftSpy.count, 1);
        compare(keyboardSpy.count, 0);
        const s = findChild(nav, "searchButton");
        const q = s.mapToItem(nav, s.width / 2, s.height / 2);
        drag(q.x, q.y, 200, 0);
        compare(rightSpy.count, 1);
        compare(searchSpy.count, 0);
    }
}
