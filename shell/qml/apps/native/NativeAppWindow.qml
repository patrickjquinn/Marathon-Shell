import "../../components" as ShellComponents
import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Core
import MarathonUI.Theme
import QtQuick
import QtWayland.Compositor

MApp {
    id: nativeAppWindow

    property var waylandSurface: null
    property string nativeAppId: ""
    property string nativeTitle: ""
    property string nativeAppIcon: ""
    property int surfaceId: -1
    // When minimized, signal to shell surface item to lock its buffer
    // This retains the last rendered frame during minimize for smooth task switcher preview
    property bool isMinimized: false

    appId: nativeAppId
    appName: nativeTitle || "Native App"
    appIcon: nativeAppIcon || "layout-grid"
    onBackPressed: {
        return false;
    }

    content: Rectangle {
        id: contentContainer

        anchors.fill: parent
        color: MColors.background

        // CRITICAL: Use our custom WaylandShellSurfaceItem with autoResize control
        ShellComponents.WaylandShellSurfaceItem {
            id: surfaceItem

            anchors.fill: parent
            // NativeAppWindow SHOULD send size updates (it's the main window, not a thumbnail)
            autoResize: true
            // Pass the surface object so our custom component can access toplevel
            surfaceObj: nativeAppWindow.waylandSurface
            // Pass isMinimized to lock buffer during minimize (prevents VK_ERROR_SURFACE_LOST)
            isMinimized: nativeAppWindow.isMinimized
            onSurfaceDestroyed: {
                // Only close if not minimized - when minimized, we expect surface destruction
                if (!nativeAppWindow.isMinimized)
                    nativeAppWindow.close();
                else
                    Logger.info("NativeAppWindow", "Surface destroyed while minimized - buffer locked, keeping app alive");
            }
            Component.onCompleted: {
                Logger.info("NativeAppWindow", "ShellSurfaceItem created for: " + nativeAppWindow.nativeAppId);
                Logger.info("NativeAppWindow", "  Container size: " + contentContainer.width + "x" + contentContainer.height);
                Logger.info("NativeAppWindow", "  Item size: " + width + "x" + height);
            }
        }

        // Splash screen - shown while app is launching
        Rectangle {
            id: splashScreen

            anchors.fill: parent
            color: MColors.background
            visible: surfaceItem.shellSurface === null
            z: 10

            Column {
                anchors.centerIn: parent
                spacing: MSpacing.xl

                // High-quality app icon with proper scaling
                Image {
                    id: splashIcon

                    width: 128
                    height: 128
                    source: nativeAppWindow.nativeAppIcon && nativeAppWindow.nativeAppIcon !== "" ? nativeAppWindow.nativeAppIcon : ""
                    anchors.horizontalCenter: parent.horizontalCenter
                    smooth: true
                    mipmap: true
                    sourceSize.width: 256 // Request high-res and downscale for crispness
                    sourceSize.height: 256
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    cache: true
                    visible: source !== ""
                    onStatusChanged: {
                        if (status === Image.Ready)
                            Logger.debug("NativeAppWindow", "Splash icon loaded: " + source + " intrinsic size: " + implicitWidth + "x" + implicitHeight);
                        else if (status === Image.Error)
                            Logger.warn("NativeAppWindow", "Failed to load splash icon: " + source);
                    }
                }

                Icon {
                    name: "grid"
                    size: 128
                    color: MColors.textTertiary
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: splashIcon.source === "" || splashIcon.status === Image.Error
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
