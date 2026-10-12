import QtQuick
import QtWayland.Compositor
import MarathonOS.Shell

// A Keel app's cover (keel/shell/PROTOCOL.md section 3), scaled into its
// task card. The app is told when it is on screen so the cover animates and
// updates only then.
Item {
    id: root

    property string appId
    property var compositor: null
    property bool shown: false
    property WaylandSurface coverSurface: compositor && appId !== "" ? compositor.coverSurface(appId) : null
    readonly property bool available: coverSurface !== null

    function _report() {
        if (appId !== "")
            AppLaunchService.setCoverVisible(appId, shown && available);
    }

    objectName: "keelCoverView"
    visible: available
    onShownChanged: _report()
    onAvailableChanged: _report()
    Component.onDestruction: if (shown && available) AppLaunchService.setCoverVisible(appId, false)

    Connections {
        target: root.compositor
        ignoreUnknownSignals: true
        function onCoverChanged(changedAppId) {
            if (changedAppId === root.appId)
                root.coverSurface = root.compositor.coverSurface(root.appId);
        }
    }

    WaylandQuickItem {
        id: coverItem

        anchors.centerIn: parent
        surface: root.coverSurface
        inputEventsEnabled: false
        scale: width > 0 && height > 0 ? Math.min(root.width / width, root.height / height) : 1
    }
}
