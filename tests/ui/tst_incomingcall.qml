import QtQuick
import QtQuick.Window
import QtTest
import MarathonOS.Shell
import "../../shell/qml/components"

TestCase {
    name: "IncomingCall"
    when: windowShown

    Window {
        width: 720
        height: 720
        visible: true

        MarathonLockScreen {}

        // As the shell: the call state changing unloads the overlay at once.
        Loader {
            id: host

            anchors.fill: parent
            active: false
            sourceComponent: IncomingCallOverlay {}
        }

        Connections {
            function onCallStateChanged() {
                host.active = false;
            }

            target: Modem
        }

        // As TelephonyIntegrationCpp: a call wakes the screen when it rings and when it ends.
        Connections {
            function onCallStateChanged() {
                DisplayPolicyControllerCpp.turnScreenOn();
            }

            target: Modem
        }
    }

    function init() {
        UIStore.opened = [];
        UIStore.appWindowOpen = true;
        SessionStore.isLocked = false;
        SessionStore.showLockScreen = false;
        Modem.callState = "incoming";
        host.active = true;
        host.item.show("+1234567890", "");
        waitForRendering(host.item);
        failOnWarning(/invalid context|is not a function/);
    }

    function button(label) {
        const action = findChild(host.item, label === "Answer" ? "answerCall" : "declineCall");
        return action ? action.children[0] : null;
    }

    function test_answerOpensThePhoneEvenWhenAnsweringUnloadsTheOverlay() {
        const answer = button("Answer");
        verify(answer);
        mouseClick(answer);
        compare(Modem.callState, "active");
        compare(UIStore.opened, ["phone"]);
    }

    function test_declineHangsUpEvenWhenHangingUpUnloadsTheOverlay() {
        const decline = button("Decline");
        verify(decline);
        mouseClick(decline);
        compare(Modem.callState, "idle");
        compare(UIStore.opened, []);
    }

    function test_declineWhileUnlockedReturnsToTheApp() {
        mouseClick(button("Decline"));
        verify(!SessionStore.isLocked);
        verify(!SessionStore.showLockScreen, "no lock screen after the call");
        verify(UIStore.appWindowOpen);
    }

    function test_declineWhileLockedStaysLocked() {
        SessionStore.isLocked = true;
        SessionStore.showLockScreen = true;
        mouseClick(button("Decline"));
        verify(SessionStore.isLocked);
        verify(SessionStore.showLockScreen);
    }
}
