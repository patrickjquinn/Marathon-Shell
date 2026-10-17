import QtQuick
import QtQuick.Window
import QtTest
import MarathonOS.Shell
import "../../shell/qml/components"

TestCase {
    id: tc

    name: "LockScreen"
    when: windowShown

    Window {
        id: win

        width: 720
        height: 720
        visible: true

        MarathonLockScreen {
            id: lockScreen

            onUnlockRequested: pad.enabled = true
        }

        // What the swipe brings up under the finger: the PIN pad or home.
        MouseArea {
            id: pad

            property int clicks: 0

            anchors.fill: parent
            enabled: false
            onClicked: clicks++
        }
    }

    function init() {
        pad.enabled = false;
        pad.clicks = 0;
        lockScreen.swipeProgress = 0;
        DisplayPolicyControllerCpp.screenOn = true;
    }

    function test_unlockSwipeEndsWithoutAClick() {
        mousePress(lockScreen, 360, 620);
        for (let y = 600; y >= 300; y -= 20) {
            mouseMove(lockScreen, 360, y);
            wait(16);
        }
        mouseRelease(lockScreen, 360, 300);
        verify(pad.enabled, "the swipe unlocked");
        compare(pad.clicks, 0);
    }

    function test_screenTurnedOnWhileOnLeavesTheSessionAlone() {
        SessionStore.showLockScreen = false;
        DisplayPolicyControllerCpp.turnScreenOn();
        verify(!SessionStore.showLockScreen, "the lock screen stays down");
    }

    // An SMS (PowerPolicyController.wake) or D-Bus Display1.Wake re-asserts the panel directly.
    function test_eventWakeOnALitScreenLeavesTheSessionAlone() {
        SessionStore.showLockScreen = false;
        DisplayManagerCpp.screenStateChanged(true);
        verify(!SessionStore.showLockScreen);
    }

    function test_wakingTheScreenShowsTheLockScreen() {
        DisplayPolicyControllerCpp.turnScreenOff("test");
        SessionStore.showLockScreen = false;
        DisplayPolicyControllerCpp.turnScreenOn();
        verify(SessionStore.showLockScreen);
    }

    function test_resumeShowsTheLockScreen() {
        SessionStore.showLockScreen = false;
        DisplayPolicyControllerCpp.forceScreenOn();
        verify(SessionStore.showLockScreen);
    }

    function test_aRingingAlarmHoldsTheIdleBlank() {
        DisplayPolicyControllerCpp.offReasons = [];
        AlarmManagerCpp.hasActiveAlarm = true;
        SettingsManagerCpp.screenTimeout = 200;
        wait(500);
        compare(DisplayPolicyControllerCpp.offReasons.length, 0);
        AlarmManagerCpp.hasActiveAlarm = false;
        tryVerify(() => DisplayPolicyControllerCpp.offReasons.length === 1, 1000);
        SettingsManagerCpp.screenTimeout = 0;
    }

    function test_tapStillReachesWhatIsBelow() {
        pad.enabled = true;
        pad.z = -1;
        mouseClick(lockScreen, 360, 400);
        compare(pad.clicks, 1);
        pad.z = 0;
    }
}
