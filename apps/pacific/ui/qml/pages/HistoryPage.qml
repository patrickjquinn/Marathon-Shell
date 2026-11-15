// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: LicenseRef-Shipwright-Proprietary

// History, newest first, in days, searchable. Long press to open in a new
// tab or delete one page; the pulley clears history by time range.

pragma ComponentBehavior: Bound

import QtQuick
import Sailfish.Silica 1.0
import Shipwright.Pacific 1.0
import "../components"
import "../js/logic.js" as Logic

Page {
    id: page
    objectName: "historyPage"

    property var browser
    property string searchText

    allowedOrientations: Orientation.All

    function sectionTitle(date: var): var {
        var today = new Date()
        var d = new Date(date + "T00:00:00")
        var days = Math.round((new Date(today.getFullYear(), today.getMonth(), today.getDate()) - d) / 86400000)
        if (days === 0)
            return qsTr("Today")
        if (days === 1)
            return qsTr("Yesterday")
        return d.toLocaleDateString(Qt.locale(), Locale.LongFormat)
    }

    SilicaListView {
        id: list
        anchors.fill: parent
        model: PacificList {
            id: history
            kind: "history"
            query: page.searchText
            revision: Pacific.revision
        }

        header: Column {
            width: list.width
            PageHeader { title: qsTr("History") }
            SearchField {
                objectName: "historySearch"
                width: parent.width
                placeholderText: qsTr("Search history")
                EnterKey.iconSource: "image://theme/icon-m-enter-close"
                EnterKey.onClicked: focus = false
                onTextChanged: page.searchText = text
            }
        }

        PullDownMenu {
            MenuItem {
                text: qsTr("Clear history")
                onClicked: pageStack.push(Qt.resolvedUrl("ClearDataDialog.qml"), { historyOnly: true })
            }
        }

        section.property: "section"
        section.delegate: SectionHeader {
            required property string section
            text: page.sectionTitle(section)
        }

        ViewPlaceholder {
            enabled: history.count === 0 && !history.loading
            text: page.searchText !== "" ? qsTr("Nothing found") : qsTr("No history")
            hintText: page.searchText !== "" ? "" : qsTr("Pages you visit appear here. Private tabs keep none.")
        }

        delegate: ListItem {
            id: item
            required property string title
            required property string url
            required property string host
            required property real time
            required property string icon
            // As tall as its lines need at a large text size.
            contentHeight: Math.max(Theme.itemSizeMedium, rowText.height + 2 * Theme.paddingSmall)
            onClicked: {
                page.browser.open(url, { transition: "typed" })
                pageStack.pop(pageStack.find(function(p) { return p.objectName === "browserPage" }))
            }
            menu: ContextMenu {
                MenuItem {
                    text: qsTr("Open in new tab")
                    onClicked: page.browser.open(item.url, { newTab: true, background: true })
                }
                MenuItem {
                    text: qsTr("Delete")
                    onClicked: item.remorseDelete(function() { Pacific.deleteHistory(item.url) })
                }
            }
            LetterIcon {
                id: siteIcon
                x: Theme.horizontalPageMargin
                anchors.verticalCenter: parent.verticalCenter
                width: Theme.iconSizeMedium
                text: Logic.initial(item.title, item.url)
                url: item.url
                iconSource: item.icon
                highlighted: item.highlighted
            }
            Column {
                id: rowText
                anchors { left: siteIcon.right; leftMargin: Theme.paddingMedium; right: parent.right; rightMargin: Theme.horizontalPageMargin; verticalCenter: parent.verticalCenter }
                Label {
                    width: parent.width
                    text: item.title
                    textFormat: Text.PlainText
                    truncationMode: TruncationMode.Fade
                    color: item.highlighted ? Theme.highlightColor : Theme.primaryColor
                }
                Label {
                    width: parent.width
                    text: item.host + " · " + new Date(item.time).toLocaleTimeString(Qt.locale(), Locale.ShortFormat)
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
