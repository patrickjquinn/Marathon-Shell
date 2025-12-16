import QtQuick
import MarathonApp.Browser
import QtWebEngine
import MarathonOS.Shell
import MarathonUI.Core

// Separate file for WebEngineView to enable true lazy loading
// This file is only loaded when needed, avoiding QtWebEngine initialization on app launch
WebEngineView {
    id: webView

    property bool updatingTabUrl: false
    property bool active: true
    property bool crashed: false
    // Allows BrowserApp to discard WebEngine state while minimized without breaking bindings.
    property bool forceDiscarded: false

    zoomFactor: 1.0

    // Keep per-tab state, but freeze background tabs (no reload) on low-end devices.
    lifecycleState: forceDiscarded ? WebEngineView.LifecycleState.Discarded : (active ? WebEngineView.LifecycleState.Active : WebEngineView.LifecycleState.Frozen)

    settings.accelerated2dCanvasEnabled: false
    settings.webGLEnabled: false
    settings.pluginsEnabled: false
    settings.fullScreenSupportEnabled: true
    settings.allowRunningInsecureContent: false
    settings.javascriptEnabled: true
    settings.javascriptCanOpenWindows: false
    settings.javascriptCanAccessClipboard: false
    settings.localContentCanAccessRemoteUrls: false
    settings.spatialNavigationEnabled: false
    settings.touchIconsEnabled: false
    settings.focusOnNavigationEnabled: true
    settings.playbackRequiresUserGesture: true
    settings.webRTCPublicInterfacesOnly: true
    settings.dnsPrefetchEnabled: false
    settings.showScrollBars: false

    Rectangle {
        anchors.fill: parent
        visible: webView.crashed
        color: Qt.rgba(0, 0, 0, 0.6)
        z: 10000

        Column {
            anchors.centerIn: parent
            spacing: 12

            Text {
                text: "Tab crashed"
                color: "white"
                font.pixelSize: 20
            }

            MButton {
                text: "Reload"
                onClicked: {
                    webView.crashed = false;
                    webView.reload();
                }
            }
        }
    }
}
