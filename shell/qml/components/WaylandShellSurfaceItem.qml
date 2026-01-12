import MarathonUI.Core
import MarathonUI.Theme
import QtQuick
import QtWayland.Compositor

ShellSurfaceItem {
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
        // Also verify surface has valid dimensions (sanity check)
        // Note: xdgSurface.surface.size is not reliable/exposed in all Qt versions,
        // so we trust the Item's width/height checked at the start.

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
        // CRITICAL: Validate the entire xdgSurface chain before calling sendMaximized
        // This prevents SIGSEGV when toplevel exists but internal structures are not yet initialized
        // (race condition on Alpine/aarch64 with Qt6WaylandCompositor)
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
        // WORKAROUND: Use sendConfigure instead of sendMaximized to avoid
        // Qt6WaylandCompositor + eglfs crash. sendMaximized causes SIGSEGV on
        // embedded platforms due to OpenGL context issues in xdg-toplevel handling.
        // sendConfigure with explicit size and states is more stable.
        var states = [];
        states.push(1); // activated (XdgToplevel.State.Activated)
        // Note: Don't push maximized state (3) - causes same crash on some platforms
        toplevel.sendConfigure(newSize, states);
        if (AppLaunchService.compositor) {
            AppLaunchService.compositor.activateSurface(surfaceId);
            // Take QML focus so keyboard events flow to the WaylandQuickItem
            Qt.callLater(takeFocusForKeyboard);
        }
    }

    // Take QML focus when the surface is activated so keyboard events flow to it
    function takeFocusForKeyboard() {
        if (!isMinimized && hasSentInitialSize)
            forceActiveFocus();
    }

    autoCreatePopupItems: true
    opacity: hasSentInitialSize && hasFirstFrame ? 1 : 0
    bufferLocked: isMinimized
    shellSurface: _xdgSurfaceFromObj(surfaceObj)
    touchEventsEnabled: true
    focusOnClick: true // Ensure keyboard focus on click
    output: AppLaunchService.compositor ? AppLaunchService.compositor.output : null
    onShellSurfaceChanged: {
        if (shellSurface) {
            if (autoResize)
                scheduleSizeUpdate();
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
    onSurfaceDestroyed: {
        Logger.info("WaylandShellSurfaceItem", "Surface destroyed");
    }
    onSurfaceIdChanged: {
        if (surfaceId !== -1) {
            Logger.info("WaylandShellSurfaceItem", "Registering surface: " + surfaceId);
            SurfaceRegistry.registerSurface(surfaceId, this);
        }
    }
    Component.onCompleted: {
        if (surfaceId !== -1) {
            Logger.info("WaylandShellSurfaceItem", "Registering surface on init: " + surfaceId);
            SurfaceRegistry.registerSurface(surfaceId, this);
        }
    }
    Component.onDestruction: {
        if (surfaceId !== -1)
            SurfaceRegistry.unregisterSurface(surfaceId);
    }

    Item {
        anchors.fill: parent

        Rectangle {
            anchors.fill: parent
            color: MColors.elevated
            visible: !parent.parent.shellSurface

            Text {
                anchors.centerIn: parent
                text: "Connecting..."
                color: MColors.textSecondary
                font.pixelSize: MTypography.sizeSmall
            }
        }
    }
}
