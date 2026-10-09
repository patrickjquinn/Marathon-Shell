// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Keel internal: Sailfish.WebView's fallback where no web engine is
// installed. It renders nothing; it shows the page's address and opens it in
// the system browser on request. Navigation state stays empty,
// runJavaScript() reports an error, and frame scripts and messages go
// nowhere.
import QtQuick 2.6
import Sailfish.Silica 1.0

Item {
    id: backend

    property Item webView
    property url url
    readonly property string title: String(url).length > 0 ? String(url).replace(/^[a-z]+:\/\//, "").split("/")[0] : ""
    readonly property bool loading: false
    readonly property int loadProgress: 0
    readonly property bool canGoBack: false
    readonly property bool canGoForward: false
    readonly property bool loaded: false
    readonly property string engineName: "external"

    readonly property bool crashed: false
    readonly property bool textSelectionActive: false
    readonly property bool painted: false
    readonly property bool moving: false
    readonly property size contentsSize: Qt.size(0, 0)
    readonly property point scrollPosition: Qt.point(0, 0)
    readonly property real zoom: 1.0
    readonly property var messages: null

    signal keelLinkClicked(string url)
    signal keelLoadRedirect()
    signal keelMessage(string name, var data)
    signal keelImeNotification(int state, bool open, int cause, int focusChange, string type)
    signal keelFirstPaint()
    signal keelWindowCloseRequested()

    function loadHtml(html, baseUrl) { }
    function reload() { }
    function stop() { }
    function goBack() { }
    function goForward() { }
    function clearSelection() { }
    function sendToContent(name, data) { }
    function enableQtNavigator() { }
    function loadFrameScript(name) { }
    function runScript(script, callback, errorCallback) {
        if (errorCallback)
            errorCallback("no web engine on this device")
    }
    function openExternally() {
        if (String(url).length > 0)
            Qt.openUrlExternally(url)
    }

    Column {
        width: parent.width - 2 * Theme.horizontalPageMargin
        x: Theme.horizontalPageMargin
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.paddingLarge
        visible: String(backend.url).length > 0

        InfoLabel {
            width: parent.width
            text: qsTr("Web content opens in the browser")
        }
        Label {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WrapAnywhere
            maximumLineCount: 3
            elide: Text.ElideRight
            text: String(backend.url)
            color: Theme.secondaryHighlightColor
            font.pixelSize: Theme.fontSizeSmall
        }
        Button {
            anchors.horizontalCenter: parent.horizontalCenter
            text: qsTr("Open in browser")
            onClicked: backend.openExternally()
        }
    }
}
