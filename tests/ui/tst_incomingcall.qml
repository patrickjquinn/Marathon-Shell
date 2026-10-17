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

            target: TelephonyService
        }
    }

    function init() {
        UIStore.opened = [];
        TelephonyService.callState = "incoming";
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
        compare(TelephonyService.callState, "active");
        compare(UIStore.opened, ["phone"]);
    }

    function test_declineHangsUpEvenWhenHangingUpUnloadsTheOverlay() {
        const decline = button("Decline");
        verify(decline);
        mouseClick(decline);
        compare(TelephonyService.callState, "idle");
        compare(UIStore.opened, []);
    }
}
