import QtQuick
import QtQuick.Window
import QtTest
import MarathonOS.Shell
import "../../shell/qml/components"

TestCase {
    id: testCase

    name: "FirstUseHints"
    when: windowShown

    readonly property string backText: "Drag the bar left to go back"
    readonly property string homeText: "Pull the bar down for quick settings"

    Window {
        width: 720
        height: 720
        visible: true

        FirstUseHints {
            id: hints

            hintDuration: 600
            minVisible: 200
        }
    }

    function init() {
        UIStore.appWindowOpen = false;
        SessionStore.isLocked = false;
        SettingsManagerCpp.firstRunComplete = true;
        hints.backCounter.reset();
        hints.homeCounter.reset();
        hints.homePending = false;
        UIStore.settingsOpen = false;
        Display.screenOn = true;
        MMotion.reduceMotion = false;
        hints.hide();
    }

    function test_firstAppShowsBackHintOnce() {
        UIStore.appWindowOpen = true;
        compare(hints.showing, true);
        compare(hints.text, backText);
        wait(300);
        UIStore.appWindowOpen = false;
        hints.hide();
        UIStore.appWindowOpen = true;
        compare(hints.showing, false);
    }

    function test_unseenHintShowsAgain() {
        UIStore.appWindowOpen = true;
        compare(hints.showing, true);
        wait(50);
        SessionStore.isLocked = true;
        compare(hints.showing, false);
        wait(300);
        SessionStore.isLocked = false;
        UIStore.appWindowOpen = false;
        UIStore.appWindowOpen = true;
        compare(hints.showing, true);
        compare(hints.text, backText);
    }

    function test_screenOffBeforeSeenShowsAgain() {
        UIStore.appWindowOpen = true;
        Display.screenOn = false;
        compare(hints.showing, false);
        Display.screenOn = true;
        UIStore.appWindowOpen = false;
        UIStore.appWindowOpen = true;
        compare(hints.text, backText);
        compare(hints.showing, true);
    }

    function test_failedLaunchDoesNotSpendBackHint() {
        UIStore.appWindowOpen = true;
        UIStore.appWindowOpen = false;
        wait(300);
        UIStore.appWindowOpen = true;
        compare(hints.text, backText);
        compare(hints.showing, true);
    }

    function test_settingsCountsAsApp() {
        UIStore.settingsOpen = true;
        compare(hints.text, backText);
        compare(hints.showing, true);
    }

    function test_reduceMotionShowsInstantly() {
        MMotion.reduceMotion = true;
        UIStore.appWindowOpen = true;
        compare(hints.opacity, 1);
    }

    function test_motionFadesIn() {
        tryCompare(hints, "opacity", 0);
        UIStore.appWindowOpen = true;
        verify(hints.opacity < 1);
        tryCompare(hints, "opacity", 1);
    }

    function test_hintTimesOut() {
        UIStore.appWindowOpen = true;
        compare(hints.showing, true);
        tryCompare(hints, "showing", false);
    }

    function test_firstReturnHomeShowsQuickSettingsHintOnce() {
        UIStore.appWindowOpen = true;
        UIStore.appWindowOpen = false;
        compare(hints.showing, true);
        compare(hints.text, homeText);
        wait(300);
        tryCompare(hints, "showing", false);
        UIStore.appWindowOpen = true;
        wait(300);
        UIStore.appWindowOpen = false;
        compare(hints.showing, false);
    }

    function test_neverDuringSetup() {
        SettingsManagerCpp.firstRunComplete = false;
        UIStore.appWindowOpen = true;
        compare(hints.showing, false);
        UIStore.appWindowOpen = false;
        compare(hints.showing, false);
    }

    function test_neverOverLockScreen() {
        SessionStore.isLocked = true;
        UIStore.appWindowOpen = true;
        compare(hints.showing, false);
    }

    function test_lockingHidesHint() {
        UIStore.appWindowOpen = true;
        compare(hints.showing, true);
        SessionStore.isLocked = true;
        compare(hints.showing, false);
    }
}
