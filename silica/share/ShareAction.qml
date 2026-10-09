// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Sailfish.Share 1.0 ShareAction. API from the public Sailfish Share
// documentation (declarative-transferengine: mimeType, resources, title,
// trigger()) and the module's type information (selectedTransferMethodInfo,
// done(), toConfiguration(), loadConfiguration()). Clean-room. trigger()
// opens the system share dialog (org.sailfishos.share, Qt 5, out of
// process) with the action's configuration, as Silica apps do. Where that
// service is missing (hosts, CI) it falls back to the clipboard: the shared
// links and text (a link's URL, a text's status or data; never file paths,
// which would expose local paths to every app reading the clipboard), a
// short on-screen notice in the app's window, and Keel's `_shared` signal.
import QtQuick
import Sailfish.Silica 1.0
import Sailfish.Share 1.0

QtObject {
    id: action

    property string mimeType
    property var resources: []
    property string title
    property var selectedTransferMethodInfo: ({})

    signal done()

    // Keel extension: what trigger() put on the clipboard ("" if nothing).
    signal _shared(string text)

    function _textOf(resource) {
        if (resource === undefined || resource === null)
            return ""
        if (typeof resource === "string")
            return resource.indexOf("file:") === 0 || resource.indexOf("/") === 0 ? "" : resource
        var keys = ["linkUrl", "url", "status", "data"]
        for (var i = 0; i < keys.length; ++i) {
            var v = resource[keys[i]]
            if (v === undefined || v === null)
                continue
            var t = String(v)
            if (t.length > 0 && t.indexOf("file:") !== 0)
                return t
        }
        return ""
    }

    property Component _noticeComponent: Component {
        Rectangle {
            id: notice
            property alias text: label.text
            anchors {
                horizontalCenter: parent ? parent.horizontalCenter : undefined
                bottom: parent ? parent.bottom : undefined
                bottomMargin: Theme.paddingLarge
            }
            width: Math.min(label.implicitWidth, parent ? parent.width - 2 * Theme.horizontalPageMargin : label.implicitWidth)
            height: Math.max(Theme.itemSizeExtraSmall, label.implicitHeight)
            radius: Theme.paddingSmall
            color: Theme.rgba(Theme.overlayBackgroundColor, Theme.opacityOverlay)
            Label {
                id: label
                anchors.fill: parent
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                leftPadding: Theme.paddingLarge
                rightPadding: Theme.paddingLarge
                textFormat: Text.PlainText
                truncationMode: TruncationMode.Fade
                font.pixelSize: Theme.fontSizeExtraSmall
            }
            Timer { running: true; interval: 3000; onTriggered: notice.destroy() }
        }
    }

    function _showNotice(text) {
        var window = typeof __silica_applicationwindow_instance !== "undefined"
                ? __silica_applicationwindow_instance : null
        var parentItem = window && window.indicatorParentItem ? window.indicatorParentItem : null
        if (!parentItem) {
            console.info("Keel: " + text)
            return
        }
        _noticeComponent.createObject(parentItem, { "text": text })
    }

    function toConfiguration() {
        return {
            "resources": resources || [],
            "mimeType": mimeType,
            "title": title,
            "selectedTransferMethodInfo": selectedTransferMethodInfo || {}
        }
    }

    function loadConfiguration(configuration) {
        if (!configuration)
            return
        if (configuration.resources !== undefined)
            resources = configuration.resources
        if (configuration.mimeType !== undefined)
            mimeType = configuration.mimeType
        if (configuration.title !== undefined)
            title = configuration.title
        if (configuration.selectedTransferMethodInfo !== undefined)
            selectedTransferMethodInfo = configuration.selectedTransferMethodInfo
    }

    function trigger() {
        if (KeelShareService.available() && KeelShareService.share(toConfiguration()))
            return
        var list = resources || []
        var texts = []
        for (var i = 0; i < list.length; ++i) {
            var t = _textOf(list[i])
            if (t.length > 0)
                texts.push(t)
        }
        var text = texts.join("\n")
        if (text.length > 0) {
            Clipboard.text = text
            _showNotice(qsTr("Copied to clipboard"))
        } else {
            _showNotice(qsTr("Sharing is not available yet"))
        }
        _shared(text)
    }
}
