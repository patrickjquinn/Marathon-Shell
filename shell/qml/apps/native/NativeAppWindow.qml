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
    readonly property Item backdropItem: keelApp ? ambienceItem : null
    // The shell draws the backdrop and surface itself (rounded, while the
    // window lands on its card); the originals only keep their textures.
    property bool texturesRequested: false
    property bool drawnByTexture: false
    readonly property bool keelApp: {
        const info = typeof MarathonAppRegistry !== "undefined" && nativeAppId !== "" ? MarathonAppRegistry.getApp(nativeAppId) : null;
        return !!info || AppLaunchService.isKeelHostApp(nativeAppId);
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
        color: nativeAppWindow.keelApp || nativeAppWindow.drawnByTexture ? "transparent" : MColors.background

        ShellComponents.KeelAmbienceBackground {
            id: ambience

            anchors.fill: parent
            opacity: nativeAppWindow.drawnByTexture ? 0 : 1
            // A texture to draw even before the wallpaper has loaded.
            layer.enabled: ready || nativeAppWindow.texturesRequested
            visible: nativeAppWindow.keelApp
            Component.onCompleted: nativeAppWindow.ambienceItem = ambience
            wallpaper: AmbienceService.wallpaperUrl
            light: AmbienceService.light
        }

        // The window went: show the app's other window, or the one that
        // replaces it (Waydroid re-creates a task's window as Android redraws
        // it, and the card waits for it, AppLaunchService), else close.
        Timer {
            id: followTask

            property int tries: 0

            interval: 100
            repeat: true
            onTriggered: {
                const task = TaskModel.getTaskByAppId(nativeAppWindow.nativeAppId);
                if (task && task.surfaceId > 0 && task.surfaceId !== nativeAppWindow.surfaceId) {
                    stop();
                    Logger.info("NativeAppWindow", "Surface destroyed - showing surfaceId " + task.surfaceId);
                    nativeAppWindow.waylandSurface = task.waylandSurface;
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

        // Sized to match MarathonAppWindow's launch splash so the swap from
        // shell-side splash → native-side splash on first surface map is
        // visually seamless (same icon size + text + spacing). Previously
        // the shell rendered 128 × scaleFactor (~229dp on L5) and this one
        // rendered raw 128 — user saw a "smaller duplicate appear" mid-load.
        Rectangle {
            id: splashScreen

            anchors.fill: parent
            color: MColors.background
            z: 10

            // revealReady comes with the app's first commit, before the shell
            // has drawn it: the splash fades once the shell has drawn three
            // frames since, or after 250 ms if it has nothing else to draw.
            property bool _revealed: false
            property int _framesSinceReady: -1

            opacity: _revealed ? 0 : 1
            visible: opacity > 0.001
            Behavior on opacity {
                NumberAnimation {
                    duration: 160
                    easing.type: Easing.OutCubic
                }
            }

            function _hold() {
                _framesSinceReady = 0;
                revealHold.restart();
            }

            Timer {
                id: revealHold

                interval: 250
                onTriggered: splashScreen._revealed = true
            }
            Connections {
                target: splashScreen._framesSinceReady >= 0 && !splashScreen._revealed ? splashScreen.Window.window : null

                function onAfterAnimating() {
                    if (++splashScreen._framesSinceReady >= 3)
                        splashScreen._revealed = true;
                }
            }
            Connections {
                target: nativeAppWindow
                function onRevealReadyChanged() {
                    // One-way: hasContent dips (suspend, buffer churn) after
                    // first reveal must not bring the splash back.
                    if (nativeAppWindow.revealReady && !splashScreen._revealed)
                        splashScreen._hold();
                }
            }
            // Restore path: the surface can already be live (revealReady true)
            // BEFORE this Connections is wired, so onRevealReadyChanged fires
            // into the void and the splash never lifts — the #497 black-on-
            // first-restore. The edge-triggered handler above can't catch a
            // transition that already happened; level-check it once at creation.
            Component.onCompleted: {
                if (nativeAppWindow.revealReady && !splashScreen._revealed)
                    splashScreen._hold();
            }

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
