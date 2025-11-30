pragma Singleton
import QtQuick

QtObject {
    id: telephonyManager

    property bool telephonyAvailable: Platform.hasModemManager
    property bool simPresent: false
    property string simOperator: ""
    property string simStatus: "absent"
    property string phoneNumber: ""

    property bool inCall: false
    property bool callMuted: false
    property bool callOnSpeaker: false
    property string activeCallNumber: ""
    property int callDuration: 0

    property int missedCallCount: 0
    property int unreadSmsCount: 0
    property int voicemailCount: 0

    property var callHistory: []
    property var smsMessages: []

    signal incomingCall(string number, string contactName)
    signal callStarted(string number)
    signal callEnded(string number, int duration)
    signal callMissed(string number)
    signal smsReceived(string number, string message)
    signal smsSent(string number)
    signal voicemailReceived(int count)

    function makeCall(number) {
        if (!telephonyAvailable) {
            console.warn("[TelephonyManager] Telephony not available");
            return false;
        }

        console.log("[TelephonyManager] Making call to:", number);
        inCall = true;
        activeCallNumber = number;
        callStarted(number);
        _platformMakeCall(number);

        callHistory.push({
            number: number,
            type: "outgoing",
            timestamp: new Date().toISOString(),
            duration: 0
        });

        return true;
    }

    function answerCall() {
        console.log("[TelephonyManager] Answering call");
        inCall = true;
        _platformAnswerCall();
    }

    function rejectCall() {
        console.log("[TelephonyManager] Rejecting call");
        _platformRejectCall();
        callEnded(activeCallNumber, 0);
        activeCallNumber = "";
    }

    function endCall() {
        console.log("[TelephonyManager] Ending call");
        var duration = callDuration;
        _platformEndCall();
        callEnded(activeCallNumber, duration);
        inCall = false;
        activeCallNumber = "";
        callDuration = 0;
    }

    function muteCall(mute) {
        console.log("[TelephonyManager] Call mute:", mute);
        callMuted = mute;
        _platformMuteCall(mute);
    }

    function setSpeakerphone(enabled) {
        console.log("[TelephonyManager] Speakerphone:", enabled);
        callOnSpeaker = enabled;
        _platformSetSpeakerphone(enabled);
    }

    function sendSms(number, message) {
        console.log("[TelephonyManager] Sending SMS to:", number);

        smsMessages.push({
            number: number,
            message: message,
            type: "outgoing",
            timestamp: new Date().toISOString(),
            read: true
        });

        smsSent(number);
        _platformSendSms(number, message);
        return true;
    }

    function markSmsRead(index) {
        if (index >= 0 && index < smsMessages.length) {
            if (!smsMessages[index].read) {
                smsMessages[index].read = true;
                unreadSmsCount = Math.max(0, unreadSmsCount - 1);
            }
        }
    }

    function deleteSms(index) {
        if (index >= 0 && index < smsMessages.length) {
            if (!smsMessages[index].read) {
                unreadSmsCount = Math.max(0, unreadSmsCount - 1);
            }
            smsMessages.splice(index, 1);
        }
    }

    function getCallHistory(limit) {
        var max = limit || callHistory.length;
        return callHistory.slice(0, Math.min(max, callHistory.length));
    }

    function clearCallHistory() {
        console.log("[TelephonyManager] Clearing call history");
        callHistory = [];
    }

    function _platformMakeCall(number) {
        if (Platform.hasModemManager) {
            console.log("[TelephonyManager] D-Bus call to ModemManager Voice interface");
        } else {
            console.log("[TelephonyManager] Simulating call...");
        }
    }

    function _platformAnswerCall() {
        if (Platform.hasModemManager) {
            console.log("[TelephonyManager] D-Bus AcceptCall");
        }
    }

    function _platformRejectCall() {
        if (Platform.hasModemManager) {
            console.log("[TelephonyManager] D-Bus HangupCall");
        }
    }

    function _platformEndCall() {
        if (Platform.hasModemManager) {
            console.log("[TelephonyManager] D-Bus HangupCall");
        }
    }

    function _platformMuteCall(mute) {
        if (Platform.hasModemManager) {
            console.log("[TelephonyManager] Audio routing via PulseAudio");
        }
    }

    function _platformSetSpeakerphone(enabled) {
        if (Platform.hasModemManager) {
            console.log("[TelephonyManager] Audio routing to speaker");
        }
    }

    function _platformSendSms(number, message) {
        if (Platform.hasModemManager) {
            console.log("[TelephonyManager] D-Bus call to ModemManager Messaging interface");
        }
    }

    function _simulateIncomingCall() {
        console.log("[TelephonyManager] Simulating incoming call...");
        activeCallNumber = "+1-555-0123";
        incomingCall(activeCallNumber, "John Doe");
    }

    function _simulateIncomingSms() {
        console.log("[TelephonyManager] Simulating incoming SMS...");
        var message = {
            number: "+1-555-0123",
            message: "Hey, what's up?",
            type: "incoming",
            timestamp: new Date().toISOString(),
            read: false
        };
        smsMessages.push(message);
        unreadSmsCount++;
        smsReceived(message.number, message.message);
    }

    property Timer callDurationTimer: Timer {
        interval: 1000
        running: inCall
        repeat: true
        onTriggered: callDuration++
    }

    Component.onCompleted: {
        console.log("[TelephonyManager] Initialized");
        console.log("[TelephonyManager] ModemManager available:", Platform.hasModemManager);
        console.log("[TelephonyManager] Telephony available:", telephonyAvailable);
    }
}
