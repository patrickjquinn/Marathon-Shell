// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Sailfish.WebView / Sailfish.WebEngine over the Qt WebEngine backend, with
// the test double of Qt WebEngine's QML module (../fake) on the import path:
// the Sailfish API mapped onto WebEngineView, as the corpus apps use it
// (hutspot, sfos-forum-viewer, sailhn, dee, hafenschau).
import QtQuick 2.6
import QtTest 1.0
import Sailfish.Silica 1.0
import Sailfish.WebView 1.0
import Sailfish.WebEngine 1.0
import QtWebEngine 1.10 as Fake

Item {
    width: 540
    height: 960
    property alias pageStack: win.pageStack
    property alias __silica_applicationwindow_instance: win

    ApplicationWindow {
        id: win
        anchors.fill: parent
        initialPage: Component { Page { } }
    }

    Component {
        id: webPage
        WebViewPage {
            id: webPageItem
            property alias view: view
            property var clicked: []
            property int redirects
            property bool destroyedSeen
            WebView {
                id: view
                anchors.fill: parent
                url: "https://example.org/a"
                onLinkClicked: function(url) { webPageItem.clicked.push(url) }
                onLoadRedirect: webPageItem.redirects++
            }
        }
    }
    Component {
        id: privateView
        WebView { privateMode: true; url: "https://example.org/private" }
    }
    Component {
        id: plainView
        WebView { }
    }
    Component {
        id: flickable
        WebViewFlickable { width: 100; height: 100 }
    }

    SignalSpy {
        id: observeSpy
        target: WebEngine
        signalName: "recvObserve"
    }

    TestCase {
        name: "WebViewEngine"
        when: windowShown

        function cleanup() {
            WebEngineSettings.javascriptEnabled = true
        }

        function openPage() {
            tryCompare(win.pageStack, "busy", false)
            var p = win.pageStack.push(webPage, {}, PageStackAction.Immediate)
            tryCompare(win.pageStack, "busy", false)
            return p
        }

        function test_loads_through_qt_webengine() {
            var p = openPage()
            var v = p.view
            compare(v._engine, "qtwebengine")
            compare(v.webViewPage, p)
            verify(v.active)
            tryCompare(v, "loaded", true)
            compare(v.loading, false)
            compare(v.loadProgress, 100)
            compare(v.title, "Title of https://example.org/a")
            // https, loaded: secure (certificate details need Keel's own
            // TLS connection, off in tests).
            verify(v.security !== null)
            verify(v.security.validState)
            verify(v.security.isSecure)
            verify(!v.security.allGood)
            verify(v.security.certIsNull)

            v.url = "https://example.org/b"
            tryCompare(v, "title", "Title of https://example.org/b")
            verify(v.canGoBack)
            v.goBack()
            compare(String(v.url), "https://example.org/a") // follows the engine
            verify(v.canGoForward)
            v.goForward()
            compare(String(v.url), "https://example.org/b")
            v.load("https://example.org/c")
            compare(String(v._backend.view.url), "https://example.org/c")
            win.pageStack.pop(undefined, PageStackAction.Immediate)
        }

        function test_run_javascript_contract() {
            var p = openPage()
            var v = p.view
            var result, error
            v.runJavaScript("return 6 * 7", function(r) { result = r }, function(e) { error = e })
            compare(result, 42)
            compare(error, undefined)
            v.runJavaScript("throw new Error('boom')", function(r) { result = r }, function(e) { error = e })
            compare(error, "Error: boom")
            // No callbacks: nothing breaks.
            v.runJavaScript("return 1")
            win.pageStack.pop(undefined, PageStackAction.Immediate)
        }

        function test_link_clicked_and_redirect() {
            var p = openPage()
            var v = p.view
            v._backend.view.fakeNavigation("https://example.org/link", Fake.WebEngineNavigationRequest.LinkClickedNavigation)
            v._backend.view.fakeNavigation("https://example.org/r", Fake.WebEngineNavigationRequest.RedirectNavigation)
            v._backend.view.fakeNavigation("https://example.org/t", Fake.WebEngineNavigationRequest.TypedNavigation)
            compare(p.clicked, ["https://example.org/link"])
            compare(p.redirects, 1)
            win.pageStack.pop(undefined, PageStackAction.Immediate)
        }

        function test_profiles() {
            var a = createTemporaryObject(plainView, null)
            var b = createTemporaryObject(plainView, null)
            var priv = createTemporaryObject(privateView, null)
            tryVerify(function() { return a._backend && b._backend && priv._backend })
            // One shared persistent profile, kept by the WebEngine singleton.
            compare(a._backend.view.profile, b._backend.view.profile)
            compare(a._backend.view.profile, WebEngine._keelProfile)
            compare(a._backend.view.profile.storageName, "keel-webview")
            verify(!a._backend.view.profile.offTheRecord)
            // privateMode: an off-the-record profile of its own.
            verify(priv._backend.view.profile !== a._backend.view.profile)
            verify(priv._backend.view.profile.offTheRecord)
            compare(String(priv._backend.view.url), "https://example.org/private")
        }

        function test_settings_and_preferences() {
            var v = createTemporaryObject(plainView, null)
            tryVerify(function() { return v._backend !== null })
            var settings = v._backend.view.settings
            verify(settings.javascriptEnabled)
            WebEngineSettings.javascriptEnabled = false
            verify(!settings.javascriptEnabled)
            WebEngineSettings.setPreference("javascript.enabled", true, WebEngineSettings.BoolPref)
            verify(WebEngineSettings.javascriptEnabled)
            verify(settings.javascriptEnabled)
            WebEngineSettings.setPreference("permissions.default.image", 2, WebEngineSettings.IntPref)
            verify(!settings.autoLoadImages)
            WebEngineSettings.autoLoadImages = true
            WebEngineSettings.popupEnabled = true
            verify(settings.javascriptCanOpenWindows)
            WebEngineSettings.popupEnabled = false
            verify(!settings.localContentCanAccessRemoteUrls)
            // The sfos-forum-viewer and documentation preferences.
            WebEngineSettings.setPreference("security.disable_cors_checks", true, WebEngineSettings.BoolPref)
            verify(settings.localContentCanAccessRemoteUrls)
            WebEngineSettings.setPreference("security.csp.enable", false, WebEngineSettings.BoolPref)
            compare(WebEngineSettings.preference("security.csp.enable"), false)
            WebEngineSettings.setPreference("general.useragent.override", "Keel/1.0", WebEngineSettings.StringPref)
            compare(v._backend.view.profile.httpUserAgent, "Keel/1.0")
            v.httpUserAgent = "PerView/2.0"
            compare(v._backend.view.profile.httpUserAgent, "PerView/2.0")
            compare(WebEngineSettings.cookieBehavior, WebEngineSettings.AcceptAll)
            WebEngineSettings.setPreference("network.cookie.cookieBehavior", 2, WebEngineSettings.IntPref)
            compare(WebEngineSettings.cookieBehavior, WebEngineSettings.BlockAll)
            verify(WebEngineSettings.initialized)
            compare(WebEngineSettings.colorScheme, WebEngineSettings.FollowsAmbience)
            // pixelRatio: Sailfish's default (1.5 times Theme.pixelRatio in
            // 0.5 steps; the offscreen screen is narrower than 1080 pixels),
            // as the view's zoom.
            verify(Screen.width < 1080)
            compare(WebEngineSettings.pixelRatio, Math.round(1.5 * Theme.pixelRatio / 0.5) * 0.5)
            compare(v._backend.view.zoomFactor, WebEngineSettings.pixelRatio)
            WebEngineSettings.pixelRatio = 2.0
            compare(v._backend.view.zoomFactor, 2.0)
            WebEngineSettings.setPreference("layout.css.devPixelsPerPx", "-1.0", WebEngineSettings.StringPref)
            compare(WebEngineSettings.pixelRatio, 2.0) // Gecko's "automatic": unchanged
            WebEngineSettings.setPreference("layout.css.devPixelsPerPx", "3.0", WebEngineSettings.StringPref)
            compare(v._backend.view.zoomFactor, 3.0)
        }

        function test_web_engine_observers() {
            verify(WebEngine.initialized)
            observeSpy.clear()
            WebEngine.notifyObservers("keel:test", { "a": 1 }) // nobody observes it yet
            WebEngine.addObserver("keel:test")
            WebEngine.notifyObservers("keel:test", { "a": 2 })
            tryCompare(observeSpy, "count", 1)
            compare(observeSpy.signalArguments[0][0], "keel:test")
            compare(observeSpy.signalArguments[0][1].a, 2)
            WebEngine.removeObserver("keel:test")
            WebEngine.notifyObservers("keel:test", { "a": 3 })
            wait(20)
            compare(observeSpy.count, 1)
            WebEngine.addComponentManifest("/nonexistent/file.manifest") // accepted, ignored
        }

        function test_html_text_selection_and_active() {
            var v = createTemporaryObject(plainView, null)
            tryVerify(function() { return v._backend !== null })
            v.loadHtml("<p>hi</p>", "https://example.org/")
            compare(v._backend.view.lastHtml, "<p>hi</p>")
            v.loadText("a < b", "text/plain")
            verify(v._backend.view.lastHtml.indexOf("a &lt; b") >= 0)
            v.clearSelection()
            compare(v._backend.view.actions, [Fake.WebEngineView.Unselect])
            v.active = false
            verify(!v._backendHost.visible)
            v.active = true
            var destroyed = false
            v.viewDestroyed.connect(function() { destroyed = true })
            v.destroy()
            tryVerify(function() { return destroyed })
        }

        function test_flickable() {
            var f = createTemporaryObject(flickable, null)
            verify(f.webView)
            compare(f.webView.width, 100)
        }
    }
}
