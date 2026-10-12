pragma Singleton
import QtQml
QtObject {
    property bool ringing: false
    function playRingtone() { ringing = true; }
    function stopRingtone() { ringing = false; }
    function playAlarmSound() {}
}
