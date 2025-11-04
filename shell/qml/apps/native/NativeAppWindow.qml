import QtQuick
import MarathonOS.Shell
import MarathonUI.Theme
import MarathonUI.Containers

MApp {
    id: nativeAppWindow
    
    // Expose HAVE_WAYLAND from C++ context
    readonly property bool haveWayland: typeof HAVE_WAYLAND !== 'undefined' ? HAVE_WAYLAND : false
    
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
        
        // Wayland surface rendering - conditionally load on Linux
        Loader {
            id: waylandSurfaceLoader
            anchors.fill: parent
            visible: haveWayland
            active: haveWayland && waylandSurface !== null
            source: haveWayland ? "qrc:/MarathonOS/Shell/qml/components/WaylandShellSurfaceItem.qml" : ""
            
            onItemChanged: {
                if (item && waylandSurface) {
                    item.surfaceObj = waylandSurface
                }
            }
            
            Connections {
                target: waylandSurfaceLoader.item
                function onSurfaceDestroyed() {
                    Logger.info("NativeAppWindow", "Surface destroyed for: " + nativeAppWindow.appId)
                    nativeAppWindow.close()
                            }
            }
        }
        
        // Show message when Wayland is not available (macOS)
        Column {
            anchors.centerIn: parent
            spacing: Constants.spacingLarge
            visible: !haveWayland
            
            Text {
                text: "Native Apps Not Supported"
                color: MColors.text
                font.pixelSize: MTypography.sizeXLarge
                anchors.horizontalCenter: parent.horizontalCenter
            }
            
            Text {
                text: "Native Linux apps require Wayland compositor,\nwhich is only available on Linux.\n\nOn macOS, only Marathon apps are supported."
                color: MColors.textSecondary
                font.pixelSize: MTypography.sizeBody
                anchors.horizontalCenter: parent.horizontalCenter
                horizontalAlignment: Text.AlignHCenter
            }
        }
        
        // Splash screen - shown while app is launching (on Linux with Wayland)
        Rectangle {
            id: splashScreen
            anchors.fill: parent
            color: MColors.background
            visible: haveWayland && (!waylandSurface || (waylandSurfaceLoader.item && !waylandSurfaceLoader.item.shellSurface))
            
            Component.onCompleted: {
                Logger.info("NativeAppWindow", "=== SPLASH SCREEN CREATED ===")
                Logger.info("NativeAppWindow", "Visible: " + visible)
                Logger.info("NativeAppWindow", "Color: " + color)
                Logger.info("NativeAppWindow", "Icon: " + nativeAppWindow.nativeAppIcon)
                Logger.info("NativeAppWindow", "Title: " + nativeAppWindow.nativeTitle)
            }
            
            onVisibleChanged: {
                var hasSurface = waylandSurfaceLoader.item && waylandSurfaceLoader.item.shellSurface
                Logger.info("NativeAppWindow", "Splash visibility changed: " + visible + " (shellSurface: " + (hasSurface ? "EXISTS" : "NULL") + ")")
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

