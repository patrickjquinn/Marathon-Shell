pragma Singleton
import QtQml

QtObject {
    property var calls: []

    function log(...args) {
        calls = calls.concat([args]);
    }

    property var alarms: []

    signal alarmTriggered(string id, string label)

    function createAlarm(time, label, repeat, options) {
        log("createAlarm", time, label);
        alarms = alarms.concat([
            {
                id: "a" + alarms.length,
                time: time,
                label: label,
                enabled: true
            }
        ]);
        return "a" + (alarms.length - 1);
    }
    function triggerAlarmNow(label) {
        log("triggerAlarmNow", label);
    }
}
