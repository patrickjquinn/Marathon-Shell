pragma Singleton
import QtQml
QtObject {
    property var activeBroadcasts: []
    signal broadcastReceived(var broadcast)
    function acknowledge(path) { activeBroadcasts = activeBroadcasts.filter(b => b.path !== path); }
}
