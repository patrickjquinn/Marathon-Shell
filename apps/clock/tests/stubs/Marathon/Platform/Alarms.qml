pragma Singleton
import QtQml

QtObject {
    property var alarms: []
    property bool fail: false
    property var triggered: []
    property var hidden: []
    property int nextId: 1

    function reset() {
        alarms = [];
        fail = false;
        triggered = [];
        hidden = [];
        nextId = 1;
    }

    function createAlarm(time, label, repeat, options) {
        if (fail)
            return "";
        const id = "a" + nextId++;
        if (options && options.hidden) {
            hidden = hidden.concat([Object.assign({ id: id, label: label }, options)]);
            return id;
        }
        alarms = alarms.concat([{ id: id, time: time, label: label, repeat: repeat, enabled: true }]);
        return id;
    }

    function updateAlarm(id, updates) {
        if (fail || !alarms.some(a => a.id === id))
            return false;
        alarms = alarms.map(a => a.id === id ? Object.assign({}, a, updates) : a);
        return true;
    }

    function deleteAlarm(id) {
        if (fail || !alarms.concat(hidden).some(a => a.id === id))
            return false;
        alarms = alarms.filter(a => a.id !== id);
        hidden = hidden.filter(a => a.id !== id);
        return true;
    }

    function triggerAlarmNow(label) {
        triggered = triggered.concat([label]);
    }
}
