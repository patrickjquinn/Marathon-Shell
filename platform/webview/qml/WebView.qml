// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Sailfish.WebView 1.0 WebView on Keel, clean-room: the public API of
// Sailfish's WebView (sailfishos.org/develop/docs/sailfish-components-
// webview/, "WebView QML Type": properties, signals and methods) over a
// rendering backend:
//   qtwebengine  Qt WebEngine (Chromium; Chum's qt6-qtwebengine on the
//                device) in-process, WebEngineBackend.qml
//   external     no web engine installed: a placeholder that opens the URL
//                in the system browser, ExternalBackend.qml
// The backend is picked when the view is created (Qt WebEngine if its QML
// module is installed; KEEL_WEBVIEW_BACKEND=external forces the
// placeholder).
// The Sailfish members Qt WebEngine has no counterpart for are mapped as
// PROVENANCE.md describes: `security` from Keel's own TLS handshake with the
// page's server, the scroll and content geometry from the view's
// scrollPosition and contentsSize, the frame script message manager
// (loadFrameScript, sendAsyncMessage, addMessageListener, recvAsyncMessage)
// through a script in an isolated JavaScript world that talks to the view
// by console messages. runJavaScript() keeps Sailfish's contract (the script
// must `return` its value; errors go to errorCallback).
import QtQuick 2.6
import Sailfish.Silica 1.0
import Sailfish.WebEngine 1.0

