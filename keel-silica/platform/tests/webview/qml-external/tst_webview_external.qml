// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Sailfish.WebView where no web engine is installed (the host has no Qt
// WebEngine): the external fallback keeps the API working, shows the
// address with an "open in browser" button, and reports runJavaScript()
// as failed.
import QtQuick 2.6
import QtTest 1.0
import Sailfish.Silica 1.0
import Sailfish.WebView 1.0

Item {
    width: 540
    height: 960
    property alias __silica_applicationwindow_instance: win

    ApplicationWindow {
        id: win
        anchors.fill: parent
        initialPage: Component { Page { } }
    }

    Component {
        id: viewComponent
        WebView { width: 540; height: 800; url: "https://example.org/login"; privateMode: true }
    }

    TestCase {
        name: "WebViewExternal"
        when: windowShown

        function test_fallback() {
            var v = createTemporaryObject(viewComponent, null)
            tryCompare(v, "_engine", "external")
            compare(String(v.url), "https://example.org/login")
            compare(String(v._backend.url), "https://example.org/login")
            compare(v.title, "example.org")
            verify(!v.loading)
            verify(!v.loaded)
            verify(!v.canGoBack)
            var error
            v.runJavaScript("return 1", function() { }, function(e) { error = e })
            compare(error, "no web engine on this device")
            v.url = "https://example.org/other"
            compare(String(v._backend.url), "https://example.org/other")
            v.reload()
            v.stop()
            v.goBack()
        }
    }
}
