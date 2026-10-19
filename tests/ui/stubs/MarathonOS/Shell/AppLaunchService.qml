pragma Singleton
import QtQml
QtObject {
    property bool androidStarting: false
    function setCoverVisible(appId, visible) {}
    function closeAppWindows(appId) { return 0; }
}
