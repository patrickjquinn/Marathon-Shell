// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

// Downloads: progress, open, share, try again, remove.

pragma ComponentBehavior: Bound

import QtQuick
import Sailfish.Silica 1.0
import Sailfish.Share 1.0
import Shipwright.Pacific 1.0
import Shipwright.Pacific.WebView 1.0
import "../js/logic.js" as Logic

Page {
    id: page
    objectName: "downloadsPage"

    property var browser

    allowedOrientations: Orientation.All

    ShareAction {
        id: share
    }

    SilicaListView {
        id: list
        anchors.fill: parent
        header: PageHeader { title: qsTr("Downloads") }
        model: PacificList {
            id: downloads
            kind: "downloads"
            revision: Pacific.revision
        }

        PullDownMenu {
            visible: downloads.count > 0
            MenuItem {
                text: qsTr("Clear finished downloads")
                onClicked: Remorse.popupAction(page, qsTr("Cleared finished downloads"), function() { Pacific.clearDownloads() })
            }
        }

        ViewPlaceholder {
            enabled: downloads.count === 0 && !downloads.loading
            text: qsTr("No downloads")
            hintText: qsTr("Files you download are saved in %1").arg(Pacific.downloadDir)
        }

        delegate: ListItem {
            id: item
            required property int itemId
            required property string title
            required property string url
            required property string path
            required property string status
            required property real progress
            required property string subtitle
            required property string detail
            required property string host // the file's MIME type
            contentHeight: Math.max(Theme.itemSizeLarge, rows.height + 2 * Theme.paddingMedium)
            onClicked: if (status === "finished") Qt.openUrlExternally("file://" + path)
            menu: ContextMenu {
                MenuItem {
                    visible: item.status === "finished"
                    text: qsTr("Open")
                    onClicked: Qt.openUrlExternally("file://" + item.path)
                }
                MenuItem {
                    visible: item.status === "finished"
                    text: qsTr("Share")
                    onClicked: {
                        share.mimeType = item.host !== "" ? item.host : "application/octet-stream"
                        share.resources = ["file://" + item.path]
                        share.trigger()
                    }
                }
                MenuItem {
                    visible: item.status === "failed" || item.status === "paused" || item.status === "cancelled"
                    text: qsTr("Try again")
                    onClicked: {
                        Pacific.removeDownload(item.itemId, true)
                        WebEngine.defaultProfile.download(item.url)
                    }
                }
                MenuItem {
                    text: qsTr("Remove from list")
                    onClicked: item.remorseDelete(function() { Pacific.removeDownload(item.itemId, false) })
                }
                MenuItem {
                    visible: item.status === "finished"
                    text: qsTr("Delete file")
                    onClicked: item.remorseDelete(function() { Pacific.removeDownload(item.itemId, true) })
                }
            }
            Item {
                id: iconSlot
                x: Theme.horizontalPageMargin
                width: Theme.iconSizeMedium
                height: parent.height
            }
            Icon {
                id: fileIcon
                anchors.centerIn: iconSlot
                source: item.status === "failed" ? "image://theme/icon-m-warning"
                        : "image://theme/" + Logic.fileIcon(item.title)
                highlighted: item.highlighted
            }
            Column {
                id: rows
                anchors { left: iconSlot.right; leftMargin: Theme.paddingMedium; right: parent.right; rightMargin: Theme.horizontalPageMargin; verticalCenter: parent.verticalCenter }
                spacing: Theme.paddingSmall
                Label {
                    width: parent.width
                    text: item.title
                    textFormat: Text.PlainText
                    truncationMode: TruncationMode.Fade
                    color: item.highlighted ? Theme.highlightColor : Theme.primaryColor
                }
                // A slim progress line while it runs (a moving segment when
                // the size is unknown).
                Rectangle {
                    width: parent.width
                    height: Theme.paddingSmall / 2
                    visible: item.status === "running"
                    radius: height / 2
                    color: Theme.rgba(Theme.highlightBackgroundColor, Theme.highlightBackgroundOpacity)
                    Rectangle {
                        height: parent.height
                        radius: parent.radius
                        width: item.progress >= 0 ? parent.width * Math.min(1, item.progress) : parent.width / 4
                        color: Theme.highlightColor
                        SequentialAnimation on x {
                            running: item.status === "running" && item.progress < 0
                            loops: Animation.Infinite
                            NumberAnimation { from: 0; to: rows.width * 3 / 4; duration: 900 }
                            NumberAnimation { from: rows.width * 3 / 4; to: 0; duration: 900 }
                        }
                    }
                }
                Label {
                    width: parent.width
                    text: {
                        var where = item.subtitle !== "" ? " · " + item.subtitle : "" // the site
                        switch (item.status) {
                        case "finished": return item.subtitle
                        case "failed": return qsTr("Failed: %1").arg(item.detail)
                        case "cancelled": return qsTr("Cancelled") + where
                        case "paused": return qsTr("Interrupted") + where
                        default: return (item.progress >= 0 ? Math.round(item.progress * 100) + "%" : qsTr("Downloading")) + where
                        }
                    }
                    textFormat: Text.PlainText
                    truncationMode: TruncationMode.Fade
                    font.pixelSize: Theme.fontSizeExtraSmall
                    color: item.highlighted ? Theme.secondaryHighlightColor : Theme.secondaryColor
                }
            }
        }

        VerticalScrollDecorator {}
    }
}
