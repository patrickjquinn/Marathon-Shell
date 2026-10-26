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

            hintDuration: 200
        }
    }

    function init() {
        UIStore.appWindowOpen = false;
        SessionStore.isLocked = false;
        SettingsManagerCpp.firstRunComplete = true;
        hints.backCounter.reset();
        hints.homeCounter.reset();
        hints.homePending = false;
        hints.hide();
    }

    function test_firstAppShowsBackHintOnce() {
        UIStore.appWindowOpen = true;
        compare(hints.showing, true);
        compare(hints.text, backText);
        UIStore.appWindowOpen = false;
        UIStore.appWindowOpen = true;
        compare(hints.showing, false);
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
        tryCompare(hints, "showing", false);
        UIStore.appWindowOpen = true;
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
