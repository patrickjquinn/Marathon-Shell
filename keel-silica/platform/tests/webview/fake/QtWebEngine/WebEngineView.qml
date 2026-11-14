// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// The fake view: setting url "loads" it (loadingChanged started, then
// succeeded on the next turn), keeps a history for goBack/goForward, and
// runJavaScript() evaluates the script in a JavaScript function so
// Keel's wrapping is exercised for real.
import QtQuick 2.6

Item {
    id: view

    enum WebAction { Back, Forward, Stop, Reload, Cut, Copy, Paste, Undo, Redo, SelectAll,
                     ReloadAndBypassCache, PasteAndMatchStyle, OpenLinkInThisWindow, OpenLinkInNewWindow,
                     OpenLinkInNewTab, CopyLinkToClipboard, DownloadLinkToDisk, CopyImageToClipboard,
                     CopyImageUrlToClipboard, DownloadImageToDisk, CopyMediaUrlToClipboard, ToggleMediaControls,
                     ToggleMediaLoop, ToggleMediaPlayPause, ToggleMediaMute, DownloadMediaToDisk,
                     InspectElement, ExitFullScreen, RequestClose, Unselect }

    property url url
    property string title
    property int loadProgress
    property bool canGoBack: index > 0
    property bool canGoForward: index < history.length - 1
    property QtObject profile
    property real zoomFactor: 1.0
    property WebEngineSettings settings: WebEngineSettings { }
    property var history: []
    property int index: -1
    property string lastHtml
    property var actions: []
    property bool _navigating
    property size contentsSize: Qt.size(0, 0)
    property point scrollPosition: Qt.point(0, 0)
    property color backgroundColor: "white"
    // Qt WebEngine's WebEngineScriptCollection: the double keeps the list.
    readonly property QtObject userScripts: QtObject { property var collection: [] }

    // Qt WebEngine's loadingChanged(loadingInfo) also notifies its
    // `loading` property; a QML type cannot have both, so the double has
    // only the signal (Keel's backend tracks loading from it).
    signal loadingChanged(WebEngineLoadingInfo loadingInfo)
    signal navigationRequested(WebEngineNavigationRequest request)
    signal javaScriptDialogRequested(var request)
    signal authenticationDialogRequested(var request)
    signal featurePermissionRequested(url securityOrigin, int feature)
    signal contextMenuRequested(var request)
    signal fileDialogRequested(var request)
    signal colorDialogRequested(var request)
    signal newWindowRequested(var request)
    signal javaScriptConsoleMessage(int level, string message, int lineNumber, string sourceID)
    signal renderProcessTerminated(int terminationStatus, int exitCode)
    signal certificateError(var error)
    signal windowCloseRequested()
    signal linkHovered(url hoveredUrl)
    property url icon

    enum Feature { MediaAudioCapture, MediaVideoCapture, MediaAudioVideoCapture, Geolocation,
                   DesktopVideoCapture, DesktopAudioVideoCapture, Notifications, ClipboardReadWrite,
                   LocalFontsAccess }

    // grantFeaturePermission() answers, as [origin, feature, granted].
    property var grants: []
    function grantFeaturePermission(securityOrigin, feature, granted) {
        grants = grants.concat([[String(securityOrigin), feature, granted]])
    }

    Component { id: infoComponent; WebEngineLoadingInfo { } }
    Component { id: requestComponent; WebEngineNavigationRequest { } }

    function _load() {
        loadProgress = 10
        loadingChanged(infoComponent.createObject(view, { "url": url, "status": WebEngineLoadingInfo.LoadStartedStatus }))
        finish.start()
    }
    Timer {
        id: finish
        interval: 1
        onTriggered: {
            view.title = "Title of " + view.url
            view.loadProgress = 100
            view.loadingChanged(infoComponent.createObject(view, { "url": view.url, "status": WebEngineLoadingInfo.LoadSucceededStatus }))
        }
    }
    onUrlChanged: {
        if (!_navigating) {
            history = history.slice(0, index + 1).concat([String(url)])
            index = history.length - 1
        }
        _load()
    }
    function goBack() { if (canGoBack) { _navigating = true; index--; url = history[index]; _navigating = false } }
    function goForward() { if (canGoForward) { _navigating = true; index++; url = history[index]; _navigating = false } }
    function reload() { _load() }
    function stop() {
        finish.stop()
        loadingChanged(infoComponent.createObject(view, { "url": url, "status": WebEngineLoadingInfo.LoadStoppedStatus }))
    }
    function loadHtml(html, baseUrl) { lastHtml = html; url = baseUrl && String(baseUrl) !== "" ? baseUrl : "data:text/html,keel" }
    function triggerWebAction(action) { actions.push(action) }
    // runJavaScript(script[, worldId][, callback]): main-world scripts are
    // evaluated; scripts for another world (Keel's bridge) are only logged.
    function runJavaScript(script, worldOrCallback, callback) {
        if (typeof worldOrCallback === "number" && worldOrCallback !== 0) {
            FakeLog.worldScripts.push(script)
            return
        }
        if (typeof worldOrCallback === "function")
            callback = worldOrCallback
        FakeLog.scripts.push(script)
        var result = (new Function("return " + script))()
        if (callback)
            callback(result)
    }
    // Test hook: the page navigates by itself.
    function fakeNavigation(target, type) {
        navigationRequested(requestComponent.createObject(view, { "url": target, "navigationType": type }))
    }

    Component.onCompleted: FakeLog.views.push(this)
}
