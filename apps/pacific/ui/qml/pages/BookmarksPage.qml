// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

// Bookmarks: one folder at a time (folders first), or matches of a search.
// Long press for edit, move and delete; the pulley adds folders, imports
// and exports bookmark files.

pragma ComponentBehavior: Bound

import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Shipwright.Pacific 1.0

Page {
    id: page
    objectName: "bookmarksPage"

    property var browser
    property int folder: 1
    property string folderTitle: ""
    property string searchText: ""

    allowedOrientations: Orientation.All

    PacificList {
        id: bookmarks
        kind: "bookmarks"
        folder: page.folder
        query: page.searchText
        revision: Pacific.revision
    }

    SilicaListView {
        id: list
        anchors.fill: parent
        model: bookmarks

        header: Column {
            width: list.width
            PageHeader {
                title: page.folderTitle !== "" ? page.folderTitle : qsTr("Bookmarks")
            }
            SearchField {
                objectName: "bookmarkSearch"
                width: parent.width
                placeholderText: qsTr("Search bookmarks")
                EnterKey.iconSource: "image://theme/icon-m-enter-close"
                EnterKey.onClicked: focus = false
                onTextChanged: page.searchText = text
            }
        }

        PullDownMenu {
            MenuItem {
                text: qsTr("Export to Downloads")
                onClicked: Pacific.exportBookmarks(Pacific.downloadDir + "/pacific-bookmarks.html")
            }
            MenuItem {
                text: qsTr("Import bookmarks file")
                onClicked: pageStack.push(Qt.resolvedUrl("FileChooserPage.qml"), { importBookmarks: true })
            }
            MenuItem {
                text: qsTr("New folder")
                onClicked: pageStack.push(Qt.resolvedUrl("BookmarkDialog.qml"), { folderMode: true, parentFolder: page.folder })
            }
        }

        ViewPlaceholder {
            enabled: bookmarks.count === 0 && !bookmarks.loading
            text: qsTr("No bookmarks")
            hintText: qsTr("Bookmark a page from the page menu")
        }

        delegate: ListItem {
            id: item
            required property int index
            required property int itemId
            required property string title
            required property string url
            required property string host
            required property bool isFolder
            // As tall as its lines need at a large text size.
            contentHeight: Math.max(Theme.itemSizeMedium, rowText.height + 2 * Theme.paddingSmall)
            onClicked: {
                if (isFolder) {
                    pageStack.push(Qt.resolvedUrl("BookmarksPage.qml"), { browser: page.browser, folder: itemId, folderTitle: title })
                } else {
                    page.browser.open(url, { transition: "bookmark" })
                    pageStack.pop(pageStack.find(function(p) { return p.objectName === "browserPage" }))
                }
            }
            menu: ContextMenu {
                MenuItem {
                    visible: !item.isFolder
                    text: qsTr("Open in new tab")
                    onClicked: page.browser.open(item.url, { newTab: true, background: true, transition: "bookmark" })
                }
                MenuItem {
                    text: qsTr("Edit")
                    onClicked: pageStack.push(Qt.resolvedUrl("BookmarkDialog.qml"), {
                        bookmarkId: item.itemId, folderMode: item.isFolder, bookmarkTitle: item.title,
                        bookmarkUrl: item.url, parentFolder: page.folder
                    })
                }
                MenuItem {
                    text: qsTr("Delete")
                    onClicked: item.remorseDelete(function() { Pacific.deleteBookmark(item.itemId) })
                }
            }

            Icon {
                id: icon
                x: Theme.horizontalPageMargin
                anchors.verticalCenter: parent.verticalCenter
                source: item.isFolder ? "image://theme/icon-m-file-folder" : "image://theme/icon-m-favorite"
                highlighted: item.highlighted
            }
            Column {
                id: rowText
                anchors { left: icon.right; leftMargin: Theme.paddingMedium; right: parent.right; rightMargin: Theme.horizontalPageMargin; verticalCenter: parent.verticalCenter }
                Label {
                    width: parent.width
                    text: item.title !== "" ? item.title : item.host
                    textFormat: Text.PlainText
                    truncationMode: TruncationMode.Fade
                    color: item.highlighted ? Theme.highlightColor : Theme.primaryColor
                }
                Label {
                    width: parent.width
                    visible: !item.isFolder
                    text: item.host
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
