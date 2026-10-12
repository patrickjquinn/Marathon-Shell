pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Marathon.Platform 1.0
import Nemo.Ngf 1.0
import "pages"
import "cover"

ApplicationWindow {
    id: app

    property int passedTests: 0
    property int failedTests: 0
    property int triggeredTests: 0
    property int totalTests: 0
    readonly property string summary: qsTr("%1 passed · %2 failed · %3 triggered").arg(passedTests).arg(failedTests).arg(triggeredTests)

    property bool autoRun: typeof MARATHON_DEBUG_ENABLED !== "undefined" && MARATHON_DEBUG_ENABLED === true
    property alias autoRunInterval: autoRunTimer.interval
    property alias autoRunning: autoRunTimer.running
    property int autoStep: 0
    // Only this app's own notifications can be closed, so they are kept.
    property var notifications: []

    // true passes, false or a throw fails; anything else only triggered an
    // effect that can't be checked from here.
    function run(name, fn) {
        totalTests++;
        let result;
        try {
            result = fn();
        } catch (e) {
            console.warn("[TestApp] FAIL:", name, "-", e);
            failedTests++;
            return "failed";
        }
        if (result === true) {
            console.info("[TestApp] PASS:", name);
            passedTests++;
            return "passed";
        }
        if (result === false) {
            console.warn("[TestApp] FAIL:", name);
            failedTests++;
            return "failed";
        }
        console.info("[TestApp] TRIGGERED:", name);
        triggeredTests++;
        return "triggered";
    }

    function inMinutes(minutes) {
        const t = new Date();
        t.setMinutes(t.getMinutes() + minutes);
        return Qt.formatTime(t, "HH:mm");
    }

    function haptic(strength) {
        const effect = strength === "heavy" ? hapticHeavy : strength === "medium" ? hapticMedium : hapticLight;
        effect.play();
    }

    function runAutoStep(step) {
        switch (step) {
        case 1:
            console.info("[AutoTest] === TELEPHONY TESTS ===");
            run("Telephony available", () => typeof Telephony !== "undefined");
            run("Sms available", () => typeof Sms !== "undefined");
            break;
        case 2:
            run("simulateIncomingCall", () => Telephony.simulateIncomingCall("+1234567890"));
            break;
        case 3:
            run("simulateCallStateChange(active)", () => Telephony.simulateCallStateChange("active"));
            break;
        case 4:
            run("setCallMuted(true)", () => Telephony.setCallMuted(true));
            run("setSpeakerphone(true)", () => Telephony.setSpeakerphone(true));
            break;
        case 5:
            run("isCallMuted() returns bool", () => typeof Telephony.isCallMuted() === "boolean");
            run("isSpeakerphoneOn() returns bool", () => typeof Telephony.isSpeakerphoneOn() === "boolean");
            break;
        case 6:
            run("simulateCallStateChange(idle)", () => Telephony.simulateCallStateChange("idle"));
            run("simulateIncomingSMS", () => Sms.simulateIncomingSMS("+1555999888", "Auto-test SMS message"));
            break;
        case 7:
            console.info("[AutoTest] === ALARM TESTS ===");
            run("Alarms available", () => typeof Alarms !== "undefined");
            run("createAlarm", () => !!Alarms.createAlarm(inMinutes(5), "Auto-test alarm", [], {}));
            break;
        case 8:
            console.info("[AutoTest] === MEDIA & AUDIO TESTS ===");
            run("Audio available", () => typeof Audio !== "undefined");
            run("Audio.volume readable", () => Audio.volume >= 0);
            run("Haptic light", () => haptic("light"));
            break;
        case 9:
            console.info("[AutoTest] === SYSTEM TESTS ===");
            run("Power.batteryLevel readable", () => Power.batteryLevel >= 0);
            run("Network.wifiConnected readable", () => typeof Network.wifiConnected === "boolean");
            run("Display.brightness readable", () => Display.brightness >= 0);
            run("Bluetooth available", () => typeof Bluetooth !== "undefined");
            break;
        case 10:
            console.info("[AutoTest] === SENSOR TESTS ===");
            run("Sensors.ambientLight readable", () => Sensors.ambientLight >= 0);
            run("Sensors.proximityNear readable", () => typeof Sensors.proximityNear === "boolean");
            run("Location.start()", () => Location.start());
            break;
        case 11:
            run("Location.stop()", () => Location.stop());
            break;
        default:
            autoRunTimer.stop();
            console.info("[AutoTest] RESULTS:", summary);
            break;
        }
    }

    appId: "test"
    Component.onCompleted: {
        if (autoRun)
            autoRunTimer.start();
    }

    NonGraphicalFeedback {
        id: hapticLight
        event: "feedback_press_weak"
    }
    NonGraphicalFeedback {
        id: hapticMedium
        event: "feedback_press"
    }
    NonGraphicalFeedback {
        id: hapticHeavy
        event: "feedback_lock"
    }

    Timer {
        id: autoRunTimer

        interval: 800
        repeat: true
        onTriggered: app.runAutoStep(++app.autoStep)
    }

    Connections {
        target: typeof Alarms !== "undefined" ? Alarms : null
        ignoreUnknownSignals: true

        function onAlarmTriggered(id, label) {
            app.run("Alarm triggered: " + label, () => true);
        }
    }

    cover: Component {
        TestCover {
            passed: app.passedTests
            failed: app.failedTests
            triggered: app.triggeredTests
        }
    }

    initialPage: Component {
        MainPage {
            app: app
        }
    }
}
