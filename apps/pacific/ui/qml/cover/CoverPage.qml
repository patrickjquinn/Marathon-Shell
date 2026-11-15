// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: LicenseRef-Shipwright-Proprietary

// The cover: the page in front (its picture, title and site) and the
// number of tabs. Actions: a new tab, or search at once.

pragma ComponentBehavior: Bound

import QtQuick
import Sailfish.Silica 1.0
import "../js/logic.js" as Logic

CoverBackground {
    id: cover

    property var browser
    readonly property var model: browser ? browser.tabs : null
    // The tab in front, read again whenever the model changes: its title,
    // address and picture change as it loads, with activeId unchanged.
    // Only while the cover is on screen, and at most four times a second:
    // the model changes many times a page load, and each read is a JSON
    // round trip on the main thread.
    property int _revision: 0
    readonly property var current: model && model.activeId !== 0 && _revision >= 0
                                   ? JSON.parse(model.get(model.activeId)) : ({})

    Connections {
        target: cover.model
        function onDataChanged() {
            if (cover.status === Cover.Active || cover.status === Cover.Activating)
                refresh.start()
        }
    }
    Timer {
        id: refresh
        interval: 250
        onTriggered: cover._revision++
    }
    onStatusChanged: if (status === Cover.Activating || status === Cover.Active) cover._revision++
    readonly property bool privateTab: browser ? browser.privateMode : false

    Image {
        id: thumb
        anchors { left: parent.left; right: parent.right; top: parent.top; bottom: info.top; bottomMargin: Theme.paddingMedium }
        source: cover.privateTab ? "" : (cover.current.thumbnail || "")
        fillMode: Image.PreserveAspectCrop
        verticalAlignment: Image.AlignTop
        // Decoded off the main thread, at the cover's size.
        asynchronous: true
        sourceSize.width: width
        opacity: 0.6
        visible: status === Image.Ready
    }

    Column {
        id: info
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: Theme.paddingLarge; bottomMargin: Theme.itemSizeSmall + Theme.paddingMedium }
        spacing: Theme.paddingSmall

        Icon {
            visible: cover.privateTab
            source: "image://theme/icon-m-incognito"
        }
        Label {
            width: parent.width
            text: cover.privateTab ? qsTr("Private tab")
                                   : (cover.current.url ? (cover.current.title || Logic.host(cover.current.url)) : qsTr("Pacific"))
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            maximumLineCount: 3
            truncationMode: TruncationMode.Fade
            color: Theme.highlightColor
            font.pixelSize: Theme.fontSizeSmall
        }
        Label {
            width: parent.width
            visible: !cover.privateTab && cover.current.url !== undefined && cover.current.url !== ""
            text: Logic.host(cover.current.url || "")
            textFormat: Text.PlainText
            truncationMode: TruncationMode.Fade
            color: Theme.secondaryHighlightColor
            font.pixelSize: Theme.fontSizeExtraSmall
        }
        Label {
            text: cover.model ? (cover.model.count === 1 ? qsTr("1 tab") : qsTr("%1 tabs").arg(cover.model.count)) : ""
            color: Theme.secondaryHighlightColor
            font.pixelSize: Theme.fontSizeExtraSmall
        }
    }

    CoverActionList {
        CoverAction {
            iconSource: "image://theme/icon-cover-new"
            onTriggered: {
                cover.browser.newTab(cover.privateTab)
                cover.browser.window.activate()
            }
        }
        CoverAction {
            iconSource: "image://theme/icon-cover-search"
            onTriggered: {
                cover.browser.window.activate()
                cover.browser.openAddress()
            }
        }
    }
}
