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
    property real radius: 0
    property int _coverRevision: 0
    // A binding, so a card that is handed another app drops the old cover.
    readonly property WaylandSurface coverSurface: {
        _coverRevision;
        return compositor && appId !== "" ? compositor.coverSurface(appId) : null;
    }
    readonly property bool available: coverSurface !== null
    // The strip of cover actions at the cover's bottom edge, in cover
    // pixels: taps there go to the cover, anywhere else to the card.
    property int _stripRevision: 0
    readonly property int actionStrip: {
        _stripRevision;
        return appId !== "" ? Tasks.coverActionStrip(appId) : 0;
    }

    function _report() {
        if (appId !== "")
            Tasks.setCoverVisible(appId, shown && available);
    }

    objectName: "keelCoverView"
    visible: available
    onShownChanged: _report()
    onAvailableChanged: _report()
    Component.onDestruction: if (shown && available)
        Tasks.setCoverVisible(appId, false)

    Connections {
        target: root.compositor
        ignoreUnknownSignals: true
        function onCoverChanged(changedAppId) {
            if (changedAppId === root.appId)
                root._coverRevision++;
        }
    }

    Connections {
        target: Tasks
        function onCoverActionStripChanged(changedAppId) {
            if (changedAppId === root.appId)
                root._stripRevision++;
        }
    }

    WaylandQuickItem {
        id: coverItem

        anchors.centerIn: parent
        surface: root.coverSurface
        inputEventsEnabled: root.actionStrip > 0
        containmentMask: actionStripArea
        scale: width > 0 && height > 0 ? Math.min(root.width / width, root.height / height) : 1
        opacity: coverTexture.ready ? 0 : 1

        Item {
            id: actionStripArea

            y: coverItem.height - height
            width: coverItem.width
            height: Math.min(root.actionStrip, coverItem.height)
        }
    }

    // Draws the cover rounded; the item above keeps its texture current.
    WindowTextureItem {
        id: coverTexture

        anchors.centerIn: parent
        width: coverItem.width * coverItem.scale
        height: coverItem.height * coverItem.scale
        source: coverItem
        radius: root.radius
    }
}
