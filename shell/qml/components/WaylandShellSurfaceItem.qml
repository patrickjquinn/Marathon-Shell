import MarathonUI.Core
import MarathonUI.Theme
import QtQuick
import QtWayland.Compositor

ShellSurfaceItem {
    id: surfaceItem
    property var surfaceObj: null
    property int surfaceId: -1
    property size lastSentSize: Qt.size(0, 0)
    property bool sizeUpdateScheduled: false
    property bool hasSentInitialSize: false
    property bool autoResize: true
    property bool isMinimized: false
    readonly property bool hasFirstFrame: {
        var s = _surfaceFromObj(surfaceObj);
        return s ? s.hasContent : false;
    }

    function scheduleSizeUpdate() {
        if (sizeUpdateScheduled)
            return;

        sizeUpdateScheduled = true;
        Qt.callLater(function () {
            sizeUpdateScheduled = false;
            sendSizeToApp();
        });
    }

    function _xdgSurfaceFromObj(obj) {
        if (!obj)
            return null;

        if (obj.xdgSurface)
            return obj.xdgSurface;

        return obj;
    }

    function _surfaceFromObj(obj) {
        if (!obj)
            return null;

        if (obj.surface)
            return obj.surface;

        if (obj.xdgSurface && obj.xdgSurface.surface)
            return obj.xdgSurface.surface;

        return null;
    }

    function _toplevelFromObj(obj) {
        if (!obj)
            return null;

        if (obj.toplevel)
            return obj.toplevel;

        var xdg = _xdgSurfaceFromObj(obj);
        if (xdg && xdg.toplevel)
            return xdg.toplevel;

        return null;
    }

    function sendSizeToApp() {
        if (!autoResize) {
            Logger.debug("WaylandShellSurfaceItem", "sendSizeToApp skipped: autoResize is false");
            return;
        }
        if (width <= 0 || height <= 0) {
            Logger.debug("WaylandShellSurfaceItem", "sendSizeToApp skipped: invalid size " + width + "x" + height);
            return;
        }
        var expectedWidth = (Constants && Constants.screenWidth > 0) ? Constants.screenWidth : width;
        var minWidth = Math.max(1, expectedWidth * 0.6);
        if (width < minWidth) {
            Logger.debug("WaylandShellSurfaceItem", "sendSizeToApp skipped: width " + width + " is below minimum (" + Math.round(minWidth) + "px) - waiting for layout completion");
            return;
        }
        var toplevel = _toplevelFromObj(surfaceObj);
        if (!toplevel) {
            Logger.debug("WaylandShellSurfaceItem", "sendSizeToApp skipped: no toplevel (surfaceObj: " + (surfaceObj ? "exists" : "null") + ")");
            return;
        }
        var xdgSurface = toplevel.xdgSurface;
        if (!xdgSurface) {
            Logger.debug("WaylandShellSurfaceItem", "sendSizeToApp deferred: toplevel.xdgSurface not ready yet");
            Qt.callLater(scheduleSizeUpdate);
            return;
        }
        if (!xdgSurface.surface) {
            Logger.debug("WaylandShellSurfaceItem", "sendSizeToApp deferred: xdgSurface.surface not ready yet");
            Qt.callLater(scheduleSizeUpdate);
            return;
        }
        var newSize = Qt.size(Math.round(width), Math.round(height));
        if (hasSentInitialSize && Math.abs(newSize.width - lastSentSize.width) < 2 && Math.abs(newSize.height - lastSentSize.height) < 2) {
            Logger.debug("WaylandShellSurfaceItem", "sendSizeToApp skipped: size unchanged (" + newSize.width + "x" + newSize.height + " vs " + lastSentSize.width + "x" + lastSentSize.height + ")");
            return;
        }
        lastSentSize = newSize;
        hasSentInitialSize = true;
        Logger.info("WaylandShellSurfaceItem", "Configuring app size: " + newSize.width + "x" + newSize.height);
        var states = [];
        states.push(1);
        toplevel.sendConfigure(newSize, states);
        if (AppLaunchService.compositor) {
            AppLaunchService.compositor.activateSurface(surfaceId);
            Qt.callLater(takeFocusForKeyboard);
        }
    }

    function takeFocusForKeyboard() {
        if (!isMinimized && hasSentInitialSize)
            forceActiveFocus();
    }

    autoCreatePopupItems: true
    // Keep the surface item visible from when it's mapped. The compositor now
    // sends an initial xdg_toplevel.configure from C++ (see handleXdgToplevelCreated
    // in waylandcompositor.cpp) so the client can ack and commit its first buffer
    // immediately. The splash overlay below covers the "no buffer yet" gap visually.
    opacity: 1
    bufferLocked: isMinimized && hasFirstFrame
    shellSurface: {
        var xdg = _xdgSurfaceFromObj(surfaceObj);
        if (xdg && xdg.surface)
            return xdg;

        return null;
    }
    touchEventsEnabled: true
    focusOnClick: true
    output: AppLaunchService.compositor ? AppLaunchService.compositor.output : null
    onShellSurfaceChanged: {
        if (shellSurface) {
            if (autoResize)
                scheduleSizeUpdate();
            Qt.callLater(_assertPrimary);
        }
    }
    onWidthChanged: {
        if (autoResize)
            scheduleSizeUpdate();
    }
    onHeightChanged: {
        if (autoResize)
            scheduleSizeUpdate();
    }
    // Qt Wayland's primaryView() is simply views.first() in attach order, and
    // it governs buffer advance + the client's frame throttling. When the
    // foreground item is destroyed and recreated (detach/adopt churn) while a
    // task-card preview view exists, the CARD view passively becomes first —
    // and a bufferLocked primary never advances, so the client stops getting
    // buffers released and the restored app renders black. The foreground
    // item therefore explicitly re-asserts primary (moves its view to index
    // 0) whenever it binds a surface or returns from minimized. Preview items
    // (isMinimized at creation) never assert.
    function _assertPrimary() {
        if (!isMinimized && surface)
            setPrimary();
    }
    onIsMinimizedChanged: {
        if (!isMinimized)
            Qt.callLater(_assertPrimary);
    }

    // Registration is deferred one tick so task-card previews — whose
    // isMinimized flag is applied by the Loader right after creation — never
    // hijack the registry slot (same surfaceId) from the foreground item.
    function _deferredRegister() {
        if (surfaceId !== -1 && !isMinimized) {
            Logger.info("WaylandShellSurfaceItem", "Registering surface: " + surfaceId);
            SurfaceRegistry.registerSurface(surfaceId, this);
        }
    }
    onSurfaceDestroyed: {
        Logger.info("WaylandShellSurfaceItem", "Surface destroyed");
    }
    onSurfaceIdChanged: Qt.callLater(_deferredRegister)
    Component.onCompleted: Qt.callLater(_deferredRegister)
    Component.onDestruction: {
        if (surfaceId !== -1 && !isMinimized)
            SurfaceRegistry.unregisterSurface(surfaceId);
    }

    Item {
        anchors.fill: parent

        Rectangle {
            anchors.fill: parent
            color: MColors.elevated
            visible: !surfaceItem.hasFirstFrame

            Text {
                anchors.centerIn: parent
                text: "Connecting..."
                color: MColors.textSecondary
                font.pixelSize: MTypography.sizeSmall
            }
        }
    }
}
