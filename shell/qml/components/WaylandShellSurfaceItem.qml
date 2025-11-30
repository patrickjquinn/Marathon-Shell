import QtQuick
import QtWayland.Compositor
import MarathonOS.Shell
import MarathonUI.Theme

ShellSurfaceItem {
    property var surfaceObj: null
    property size lastSentSize: Qt.size(0, 0)
    property bool sizeUpdateScheduled: false

    shellSurface: surfaceObj && surfaceObj.xdgSurface ? surfaceObj.xdgSurface : null
    touchEventsEnabled: true

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
        if (width <= 0 || height <= 0) {
            Logger.debug("WaylandShellSurfaceItem", "sendSizeToApp skipped: invalid size " + width + "x" + height);
            return;
        }

        var toplevel = surfaceObj ? surfaceObj.toplevel : null;
        if (!toplevel) {
            Logger.debug("WaylandShellSurfaceItem", "sendSizeToApp skipped: no toplevel (surfaceObj: " + (surfaceObj ? "exists" : "null") + ")");
            return;
        }

        var newSize = Qt.size(Math.round(width), Math.round(height));

        // Only send if size actually changed (avoid sub-pixel resize spam)
        if (Math.abs(newSize.width - lastSentSize.width) < 2 && Math.abs(newSize.height - lastSentSize.height) < 2) {
            Logger.debug("WaylandShellSurfaceItem", "sendSizeToApp skipped: size unchanged (" + newSize.width + "x" + newSize.height + " vs " + lastSentSize.width + "x" + lastSentSize.height + ")");
            return;
        }

        lastSentSize = newSize;
        Logger.info("WaylandShellSurfaceItem", "📱 Configuring app as MAXIMIZED: " + newSize.width + "x" + newSize.height);

        // SOLUTION: Mobile compositors MAXIMIZE all windows by default
        //
        // sendMaximized() tells the app:
        // - "You MUST fill this exact size" (not a hint, but a requirement)
        // - "You are maximized" (XDG_TOPLEVEL_STATE_MAXIMIZED)
        // - "Remove window decorations" (no title bar, borders, etc.)
        //
        // This is how Phosh, Plasma Mobile, and other mobile shells work:
        // - All apps are maximized by default (fill the screen)
        // - Apps respond to the maximized state by using their mobile/adaptive layouts
        // - Combined with physical size (68mm) and env vars (LIBADWAITA_MOBILE=1),
        //   this triggers full mobile behavior
        //
        // Reference: https://wayland.freedesktop.org/docs/html/apa.html#protocol-spec-xdg-shell
        // Reference: Phosh/phoc compositor source (wlroots-based mobile compositor)
        toplevel.sendMaximized(newSize);
    }

    onShellSurfaceChanged: {
        Logger.info("WaylandShellSurfaceItem", "📱 onShellSurfaceChanged fired - shellSurface: " + (shellSurface ? "EXISTS" : "NULL"));
        if (shellSurface) {
            Logger.info("WaylandShellSurfaceItem", "ShellSurface assigned, configuring: " + width + "x" + height);
            Logger.info("WaylandShellSurfaceItem", "  surfaceObj: " + (surfaceObj ? "exists" : "null"));
            Logger.info("WaylandShellSurfaceItem", "  surfaceObj.toplevel: " + (surfaceObj && surfaceObj.toplevel ? "exists" : "null"));
            scheduleSizeUpdate();
        } else {
            Logger.warn("WaylandShellSurfaceItem", " ShellSurface is NULL!");
        }
    }

    Component.onCompleted: {
        Logger.info("WaylandShellSurfaceItem", " Component created - initial state:");
        Logger.info("WaylandShellSurfaceItem", "  width: " + width + ", height: " + height);
        Logger.info("WaylandShellSurfaceItem", "  shellSurface: " + (shellSurface ? "exists" : "null"));
        Logger.info("WaylandShellSurfaceItem", "  surfaceObj: " + (surfaceObj ? "exists" : "null"));
    }

    onWidthChanged: scheduleSizeUpdate()
    onHeightChanged: scheduleSizeUpdate()

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
