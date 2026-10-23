pragma ComponentBehavior: Bound

import "../../components" as ShellComponents
import MarathonOS.Shell
import QtQuick
import Sailfish.Silica 1.0 as Silica

MApp {
    id: nativeAppWindow

    property var waylandSurface: null
    property string nativeAppId: ""
    property string nativeTitle: ""
    property string nativeAppIcon: ""
    property int surfaceId: -1
    property bool isNative: true
    property var surfaceItemRef: null
    property Item ambienceItem: null
    readonly property Item backdropItem: ambienceBackdrop ? ambienceItem : null
    // The shell draws the backdrop and surface itself (rounded, while the
    // window lands on its card); the originals only keep their textures.
    property bool texturesRequested: false
    property bool drawnByTexture: false
    // Android windows carry alpha too (a platform-themed app draws a clear
    // window background), so they sit on the ambience as Keel apps do.
    readonly property bool ambienceBackdrop: keelApp || nativeAppId.startsWith("waydroid.")
    readonly property bool keelApp: {
        return AppModel.hasApp(nativeAppId) || Tasks.isKeelHostApp(nativeAppId);
    }

    // Both of these are declared and driven by MApp. Redeclaring them here
    // shadowed the base, so MApp.minimize() set a property nobody read and
    // the shell's isMinimized never changed. isMinimized now simply inherits;
    // revealReady overrides the BASE BINDING, because a native window's
    // reveal must wait for the Wayland surface's first frame rather than
    // MApp's next-tick default.
    revealReady: surfaceItemRef && surfaceItemRef.hasSentInitialSize && surfaceItemRef.hasFirstFrame

    signal requestClose(bool skipNative)
    signal surfaceSwitched

    appId: nativeAppId
    appName: nativeTitle || "Native App"
    appIcon: nativeAppIcon || "layout-grid"
    onBackPressed: {
        return false;
    }

    content: Rectangle {
        id: contentContainer

        anchors.fill: parent
        color: nativeAppWindow.ambienceBackdrop || nativeAppWindow.drawnByTexture ? "transparent" : MColors.background

        ShellComponents.KeelAmbienceBackground {
            id: ambience

            anchors.fill: parent
            opacity: nativeAppWindow.drawnByTexture ? 0 : 1
            // A texture to draw even before the wallpaper has loaded.
            layer.enabled: ready || nativeAppWindow.texturesRequested
            visible: nativeAppWindow.ambienceBackdrop
            Component.onCompleted: nativeAppWindow.ambienceItem = ambience
            wallpaper: AmbienceService.wallpaperUrl
            light: AmbienceService.light
        }

        // The window went: show the app's other window, or the one that
        // replaces it (Waydroid re-creates a task's window as Android redraws
        // it, and the card waits for it, Tasks), else close.
        Timer {
            id: followTask

            property int tries: 0

            interval: 100
            repeat: true
            onTriggered: {
                const task = Tasks.getTaskByAppId(nativeAppWindow.nativeAppId);
                if (task && task.surfaceId > 0 && task.surfaceId !== nativeAppWindow.surfaceId) {
                    stop();
                    Logger.info("NativeAppWindow", "Surface destroyed - showing surfaceId " + task.surfaceId);
                    nativeAppWindow.waylandSurface = WaylandCompositorManager.compositor.shellSurfaceById(task.surfaceId);
                    nativeAppWindow.surfaceId = task.surfaceId;
                    nativeAppWindow.surfaceSwitched();
                } else if (!task || ++tries > 12) {
                    stop();
                    Logger.info("NativeAppWindow", "Surface destroyed (user closed app) - requesting close");
                    nativeAppWindow.requestClose(true);
                }
            }
        }

        ShellComponents.WaylandShellSurfaceItem {
            id: surfaceItem

            autoResize: true
            surfaceObj: nativeAppWindow.waylandSurface
            surfaceId: nativeAppWindow.surfaceId
            isMinimized: nativeAppWindow.isMinimized
            opacity: nativeAppWindow.drawnByTexture ? 0 : 1
            onSurfaceDestroyed: {
                if (nativeAppWindow.isMinimized) {
                    Logger.info("NativeAppWindow", "Surface destroyed while minimized - keeping app alive");
                } else {
                    followTask.tries = 0;
                    followTask.start();
                }
            }
            Component.onCompleted: {
                nativeAppWindow.surfaceItemRef = surfaceItem;
                Logger.info("NativeAppWindow", "ShellSurfaceItem created for: " + nativeAppWindow.nativeAppId);
                Logger.info("NativeAppWindow", "  Container size: " + contentContainer.width + "x" + contentContainer.height);
                Logger.info("NativeAppWindow", "  Item size: " + width + "x" + height);
            }
        }

        // The outer MarathonAppWindow splash remains above this item until
        // revealReady. Hide this fallback on the same edge: delaying it after
        // the first buffer draws the launch cover over live app content.
        Rectangle {
            id: splashScreen

            anchors.fill: parent
            color: MColors.background
            z: 10

            visible: !nativeAppWindow.revealReady

            // Laid out as MarathonAppWindow's splash, so the icon stays launcher-size through the hand-off.
            Column {
                anchors.centerIn: parent
                spacing: Silica.Theme.paddingLarge

                MAppIcon {
                    id: splashIcon

                    loadAsync: false
                    size: Silica.Theme.iconSizeLauncher
                    source: nativeAppWindow.nativeAppIcon && nativeAppWindow.nativeAppIcon !== "" ? nativeAppWindow.nativeAppIcon : ""
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: source !== ""
                }

                GlyphIcon {
                    name: "grid-3x3"
                    size: Silica.Theme.iconSizeLauncher
                    color: MColors.textTertiary
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: splashIcon.source === "" || splashIcon.status === Image.Error
                }

                // Holds the shell splash's spinner slot.
                Silica.BusyIndicator {
                    anchors.horizontalCenter: parent.horizontalCenter
                    size: Silica.BusyIndicatorSize.Small
                    running: false
                }
            }
        }
    }
}
