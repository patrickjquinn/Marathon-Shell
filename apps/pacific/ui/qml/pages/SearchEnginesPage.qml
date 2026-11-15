// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

// Search engines: tap to make one the default; add your own; remove the
// ones you added. Keywords search one engine once: "w sailfish".

pragma ComponentBehavior: Bound

import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Shipwright.Pacific 1.0

Page {
    id: page
    objectName: "enginesPage"

    allowedOrientations: Orientation.All

    SilicaListView {
        anchors.fill: parent
        header: Column {
            width: parent.width
            PageHeader { title: qsTr("Search engine") }
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * x
                bottomPadding: Theme.paddingLarge
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.secondaryHighlightColor
                text: qsTr("Tap an engine to make it the default. To use another one once, type its keyword and a space before your search.")
            }
        }
        model: PacificList {
            kind: "engines"
            revision: Pacific.revision + (Pacific.defaultEngine.length * 1000) + JSON.parse(Pacific.engines).length
        }

        PullDownMenu {
            MenuItem {
                text: qsTr("Add search engine")
                onClicked: pageStack.push(Qt.resolvedUrl("AddEngineDialog.qml"))
            }
        }

        delegate: ListItem {
            id: item
            required property string itemId
            required property string title
            required property string subtitle
            required property string keyword
            required property bool builtin
            required property bool on
            // As tall as its lines need at a large text size.
            contentHeight: Math.max(Theme.itemSizeMedium, rowText.height + 2 * Theme.paddingSmall)
            highlighted: down || item.on
            onClicked: Pacific.setDefaultEngine(itemId)
            menu: item.builtin ? null : removeMenu
            Component {
                id: removeMenu
                ContextMenu {
                    MenuItem {
                        text: qsTr("Remove")
                        onClicked: item.remorseDelete(function() { Pacific.removeEngine(item.itemId) })
                    }
                }
            }
            Column {
                id: rowText
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * x
                anchors.verticalCenter: parent.verticalCenter
                Label {
                    width: parent.width
                    text: item.title
                    textFormat: Text.PlainText
                    color: item.highlighted ? Theme.highlightColor : Theme.primaryColor
                }
                Label {
                    width: parent.width
                    text: item.keyword !== "" ? qsTr("%1, keyword %2").arg(item.subtitle).arg(item.keyword) : item.subtitle
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
