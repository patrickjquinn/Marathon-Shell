import QtQuick
import QtWebEngine
import MarathonOS.Shell

// Separate file for WebEngineView to enable true lazy loading
// This file is only loaded when needed, avoiding QtWebEngine initialization on app launch
WebEngineView {
    id: webView

    property bool updatingTabUrl: false

    zoomFactor: 1.0

    profile.httpUserAgent: "Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36"

    settings.accelerated2dCanvasEnabled: true
    settings.webGLEnabled: true
    settings.pluginsEnabled: true
    settings.fullScreenSupportEnabled: true
    settings.allowRunningInsecureContent: false
    settings.javascriptEnabled: true
    settings.javascriptCanOpenWindows: false
    settings.javascriptCanAccessClipboard: false
    settings.localContentCanAccessRemoteUrls: false
    settings.spatialNavigationEnabled: false
    settings.touchIconsEnabled: true
    settings.focusOnNavigationEnabled: true
    settings.playbackRequiresUserGesture: false
    settings.webRTCPublicInterfacesOnly: true
    settings.dnsPrefetchEnabled: true
    settings.showScrollBars: false
}
