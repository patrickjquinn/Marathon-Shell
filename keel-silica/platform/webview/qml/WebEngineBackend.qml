// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Keel internal: the Qt WebEngine backend of Sailfish.WebView's WebView.
// Loaded at run time (not compiled ahead), so a system without Qt
// WebEngine's QML module falls back to ExternalBackend.qml. Uses only API
// present in Qt 6.4 and 6.8 (checked with qmllint against Qt 6.4's
// QtWebEngine type information).
//
// The WebEngineView is created once the WebView's privateMode is known:
// private views get an off-the-record profile of their own, the others share
// one persistent profile ("keel-webview", under the app's data directory)
// that the WebEngine singleton keeps.
//
// pixelRatio becomes the view's zoomFactor. cookieBehavior, doNotTrack and
// colorScheme have no Qt WebEngine QML property: Keel.WebEngine's
// ProfilePolicy (built where Qt WebEngine's C++ API is) applies them to each
// profile. It is created by name so that the backend still loads without it;
// those three settings then have no effect.
//
// Dialogs: sailfish-components-webview's PopupOpener and PickerOpener (MPL,
// Sailfish.WebView.Popups and .Pickers) show the page's JavaScript dialogs,
// HTTP authentication, context menu (links and images), permission requests
// (geolocation, camera and microphone) and file, colour pickers, as in
// Sailfish's WebView, and use the app's popupProvider. They speak Gecko's
// message manager; `messages` below plays that part for Qt WebEngine: each
// request becomes the Gecko message the openers handle, and their answer
// (sendAsyncMessage) settles the request. Remembered permissions
// ("don't ask again") are kept by Sailfish.WebEngine's WebEngine.
//
// Frame scripts and page events: a script in Qt WebEngine's isolated
// application world (the page's DOM, not its JavaScript) plays Gecko's
// content message manager. It reports to the view with console messages
// starting with "\u0001keel:" and a secret of the view (frame scripts'
// sendAsyncMessage, the
// selection, copying, input focus) and receives the view's
// sendAsyncMessage through runJavaScript in the same world. Frame scripts
// run in that world with Gecko's globals for them: sendAsyncMessage,
// sendSyncMessage (no answer), addMessageListener, removeMessageListener,
// addEventListener, removeEventListener, content (the window).
import QtQuick 2.6
import QtWebEngine 1.10
import Sailfish.Silica 1.0
import Sailfish.WebView.Popups 1.0 as Popups
import Sailfish.WebView.Pickers 1.0 as Pickers
// Qualified: Qt WebEngine has a WebEngine singleton of its own.
import Sailfish.WebEngine 1.0 as Sailfish

