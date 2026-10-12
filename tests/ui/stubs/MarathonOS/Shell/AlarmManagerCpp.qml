pragma Singleton
import QtQml
QtObject {
    property var activeAlarms: []
    property var dismissed: []
    property var snoozed: []
    function dismissAlarm(id) { dismissed = dismissed.concat([id]); return true; }
    function snoozeAlarm(id) { snoozed = snoozed.concat([id]); return true; }
}
