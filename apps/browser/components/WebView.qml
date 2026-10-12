import QtQuick
import QtWebEngine
import Sailfish.Silica 1.0
import Marathon.Silica 1.0

WebEngineView {
    id: webView

    property bool updatingTabUrl: false
    property bool active: true
    property bool crashed: false
    property bool forceDiscarded: false

    zoomFactor: 1
    // The default white flashes between navigation start and first paint.
    // Chromium takes only an opaque or a fully transparent background;
    // the translucent overlay colour failed a CHECK on the first load.
    backgroundColor: Qt.rgba(Theme.overlayBackgroundColor.r, Theme.overlayBackgroundColor.g, Theme.overlayBackgroundColor.b, 1)
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
    // false: with this on, every navigation handed focus to the web view,
    // and any page that autofocuses a field yanked the on-screen keyboard up
    // over the content the user had just tapped through to. Mobile browsers
    // leave focus where the user put it.
    settings.focusOnNavigationEnabled: false
    settings.playbackRequiresUserGesture: true
    settings.webRTCPublicInterfacesOnly: true
    settings.dnsPrefetchEnabled: false
    settings.showScrollBars: false
    // BrowserApp draws its own error page from loadingChanged.
    settings.errorPageEnabled: false

    Rectangle {
        anchors.fill: parent
        visible: webView.crashed
        color: Theme.overlayBackgroundColor
        z: 10000

        Column {
            anchors.centerIn: parent
            width: parent.width - 2 * Theme.horizontalPageMargin
            spacing: Theme.paddingLarge

            InfoLabel {
                text: qsTr("This page stopped working")
            }

            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                text: qsTr("Reload")
                onClicked: {
                    webView.crashed = false;
                    webView.reload();
                }
            }
        }
    }
}
