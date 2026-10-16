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
    SignalSpy { id: pilotSpy; target: nav; signalName: "pilotRequested" }
    SignalSpy { id: backSpy; target: nav; signalName: "swipeBack" }

    function init() {
        UIStore.closeQuickSettings();
        nav.isAppOpen = false;
        nav.pilotEnabled = true;
        pilotSpy.clear();
        backSpy.clear();
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

    function hold(x, y, ms) {
        mousePress(nav, x, y);
        wait(ms);
    }

    function test_holdAsksPilot() {
        hold(nav.width / 2, nav.height / 2, 400);
        verify(nav.pilotLit);
        compare(pilotSpy.count, 0);
        tryCompare(pilotSpy, "count", 1);
        mouseRelease(nav, nav.width / 2, nav.height / 2);
        verify(!nav.pilotLit);
        compare(nav.pilotCharge, 0);
        compare(homeSpy.count, 0);
        compare(searchSpy.count, 0);
        verify(!UIStore.quickSettingsOpen);
    }

    function test_holdThenDragDoesNothingMore() {
        nav.isAppOpen = true;
        hold(nav.width / 2, nav.height / 2, 700);
        compare(pilotSpy.count, 1);
        for (let i = 1; i <= 8; ++i)
            mouseMove(nav, nav.width / 2 - 25 * i, nav.height / 2, 16);
        mouseRelease(nav, nav.width / 2 - 200, nav.height / 2);
        compare(backSpy.count, 0);
        compare(nav.backProgress, 0);
        compare(pilotSpy.count, 1);
    }

    function test_noPilotWhenDisabled() {
        nav.pilotEnabled = false;
        hold(nav.width / 2, nav.height / 2, 700);
        mouseRelease(nav, nav.width / 2, nav.height / 2);
        compare(pilotSpy.count, 0);
        verify(!nav.pilotLit);
    }

    function test_holdOnAButtonIsNotPilot() {
        const k = findChild(nav, "keyboardButton");
        const p = k.mapToItem(nav, k.width / 2, k.height / 2);
        hold(p.x, p.y, 700);
        mouseRelease(nav, p.x, p.y);
        compare(pilotSpy.count, 0);
        compare(keyboardSpy.count, 1);
    }

    function test_gesturesAndTapsAreNotPilot() {
        nav.isAppOpen = true;
        mouseClick(nav, nav.width / 2, nav.height / 2);
        drag(nav.width / 2, nav.height / 2, -200, 0);
        drag(nav.width / 2, nav.height / 2, 200, 0);
        drag(nav.width / 2, nav.height - 5, 0, -80);
        drag(nav.width / 2, nav.height / 2, 0, 40);
        wait(700);
        compare(pilotSpy.count, 0);
        compare(backSpy.count, 1);
        compare(rightSpy.count, 1);
        verify(UIStore.quickSettingsOpen);
    }

    function test_slowSwipeIsNotPilot() {
        mousePress(nav, nav.width / 2, nav.height / 2);
        wait(200);
        for (let i = 1; i <= 8; ++i)
            mouseMove(nav, nav.width / 2 + 25 * i, nav.height / 2, 16);
        wait(600);
        mouseRelease(nav, nav.width / 2 + 200, nav.height / 2);
        compare(pilotSpy.count, 0);
        compare(rightSpy.count, 1);
    }

    function test_backFollowsTheFinger() {
        nav.isAppOpen = true;
        mousePress(nav, nav.width / 2, nav.height / 2);
        for (let i = 1; i <= 8; ++i)
            mouseMove(nav, nav.width / 2 - 25 * i, nav.height / 2, 16);
        verify(nav.backProgress > 0.3, "backProgress " + nav.backProgress);
        compare(nav.backTracker.value, 200);
        mouseRelease(nav, nav.width / 2 - 200, nav.height / 2);
        compare(backSpy.count, 1);
        compare(nav.backProgress, 0);
    }

    function test_shortSlowBackCancels() {
        nav.isAppOpen = true;
        mousePress(nav, nav.width / 2, nav.height / 2);
        for (let i = 1; i <= 8; ++i)
            mouseMove(nav, nav.width / 2 - 3 * i, nav.height / 2, 40);
        wait(120);
        mouseRelease(nav, nav.width / 2 - 24, nav.height / 2);
        compare(backSpy.count, 0);
        compare(nav.backProgress, 0);
    }

    function test_pullDownDrawsTheShadeAlong() {
        mousePress(nav, nav.width / 2, nav.height / 2);
        for (let i = 1; i <= 4; ++i)
            mouseMove(nav, nav.width / 2, nav.height / 2 + 6 * i, 16);
        verify(UIStore.quickSettingsDragging);
        verify(UIStore.quickSettingsHeight > 0 && UIStore.quickSettingsHeight < 1000, "height " + UIStore.quickSettingsHeight);
        mouseRelease(nav, nav.width / 2, nav.height / 2 + 24);
        verify(!UIStore.quickSettingsDragging);
        verify(UIStore.quickSettingsOpen);
    }

    function test_pullDownThenBackUpCancels() {
        mousePress(nav, nav.width / 2, nav.height / 2);
        for (let i = 1; i <= 4; ++i)
            mouseMove(nav, nav.width / 2, nav.height / 2 + 6 * i, 16);
        for (let i = 1; i <= 4; ++i)
            mouseMove(nav, nav.width / 2, nav.height / 2 + 24 - 6 * i, 16);
        mouseRelease(nav, nav.width / 2, nav.height / 2);
        verify(!UIStore.quickSettingsOpen);
        compare(UIStore.quickSettingsHeight, 0);
    }

    function test_pillIsTheNotch() {
        const pill = findChild(nav, "navPill");
        verify(pill);
        compare(pill.width, Silica.Theme.itemSizeExtraLarge);
        compare(pill.x + pill.width / 2, nav.width / 2);
    }
}
