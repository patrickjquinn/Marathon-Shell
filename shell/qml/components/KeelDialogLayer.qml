pragma ComponentBehavior: Bound

import MarathonOS.Shell 1.0
import QtQuick
import QtQuick.Effects

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
        opacity: root._showing && !MMotion.reduceBlur ? 1 : 0
        visible: opacity > 0

        KeelAmbienceBackground {
            anchors.fill: parent
            visible: !root.backdropSource
            wallpaper: AmbienceService.wallpaperUrl
            light: AmbienceService.light
            brightest: AmbienceService.brightest
            darkest: AmbienceService.darkest
        }

        // Quarter resolution, captured when the dialog opens or moves, not
        // live: the blur hides the detail and etnaviv can't afford a pass a frame.
        ShaderEffectSource {
            id: snapshot

            objectName: "keelDialogSnapshot"
            anchors.fill: parent
            visible: false
            sourceItem: backdrop.visible ? root.backdropSource : null
            sourceRect: {
                root.y;
                root.height;
                const p = sourceItem ? root.mapToItem(sourceItem, 0, 0) : Qt.point(0, 0);
                return Qt.rect(p.x, p.y, root.width, root.height);
            }
            textureSize: Qt.size(Math.ceil(root.width / 4), Math.ceil(root.height / 4))
            live: false
            hideSource: false
            onSourceItemChanged: scheduleUpdate()
            onSourceRectChanged: scheduleUpdate()
        }

        MultiEffect {
            anchors.fill: parent
            visible: snapshot.sourceItem !== null
            source: snapshot
            autoPaddingEnabled: false
            blurEnabled: true
            blur: 1
            blurMax: 16
            brightness: -0.15
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

            anchors.fill: parent
            hasSentInitialSize: true
            // Shown once it has drawn; the item's placeholder is opaque.
            visible: hasFirstFrame
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
