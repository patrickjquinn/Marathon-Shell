pragma ComponentBehavior: Bound

import MarathonOS.Shell 1.0
import QtQuick

// Keel apps' dialog windows (KeelDialog), above the app on screen or the
// home screen, as Lipstick's dialog layer: Pilot's overlay. The dialog has
// the keyboard while it shows; its app stays awake.
Item {
    id: root

    readonly property int count: dialogs.length
    property var dialogs: []

    signal shown(string appId)
    signal closed(string appId)

    function add(appId, xdgSurface, surfaceId) {
        const dialog = dialogComponent.createObject(root, {
            "appId": appId,
            "surfaceObj": xdgSurface,
            "surfaceId": surfaceId
        });
        dialogs = dialogs.concat([dialog]);
        AppLifecycleManager.addCapability(appId, "dialog");
    }

    function _remove(dialog) {
        if (!dialogs.includes(dialog))
            return;
        dialogs = dialogs.filter(d => d !== dialog);
        if (!dialogs.some(d => d.appId === dialog.appId))
            AppLifecycleManager.removeCapability(dialog.appId, "dialog");
        closed(dialog.appId);
        dialog.destroy();
    }

    Component {
        id: dialogComponent

        WaylandShellSurfaceItem {
            id: dialogItem

            property string appId
            property bool wasShown: false

            anchors.fill: parent
            hasSentInitialSize: true
            // Shown once it has drawn; the item's placeholder is opaque.
            visible: hasFirstFrame
            onHasFirstFrameChanged: {
                if (hasFirstFrame) {
                    wasShown = true;
                    root.shown(appId);
                } else if (wasShown) {
                    root._remove(dialogItem);
                }
            }
            // This item's view keeps the surface alive until the item goes.
            onSurfaceDestroyed: root._remove(dialogItem)
        }
    }
}