Item {
    id: backend

    property var webView
    property url url
    property bool loaded
    property WebEngineView view
    readonly property string title: view ? view.title : ""
    // From loadingChanged's statuses (the signal is also the notifier of
    // WebEngineView.loading).
    property bool loading
    readonly property int loadProgress: view ? view.loadProgress : 0
    readonly property bool canGoBack: view ? view.canGoBack : false
    readonly property bool canGoForward: view ? view.canGoForward : false
    readonly property string engineName: "qtwebengine"

    signal keelLinkClicked(string url)
    signal keelLoadRedirect()
    signal keelMessage(string name, var data)
    signal keelImeNotification(int state, bool open, int cause, int focusChange, string type)
    signal keelFirstPaint()
    signal keelWindowCloseRequested()
    // For Silica's SilicaWebView (QtWebKit's WebView API): each load's
    // status as a QtWebKit load request, each navigation as a QtWebKit
    // navigation request (action 1, IgnoreRequest, refuses it), hovered
    // links.
    signal keelLoadingChanged(var loadRequest)
    signal keelNavigationRequested(var request)
    signal keelLinkHovered(url hoveredUrl)
    readonly property url icon: view ? view.icon : ""

    property bool crashed
    property bool textSelectionActive
    property bool painted
    readonly property bool moving: movingTimer.running
    readonly property size contentsSize: view ? view.contentsSize : Qt.size(0, 0)
    readonly property point scrollPosition: view ? view.scrollPosition : Qt.point(0, 0)
    readonly property real zoom: view ? view.zoomFactor : 1.0
    // Frame scripts loaded with loadFrameScript(), as source code.
    property var _frameScripts: []
    // Downloads asked for from the context menu: URL -> target file URL.
    property var _downloads: ({})
    property real _lastScrollY
    property real _chromeTravel
    property var _lastContextMenu: null

    // Gecko's message manager for the popup and picker openers.
    readonly property QtObject messages: QtObject {
        id: messages

        readonly property int uniqueId: backend._keelViewId
        property var listeners: ({})
        // Pending Qt WebEngine requests by the id the Gecko message carries.
        property var pending: ({})
        property int nextId: 1

        function addMessageListener(topic) { listeners[topic] = true }
        function removeMessageListener(topic) { delete listeners[topic] }
        function cancelPendingNavigation() { if (backend.view) backend.view.stop() }
        function sendAsyncMessage(topic, data) { backend._settle(topic, data) }
    }
    // Gecko's per-view id (contentItem.uniqueId), unique within the app.
    readonly property int _keelViewId: Math.floor(Math.random() * 2147483647)
    property var _pageStack: _findPageStack()

    function _findPageStack() {
        for (var p = webView; p; p = p.parent) {
            if (p.pageStack !== undefined && p.pageStack !== null)
                return p.pageStack
        }
        return (typeof __silica_applicationwindow_instance !== "undefined" && __silica_applicationwindow_instance)
                ? __silica_applicationwindow_instance.pageStack : null
    }

    function _track(request) {
        var id = messages.nextId++
        messages.pending[id] = request
        return id
    }
    function _take(id) {
        var request = messages.pending[id]
        delete messages.pending[id]
        return request
    }

    // Requests from Qt WebEngine, as Gecko's messages.
    function _javaScriptDialog(request) {
        var id = _track(request)
        request.accepted = true
        var data = { "winId": id, "promptId": id, "text": request.message, "title": "" }
        var topic = "embed:alert"
        if (request.type === JavaScriptDialogRequest.DialogTypeConfirm) {
            topic = "embed:confirm"
        } else if (request.type === JavaScriptDialogRequest.DialogTypeBeforeUnload) {
            topic = "embed:confirm"
            data.inPermitUnload = true
        } else if (request.type === JavaScriptDialogRequest.DialogTypePrompt) {
            topic = "embed:prompt"
            data.defaultValue = request.defaultText
            data.inputs = [{ "value": request.defaultText }]
        }
        if (!popupOpener.message(topic, data)) {
            _take(id)
            request.dialogReject()
        }
    }

    function _authentication(request) {
        var id = _track(request)
        request.accepted = true
        var host = String(request.url).replace(/^[a-z]+:\/\//, "").replace(/[\/:].*$/, "")
        var data = {
            "winId": id,
            // Shown as given (StringUtils.geckoKeyToString finds no
            // translation for it).
            "text": "%1 asks for a user name and password".arg(request.type === AuthenticationDialogRequest.AuthenticationTypeProxy
                                                                ? request.proxyHost : host),
            "hostname": host,
            "realm": request.realm,
            "inputs": [{ "hint": "username", "value": "" }, { "hint": "password", "value": "" }]
        }
        if (!popupOpener.message("embed:auth", data)) {
            _take(id)
            request.dialogReject()
        }
    }

    function _origin(url) {
        return String(url).replace(/^[a-z]+:\/\//, "").replace(/[\/:].*$/, "")
    }

    function _permission(securityOrigin, feature) {
        var host = _origin(securityOrigin)
        var type = feature === WebEngineView.Geolocation ? "geolocation"
                 : feature === WebEngineView.MediaVideoCapture ? "camera"
                 : feature === WebEngineView.MediaAudioCapture ? "microphone"
                 : feature === WebEngineView.MediaAudioVideoCapture ? "camera" : ""
        if (type === "") {
            view.grantFeaturePermission(securityOrigin, feature, false)
            return
        }
        // Remembered ("don't ask again"): 1 allow, 2 deny.
        var remembered = Sailfish.WebEngine._keelPermission(host, type)
        if (remembered === 1 || remembered === 2) {
            view.grantFeaturePermission(securityOrigin, feature, remembered === 1)
            return
        }
        var id = _track({ "origin": securityOrigin, "feature": feature, "host": host, "type": type })
        var handled
        if (type === "geolocation") {
            handled = popupOpener.message("embed:permissions", { "title": "geolocation", "host": host, "id": id,
                                                                 "privateBrowsing": !!(webView && webView.privateMode) })
        } else {
            var devices = {}
            if (feature !== WebEngineView.MediaAudioCapture)
                devices.camera = [{ "id": "default", "name": "" }]
            if (feature !== WebEngineView.MediaVideoCapture)
                devices.microphone = [{ "id": "default", "name": "" }]
            handled = popupOpener.message("embed:webrtcrequest", { "origin": String(securityOrigin), "devices": devices,
                                                                   "id": id })
        }
        if (!handled) {
            _take(id)
            view.grantFeaturePermission(securityOrigin, feature, false)
        }
    }

    function _contextMenu(request) {
        var types = []
        if (String(request.linkUrl) !== "")
            types.push("link")
        if (request.mediaType === ContextMenuRequest.MediaTypeImage)
            types.push("image")
        // Qt WebEngine's own menu needs Qt Quick Controls: the Sailfish menu
        // is shown for links and images, nothing otherwise.
        request.accepted = true
        if (types.length === 0)
            return
        var link = String(request.linkUrl)
        var scheme = link.indexOf(":") > 0 ? link.substring(0, link.indexOf(":")) : ""
        popupOpener.message("Content:ContextMenu", {
            "types": types,
            "linkURL": link,
            "mediaURL": request.mediaType === ContextMenuRequest.MediaTypeImage ? String(request.mediaUrl) : "",
            "linkTitle": request.linkText || "",
            "linkProtocol": scheme === "https" ? "http" : scheme,
            "contentType": "",
            "xPos": request.position.x,
            "yPos": request.position.y
        })
    }

    function _fileDialog(request) {
        var id = _track(request)
        request.accepted = true
        var mimes = request.acceptedMimeTypes
        var data = {
            "winId": id,
            // nsIFilePicker modes: 0 open, 3 open multiple.
            "mode": request.mode === FileDialogRequest.FileModeOpenMultiple ? 3 : 0,
            "mimeType": mimes.length === 1 ? String(mimes[0]) : ""
        }
        if (request.mode === FileDialogRequest.FileModeSave || request.mode === FileDialogRequest.FileModeUploadFolder
                || !pickerOpener.message("embed:filepicker", data)) {
            _take(id)
            request.dialogReject()
        }
    }

    function _colorDialog(request) {
        var id = _track(request)
        request.accepted = true
        if (!pickerOpener.message("embed:colorpicker", { "winId": id, "initialColor": String(request.color),
                                                          "defaultColors": [] })) {
            _take(id)
            request.dialogReject()
        }
    }

    // Answers from the openers (Gecko's response messages).
    function _settle(topic, data) {
        var key = data.winId !== undefined ? data.winId : data.id
        var request = _take(key)
        if (!request)
            return
        switch (topic) {
        case "alertresponse":
            request.dialogAccept()
            break
        case "confirmresponse":
            if (data.accepted) request.dialogAccept(); else request.dialogReject()
            break
        case "promptresponse":
            if (data.accepted) request.dialogAccept(data.promptvalue === undefined ? "" : String(data.promptvalue))
            else request.dialogReject()
            break
        case "authresponse":
            if (data.accepted) request.dialogAccept(data.username || "", data.password || "")
            else request.dialogReject()
            break
        case "embedui:permissions":
        case "embedui:webrtcresponse":
            if (view)
                view.grantFeaturePermission(request.origin, request.feature, !!data.allow)
            if (data.checkedDontAsk)
                Sailfish.WebEngine._keelRememberPermission(request.host, request.type, !!data.allow,
                                                           !!(webView && webView.privateMode))
            break
        case "filepickerresponse":
            if (data.accepted && data.items && data.items.length > 0) {
                var files = []
                for (var i = 0; i < data.items.length; ++i)
                    files.push(String(data.items[i]).indexOf("/") === 0 ? "file://" + data.items[i] : String(data.items[i]))
                request.dialogAccept(files)
            } else {
                request.dialogReject()
            }
            break
        case "embedui:colorpickerresponse":
            if (data.accepted) request.dialogAccept(data.color); else request.dialogReject()
            break
        default:
            break
        }
    }

    Pickers.PickerOpener {
        id: pickerOpener
        pageStack: backend._pageStack
        contentItem: messages
    }

    Popups.PopupOpener {
        id: popupOpener
        pageStack: backend._pageStack
        parentItem: backend.webView ? (backend.webView.webViewPage || backend.webView) : backend
        contentItem: messages
        downloadsEnabled: !!(backend.webView && backend.webView.downloadsEnabled)
        popupProvider: backend.webView && backend.webView.popupProvider ? backend.webView.popupProvider
                                                                          : defaultPopupProvider
    }
    Popups.PopupProvider { id: defaultPopupProvider }
    // Keel: for tests.
    readonly property QtObject popupOpenerForTests: popupOpener

    // Qt WebEngine's script worlds and injection points (numbers: the
    // WebEngineScript enums are not reachable from every Qt 6 version).
    readonly property int _applicationWorld: 1
    readonly property int _mainWorld: 0
    readonly property int _documentCreation: 2
    readonly property int _documentReady: 1
    // With a secret of this view, so that the page's own console messages
    // (main world) cannot pass for the bridge's.
    readonly property string _bridgePrefix: "\u0001keel:" + Math.floor(Math.random() * 4294967296).toString(16)
                                            + Math.floor(Math.random() * 4294967296).toString(16) + ":"

    // The content side of the message manager (application world).
    readonly property string _bridgeScript: "(function() {\n"
        + "if (window.__keelBridge) return;\n"
        + "var listeners = {};\n"
        + "var prefix = " + JSON.stringify(_bridgePrefix) + ";\n"
        + "function post(name, data) { console.log(prefix + JSON.stringify({ n: String(name), d: data === undefined ? null : data })); }\n"
        + "function add(name, fn) { (listeners[name] = listeners[name] || []).push(typeof fn === 'function' ? fn : function(m) { fn.receiveMessage(m); }); }\n"
        + "function remove(name, fn) { var l = listeners[name] || []; for (var i = l.length - 1; i >= 0; --i) if (l[i] === fn) l.splice(i, 1); }\n"
        + "window.__keelBridge = {\n"
        + "  receive: function(name, data) { (listeners[name] || []).slice().forEach(function(f) { try { f({ name: name, data: data, json: data, target: null }); } catch (e) { console.error(e); } }); },\n"
        + "  scope: { sendAsyncMessage: post, sendSyncMessage: function(n, d) { post(n, d); return []; }, addMessageListener: add, removeMessageListener: remove,\n"
        + "           addEventListener: function(t, f, c) { window.addEventListener(t, f, c); }, removeEventListener: function(t, f, c) { window.removeEventListener(t, f, c); }, content: window }\n"
        + "};\n"
        + "var selecting = false;\n"
        + "document.addEventListener('selectionchange', function() { var s = window.getSelection(); var now = !!s && !s.isCollapsed; if (now !== selecting) { selecting = now; post('keel:selection', now); } });\n"
        + "document.addEventListener('copy', function() { post('keel:copy', null); }, true);\n"
        + "document.addEventListener('cut', function() { post('keel:copy', null); }, true);\n"
        + "function editable(e) { if (!e) return ''; if (e.isContentEditable) return 'contenteditable'; var t = (e.tagName || '').toLowerCase(); if (t === 'textarea') return 'textarea'; if (t === 'input') return (e.type || 'text').toLowerCase(); return ''; }\n"
        + "document.addEventListener('focusin', function(ev) { var t = editable(ev.target); if (t) post('keel:ime', { open: true, type: t }); }, true);\n"
        + "document.addEventListener('focusout', function(ev) { var t = editable(ev.target); if (t) post('keel:ime', { open: false, type: t }); }, true);\n"
        + "})();\n"

    function _frameScriptSource(code) {
        return "(function(s) { (function(sendAsyncMessage, sendSyncMessage, addMessageListener, removeMessageListener, "
                + "addEventListener, removeEventListener, content) {\n" + code + "\n})(s.sendAsyncMessage, s.sendSyncMessage, "
                + "s.addMessageListener, s.removeMessageListener, s.addEventListener, s.removeEventListener, s.content); })"
                + "(window.__keelBridge.scope);\n"
    }

    // The user scripts of the view: the bridge, the frame scripts and
    // WebEngine's user style sheets.
    function _updateUserScripts() {
        if (!view || !view.userScripts)
            return
        var scripts = [{ "name": "keel-bridge", "sourceCode": _bridgeScript,
                         "injectionPoint": _documentCreation, "worldId": _applicationWorld, "runsOnSubFrames": false }]
        for (var i = 0; i < _frameScripts.length; ++i) {
            scripts.push({ "name": "keel-frame-script-" + i, "sourceCode": _frameScriptSource(_frameScripts[i]),
                           "injectionPoint": _documentCreation, "worldId": _applicationWorld, "runsOnSubFrames": false })
        }
        if (_qtNavigator) {
            scripts.push({ "name": "keel-qt-navigator", "injectionPoint": _documentCreation, "worldId": _mainWorld,
                           "runsOnSubFrames": false,
                           "sourceCode": "navigator.qt = { onmessage: null, postMessage: function(m) { console.log("
                                         + JSON.stringify(_qtPrefix) + " + JSON.stringify(m)); } };\n" })
        }
        var sheets = Sailfish.WebEngine._keelUserStyleSheets
        if (sheets.length > 0)
            scripts.push({ "name": "keel-user-style-sheets", "sourceCode": _styleSheetSource(sheets),
                           "injectionPoint": _documentReady, "worldId": _applicationWorld, "runsOnSubFrames": true })
        view.userScripts.collection = scripts
    }

    function _styleSheetSource(sheets) {
        return "(function(sheets) { var old = document.getElementById('keel-user-style-sheets'); if (old) old.remove();\n"
                + "if (!sheets.length) return; var style = document.createElement('style'); style.id = 'keel-user-style-sheets';\n"
                + "style.textContent = sheets.join('\\n'); (document.head || document.documentElement).appendChild(style); })("
                + JSON.stringify(sheets) + ");\n"
    }

    // QtWebKit's navigator.qt in the page's own world, for Silica's
    // SilicaWebView: postMessage() reaches the view as "keel:qt-message"
    // (page data, like any message from the page).
    property bool _qtNavigator
    readonly property string _qtPrefix: "\u0001keel-qt:"
    function enableQtNavigator() {
        _qtNavigator = true
        _updateUserScripts()
    }

    function loadFrameScript(name) {
        var code = Sailfish.WebEngine._keelReadText(name)
        if (code.length === 0) {
            console.warn("Sailfish.WebView: cannot read frame script", name)
            return
        }
        _frameScripts = _frameScripts.concat([code])
        _updateUserScripts()
        // Also into the page shown now.
        if (view && loaded)
            view.runJavaScript(_bridgeScript + _frameScriptSource(code), _applicationWorld)
    }

    function sendToContent(name, data) {
        if (view)
            view.runJavaScript("window.__keelBridge && window.__keelBridge.receive(" + JSON.stringify(String(name)) + ", "
                               + JSON.stringify(data === undefined ? null : data) + ")", _applicationWorld)
    }

    // A console message from the bridge (others are the page's).
    function _consoleMessage(message) {
        if (_qtNavigator && message.indexOf(_qtPrefix) === 0) {
            try {
                keelMessage("keel:qt-message", JSON.parse(message.substring(_qtPrefix.length)))
            } catch (e) {
            }
            return true
        }
        if (message.indexOf(_bridgePrefix) !== 0)
            return false
        var m
        try {
            m = JSON.parse(message.substring(_bridgePrefix.length))
        } catch (e) {
            return true
        }
        switch (m.n) {
        case "keel:selection":
            textSelectionActive = !!m.d
            break
        case "keel:copy":
            Sailfish.WebEngine._keelClipboardSet(!!(webView && webView.privateMode))
            break
        case "keel:ime":
            // Gecko's IME notification: state 1 enabled / 0 disabled, open,
            // cause 0 (unknown), focusChange 1 (gained/lost), input type.
            keelImeNotification(m.d.open ? 1 : 0, !!m.d.open, 0, 1, String(m.d.type || ""))
            break
        default:
            keelMessage(m.n, m.d)
            break
        }
        return true
    }

    function _scrolled() {
        movingTimer.restart()
        if (!view || !webView)
            return
        var y = view.scrollPosition.y
        var delta = y - _lastScrollY
        _lastScrollY = y
        if (!webView.chromeGestureEnabled)
            return
        // The chrome hides after the page has scrolled down the threshold,
        // and shows again after scrolling up as far, or at the top.
        _chromeTravel = (delta > 0) === (_chromeTravel > 0) ? _chromeTravel + delta : delta
        if (y <= 0.5)
            webView.chrome = true
        else if (_chromeTravel > webView.chromeGestureThreshold)
            webView.chrome = false
        else if (_chromeTravel < -webView.chromeGestureThreshold)
            webView.chrome = true
    }

    // Downloads: from the context menu (embedui:download, to a chosen file)
    // or started by the page (to WebEngineSettings' download directory).
    function _requestDownload(download) {
        if (!view || download.viewId !== messages.uniqueId)
            return
        var from = String(download.from)
        _downloads[from] = String(download.to)
        var menu = _lastContextMenu
        if (menu && from === menu.link)
            view.triggerWebAction(WebEngineView.DownloadLinkToDisk)
        else if (menu && from === menu.media)
            view.triggerWebAction(WebEngineView.DownloadImageToDisk)
        else
            view.runJavaScript("(function(u) { var a = document.createElement('a'); a.href = u; a.download = ''; "
                               + "document.body.appendChild(a); a.click(); a.remove(); })(" + JSON.stringify(from) + ")",
                               _applicationWorld)
    }

    function _download(download) {
        if (!view || (download.view !== undefined && download.view !== null && download.view !== view))
            return
        var from = String(download.url)
        var target = _downloads[from]
        if (target === undefined && !(webView && webView.downloadsEnabled)) {
            download.cancel()
            return
        }
        delete _downloads[from]
        if (target !== undefined) {
            var path = target.replace(/^file:\/\//, "")
            var slash = path.lastIndexOf("/")
            download.downloadDirectory = path.substring(0, slash)
            download.downloadFileName = path.substring(slash + 1)
        } else if (Sailfish.WebEngineSettings.useDownloadDir && Sailfish.WebEngineSettings.downloadDir.length > 0) {
            download.downloadDirectory = Sailfish.WebEngineSettings.downloadDir
        }
        var id = download.id
        var to = "file://" + download.downloadDirectory + "/" + download.downloadFileName
        Sailfish.WebEngine.notifyObservers("embed:download", { "msg": "dl-start", "id": id, "from": from, "to": to })
        download.isFinishedChanged.connect(function() {
            if (download.isFinished)
                Sailfish.WebEngine.notifyObservers("embed:download",
                                                   { "msg": download.state === 2 ? "dl-done" : "dl-fail",
                                                     "id": id, "from": from, "to": to })
        })
        download.accept()
    }

    function loadHtml(html, baseUrl) { if (view) view.loadHtml(html, baseUrl) }
    function reload() { if (view) view.reload() }
    function stop() { if (view) view.stop() }
    function goBack() { if (view) view.goBack() }
    function goForward() { if (view) view.goForward() }
    function clearSelection() {
        if (!view)
            return
        view.triggerWebAction(WebEngineView.Unselect)
        // Unselect leaves a selection made by the page's script.
        view.runJavaScript("window.getSelection().removeAllRanges()", _applicationWorld)
    }

    function runScript(script, callback, errorCallback) {
        if (!view) {
            if (errorCallback)
                errorCallback("WebView is not ready")
            return
        }
        // Sailfish's runJavaScript() runs the script as a function body (it
        // must `return` its value); exceptions go to errorCallback.
        var wrapped = "(function() { try { return { v: (function() {\n" + script
                + "\n})() } } catch (e) { return { e: String(e) } } })()"
        view.runJavaScript(wrapped, function(result) {
            if (result && result.e !== undefined) {
                if (errorCallback)
                    errorCallback(result.e)
            } else if (callback) {
                callback(result ? result.v : undefined)
            }
        })
    }

    onUrlChanged: {
        if (view && String(view.url) !== String(url))
            view.url = url
    }

    Component {
        id: persistentProfile
        WebEngineProfile {
            storageName: "keel-webview"
        }
    }

    Component {
        id: privateProfile
        // No storageName: off the record.
        WebEngineProfile { }
    }

    Component {
        id: viewComponent

        WebEngineView {
            width: backend.webView ? backend.webView.viewportWidth : backend.width
            height: backend.webView ? backend.webView.viewportHeight : backend.height
            backgroundColor: backend.webView ? backend.webView.backgroundColor : "white"
            settings.javascriptEnabled: Sailfish.WebEngineSettings.javascriptEnabled
                                        && (!backend.webView || backend.webView.javascriptEnabled)
            settings.autoLoadImages: Sailfish.WebEngineSettings.autoLoadImages
            settings.javascriptCanOpenWindows: Sailfish.WebEngineSettings.popupEnabled
            settings.localContentCanAccessRemoteUrls: Sailfish.WebEngineSettings._keelLocalContentCanAccessRemoteUrls
            settings.localContentCanAccessFileUrls: Sailfish.WebEngineSettings._keelLocalContentCanAccessFileUrls
            // pixelRatio is device pixels per CSS pixel; Qt WebEngine already
            // scales by the screen's devicePixelRatio (1 in Keel apps).
            zoomFactor: Math.max(0.25, Math.min(5.0, Sailfish.WebEngineSettings.pixelRatio
                                                     / Math.max(1.0, Screen.devicePixelRatio)))
        }
    }

    Connections {
        target: backend.view
        function onUrlChanged() {
            if (String(backend.url) !== String(backend.view.url))
                backend.url = backend.view.url
        }
        function onLoadingChanged(loadingInfo) {
            backend.loading = loadingInfo.status === WebEngineLoadingInfo.LoadStartedStatus
            // QtWebKit's error domains: 0 none, 1 internal, 2 network, 3 HTTP.
            var domain = loadingInfo.status !== WebEngineLoadingInfo.LoadFailedStatus ? 0
                       : loadingInfo.errorDomain === WebEngineLoadingInfo.HttpStatusCodeDomain ? 3
                       : loadingInfo.errorDomain === WebEngineLoadingInfo.InternalErrorDomain ? 1 : 2
            backend.keelLoadingChanged({ "url": loadingInfo.url, "status": loadingInfo.status,
                                         "errorString": loadingInfo.errorString || "",
                                         "errorCode": loadingInfo.errorCode || 0, "errorDomain": domain })
            var security = backend.webView ? backend.webView.security : null
            if (loadingInfo.status === WebEngineLoadingInfo.LoadStartedStatus) {
                backend.loaded = false
                backend.crashed = false
                backend.textSelectionActive = false
                if (security)
                    security._keelReset()
            } else if (loadingInfo.status === WebEngineLoadingInfo.LoadSucceededStatus) {
                backend.loaded = true
                if (security)
                    security._keelLoaded(loadingInfo.url)
                if (!backend.painted) {
                    backend.painted = true
                    backend.keelFirstPaint()
                }
            }
        }
        function onCertificateError(error) {
            var security = backend.webView ? backend.webView.security : null
            if (security)
                security._keelCertificateError(error.url, error.type)
        }
        function onRenderProcessTerminated(terminationStatus, exitCode) {
            // 0: normal termination (the view is going away).
            if (terminationStatus !== 0) {
                backend.crashed = true
                backend.textSelectionActive = false
            }
        }
        function onJavaScriptConsoleMessage(level, message, lineNumber, sourceID) {
            backend._consoleMessage(message)
        }
        function onScrollPositionChanged() { backend._scrolled() }
        function onWindowCloseRequested() { backend.keelWindowCloseRequested() }
        function onJavaScriptDialogRequested(request) { backend._javaScriptDialog(request) }
        function onAuthenticationDialogRequested(request) { backend._authentication(request) }
        function onFeaturePermissionRequested(securityOrigin, feature) { backend._permission(securityOrigin, feature) }
        function onContextMenuRequested(request) {
            backend._lastContextMenu = { "link": String(request.linkUrl), "media": String(request.mediaUrl) }
            backend._contextMenu(request)
        }
        function onFileDialogRequested(request) { backend._fileDialog(request) }
        function onColorDialogRequested(request) { backend._colorDialog(request) }
        // target="_blank" and window.open(): Sailfish's WebView opens them in
        // the same view.
        function onNewWindowRequested(request) {
            if (backend.view && String(request.requestedUrl) !== "")
                backend.view.url = request.requestedUrl
        }
        function onLinkHovered(hoveredUrl) { backend.keelLinkHovered(hoveredUrl) }
        function onNavigationRequested(request) {
            // QtWebKit's navigation types: 0 link, 1 form, 2 back/forward,
            // 3 reload, 4 form resubmitted, 5 other.
            var type = request.navigationType
            var webKitType = type === WebEngineNavigationRequest.LinkClickedNavigation ? 0
                           : type === WebEngineNavigationRequest.FormSubmittedNavigation ? 1
                           : type === WebEngineNavigationRequest.BackForwardNavigation ? 2
                           : type === WebEngineNavigationRequest.ReloadNavigation ? 3 : 5
            var wrapped = { "url": request.url, "navigationType": webKitType, "action": 0 }
            backend.keelNavigationRequested(wrapped)
            if (wrapped.action === 1) {
                request.reject()
                return
            }
            if (request.navigationType === WebEngineNavigationRequest.LinkClickedNavigation)
                backend.keelLinkClicked(String(request.url))
            else if (request.navigationType === WebEngineNavigationRequest.RedirectNavigation)
                backend.keelLoadRedirect()
        }
    }

    Timer {
        id: movingTimer
        interval: 250
    }

    Connections {
        target: Sailfish.WebEngine
        function onKeelUserStyleSheetsChanged() {
            backend._updateUserScripts()
            if (backend.view && backend.loaded)
                backend.view.runJavaScript(backend._styleSheetSource(Sailfish.WebEngine._keelUserStyleSheets),
                                           backend._applicationWorld)
        }
        function on_KeelDownloadRequested(download) { backend._requestDownload(download) }
    }

    Connections {
        target: backend.view ? backend.view.profile : null
        ignoreUnknownSignals: true
        function onDownloadRequested(download) { backend._download(download) }
    }

    // The user agent (WebView.httpUserAgent, else the Gecko preference
    // general.useragent.override, else Qt WebEngine's own with "Mobile" as
    // Sailfish's mobile user agent has it, unless the view is in desktopMode)
    // and the download directory go to the profile; with the shared profile
    // they apply to all of the app's views.
    property string _engineUserAgent
    function _mobileUserAgent(agent) {
        if (agent.indexOf(" Mobile") >= 0)
            return agent
        var at = agent.indexOf(" Safari/")
        return at >= 0 ? agent.substring(0, at) + " Mobile" + agent.substring(at) : agent + " Mobile"
    }
    Binding {
        target: backend.view ? backend.view.profile : null
        property: "httpUserAgent"
        value: backend.webView && backend.webView.httpUserAgent.length > 0
               ? backend.webView.httpUserAgent
               : Sailfish.WebEngineSettings._keelUserAgentOverride.length > 0
                 ? Sailfish.WebEngineSettings._keelUserAgentOverride
                 : backend.webView && backend.webView.desktopMode ? backend._engineUserAgent
                                                                  : backend._mobileUserAgent(backend._engineUserAgent)
        when: backend.view !== null && backend._engineUserAgent.length > 0
    }
    Binding {
        target: backend.view ? backend.view.profile : null
        property: "downloadPath"
        value: Sailfish.WebEngineSettings.downloadDir
        when: backend.view !== null && Sailfish.WebEngineSettings.useDownloadDir && Sailfish.WebEngineSettings.downloadDir.length > 0
    }

    // A ProfilePolicy (owned by owner) applying the settings to the profile
    // made by makeProfile, or that profile alone without Keel.WebEngine.
    function createProfile(makeProfile, owner) {
        var policy = null
        try {
            policy = Qt.createQmlObject("import Keel.WebEngine 1.0; ProfilePolicy { }", owner,
                                        "WebEngineBackend.policy")
        } catch (e) {
            policy = null
        }
        if (policy) {
            // Chromium reads its preferred colour scheme once, when Qt
            // WebEngine starts (at its first profile): the value then is the
            // one in effect.
            var scheme = Sailfish.WebEngineSettings.colorScheme
            policy.preferDark(scheme === Sailfish.WebEngineSettings.PrefersDarkMode
                              || (scheme === Sailfish.WebEngineSettings.FollowsAmbience
                                  && Theme.colorScheme === Theme.LightOnDark))
            policy.cookieBehavior = Qt.binding(function() { return Sailfish.WebEngineSettings.cookieBehavior })
            policy.doNotTrack = Qt.binding(function() { return Sailfish.WebEngineSettings.doNotTrack })
        }
        var profile = makeProfile()
        if (policy)
            policy.profile = profile
        return profile
    }

    Component.onCompleted: {
        var profile
        if (webView && webView.privateMode) {
            profile = createProfile(function() { return privateProfile.createObject(backend) }, backend)
        } else {
            if (!Sailfish.WebEngine._keelProfile) {
                // The shared profile and its policy last as long as the app.
                Sailfish.WebEngine._keelProfile = createProfile(function() { return persistentProfile.createObject(null) },
                                                                Sailfish.WebEngine)
            }
            profile = Sailfish.WebEngine._keelProfile
        }
        // Qt WebEngine's own user agent, before Keel sets one.
        if (profile !== Sailfish.WebEngine._keelProfile)
            _engineUserAgent = String(profile.httpUserAgent).replace(" Mobile", "")
        else if (Sailfish.WebEngine._keelEngineUserAgent.length > 0)
            _engineUserAgent = Sailfish.WebEngine._keelEngineUserAgent
        else
            _engineUserAgent = Sailfish.WebEngine._keelEngineUserAgent = String(profile.httpUserAgent).replace(" Mobile", "")
        view = viewComponent.createObject(backend, { "profile": profile })
        _updateUserScripts()
        if (String(url) !== "")
            view.url = url
    }
}
