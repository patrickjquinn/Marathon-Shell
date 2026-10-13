pragma Singleton
import QtQml
QtObject {
    property int appGridColumns: 0
    property bool showNotificationBadges: true
    function get(key, fallback) { return fallback; }
}
