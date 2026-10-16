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

    function test_tapStillReachesWhatIsBelow() {
        pad.enabled = true;
        pad.z = -1;
        mouseClick(lockScreen, 360, 400);
        compare(pad.clicks, 1);
        pad.z = 0;
    }
}
