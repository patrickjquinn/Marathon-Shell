// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: LicenseRef-Shipwright-Proprietary

// The new-tab page: the most visited sites as icons, the recent
// searches, the newest bookmarks and a privacy report. When it is short it
// hangs from the bottom, under the thumb; the address bar below is the
// search. The pull-down menu opens a private tab, bookmarks, history and
// settings.

pragma ComponentBehavior: Bound

import QtQuick
import Sailfish.Silica 1.0
import Shipwright.Pacific 1.0
import "../js/logic.js" as Logic

SilicaFlickable {
    id: view

    property var browser
    property var totals: null
    signal searchClicked()
    signal openUrl(string url)
    signal pushPage(string page)

    readonly property bool privateTab: browser ? browser.privateMode : false
    contentHeight: column.height
    // Short content hangs from the bottom, next to the toolbar; long
    // content starts at its top, fully visible, and scrolls.
    topMargin: Math.max(0, height - column.height)

    Component.onCompleted: Pacific.loadTotals()
    onVisibleChanged: {
        if (visible) {
            recent.refresh()
            Pacific.loadTotals()
        }
    }
    Connections {
        target: Pacific
        function onTotalsReady(json) { view.totals = JSON.parse(json).totals }
    }

    PullDownMenu {
        MenuItem {
            text: qsTr("Settings")
            onClicked: view.pushPage("SettingsPage.qml")
        }
        MenuItem {
            text: qsTr("History")
            onClicked: view.pushPage("HistoryPage.qml")
        }
        MenuItem {
            text: qsTr("Bookmarks")
            onClicked: view.pushPage("BookmarksPage.qml")
        }
        MenuItem {
            text: view.privateTab ? qsTr("New tab") : qsTr("New private tab")
            onClicked: view.browser.newTab(!view.privateTab)
        }
    }

    Column {
        id: column
        width: parent.width
        bottomPadding: Theme.paddingLarge

        PageHeader {
            title: view.privateTab ? qsTr("Private tab") : qsTr("New tab")
        }

        // Private: what it means, said once and plainly.
        Label {
            x: Theme.horizontalPageMargin
            width: parent.width - 2 * x
            visible: view.privateTab
            wrapMode: Text.Wrap
            bottomPadding: Theme.paddingLarge
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.secondaryHighlightColor
            text: qsTr("Pages you open here aren't saved to history. Their cookies and site data are deleted when you close the last private tab. Downloads and bookmarks stay. Sites and your network can still see what you visit.")
        }

        SectionHeader {
            text: qsTr("Frequently visited")
            visible: topSites.count > 0 && !view.privateTab
        }

        Grid {
            id: grid
            visible: topSites.count > 0 && !view.privateTab
            x: Theme.horizontalPageMargin - Theme.paddingSmall
            columns: Math.max(4, Math.floor((view.width - 2 * x) / Theme.itemSizeHuge))
            Repeater {
                model: PacificList {
                    id: topSites
                    kind: "topSites"
                    limit: 8
                    revision: Pacific.revision
                }
                delegate: SiteTile {
                    required property string title
                    required property string url
                    required property string icon
                    width: (view.width - 2 * grid.x) / grid.columns
                    siteTitle: title
                    siteUrl: url
                    iconSource: icon
                    onClicked: view.openUrl(url)
                }
            }
        }

        SectionHeader {
            text: qsTr("Recent searches")
            visible: recent.count > 0 && !view.privateTab
        }

        Column {
            width: parent.width
            visible: recent.count > 0 && !view.privateTab
            Repeater {
                model: SuggestionModel {
                    id: recent
                    Component.onCompleted: refresh()
                }
                // A recent search: a list item with the history icon, long
                // press to forget it (with remorse), as list items do.
                delegate: ListItem {
                    id: row
                    required property string query
                    required property string url
                    required property string kind
                    visible: kind === "recent"
                    width: parent.width
                    contentHeight: visible ? Theme.itemSizeSmall : 0
                    onClicked: view.openUrl(url)
                    menu: Component {
                        ContextMenu {
                            MenuItem {
                                text: qsTr("Remove")
                                onClicked: row.remorseDelete(function() { Pacific.deleteSearch(row.query); recent.refresh() })
                            }
                        }
                    }
                    Icon {
                        id: recentIcon
                        x: Theme.horizontalPageMargin
                        anchors.verticalCenter: parent.verticalCenter
                        source: "image://theme/icon-m-history"
                        highlighted: row.highlighted
                    }
                    Label {
                        anchors { left: recentIcon.right; leftMargin: Theme.paddingMedium; right: parent.right; rightMargin: Theme.horizontalPageMargin; verticalCenter: parent.verticalCenter }
                        text: row.query
                        textFormat: Text.PlainText
                        truncationMode: TruncationMode.Fade
                        color: row.highlighted ? Theme.highlightColor : Theme.primaryColor
                    }
                }
            }
        }

        SectionHeader {
            text: qsTr("Bookmarks")
            visible: recentBookmarks.count > 0
        }

        Repeater {
            model: PacificList {
                id: recentBookmarks
                kind: "recentBookmarks"
                limit: 5
                revision: Pacific.revision
            }
            delegate: ListItem {
                id: item
                required property string title
                required property string url
                required property string host
                required property string icon
                // As tall as its lines need at a large text size.
                contentHeight: Math.max(Theme.itemSizeMedium, rowText.height + 2 * Theme.paddingSmall)
                onClicked: view.openUrl(url)
                LetterIcon {
                    id: bmIcon
                    x: Theme.horizontalPageMargin
                    anchors.verticalCenter: parent.verticalCenter
                    width: Theme.iconSizeMedium
                    text: Logic.initial(item.title, item.url)
                    url: item.url
                    iconSource: item.icon
                }
                Column {
                    id: rowText
                    anchors { left: bmIcon.right; leftMargin: Theme.paddingMedium; right: parent.right; rightMargin: Theme.horizontalPageMargin; verticalCenter: parent.verticalCenter }
                    Label {
                        width: parent.width
                        text: item.title !== "" ? item.title : item.host
                        textFormat: Text.PlainText
                        truncationMode: TruncationMode.Fade
                        color: item.highlighted ? Theme.highlightColor : Theme.primaryColor
                    }
                    Label {
                        width: parent.width
                        text: item.host
                        textFormat: Text.PlainText
                        truncationMode: TruncationMode.Fade
                        font.pixelSize: Theme.fontSizeExtraSmall
                        color: item.highlighted ? Theme.secondaryHighlightColor : Theme.secondaryColor
                    }
                }
            }
        }

        SectionHeader {
            text: qsTr("Privacy report")
            visible: report.visible
        }

        BackgroundItem {
            id: report
            objectName: "privacyReport"
            visible: !view.privateTab && view.totals !== null && view.totals.blocked > 0
            width: parent.width
            height: Theme.itemSizeLarge
            onClicked: view.pushPage("PrivacyPage.qml")
            Icon {
                id: reportIcon
                x: Theme.horizontalPageMargin
                anchors.verticalCenter: parent.verticalCenter
                source: "image://theme/icon-m-browser-permissions"
                highlighted: report.highlighted
            }
            Label {
                anchors { left: reportIcon.right; leftMargin: Theme.paddingMedium; right: parent.right; rightMargin: Theme.horizontalPageMargin; verticalCenter: parent.verticalCenter }
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeSmall
                color: report.highlighted ? Theme.highlightColor : Theme.primaryColor
                text: view.totals ? qsTr("%1 ads and trackers blocked and %2 cookie banners rejected for you")
                                    .arg(view.totals.blocked).arg(view.totals.cookie_banners) : ""
            }
        }

        Label {
            x: Theme.horizontalPageMargin
            width: parent.width - 2 * x
            visible: !view.privateTab && topSites.count === 0 && recentBookmarks.count === 0 && !topSites.loading
            wrapMode: Text.Wrap
            horizontalAlignment: Text.AlignHCenter
            topPadding: Theme.paddingLarge
            text: qsTr("Sites you visit often and your bookmarks appear here. Search or type an address in the bar below.")
            color: Theme.secondaryHighlightColor
            font.pixelSize: Theme.fontSizeSmall
        }
    }

    VerticalScrollDecorator {}
}
