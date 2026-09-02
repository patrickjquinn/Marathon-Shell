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
    // Preview views must never bufferLock: a fresh second view has no
    // buffer yet, and a locked empty view can never take one — the lock
    // exists to hold the detached foreground item's last frame, not this.
    property bool isPreview: false
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
    bufferLocked: !isPreview && isMinimized && hasFirstFrame
    // Eager buffer release for the live foreground view (MARATHON_DISCARD_FRONT):
    // release the client's buffer once composited instead of holding it to the
    // next commit, so a scrolling double-buffered client isn't starved by
    // etnaviv's implicit fence. Never on preview views or a locked (minimized)
    // view -- those intentionally retain their last frame.
    allowDiscardFrontBuffer: !isPreview && !bufferLocked
                             && AppLaunchService.compositor
                             && AppLaunchService.compositor.discardFrontBuffer
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
    // An idle client only commits when its frame callbacks flow, and a
    // view with no current buffer paints nothing — which itself stops the
    // callbacks. nudgeSurface fires the pending callbacks so the client
    // commits: on foreground (re)attach after re-asserting primary, and
    // once at preview attach so an idle client fills the second view.
    function _nudge() {
        if (surfaceId !== -1 && AppLaunchService.compositor)
            AppLaunchService.compositor.nudgeSurface(surfaceId);
    }
    function _assertPrimary() {
        if (!isMinimized && surface) {
            setPrimary();
            _nudge();
        }
    }
    function _nudgePreview() {
        if (isMinimized)
            _nudge();
        else if (surfaceId !== -1)
            SurfaceRegistry.registerSurface(surfaceId, this);
    }
    onIsMinimizedChanged: {
        if (!isMinimized)
            Qt.callLater(_assertPrimary);
    }
    // A restored / just-thawed idle client won't commit a fresh buffer until a
    // frame callback fires. The single nudge in _assertPrimary can race ahead
    // of the cgroup thaw, leaving the foreground view with no current buffer =
    // black void. Re-nudge briefly until the surface actually has content. The
    // binding stops the instant it paints (hasFirstFrame); a genuinely dead
    // client is still caught by MarathonAppWindow's 20 s launch watchdog.
    Timer {
        id: contentNudge
        interval: 150
        repeat: true
        running: !surfaceItem.isPreview && !surfaceItem.isMinimized && surfaceItem.surfaceId !== -1
                 && surfaceItem.shellSurface && !surfaceItem.hasFirstFrame
        onTriggered: surfaceItem._nudge()
    }
    // Deferred one tick: preview items get isMinimized set just after creation.
    onSurfaceIdChanged: Qt.callLater(_nudgePreview)
    Component.onCompleted: Qt.callLater(_nudgePreview)
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
