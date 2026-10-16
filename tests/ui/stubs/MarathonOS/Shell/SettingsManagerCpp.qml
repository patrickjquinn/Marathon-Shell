pragma Singleton
import QtQml
QtObject {
    property int appGridColumns: 0
    property string timeZone: "Europe/Dublin"
    property bool automaticTimeZone: true
    property bool showNotificationBadges: true
    property var enabledQuickSettingsTiles: ["wifi", "cellular", "bluetooth", "airplane", "dnd", "torch", "location", "hotspot", "nightlight", "rotation", "autobrightness", "lowpower", "vibration", "power"]
    function get(key, fallback) { return fallback; }
    function set(key, value) {}
}
