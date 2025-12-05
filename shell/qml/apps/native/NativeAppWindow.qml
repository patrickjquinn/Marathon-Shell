import QtQuick
import QtWayland.Compositor
import MarathonOS.Shell
import MarathonUI.Core
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
    appIcon: nativeAppIcon || "layout-grid"

    onBackPressed: {
        return false;
    }

    content: Rectangle {
        anchors.fill: parent
        color: MColors.background

        ShellSurfaceItem {
            id: surfaceItem
            anchors.fill: parent

            property bool hasConfigured: false

            // Access the xdgSurface that was set from QML (not C++ property)
            shellSurface: nativeAppWindow.waylandSurface ? nativeAppWindow.waylandSurface.xdgSurface : null

            // Ensure proper rendering
            touchEventsEnabled: true

            // CRITICAL: Wait for surface to have content before configuring
            // Sending configure too early causes incorrect initial scaling
            Connections {
                target: nativeAppWindow.waylandSurface
                enabled: nativeAppWindow.waylandSurface !== null

                function onHasContentChanged() {
                    if (nativeAppWindow.waylandSurface.hasContent && !surfaceItem.hasConfigured) {
                        surfaceItem.hasConfigured = true;
                        var toplevel = nativeAppWindow.waylandSurface.toplevel;
                        if (toplevel && surfaceItem.width > 0 && surfaceItem.height > 0) {
                            toplevel.sendMaximized(Qt.size(surfaceItem.width, surfaceItem.height));
                        }
                    }
                }
            }

            onWidthChanged: {
                // Only reconfigure if we've already sent initial configure
                if (hasConfigured && width > 0 && height > 0 && shellSurface) {
                    var toplevel = nativeAppWindow.waylandSurface ? nativeAppWindow.waylandSurface.toplevel : null;
                    if (toplevel) {
                        toplevel.sendMaximized(Qt.size(width, height));
                    }
                }
            }

            onHeightChanged: {
                // Only reconfigure if we've already sent initial configure
                if (hasConfigured && width > 0 && height > 0 && shellSurface) {
                    var toplevel = nativeAppWindow.waylandSurface ? nativeAppWindow.waylandSurface.toplevel : null;
                    if (toplevel) {
                        toplevel.sendMaximized(Qt.size(width, height));
                    }
                }
            }

            onSurfaceDestroyed: {
                // NOTE: Task cleanup is now handled automatically in MarathonShell.qml via surfaceDestroyed signal
                // This handler just closes the window
                nativeAppWindow.close();
            }
        }

        // Splash screen - shown while app is launching
        Rectangle {
            id: splashScreen
            anchors.fill: parent
            color: MColors.background
            visible: surfaceItem.shellSurface === null

            Column {
                anchors.centerIn: parent
                spacing: MSpacing.xl

                // Show the actual app icon if available, otherwise fallback to generic icon
                MAppIcon {
                    width: 128
                    height: 128
                    source: nativeAppWindow.nativeAppIcon || "grid"
                    anchors.horizontalCenter: parent.horizontalCenter
                    smooth: true
                    visible: nativeAppWindow.nativeAppIcon !== ""
                }

                Icon {
                    name: "grid"
                    size: 128
                    color: MColors.textTertiary
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: nativeAppWindow.nativeAppIcon === ""
                }

                Text {
                    text: "Loading " + (nativeAppWindow.nativeTitle || "native app") + "..."
                    color: MColors.textSecondary
                    font.pixelSize: MTypography.sizeBody
                    font.family: MTypography.fontFamily
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }
        }
    }
}
