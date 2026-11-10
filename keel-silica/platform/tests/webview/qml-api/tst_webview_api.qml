// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// The rest of Sailfish.WebView's WebView API and Sailfish.WebEngine's
// WebEngine API over the Qt WebEngine test double: crashed,
// javascriptEnabled, security, the scroll geometry and the chrome gesture,
// desktopMode, the frame script message manager (through the isolated
// world bridge), selection, copying and input focus reported by the
// bridge, downloads, user style sheets, isAccelerated, lastWindowDestroyed,
// stopEmbedding and notifyFirstUIInitialized; WebViewFlickable's header;
// Silica's SilicaWebView.
import QtQuick 2.6
import QtTest 1.0
import Sailfish.Silica 1.0
import Sailfish.WebView 1.0
import Sailfish.WebEngine 1.0
import QtWebEngine 1.10 as Fake

Item {
    id: root
    width: 540
    height: 960

    Component {
        id: plainView
        WebView { width: 540; height: 960; url: "https://example.org/a" }
    }
    Component {
        id: httpView
        WebView { width: 540; height: 960; url: "http://example.org/plain" }
    }

    Component {
        id: flickableWithHeader
        WebViewFlickable {
            width: 540; height: 960
            header: Component { Item { height: 100 } }
        }
    }

    Component { id: navRequest; Fake.WebEngineNavigationRequest { } }
    Component {
        id: silicaWebView
        SilicaWebView {
            width: 540; height: 960
            url: "https://example.org/silica"
            header: Component { Item { height: 50 } }
            PullDownMenu { MenuItem { text: "Reload" } }
        }
    }

    SignalSpy { id: observeSpy; target: WebEngine; signalName: "recvObserve" }
    SignalSpy { id: lastWindowSpy; target: WebEngine; signalName: "lastWindowDestroyed" }
    SignalSpy { id: contextSpy; target: WebEngine; signalName: "contextDestroyed" }

    TestCase {
        name: "WebViewApi"
        when: windowShown

        function view(component) {
            var v = createTemporaryObject(component || plainView, root)
            tryVerify(function() { return v._backend !== null && v._backend.view !== null })
            tryCompare(v, "loaded", true)
            return v
        }

        // Qt WebEngine's download request, as far as the view uses it.
        function fakeDownload(url) {
            return {
                "url": url, "view": null, "id": 7, "downloadDirectory": "/tmp", "downloadFileName": "file.bin",
                "isFinished": false, "state": 0, "result": "",
                "isFinishedChanged": { "connect": function() { } },
                "accept": function() { this.result = "accepted" },
                "cancel": function() { this.result = "cancelled" }
            }
        }

        function bridge(v, name, data) {
            v._backend.view.javaScriptConsoleMessage(0, v._backend._bridgePrefix + JSON.stringify({ n: name, d: data }), 1, "")
        }

        function test_crashed_and_javascript() {
            var v = view()
            verify(!v.crashed)
            v._backend.view.renderProcessTerminated(2, 9) // crashed
            verify(v.crashed)
            v.reload()
            tryCompare(v, "crashed", false)
            verify(v._backend.view.settings.javascriptEnabled)
            v.javascriptEnabled = false
            verify(!v._backend.view.settings.javascriptEnabled)
        }

        function test_security() {
            var v = view(httpView)
            verify(v.security.validState)
            verify(v.security.isInsecure)
            verify(!v.security.isSecure)
            verify(!v.security.allGood)
            v.url = "https://example.org/b"
            tryVerify(function() { return v.security.isSecure })
            v._backend.view.certificateError({ "url": "https://example.org/b", "type": -201 })
            verify(v.security.isBroken)
            verify(v.security.notValidAtThisTime)
            verify(!v.security.domainMismatch)
            compare(v.security.protocolVersion, -1)
        }

        function test_flickable_header() {
            var f = createTemporaryObject(flickableWithHeader, root)
            verify(f.headerItem)
            compare(f.headerItem.height, 100)
            compare(f.webView.y, 100)
            compare(f.webView.height, 860)
        }

        // Silica's SilicaWebView (QtWebKit's WebView API) on WebView.
        function test_silica_web_view() {
            var w = createTemporaryObject(silicaWebView, root)
            tryVerify(function() { return w._view !== null && w._view._backend !== null })
            var loads = []
            var navigations = []
            w.loadingChanged.connect(function() { loads.push(w.loadRequest.status) })
            w.navigationRequested.connect(function(r) {
                navigations.push(r.url)
                if (String(r.url).indexOf("blocked") >= 0)
                    r.action = SilicaWebView.IgnoreRequest
            })
            tryCompare(w, "title", "Title of https://example.org/silica")
            compare(w._headerItem.height, 50)
            compare(w._view.y, 0)
            compare(w._view.parent.y, 50)
            tryCompare(w, "loading", false)
            loads = []
            w.url = "https://example.org/two"
            tryCompare(w, "title", "Title of https://example.org/two")
            tryCompare(w, "loading", false)
            compare(loads, [SilicaWebView.LoadStartedStatus, SilicaWebView.LoadSucceededStatus])
            verify(w.canGoBack)
            w.goBack()
            compare(String(w.url), "https://example.org/silica")
            var engine = w._view._backend.view
            var request = navRequest.createObject(root, { "url": "https://example.org/blocked" })
            engine.navigationRequested(request)
            compare(request.result, "rejected")
            compare(String(navigations[navigations.length - 1]), "https://example.org/blocked")
            // Pulley menu: the flickable takes drags at the page's top only.
            verify(w.interactive)
            engine.contentsSize = Qt.size(w._view.contentRect.width, 5000)
            engine.scrollPosition = Qt.point(0, 100)
            tryVerify(function() { return !w.interactive })
            // experimental: user agent and JavaScript.
            w.experimental.userAgent = "Old/1.0"
            compare(engine.profile.httpUserAgent, "Old/1.0")
            var result
            w.experimental.evaluateJavaScript("1 + 2", function(r) { result = r })
            compare(result, 3)
            // navigator.qt: page messages arrive as messageReceived.
            var scripts = engine.userScripts.collection
            verify(scripts.some(function(s) { return s.name === "keel-qt-navigator" }))
            var got = []
            w.experimental.messageReceived.connect(function(m) { got.push(m.data) })
            engine.javaScriptConsoleMessage(0, "\u0001keel-qt:" + JSON.stringify("hi"), 1, "")
            compare(got, ["hi"])
            request.destroy()
        }

        function test_geometry_and_chrome() {
            var v = view()
            var engine = v._backend.view
            engine.contentsSize = Qt.size(v.contentRect.width, 3000)
            compare(v.contentHeight, 3000)
            compare(v.viewportHeight, 960)
            verify(v.atYBeginning)
            verify(!v.atYEnd)
            verify(v.atXBeginning && v.atXEnd)
            verify(v.chrome)
            engine.scrollPosition = Qt.point(0, 10)
            verify(v.moving)
            verify(v.chrome) // under the threshold
            engine.scrollPosition = Qt.point(0, 10 + v.chromeGestureThreshold + 1)
            verify(!v.chrome)
            compare(v.scrollableOffset.y, 11 + v.chromeGestureThreshold)
            verify(v.verticalScrollDecorator.position > 0)
            compare(v.contentRect.y, v.scrollableOffset.y)
            engine.scrollPosition = Qt.point(0, 3000 - v.contentRect.height)
            verify(v.atYEnd)
            engine.scrollPosition = Qt.point(0, 0)
            verify(v.chrome)
            tryCompare(v, "moving", false)
            v.virtualKeyboardMargin = 300
            compare(engine.height, 660)
            verify(v.painted)
        }

        function test_desktop_mode() {
            WebEngineSettings.setPreference("general.useragent.override", "", WebEngineSettings.StringPref)
            var v = view()
            var profile = v._backend.view.profile
            compare(profile.httpUserAgent, "FakeEngine/1.0 Mobile")
            v.desktopMode = true
            compare(profile.httpUserAgent, "FakeEngine/1.0")
            v.desktopMode = false
            compare(profile.httpUserAgent, "FakeEngine/1.0 Mobile")
        }

        function test_frame_scripts_and_messages() {
            var v = view()
            var received = []
            v.recvAsyncMessage.connect(function(name, data) { received.push([name, data]) })
            var scripts = v._backend.view.userScripts.collection
            compare(scripts.length, 1)
            compare(scripts[0].name, "keel-bridge")
            compare(scripts[0].worldId, 1)
            v.loadFrameScript(Qt.resolvedUrl("framescript.js"))
            scripts = v._backend.view.userScripts.collection
            compare(scripts.length, 2)
            verify(scripts[1].sourceCode.indexOf('addMessageListener("test:ping"') >= 0)
            // ...and into the page shown now, in the bridge's world.
            verify(Fake.FakeLog.worldScripts[Fake.FakeLog.worldScripts.length - 1].indexOf("test:ping") >= 0)
            // Content to app: only names the app listens to.
            bridge(v, "test:pong", { "title": "T" })
            compare(received.length, 0)
            v.addMessageListener("test:pong")
            bridge(v, "test:pong", { "title": "T" })
            compare(received.length, 1)
            compare(received[0][1].title, "T")
            // A page's own console messages are not messages, even if they
            // look like the bridge's.
            v._backend.view.javaScriptConsoleMessage(0, "hello", 1, "")
            v._backend.view.javaScriptConsoleMessage(0, "\u0001keel:" + JSON.stringify({ n: "test:pong", d: {} }), 1, "")
            compare(received.length, 1)
            // App to content.
            v.sendAsyncMessage("test:ping", { "n": 1 })
            var last = Fake.FakeLog.worldScripts[Fake.FakeLog.worldScripts.length - 1]
            verify(last.indexOf('window.__keelBridge.receive("test:ping", {"n":1})') >= 0)
            compare(v.uniqueId, v._backend.messages.uniqueId)
        }

        function test_selection_copy_and_ime() {
            var v = view()
            bridge(v, "keel:selection", true)
            verify(v.textSelectionActive)
            bridge(v, "keel:selection", false)
            verify(!v.textSelectionActive)
            var ime = []
            v.imeNotification.connect(function(state, open, cause, focusChange, type) { ime.push([state, open, type]) })
            bridge(v, "keel:ime", { "open": true, "type": "email" })
            compare(ime, [[1, true, "email"]])
            observeSpy.clear()
            WebEngine.addObserver("clipboard:setdata")
            bridge(v, "keel:copy", null)
            tryCompare(observeSpy, "count", 1)
            compare(observeSpy.signalArguments[0][0], "clipboard:setdata")
            compare(observeSpy.signalArguments[0][1].private, false)
            WebEngine.removeObserver("clipboard:setdata")
        }

        function test_downloads() {
            var v = view()
            var engine = v._backend.view
            // From the context menu: to the file the menu chose.
            engine.contextMenuRequested({ "linkUrl": "https://example.org/f.zip", "mediaUrl": "", "mediaType": 0,
                                          "linkText": "", "position": Qt.point(1, 1), "accepted": false })
            WebEngine.notifyObservers("embedui:download", { "msg": "addDownload", "from": "https://example.org/f.zip",
                                                            "to": "file:///tmp/dl/f(1).zip", "contentType": "",
                                                            "viewId": v.uniqueId })
            compare(engine.actions[engine.actions.length - 1], Fake.WebEngineView.DownloadLinkToDisk)
            var d = fakeDownload("https://example.org/f.zip")
            engine.profile.downloadRequested(d)
            compare(d.result, "accepted")
            compare(d.downloadDirectory, "/tmp/dl")
            compare(d.downloadFileName, "f(1).zip")
            // Started by the page: refused without downloadsEnabled.
            v.downloadsEnabled = false
            var e = fakeDownload("https://example.org/g.zip")
            engine.profile.downloadRequested(e)
            compare(e.result, "cancelled")
        }

        function test_user_style_sheets() {
            var v = view()
            var sheet = Qt.resolvedUrl("style.css")
            WebEngine.addUserStyleSheet(sheet)
            compare(WebEngine._keelUserStyleSheets.length, 1)
            verify(String(WebEngine._keelUserStyleSheets[0]).indexOf("rgb(1, 2, 3)") >= 0)
            var scripts = v._backend.view.userScripts.collection
            compare(scripts[scripts.length - 1].name, "keel-user-style-sheets")
            verify(scripts[scripts.length - 1].sourceCode.indexOf("rgb(1, 2, 3)") >= 0)
            WebEngine.removeUserStyleSheet(sheet)
            compare(WebEngine._keelUserStyleSheets.length, 0)
            scripts = v._backend.view.userScripts.collection
            compare(scripts[scripts.length - 1].name, "keel-bridge")
            // Remote: imported.
            WebEngine.addUserStyleSheet("https://example.org/s.css")
            compare(WebEngine._keelUserStyleSheets[0], '@import url("https://example.org/s.css");')
            WebEngine.removeUserStyleSheet("https://example.org/s.css")
        }

        function test_web_engine_lifecycle() {
            verify(WebEngine.isAccelerated() === true || WebEngine.isAccelerated() === false)
            observeSpy.clear()
            WebEngine.addObserver("final-ui-startup")
            WebEngine.notifyFirstUIInitialized()
            tryCompare(observeSpy, "count", 1)
            compare(observeSpy.signalArguments[0][0], "final-ui-startup")
            WebEngine.removeObserver("final-ui-startup")
            WebEngine.runEmbedding()
            WebEngine.runEmbedding(100)
            var v = createTemporaryObject(plainView, root)
            tryVerify(function() { return v._backend !== null })
            lastWindowSpy.clear()
            contextSpy.clear()
            WebEngine.stopEmbedding()
            wait(20)
            compare(contextSpy.count, 0) // a view is still there
            v.destroy()
            tryCompare(lastWindowSpy, "count", 1)
            tryCompare(contextSpy, "count", 1)
            WebEngine.runEmbedding()
        }
    }
}
