pragma Singleton
import QtQuick
import MarathonOS.Shell

QtObject {
    id: root

    property string lastCallState: "idle"
    property string lastCallerNumber: ""
    property bool callWasAnswered: false
    property var incomingCallOverlay: null

    function resolveContactName(number) {
        if (typeof ContactsManager !== 'undefined') {
            var contact = ContactsManager.getContactByNumber(number);
            if (contact && contact.name) {
                return contact.name;
            }
        }
        return number;
    }

    function createMissedCallNotification(number) {
        var contactName = root.resolveContactName(number);

        if (typeof NotificationService !== 'undefined') {
            NotificationService.sendNotification("phone", "Missed Call", "From: " + contactName, {
                icon: "phone-missed",
                category: "call",
                priority: "high",
                actions: [
                    {
                        id: "call_back",
                        label: "Call Back"
                    },
                    {
                        id: "message",
                        label: "Message"
                    }
                ]
            });
        }

        if (typeof HapticService !== 'undefined') {
            HapticService.heavy();
        }
    }

    function handleIncomingCall(number) {
        Logger.info("TelephonyIntegration", "📞 INCOMING CALL from: " + number);

        root.lastCallerNumber = number;
        root.callWasAnswered = false;

        if (typeof PowerManager !== 'undefined') {
            PowerManager.wake("call");
        }
        if (typeof DisplayManager !== 'undefined') {
            DisplayManager.turnScreenOn();
        }

        // Play ringtone
        if (typeof AudioManager !== 'undefined') {
            AudioManager.playRingtone();
        }

        var contactName = root.resolveContactName(number);
        if (root.incomingCallOverlay) {
            root.incomingCallOverlay.show(number, contactName);
        }

        if (typeof HapticService !== 'undefined') {
            HapticService.vibratePattern([1000, 500], -1);
        }
    }

    function handleCallStateChanged(state) {
        Logger.info("TelephonyIntegration", "📞 Call state changed: " + state);

        if (root.lastCallState === "incoming" && (state === "idle" || state === "terminated")) {
            if (!root.callWasAnswered) {
                Logger.info("TelephonyIntegration", "📞 MISSED CALL from: " + root.lastCallerNumber);
                root.createMissedCallNotification(root.lastCallerNumber);
            }
        }

        if (state === "active" || state === "idle" || state === "terminated") {
            // Stop ringtone when call is answered/ended
            if (typeof AudioManager !== 'undefined') {
                AudioManager.stopRingtone();
            }

            if (root.incomingCallOverlay && root.incomingCallOverlay.visible) {
                root.incomingCallOverlay.hide();
            }

            if (typeof HapticService !== 'undefined') {
                HapticService.stopVibration();
            }
        }

        root.lastCallState = state;
    }

    function handleMessageReceived(sender, text, timestamp) {
        Logger.info("TelephonyIntegration", "💬 SMS RECEIVED from: " + sender);

        if (typeof PowerManager !== 'undefined') {
            PowerManager.wake("notification");
        }

        var contactName = root.resolveContactName(sender);
        if (typeof NotificationService !== 'undefined') {
            NotificationService.sendNotification("messages", contactName, text, {
                icon: "message-circle",
                category: "message",
                priority: "high",
                actions: [
                    {
                        id: "reply",
                        label: "Reply"
                    },
                    {
                        id: "mark_read",
                        label: "Mark Read"
                    }
                ]
            });
        }

        if (typeof HapticService !== 'undefined') {
            HapticService.medium();
        }

        if (typeof AudioManager !== 'undefined') {
            AudioManager.playNotificationSound();
        }
    }
}
