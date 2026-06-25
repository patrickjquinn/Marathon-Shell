import "../../components" as ShellComponents
import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Core
import MarathonUI.Theme
import QtQuick

MApp {
    id: nativeAppWindow

    property var waylandSurface: null
    property string nativeAppId: ""
    property string nativeTitle: ""
    property string nativeAppIcon: ""
    property int surfaceId: -1
    property bool isMinimized: false
    property bool isNative: true
    property var surfaceItemRef: null
    readonly property bool revealReady: surfaceItemRef && surfaceItemRef.hasSentInitialSize && surfaceItemRef.hasFirstFrame

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

        ShellComponents.WaylandShellSurfaceItem {
            id: surfaceItem

            anchors.fill: parent
            autoResize: true
            surfaceObj: nativeAppWindow.waylandSurface
            surfaceId: nativeAppWindow.surfaceId
            isMinimized: nativeAppWindow.isMinimized
            onSurfaceDestroyed: {
                if (nativeAppWindow.isMinimized) {
                    Logger.info("NativeAppWindow", "Surface destroyed while minimized - keeping app alive");
                } else {
                    Logger.info("NativeAppWindow", "Surface destroyed (user closed app) - requesting close");
                    Qt.callLater(function () {
                        nativeAppWindow.requestClose(true);
                    });
                }
            }
            Component.onCompleted: {
                nativeAppWindow.surfaceItemRef = surfaceItem;
                Logger.info("NativeAppWindow", "ShellSurfaceItem created for: " + nativeAppWindow.nativeAppId);
                Logger.info("NativeAppWindow", "  Container size: " + contentContainer.width + "x" + contentContainer.height);
                Logger.info("NativeAppWindow", "  Item size: " + width + "x" + height);
            }
        }

        // Sized to match MarathonAppWindow's launch splash so the swap from
        // shell-side splash → native-side splash on first surface map is
        // visually seamless (same icon size + text + spacing). Previously
        // the shell rendered 128 × scaleFactor (~229dp on L5) and this one
        // rendered raw 128 — user saw a "smaller duplicate appear" mid-load.
        Rectangle {
            id: splashScreen

            anchors.fill: parent
            color: MColors.background
            visible: !nativeAppWindow.revealReady
            z: 10

            Column {
                anchors.centerIn: parent
                spacing: 24

                MAppIcon {
                    id: splashIcon

                    size: Math.round(128 * Constants.scaleFactor)
                    source: nativeAppWindow.nativeAppIcon && nativeAppWindow.nativeAppIcon !== "" ? nativeAppWindow.nativeAppIcon : ""
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: source !== ""
                }

                Icon {
                    name: "grid-3x3"
                    size: Math.round(128 * Constants.scaleFactor)
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
