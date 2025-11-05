import QtQuick
import QtWayland.Compositor
import MarathonOS.Shell
import MarathonUI.Theme

ShellSurfaceItem {
    property var surfaceObj: null
    
    shellSurface: surfaceObj && surfaceObj.xdgSurface ? surfaceObj.xdgSurface : null
    touchEventsEnabled: true
    
    onShellSurfaceChanged: {
        if (shellSurface) {
            Logger.info("WaylandShellSurfaceItem", "ShellSurface assigned, configuring: " + width + "x" + height)
            
            var toplevel = surfaceObj ? surfaceObj.toplevel : null
            if (toplevel) {
                Qt.callLater(function() {
                    if (width > 0 && height > 0) {
                        Logger.info("WaylandShellSurfaceItem", "Sending maximized state: " + width + "x" + height)
                        toplevel.sendMaximized(Qt.size(width, height))
                    }
                })
            }
        }
    }
    
    onWidthChanged: {
        if (width > 0 && height > 0) {
            var toplevel = surfaceObj ? surfaceObj.toplevel : null
            if (toplevel) {
                Logger.info("WaylandShellSurfaceItem", "Width changed, sending maximized: " + width + "x" + height)
                toplevel.sendMaximized(Qt.size(width, height))
            }
        }
    }
    
    onHeightChanged: {
        if (width > 0 && height > 0) {
            var toplevel = surfaceObj ? surfaceObj.toplevel : null
            if (toplevel) {
                Logger.info("WaylandShellSurfaceItem", "Height changed, sending maximized: " + width + "x" + height)
                toplevel.sendMaximized(Qt.size(width, height))
            }
        }
    }
    
    onSurfaceDestroyed: {
        Logger.info("WaylandShellSurfaceItem", "Surface destroyed")
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

