import QtQuick
import QtQuick.Window
import QtTest
import MarathonOS.Shell
import "../../shell/qml/components/oobe"

TestCase {
    id: testCase

    name: "OOBEHub"
    when: windowShown

    Window {
        width: 720
        height: 720
        visible: true

        OobeHub {
            id: hub

            anchors.fill: parent
            visible: false
        }
    }

    SignalSpy {
        id: doneSpy

        target: hub
        signalName: "done"
    }

    function enter() {
        hub.visible = false;
        hub.visible = true;
    }

    function init() {
        NotificationService.clear();
        SettingsManagerCpp.store = ({});
        MMotion.reduceMotion = false;
        doneSpy.clear();
        enter();
    }

    function cleanup() {
        hub.visible = false;
    }

    function welcomes() {
        let n = 0;
        for (let i = 0; i < NotificationService.count; ++i)
            if (NotificationService.get(i).appId === "Marathon" && NotificationService.get(i).title === "Welcome to Marathon")
                ++n;
        return n;
    }

    function peek() {
        return findChild(hub, "oobeHubPeek");
    }

    function drag(x) {
        const p = peek();
        const y = p.height / 2;
        mousePress(p, 2, y);
        for (let i = 1; i <= 10; ++i)
            mouseMove(p, 2 + (x - 2) * i / 10, y, 40);
        wait(100);
        mouseMove(p, x, y + 1, 40);
        mouseRelease(p, x, y + 1, Qt.LeftButton, Qt.NoModifier, 40);
    }

    function demo() {
        return findChild(hub, "practiceDemo");
    }

    function notNow() {
        return findChild(hub, "practiceNotNow");
    }

    function test_postsOneWelcomeNotification() {
        compare(welcomes(), 1);
        compare(NotificationService.get(0).body, "Swipe in from the left edge any time to see what's new.");
    }

    function test_reenteringDoesNotPostAgain() {
        enter();
        enter();
        compare(welcomes(), 1);
    }

    function test_savedFlagReadBackAsStringDoesNotPostAgain() {
        NotificationService.clear();
        SettingsManagerCpp.store = ({
                "onboarding/welcomePosted": "true"
            });
        enter();
        compare(welcomes(), 0);
    }

    function test_dragToTheIconStopCompletes() {
        drag(peek().width * 0.25);
        tryVerify(() => peek().iconsShown);
        compare(findChild(hub, "oobeHubHeading").text, "That's it");
        compare(doneSpy.count, 0);
        tryCompare(doneSpy, "count", 1, 3000);
    }

    function test_leavingBeforeTheConfirmationEndsDoesNotFinish() {
        drag(peek().width * 0.25);
        tryVerify(() => peek().iconsShown);
        hub.visible = false;
        wait(1700);
        compare(doneSpy.count, 0);
    }

    function test_openingFullyShutsTheHubBeforeMovingOn() {
        drag(peek().width * 0.6);
        tryVerify(() => peek().isFullyOpen);
        compare(findChild(hub, "oobeHubHeading").text, "That's it");
        wait(1700);
        compare(doneSpy.count, 0);
        tryVerify(() => !peek().isFullyOpen, 1000);
        compare(doneSpy.count, 0);
        tryCompare(doneSpy, "count", 1, 2000);
    }

    function test_idleStartsTheDemo() {
        verify(!demo().running);
        tryVerify(() => demo().running, 10000);
        verify(!notNow().visible);
    }

    function test_twoShortDragsStartTheDemo() {
        drag(peek().iconsStop * 0.3);
        verify(!demo().running);
        drag(peek().iconsStop * 0.3);
        tryVerify(() => demo().running, 1000);
    }

    function test_notNowAfterTheDemoAdvances() {
        tryVerify(() => demo().running, 10000);
        tryVerify(() => notNow().visible, 15000);
        mouseClick(notNow());
        compare(doneSpy.count, 1);
    }

    function test_reduceMotionPlaysTheDemoOnce() {
        MMotion.reduceMotion = true;
        enter();
        tryVerify(() => demo().running, 10000);
        compare(demo().loops, 1);
    }
}
