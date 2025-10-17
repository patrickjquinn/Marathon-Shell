import QtQuick
import QtQuick.Controls
import QtWayland.Compositor
import MarathonOS.Shell
import MarathonUI.Theme
import MarathonUI.Containers

MApp {
    id: nativeAppWindow
    
    property var waylandSurface: null
    property string nativeAppId: ""
    property string nativeTitle: ""
    property int surfaceId: -1
    
    appId: nativeAppId
    appName: nativeTitle || "Native App"
    appIcon: "qrc:/images/icons/lucide/grid.svg"
    
    onBackPressed: {
        return false
    }
    
    content: Rectangle {
        anchors.fill: parent
        color: MColors.background
        
        ShellSurfaceItem {
            id: surfaceItem
            anchors.fill: parent
            shellSurface: nativeAppWindow.waylandSurface
            onSurfaceDestroyed: {
                Logger.info("NativeAppWindow", "Surface destroyed for: " + nativeAppWindow.appId)
                nativeAppWindow.close()
            }
        }
        
        Rectangle {
            anchors.fill: parent
            color: MColors.background
            visible: !surfaceItem.shellSurface
            
            Column {
                anchors.centerIn: parent
                spacing: MSpacing.xl
                
                Icon {
                    name: "grid"
                    size: 128
                    color: MColors.textTertiary
                    anchors.horizontalCenter: parent.horizontalCenter
                }
                
                Text {
                    text: "Loading native app..."
                    color: MColors.textSecondary
                    font.pixelSize: MTypography.sizeBody
                    font.family: MTypography.fontFamily
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }
        }
    }
    
    Component.onCompleted: {
        Logger.info("NativeAppWindow", "Created for surface: " + surfaceId)
    }
}

