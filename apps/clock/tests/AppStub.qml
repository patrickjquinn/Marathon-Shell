import QtQml

QtObject {
    property var alarms: []
    property var calls: []

    function record(call) {
        calls = calls.concat([call]);
    }
    function editAlarm(alarm) {
        record(["edit", alarm ? alarm.id : null]);
    }
    function saveAlarm(id, hour, minute, label, repeat) {
        record(["save", id, hour, minute, label, repeat]);
    }
    function toggleAlarm(id) {
        record(["toggle", id]);
    }
    function deleteAlarm(id) {
        record(["delete", id]);
    }
}
