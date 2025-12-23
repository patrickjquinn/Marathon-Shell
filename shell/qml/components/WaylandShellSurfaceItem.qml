import MarathonOS.Shell
import MarathonUI.Core
import MarathonUI.Theme
import QtQuick
import QtWayland.Compositor

ShellSurfaceItem {
    // Native Wayland apps are configured as maximized by default (mobile-shell semantics).
    // We send maximized configure events and keep sizing stable to avoid resize/jank issues in toolkits.

    property var surfaceObj: null
    property int surfaceId: -1
    property size lastSentSize: Qt.size(0, 0)
    property bool sizeUpdateScheduled: false
    property bool hasSentInitialSize: false
    property bool autoResize: true
    // CRITICAL: When isMinimized is true, lock the buffer to retain the last frame
    // This prevents Vulkan surface lost errors when apps like Chromium destroy their surface during minimize
    // The buffer stays visible for task switcher preview even after surface destruction
    property bool isMinimized: false
    // True once the client has committed at least one buffer.
    // We use this to avoid a "white gap" between splash dismissal and first frame.
    readonly property bool hasFirstFrame: {
        var s = _surfaceFromObj(surfaceObj);
        return s ? s.hasContent : false;
    }

    // CRITICAL: Debounced size update to prevent resize spam during animations
    // Apps rescale when they receive size changes, causing fuzzy/squished rendering
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

        // Some call sites pass a wrapper object { xdgSurface, toplevel }.
        if (obj.xdgSurface)
            return obj.xdgSurface;

        // Others may pass the xdg surface itself.
        return obj;
    }

    function _surfaceFromObj(obj) {
        if (!obj)
            return null;

        // If we got an xdg surface, it usually exposes `.surface`.
        if (obj.surface)
            return obj.surface;

        // Wrapper cases: { xdgSurface: ..., surface: ... }
        if (obj.xdgSurface && obj.xdgSurface.surface)
            return obj.xdgSurface.surface;

        return null;
    }

    function _toplevelFromObj(obj) {
        if (!obj)
            return null;

        // Wrapper object path
        if (obj.toplevel)
            return obj.toplevel;

        // xdg surface path
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
        // CRITICAL: Don't send size until we have a reasonable window size
        // During initial layout, QML may report intermediate sizes (e.g., 234x430)
        // before the final full-screen size (e.g., 540x932). Firefox uses the first
        // configure event, so we must wait for the real size.
        // Don't send size until we're close to the expected full-screen width.
        // During initial layout, QML may report intermediate sizes which some clients (e.g. Firefox)
        // treat as the "real" initial configure. Use Constants.screenWidth as the expected target.
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
        var newSize = Qt.size(Math.round(width), Math.round(height));
        // Only send if size actually changed (avoid sub-pixel resize spam)
        // EXCEPTION: Always send if this is the first time (to ensure app knows its size)
        if (hasSentInitialSize && Math.abs(newSize.width - lastSentSize.width) < 2 && Math.abs(newSize.height - lastSentSize.height) < 2) {
            Logger.debug("WaylandShellSurfaceItem", "sendSizeToApp skipped: size unchanged (" + newSize.width + "x" + newSize.height + " vs " + lastSentSize.width + "x" + lastSentSize.height + ")");
            return;
        }
        lastSentSize = newSize;
        hasSentInitialSize = true;
        Logger.info("WaylandShellSurfaceItem", "Configuring app as maximized: " + newSize.width + "x" + newSize.height);
        toplevel.sendMaximized(newSize);
        // AUTO-ACTIVATE: Activate window when ready (removes "grey" state)
        // This ensures the app looks active/focused immediately on launch
        if (AppLaunchService.compositor)
            AppLaunchService.compositor.activateSurface(surfaceId);
    }

    // CRITICAL: Let Qt's ShellSurfaceItem automatically create popup items
    // This handles positioning, sizing, and rendering of xdg_popups without manual intervention
    autoCreatePopupItems: true
    // Hide the surface until:
    // - we sent the initial configure (size), AND
    // - the client has committed a buffer (hasFirstFrame)
    // This prevents "white flashes" and wrong-size first frames.
    opacity: hasSentInitialSize && hasFirstFrame ? 1 : 0
    // bufferLocked is inherited from WaylandQuickItem (parent of ShellSurfaceItem)
    // When true, the compositor retains the buffer instead of releasing it to the client
    bufferLocked: isMinimized
    // Accept either:
    // - wrapper object containing { xdgSurface } (older glue)
    // - the xdg surface itself (preferred from C++)
    shellSurface: _xdgSurfaceFromObj(surfaceObj)
    touchEventsEnabled: true
    // CRITICAL: Bind output to compositor's output
    // Qt's XdgToplevelIntegration gets output from view()->output()
    // If not set, it returns nullptr and crashes when calling availableGeometry()
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
    // CRITICAL: surfaceId may be set via binding AFTER Component.onCompleted
    // so we also register on property change
    onSurfaceIdChanged: {
        if (surfaceId !== -1) {
            Logger.info("WaylandShellSurfaceItem", "Registering surface: " + surfaceId);
            SurfaceRegistry.registerSurface(surfaceId, this);
        }
    }
    Component.onCompleted: {
        // Initial registration if surfaceId is already set
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
