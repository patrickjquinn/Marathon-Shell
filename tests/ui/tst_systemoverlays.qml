import QtQuick
import QtQuick.Window
import QtTest
import MarathonOS.Shell
import "../../shell/qml/components"

TestCase {
    id: tc

    name: "SystemOverlays"
    when: windowShown

    Window {
        id: win

        width: 540
        height: 1140
        visible: true

        MouseArea {
            id: underneath

            property int taps: 0

            anchors.fill: parent
            onClicked: taps++
        }

        MarathonAlarmOverlay {
            id: alarm
        }

        MarathonCellBroadcastOverlay {
            id: broadcast
        }

        IncomingCallOverlay {
            id: call
        }
    }

    function init() {
        underneath.taps = 0;
        AlarmManagerCpp.dismissed = [];
        AlarmManagerCpp.snoozed = [];
        AlarmManagerCpp.activeAlarms = [{
                "id": "a1",
                "snoozeEnabled": true,
                "snoozeDuration": 5
            }];
        Modem.activeBroadcasts = [];
        Modem.callState = "idle";
        SessionStore.isLocked = false;
        UIStore.opened = [];
        call.hide();
        call.pinShown = false;
    }

    function cleanup() {
        alarm.visible = false;
    }

    function test_alarmSnoozeIsTheEasyTarget() {
        alarm.show({
            "id": "a1",
            "label": "Wake"
        });
        const snooze = findChild(alarm, "snoozeAction");
        verify(snooze.visible);
        compare(snooze.label, "Snooze 5 min");
        verify(snooze.emphasised);
        verify(!findChild(alarm, "dismissAction").emphasised);
    }

    function test_alarmSwipeUpDoesNotDismiss() {
        alarm.show({
            "id": "a1",
            "label": "Wake"
        });
        const x = win.width / 2;
        mousePress(win.contentItem, x, 900);
        for (let i = 1; i <= 10; i++)
            mouseMove(win.contentItem, x, 900 - i * 40);
        mouseRelease(win.contentItem, x, 500);
        verify(alarm.visible);
        compare(AlarmManagerCpp.dismissed.length, 0);
        compare(underneath.taps, 0);
    }

    function test_alarmDismissNeedsAHold() {
        alarm.show({
            "id": "a1",
            "label": "Wake"
        });
        const dismiss = findChild(alarm, "dismissAction");
        mouseClick(dismiss, dismiss.width / 2, dismiss.width / 2);
        compare(AlarmManagerCpp.dismissed.length, 0);
        mousePress(dismiss, dismiss.width / 2, dismiss.width / 2);
        wait(1200);
        mouseRelease(dismiss, dismiss.width / 2, dismiss.width / 2);
        compare(AlarmManagerCpp.dismissed, ["a1"]);
        verify(!alarm.visible);
    }

    function test_alarmHidesSnoozeWhenDisabled() {
        AlarmManagerCpp.activeAlarms = [{
                "id": "a1",
                "snoozeEnabled": false
            }];
        alarm.show({
            "id": "a1",
            "label": "Wake"
        });
        verify(!findChild(alarm, "snoozeAction").visible);
    }

    function test_broadcastSwallowsTaps() {
        Modem.activeBroadcasts = [{
                "path": "/cb/1",
                "category": "amber",
                "text": "Alert",
                "nonDismissable": false
            }];
        verify(broadcast.visible);
        mouseClick(win.contentItem, 20, 40);
        compare(underneath.taps, 0);
    }

    function test_answerWhileLockedKeepsTheDeviceLocked() {
        SessionStore.isLocked = true;
        call.show("+14155550142", "");
        Modem.callState = "incoming";
        verify(call.visible);
        call.answeredHere = true;
        Modem.answer();
        call.hide();
        verify(SessionStore.isLocked);
        verify(call.inCall);
        verify(call.visible);
        verify(findChild(call, "endCall").visible);
        call.pinShown = true;
        verify(!call.visible);
        call.pinShown = false;
        Modem.hangup();
        verify(!call.visible);
    }

    function test_answerWhileUnlockedLeavesToThePhoneApp() {
        call.show("+14155550142", "");
        verify(call.visible);
        call.answeredHere = true;
        Modem.answer();
        call.hide();
        verify(!call.inCall);
        verify(!call.visible);
    }
}
