import MarathonOS.Shell
import MarathonUI.Theme
import QtQuick
import QtWayland.Compositor

ShellSurfaceItem {
    // SOLUTION: Mobile compositors MAXIMIZE all windows by default
    // sendMaximized() tells the app:
    // - "You MUST fill this exact size" (not a hint, but a requirement)
    // - "You are maximized" (XDG_TOPLEVEL_STATE_MAXIMIZED)
    // - "Remove window decorations" (no title bar, borders, etc.)
    // This is how Phosh, Plasma Mobile, and other mobile shells work:
    // - All apps are maximized by default (fill the screen)
    // - Apps respond to the maximized state by using their mobile/adaptive layouts
    // - Combined with physical size (68mm) and env vars (LIBADWAITA_MOBILE=1),
    //   this triggers full mobile behavior
    // ShellSurfaceItem created for native app

    property var surfaceObj: null
    property size lastSentSize: Qt.size(0, 0)
    property bool sizeUpdateScheduled: false
    property bool hasSentInitialSize: false
    property bool autoResize: true
    // CRITICAL: When isMinimized is true, lock the buffer to retain the last frame
    // This prevents Vulkan surface lost errors when apps like Chromium destroy their surface during minimize
    // The buffer stays visible for task switcher preview even after surface destruction
    property bool isMinimized: false

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
        // Minimum reasonable mobile app width is ~320px (iPhone SE width)
        if (width < 320) {
            Logger.debug("WaylandShellSurfaceItem", "sendSizeToApp skipped: width " + width + " is below minimum (320px) - waiting for layout completion");
            return;
        }
        var toplevel = surfaceObj ? surfaceObj.toplevel : null;
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
        hasSentInitialSize = true;
        Logger.info("WaylandShellSurfaceItem", "📱 Configuring app as MAXIMIZED: " + newSize.width + "x" + newSize.height);
        // Reference: https://wayland.freedesktop.org/docs/html/apa.html#protocol-spec-xdg-shell
        // Reference: Phosh/phoc compositor source (wlroots-based mobile compositor)
        toplevel.sendMaximized(newSize);
    }

    // bufferLocked is inherited from WaylandQuickItem (parent of ShellSurfaceItem)
    // When true, the compositor retains the buffer instead of releasing it to the client
    bufferLocked: isMinimized
    shellSurface: surfaceObj && surfaceObj.xdgSurface ? surfaceObj.xdgSurface : null
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
    Component.onCompleted: {}
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
