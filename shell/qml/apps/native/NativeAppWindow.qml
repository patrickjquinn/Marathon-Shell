import QtQuick
import QtWayland.Compositor
import MarathonOS.Shell
import MarathonUI.Theme
import MarathonUI.Containers

MApp {
    id: nativeAppWindow
    
    property var waylandSurface: null
    property string nativeAppId: ""
    property string nativeTitle: ""
    property string nativeAppIcon: ""
    property int surfaceId: -1
    
    appId: nativeAppId
    appName: nativeTitle || "Native App"
    appIcon: nativeAppIcon || "qrc:/images/icons/lucide/grid.svg"
    
    onBackPressed: {
        return false
    }
    
    content: Rectangle {
        anchors.fill: parent
        color: MColors.background
        
        ShellSurfaceItem {
            id: surfaceItem
            anchors.fill: parent
            
            // Access the xdgSurface that was set from QML (not C++ property)
            shellSurface: nativeAppWindow.waylandSurface ? nativeAppWindow.waylandSurface.xdgSurface : null
            
            // Ensure proper rendering
            touchEventsEnabled: true
            
            onShellSurfaceChanged: {
                if (shellSurface) {
                    Logger.info("NativeAppWindow", "ShellSurface assigned, configuring: " + width + "x" + height)
                    
                    // Get the toplevel from the Wayland surface (stored in QML)
                    var toplevel = nativeAppWindow.waylandSurface ? nativeAppWindow.waylandSurface.toplevel : null
                    
                    if (toplevel) {
                        // Configure the surface to be maximized once we have a valid size
                        Qt.callLater(function() {
                            if (width > 0 && height > 0) {
                                Logger.info("NativeAppWindow", "Sending maximized state: " + width + "x" + height)
                                toplevel.sendMaximized(Qt.size(width, height))
                            }
                        })
                    }
                }
            }
            
            onWidthChanged: {
                if (width > 0 && height > 0) {
                    var toplevel = nativeAppWindow.waylandSurface ? nativeAppWindow.waylandSurface.toplevel : null
                    if (toplevel) {
                        Logger.info("NativeAppWindow", "Width changed, sending maximized: " + width + "x" + height)
                        toplevel.sendMaximized(Qt.size(width, height))
                    }
                }
            }
            
            onHeightChanged: {
                if (width > 0 && height > 0) {
                    var toplevel = nativeAppWindow.waylandSurface ? nativeAppWindow.waylandSurface.toplevel : null
                    if (toplevel) {
                        Logger.info("NativeAppWindow", "Height changed, sending maximized: " + width + "x" + height)
                        toplevel.sendMaximized(Qt.size(width, height))
                    }
                }
            }
            
            onSurfaceDestroyed: {
                Logger.info("NativeAppWindow", "Surface destroyed for: " + nativeAppWindow.appId)
                nativeAppWindow.close()
            }
        }
        
        // Splash screen - shown while app is launching
        Rectangle {
            id: splashScreen
            anchors.fill: parent
            color: MColors.background
            visible: surfaceItem.shellSurface === null
            
            Component.onCompleted: {
                Logger.info("NativeAppWindow", "=== SPLASH SCREEN CREATED ===")
                Logger.info("NativeAppWindow", "Visible: " + visible)
                Logger.info("NativeAppWindow", "Color: " + color)
                Logger.info("NativeAppWindow", "Icon: " + nativeAppWindow.nativeAppIcon)
                Logger.info("NativeAppWindow", "Title: " + nativeAppWindow.nativeTitle)
            }
            
            onVisibleChanged: {
                Logger.info("NativeAppWindow", "Splash visibility changed: " + visible + " (shellSurface: " + (surfaceItem.shellSurface ? "EXISTS" : "NULL") + ")")
            }
            
            Column {
                anchors.centerIn: parent
                spacing: MSpacing.xl
                
                Component.onCompleted: {
                    Logger.info("NativeAppWindow", "Splash Column created")
                }
                
                // Show the actual app icon if available, otherwise fallback to generic icon
                Image {
                    width: 128
                    height: 128
                    source: nativeAppWindow.nativeAppIcon || "qrc:/images/icons/lucide/grid.svg"
                    sourceSize.width: 128
                    sourceSize.height: 128
                    fillMode: Image.PreserveAspectFit
                    anchors.horizontalCenter: parent.horizontalCenter
                    smooth: true
                    visible: nativeAppWindow.nativeAppIcon !== ""
                    
                    onStatusChanged: {
                        if (status === Image.Error) {
                            Logger.warn("NativeAppWindow", "Failed to load icon: " + source)
                        } else if (status === Image.Ready) {
                            Logger.info("NativeAppWindow", "Icon loaded successfully: " + source)
                        }
                    }
                }
                
                Icon {
                    name: "grid"
                    size: 128
                    color: MColors.textTertiary
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: nativeAppWindow.nativeAppIcon === ""
                    
                    Component.onCompleted: {
                        Logger.info("NativeAppWindow", "Fallback Icon visible: " + visible)
                    }
                }
                
                Text {
                    text: "Loading " + (nativeAppWindow.nativeTitle || "native app") + "..."
                    color: MColors.textSecondary
                    font.pixelSize: MTypography.sizeBody
                    font.family: MTypography.fontFamily
                    anchors.horizontalCenter: parent.horizontalCenter
                    
                    Component.onCompleted: {
                        Logger.info("NativeAppWindow", "Loading text: '" + text + "'")
                    }
                }
            }
        }
    }
    
    Component.onCompleted: {
        Logger.info("NativeAppWindow", "Created for surface: " + surfaceId)
        Logger.info("NativeAppWindow", "appId: " + nativeAppId + " (property: " + appId + ")")
        Logger.info("NativeAppWindow", "nativeTitle: " + nativeTitle)
    }
}

