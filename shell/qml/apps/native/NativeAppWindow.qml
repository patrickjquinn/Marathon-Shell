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
    property bool isNative: true

    // Signal to request closing the app window (e.g. when native app exits)
    // skipNative: true if the native surface is already destroyed (client closed)
    signal requestClose(bool skipNative)

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
            // CRITICAL: Pass surfaceId so this item registers with SurfaceRegistry for popup parenting
            surfaceId: nativeAppWindow.surfaceId
            // Pass isMinimized to lock buffer during minimize (prevents VK_ERROR_SURFACE_LOST)
            isMinimized: nativeAppWindow.isMinimized
            onSurfaceDestroyed: {
                // Determine if this is a user-initiated close vs. a minimize transition
                // If the app is already minimized (user swiped to task switcher), keep it alive
                // If the app is NOT minimized, the native app itself is closing (user clicked X button)
                if (nativeAppWindow.isMinimized) {
                    Logger.info("NativeAppWindow", "Surface destroyed while minimized - keeping app alive");
                } else {
                    Logger.info("NativeAppWindow", "Surface destroyed (user closed app) - requesting close");
                    // The native app was closed by the user from within the app UI
                    // Emit requestClose to properly clean up the app window
                    // The native app was closed by the user from within the app UI
                    // Emit requestClose to properly clean up the app window
                    // skipNative=true because the surface is ALREADY destroyed!
                    nativeAppWindow.requestClose(true);
                }
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
                MAppIcon {
                    id: splashIcon

                    size: 128
                    source: nativeAppWindow.nativeAppIcon && nativeAppWindow.nativeAppIcon !== "" ? nativeAppWindow.nativeAppIcon : ""
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: source !== ""
                }

                Icon {
                    name: "grid-3x3"
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
