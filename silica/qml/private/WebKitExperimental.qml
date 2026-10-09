// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Keel internal: SilicaWebView's `experimental` group (QtWebKit 3.0's
// WebView experimental API as apps used it: userAgent, preferences,
// transparentBackground, evaluateJavaScript(), postMessage() and
// messageReceived). A named type so that `experimental.onMessageReceived:`
// can be written. The view sets `view`.
import QtQuick

QtObject {
    id: experimental

    // The SilicaWebView, untyped (Sailfish.Silica's type is not known here).
    property var view
    property string userAgent
    property bool transparentBackground
    property real deviceWidth
    property real deviceHeight
    property real preferredMinimumContentsWidth
    property bool useDefaultContentItemSize: true
    readonly property var page: view ? view._view : null
    readonly property var headerItem: view ? view._headerItem : null
    component Preferences: QtObject {
        property bool javascriptEnabled: true
        property bool autoLoadImages: true
        property bool cookiesEnabled: true
    }
    readonly property Preferences preferences: Preferences { }

    signal messageReceived(var message)

    // The result of the script's last expression, as QtWebKit's.
    function evaluateJavaScript(script, callback) {
        if (page)
            page.runJavaScript("return eval(" + JSON.stringify(String(script)) + ")", callback, function() {
                if (callback)
                    callback(undefined)
            })
    }

    // To the page's navigator.qt.onmessage.
    function postMessage(message) {
        if (page)
            page.runJavaScript("if (navigator.qt && typeof navigator.qt.onmessage === 'function')"
                               + " navigator.qt.onmessage({ data: " + JSON.stringify(message) + " }); return true")
    }
}
