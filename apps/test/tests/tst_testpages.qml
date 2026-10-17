import QtQuick
import QtTest
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Marathon.Platform 1.0
import ".."

TestCase {
    id: testCase
    name: "TestPages"
    when: windowShown
    visible: true
    width: 540; height: 1140

    Component {
        id: appComponent
        TestApp { width: 540; height: 1140 }
    }
    Component {
        id: notificationStub
        QtObject {
            property string appName
            property string summary
            property string body
            property string appIcon
            property string category
            property var urgency
            property int expireTimeout
            property var remoteActions
            property bool published
            property bool closed
            function publish() { published = true; }
            function close() { closed = true; }
        }
    }

    property var app

    function init() {
        [Telephony, Sms, Contacts, Alarms, Audio, Power, Network, Display, Location].forEach(s => s.calls = []);
        Power.permitted = true;
        Display.permitted = true;
        app = createTemporaryObject(appComponent, testCase);
        tryVerify(() => app.pageStack.currentPage !== null && !app.pageStack.busy);
    }

    function open(file) {
        app.pageStack.push(Qt.resolvedUrl("../pages/" + file), { app: app }, PageStackAction.Immediate);
        tryCompare(app.pageStack, "depth", 2);
        return app.pageStack.currentPage;
    }

    function tap(page, name) {
        const button = findChild(page, name);
        verify(button, name);
        button.clicked(null);
    }

    function calls(service, method) {
        return service.calls.filter(c => c[0] === method).map(c => c.slice(1));
    }

    function test_telephony() {
        const page = open("TelephonyTestsPage.qml");
        tap(page, "callUnknown");
        tap(page, "callContact");
        tap(page, "smsSingle");
        tap(page, "smsMultiple");
        tap(page, "stateActive");
        tap(page, "stateRinging");
        tap(page, "stateIdle");
        tap(page, "missedCall");
        compare(calls(Telephony, "simulateIncomingCall"), [["+1234567890"], ["+1555123456"], ["+1555111222"]]);
        compare(calls(Contacts, "addContact"), [["John Doe", "+1555123456", "john@example.com"]]);
        compare(calls(Sms, "simulateIncomingSMS").length, 4);
        tryVerify(() => calls(Telephony, "simulateCallStateChange").length === 4);
        compare(calls(Telephony, "simulateCallStateChange").map(c => c[0]), ["active", "ringing", "idle", "terminated"]);
        compare(app.triggeredTests, 8);
        compare(app.passedTests, 0);
        compare(app.failedTests, 0);
    }

    function test_notifications() {
        const page = open("NotificationTestsPage.qml");
        page.notification = notificationStub;
        tap(page, "simple");
        tap(page, "highPriority");
        tap(page, "withActions");
        tap(page, "email");
        compare(app.notifications.length, 4);
        verify(app.notifications.every(n => n.published));
        compare(app.notifications[0].appName, "test");
        compare(app.notifications[0].summary, "Test Notification");
        compare(app.notifications[1].expireTimeout, 0);
        verify(app.notifications[1].urgency > app.notifications[0].urgency);
        compare(app.notifications[2].remoteActions.map(a => a.name), ["reply", "dismiss", "snooze"]);
        compare(app.notifications[3].appName, "mail");
        compare(app.notifications[3].category, "email");
        tap(page, "burst");
        compare(app.notifications.length, 14);
        const all = app.notifications;
        tap(page, "clearAll");
        verify(all.every(n => n.closed));
        compare(app.notifications.length, 0);
        compare(app.triggeredTests, 6);
    }

    function test_alarms() {
        Alarms.alarms = [{ id: "rang", time: "07:00", label: "Rang", enabled: false }];
        const page = open("AlarmTestsPage.qml");
        compare(findChild(page, "alarmCount").value, "0");
        tap(page, "triggerAlarm");
        tap(page, "createAlarm");
        compare(calls(Alarms, "triggerAlarmNow"), [["Test Alarm"]]);
        compare(calls(Alarms, "createAlarm")[0][1], "Test Alarm (+1 min)");
        tryCompare(findChild(page, "alarmCount"), "value", "1");
        compare(app.passedTests, 1);
        compare(app.triggeredTests, 1);
        ["wakeAlarm", "wakeCall", "wakeNotification", "scheduleWake"].forEach(n => tap(page, n));
        compare(calls(Power, "wake"), [["alarm"], ["call"], ["notification"]]);
        const scheduled = calls(Power, "scheduleWake")[0];
        verify(scheduled[0] > new Date());
        compare(scheduled[1], "test");
        compare(app.passedTests, 5);
        compare(app.failedTests, 0);
    }

    function test_media() {
        const page = open("MediaTestsPage.qml");
        compare(findChild(page, "volume").value, "40%");
        ["playRingtone", "stopRingtone", "notificationSound", "alarmSound", "stopAlarm"].forEach(n => tap(page, n));
        compare(Audio.calls.map(c => c[0]), ["playRingtone", "stopRingtone", "playNotificationSound", "playAlarmSound", "stopAlarmSound"]);
        tap(page, "profileSilent");
        compare(Audio.audioProfile, "silent");
        compare(findChild(page, "profile").value, "silent");
        tap(page, "profileNormal");
        ["hapticLight", "hapticMedium", "hapticHeavy", "hapticPattern"].forEach(n => tap(page, n));
        compare(calls(Audio, "vibratePattern"), [[[100, 50, 100, 50, 200]]]);
        compare([app.passedTests, app.triggeredTests], [0, 11]);
        compare(app.failedTests, 0);
    }

    function test_system() {
        const page = open("SystemTestsPage.qml");
        compare(findChild(page, "battery").value, "81%");
        tap(page, "togglePowerSave");
        verify(Power.isPowerSaveMode);
        compare(findChild(page, "powerSave").value, "On");
        tap(page, "togglePowerSave");
        tap(page, "scanWifi");
        tap(page, "toggleAirplane");
        verify(Network.airplaneModeEnabled);
        tap(page, "toggleAirplane");
        Display.brightness = 0.5;
        tap(page, "brightnessUp");
        fuzzyCompare(Display.brightness, 0.6, 0.001);
        tap(page, "brightnessDown");
        tap(page, "brightnessDown");
        fuzzyCompare(Display.brightness, 0.4, 0.001);
        tap(page, "toggleAuto");
        verify(Display.autoBrightnessEnabled);
        compare(findChild(page, "autoBrightness").value, "On");
        tap(page, "toggleAuto");
        Display.lightSensorAvailable = false;
        compare(findChild(page, "autoBrightness").value, "No light sensor");
        verify(!findChild(page, "toggleAuto").visible);
        Display.lightSensorAvailable = true;
        tap(page, "blank");
        tap(page, "wake");
        compare(calls(Display, "setScreenState"), [[false], [true]]);
        tap(page, "brightness100");
        compare(Display.brightness, 1);
        compare(app.failedTests, 0);
        tap(page, "screenshot");
        compare(app.failedTests, 1);
    }

    // The shell refuses Power and Display to an unprotected app; its
    // defaults are not readings.
    function test_systemRefused() {
        const page = open("SystemTestsPage.qml");
        Power.permitted = false;
        Display.permitted = false;
        for (const name of ["battery", "charging", "powerSave", "brightness", "autoBrightness"])
            compare(findChild(page, name).value, "Not permitted", name);
        Power.permitted = true;
        Display.permitted = true;
        compare(findChild(page, "battery").value, "81%");
        compare(findChild(page, "brightness").value, Math.round(Display.brightness * 100) + "%");
    }

    function test_sensors() {
        const page = open("SensorTestsPage.qml");
        compare(findChild(page, "light").value, "120 lux");
        compare(findChild(page, "near").value, "No");
        tap(page, "locationStart");
        compare(findChild(page, "locationActive").value, "Yes");
        tap(page, "locationStop");
        compare(calls(Location, "start").length, 1);
        compare(calls(Location, "stop").length, 1);
        compare([app.passedTests, app.triggeredTests], [0, 2]);
        compare(findChild(page, "torchAvailable").value, "Not available");
        Display.torchAvailable = true;
        compare(findChild(page, "torchAvailable").value, "Yes");
        Display.torchAvailable = false;
        compare(app.failedTests, 0);
    }
}