Item {
    id: webView

    property url url
    property bool active: visible && (!webViewPage || webViewPage.status === PageStatus.Active
                                      || webViewPage.status === PageStatus.Activating)
    readonly property bool canGoBack: _backend ? _backend.canGoBack : false
    readonly property bool canGoForward: _backend ? _backend.canGoForward : false
    property string httpUserAgent
    readonly property int loadProgress: _backend ? _backend.loadProgress : 0
    property bool loaded
    readonly property bool loading: _backend ? _backend.loading : false
    property QtObject popupProvider
    property bool privateMode
    readonly property QtObject security: _security
    readonly property string title: _backend ? _backend.title : ""
    property Page webViewPage: _findWebViewPage()
    // The content process ended (Chromium's render process); cleared by the
    // next load.
    readonly property bool crashed: _backend ? _backend.crashed : false
    // This view's JavaScript, on top of WebEngineSettings.javascriptEnabled.
    property bool javascriptEnabled: true

    // Additional attributes (Sailfish's "WebView Additional Attributes").
    property bool canShowSelectionMarkers: true
    readonly property bool textSelectionActive: _backend ? _backend.textSelectionActive : false
    property Item textSelectionController: null
    property bool downloadsEnabled: true
    property real virtualKeyboardMargin
    property int orientation: {
        switch (webViewPage ? webViewPage.orientation : Orientation.None) {
        case Orientation.Portrait: return Qt.PortraitOrientation
        case Orientation.Landscape: return Qt.LandscapeOrientation
        case Orientation.PortraitInverted: return Qt.InvertedPortraitOrientation
        case Orientation.LandscapeInverted: return Qt.InvertedLandscapeOrientation
        default: return Qt.PrimaryOrientation
        }
    }
    property real viewportWidth: width
    property real viewportHeight: height - virtualKeyboardMargin
    readonly property bool atXBeginning: scrollableOffset.x <= 0.5
    readonly property bool atXEnd: scrollableOffset.x + contentRect.width >= scrollableSize.width - 0.5
    readonly property bool atYBeginning: scrollableOffset.y <= 0.5
    readonly property bool atYEnd: scrollableOffset.y + contentRect.height >= scrollableSize.height - 0.5
    readonly property bool dragging: _backend ? _backend.moving : false
    readonly property bool moving: _backend ? _backend.moving : false
    readonly property bool pinching: false
    property bool chrome: true
    property bool chromeGestureEnabled: true
    property real chromeGestureThreshold: Theme.itemSizeSmall / 2
    property bool desktopMode
    property color backgroundColor: Theme.colorScheme === Theme.LightOnDark ? "black" : "white"
    // Experimental: the visible part of the page and the page's size, in CSS
    // pixels, and the zoom.
    readonly property rect contentRect: Qt.rect(scrollableOffset.x, scrollableOffset.y,
                                                viewportWidth / Math.max(0.01, resolution),
                                                viewportHeight / Math.max(0.01, resolution))
    readonly property real contentWidth: scrollableSize.width
    readonly property real contentHeight: scrollableSize.height
    readonly property size scrollableSize: _backend ? _backend.contentsSize : Qt.size(0, 0)
    readonly property point scrollableOffset: _backend ? _backend.scrollPosition : Qt.point(0, 0)
    readonly property real resolution: _backend ? _backend.zoom : 1.0
    readonly property QtObject horizontalScrollDecorator: QtObject {
        readonly property int size: webView.scrollableSize.width > 0
                                    ? Math.round(webView.viewportWidth * webView.contentRect.width / webView.scrollableSize.width) : 0
        readonly property int position: webView.scrollableSize.width > 0
                                        ? Math.round(webView.viewportWidth * webView.scrollableOffset.x / webView.scrollableSize.width) : 0
        readonly property bool moving: webView.moving
    }
    readonly property QtObject verticalScrollDecorator: QtObject {
        readonly property int size: webView.scrollableSize.height > 0
                                    ? Math.round(webView.viewportHeight * webView.contentRect.height / webView.scrollableSize.height) : 0
        readonly property int position: webView.scrollableSize.height > 0
                                        ? Math.round(webView.viewportHeight * webView.scrollableOffset.y / webView.scrollableSize.height) : 0
        readonly property bool moving: webView.moving
    }
    readonly property bool painted: _backend ? _backend.painted : false
    readonly property int parentId: 0
    readonly property int uniqueId: _backend && _backend.messages ? _backend.messages.uniqueId : 0
    property int _inputMethodHints: Qt.ImhNone

    signal contentOrientationChanged(int orientation)
    signal linkClicked(string url)
    signal loadRedirect()
    signal viewDestroyed()
    signal recvAsyncMessage(string message, var data)
    signal imeNotification(int state, bool open, int cause, int focusChange, string type)
    signal firstPaint(int offx, int offy)
    signal windowCloseRequested()

    // Keel: "qtwebengine" or "external" once the backend is up.
    readonly property string _engine: _backend ? _backend.engineName : ""
    // The backend (WebEngineBackend.qml or ExternalBackend.qml), untyped:
    // both declare the same members.
    readonly property var _backend: backendLoader.status === Loader.Ready ? backendLoader.item : null
    readonly property Item _backendHost: backendLoader
    property QtObject _security: null
    property var _messageListeners: ({})

    function load(url) {
        webView.url = url
    }

    function loadHtml(html, baseUrl) {
        if (_backend)
            _backend.loadHtml(html, baseUrl === undefined ? "" : baseUrl)
    }

    function loadText(text, mimeType) {
        loadHtml("<html><body><pre>" + String(text).replace(/&/g, "&amp;").replace(/</g, "&lt;")
                 + "</pre></body></html>", "")
    }

    function reload() { if (_backend) _backend.reload() }
    function stop() { if (_backend) _backend.stop() }
    function goBack() { if (_backend) _backend.goBack() }
    function goForward() { if (_backend) _backend.goForward() }
    function clearSelection() { if (_backend) _backend.clearSelection() }

    function runJavaScript(script, callback, errorCallback) {
        if (_backend)
            _backend.runScript(script, callback, errorCallback)
        else if (errorCallback)
            errorCallback("WebView is not ready")
    }

    // The frame script message manager. Messages a frame script sends with
    // sendAsyncMessage() reach recvAsyncMessage for the names added here.
    function addMessageListener(name) { _messageListeners[name] = true }
    function addMessageListeners(names) {
        for (var i = 0; i < names.length; ++i)
            addMessageListener(names[i])
    }
    function removeMessageListener(name) { delete _messageListeners[name] }
    function sendAsyncMessage(name, data) { if (_backend) _backend.sendToContent(name, data) }
    function loadFrameScript(name) { if (_backend) _backend.loadFrameScript(name) }
    function setInputMethodHints(hints) { _inputMethodHints = hints }
    // Sailfish's (internal) members.
    function newWindow(url) { load(url) }
    function suspendView() { active = false }
    function resumeView() { active = true }

    function _receive(name, data) {
        if (_messageListeners[name])
            recvAsyncMessage(name, data)
    }

    function _findWebViewPage() {
        for (var p = parent; p; p = p.parent) {
            if (p.hasOwnProperty("_keelWebViewPage"))
                return p
        }
        return null
    }

    onUrlChanged: {
        if (_backend && String(_backend.url) !== String(url))
            _backend.url = url
    }
    Component.onDestruction: {
        WebEngine._keelViewDestroyed()
        viewDestroyed()
    }
    onOrientationChanged: contentOrientationChanged(orientation)

    Connections {
        target: webView._backend
        ignoreUnknownSignals: true
        function onUrlChanged() {
            if (String(webView.url) !== String(webView._backend.url))
                webView.url = webView._backend.url
        }
        function onLoadedChanged() { webView.loaded = webView._backend.loaded }
        function onKeelLinkClicked(url) { webView.linkClicked(url) }
        function onKeelLoadRedirect() { webView.loadRedirect() }
        function onKeelMessage(name, data) { webView._receive(name, data) }
        function onKeelImeNotification(state, open, cause, focusChange, type) {
            webView.imeNotification(state, open, cause, focusChange, type)
        }
        function onKeelFirstPaint() { webView.firstPaint(0, 0) }
        function onKeelWindowCloseRequested() { webView.windowCloseRequested() }
    }

    Loader {
        id: backendLoader
        width: webView.viewportWidth
        height: webView.viewportHeight
        visible: webView.active
        onStatusChanged: {
            if (status === Loader.Error && String(source).indexOf("WebEngineBackend") >= 0) {
                console.info("Sailfish.WebView: Qt WebEngine is not available; pages open in the browser")
                webView._createBackend("ExternalBackend.qml")
            }
        }
    }

    BusyIndicator {
        anchors.centerIn: backendLoader
        size: BusyIndicatorSize.Large
        running: webView.loading && !webView.crashed && webView._engine === "qtwebengine"
    }

    // As Sailfish's: a neutral placeholder over a crashed view; the app
    // decides whether to load again.
    Rectangle {
        anchors.fill: backendLoader
        visible: webView.crashed
        color: Theme.colorScheme === Theme.LightOnDark ? "black" : "white"
        MouseArea { anchors.fill: parent }
        Label {
            x: Theme.horizontalPageMargin
            width: parent.width - 2 * Theme.horizontalPageMargin
            anchors.verticalCenter: parent.verticalCenter
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            color: Theme.colorScheme === Theme.LightOnDark ? "white" : "black"
            font.pixelSize: Theme.fontSizeLarge
            //% "WebView crashed"
            text: qsTrId("sailfish_components_webview-la-webview_crashed")
        }
    }

    function _createBackend(file) {
        // Initial properties: the backend sees the view (privateMode) and the
        // first URL while it is created.
        backendLoader.setSource(file, { "webView": webView, "url": webView.url })
    }

    Component.onCompleted: {
        WebEngine._keelViewCreated()
        _security = WebEngine._keelCreateSecurity(webView)
        _createBackend(WebEngine._keelBackend === "qtwebengine" ? "WebEngineBackend.qml" : "ExternalBackend.qml")
    }
}
