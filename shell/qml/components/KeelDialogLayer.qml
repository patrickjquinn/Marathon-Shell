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
    // What the dialogs sit over, frosted behind them; null over the home
    // screen, which gets the ambience instead.
    property Item backdropSource: null
    // The WaylandCompositor that back and forward go through.
    property var compositor: null
    property bool _showing: false

    signal shown(string appId)
    signal closed(string appId)

    function add(appId, xdgSurface, surfaceId) {
        const dialog = dialogComponent.createObject(root, {
            "appId": appId,
            "surfaceObj": xdgSurface,
            "surfaceId": surfaceId
        });
        dialogs = dialogs.concat([dialog]);
        Tasks.addCapability(appId, "dialog");
    }

    // The dialog in front, or null.
    function front() {
        if (!visible)
            return null;
        for (let i = dialogs.length - 1; i >= 0; --i) {
            if (dialogs[i].visible)
                return dialogs[i];
        }
        return null;
    }

    // System back with a dialog up is the dialog's, never the app's under
    // it: a runner's window (marathon_surface_v1) takes it, and is closed
    // if it shows no change; any other dialog is asked to close. False
    // when no dialog shows.
    function back() {
        const dialog = front();
        if (!dialog)
            return false;
        if (compositor && compositor.marathonSurfaces[dialog.surfaceId])
            compositor.sendNativeBack(dialog.surfaceId, false);
        else
            _close(dialog);
        return true;
    }

    function forward() {
        const dialog = front();
        if (!dialog)
            return false;
        if (compositor)
            compositor.sendNativeForward(dialog.surfaceId, true);
        return true;
    }

    function _close(dialog) {
        const toplevel = dialog._toplevelFromObj(dialog.surfaceObj);
        if (toplevel)
            toplevel.sendClose();
    }

    function _updateShowing() {
        _showing = dialogs.some(d => d.visible);
    }

    function _remove(dialog) {
        if (!dialogs.includes(dialog))
            return;
        dialogs = dialogs.filter(d => d !== dialog);
        _updateShowing();
        if (!dialogs.some(d => d.appId === dialog.appId))
            Tasks.removeCapability(dialog.appId, "dialog");
        closed(dialog.appId);
        dialog.destroy();
    }

    Connections {
        function onNativeBackUnhandled(surfaceId) {
            const dialog = root.dialogs.find(d => d.surfaceId === surfaceId);
            if (dialog)
                root._close(dialog);
        }

        target: root.compositor
    }

    Item {
        id: backdrop

        objectName: "keelDialogBackdrop"
        anchors.fill: parent
        opacity: root._showing ? 1 : 0
        visible: opacity > 0

        KeelAmbienceBackground {
            anchors.fill: parent
            visible: !root.backdropSource
            wallpaper: AmbienceService.wallpaperUrl
            light: AmbienceService.light
            brightest: AmbienceService.brightest
            darkest: AmbienceService.darkest
        }

        // The app stays live under a flat dim: no capture, no blur.
        Rectangle {
            objectName: "keelDialogDim"
            anchors.fill: parent
            // E-paper: no dim, which the panel can only dither.
            visible: !!root.backdropSource && !MColors.eink
            color: Qt.rgba(0, 0, 0, 0.6)
        }

        Behavior on opacity {
            NumberAnimation {
                duration: root._showing ? MMotion.durationFor("modal") : MMotion.exitDurationFor("modal")
                easing.type: MMotion.easingFor("hover")
            }
        }
    }

    Component {
        id: dialogComponent

        WaylandShellSurfaceItem {
            id: dialogItem

            property string appId
            property bool wasShown: false

            // Sized as an app window is: in the client's logical pixels, then
            // scaled. Filling the layer and then scaling drew a GTK modal
            // dialog (Tuba's "Add Account") 1.5 times too wide.
            hasSentInitialSize: true
            // Keel's dialogs (Pilot's overlay) float over any app; an app's own
            // modal window (Tuba's "Add Account") only over that app: closing
            // Tuba left it over every app after.
            readonly property bool keelDialog: {
                const toplevel = _toplevelFromObj(surfaceObj);
                return !!toplevel && String(toplevel.title).startsWith("keel:dialog");
            }

            // Shown once it has drawn; the item's placeholder is opaque.
            visible: hasFirstFrame && (keelDialog || (UIStore.appWindowOpen && UIStore.currentAppId === appId))
            onVisibleChanged: root._updateShowing()
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
