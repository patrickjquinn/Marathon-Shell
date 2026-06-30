import MarathonApp.Browser
import MarathonOS.Shell
import MarathonUI.Core
import MarathonUI.Theme
import QtQuick
import QtWebEngine

WebEngineView {
    id: webView

    property bool updatingTabUrl: false
    property bool active: true
    property bool crashed: false
    property bool forceDiscarded: false

    zoomFactor: 1
    // Default WebEngineView backgroundColor is white — visible as a
    // jarring white flash between navigation start and first paint, and
    // as a persistent white viewport while the homepage is still
    // loading. The shell renders against a dark wallpaper / dark Browser
    // chrome, so the cold-start period reads as a wrong-theme strobe.
    // Match the shell background; pages that set their own body
    // background paint over this immediately on first paint.
    backgroundColor: MColors.background
    lifecycleState: forceDiscarded ? WebEngineView.LifecycleState.Discarded : (active ? WebEngineView.LifecycleState.Active : WebEngineView.LifecycleState.Frozen)
    settings.accelerated2dCanvasEnabled: true
    settings.webGLEnabled: true
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
