// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: LicenseRef-Shipwright-Proprietary

// The page a swipe back or forward leads to (BrowserPage): the picture the
// web view kept of it when it was left (WebView.captureHistoryPicture, an
// image://pacifichistory/ source), or, without one (a restored session, a
// page changed by script), its site and title on the browser's glass, as
// the tab swipe's peek shows a tab with no picture.

pragma ComponentBehavior: Bound

import QtQuick
import Sailfish.Silica 1.0
import "../js/logic.js" as Logic

Item {
    id: picture

    property var view
    // {key, url, title} (WebView.historyItemAt), or null.
    property var item: null
    readonly property string key: item && item.key ? item.key : ""
    property bool _has: false

    function refresh(): void {
        _has = false
        _has = !!view && key !== "" && view.hasHistoryPicture(key)
    }
    onKeyChanged: refresh()
    onViewChanged: refresh()
    Connections {
        target: picture.view
        ignoreUnknownSignals: true
        function onHistoryPictureReady(k) {
            if (k === picture.key)
                picture.refresh()
        }
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.overlayBackgroundColor
    }
    Image {
        anchors.fill: parent
        visible: picture._has
        source: picture._has ? "image://pacifichistory/" + picture.key : ""
        cache: false
        fillMode: Image.PreserveAspectCrop
        verticalAlignment: Image.AlignTop
        smooth: true
    }
    Column {
        visible: !picture._has && picture.item !== null
        anchors.centerIn: parent
        width: parent.width - 2 * Theme.horizontalPageMargin
        spacing: Theme.paddingMedium
        LetterIcon {
            anchors.horizontalCenter: parent.horizontalCenter
            text: picture.item ? Logic.initial(picture.item.title || "", picture.item.url || "") : ""
            url: picture.item ? picture.item.url || "" : ""
        }
        Label {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            maximumLineCount: 3
            truncationMode: TruncationMode.Elide
            textFormat: Text.PlainText
            text: picture.item ? (picture.item.title || Logic.displayUrl(picture.item.url || "", "")) : ""
            color: Theme.highlightColor
            font.pixelSize: Theme.fontSizeLarge
        }
    }
}
