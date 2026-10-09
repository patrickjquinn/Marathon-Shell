// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Keel internal: one cell of the image and video picker grids. Images are
// scaled by Qt (asynchronous, to the cell size); videos show the theme's
// video icon and their name (no frame extraction on Keel).
import QtQuick 2.6
import Sailfish.Silica 1.0

GridItem {
    id: cell

    property url itemUrl
    property string itemFileName
    property bool isVideo
    property bool checked

    highlighted: down || checked

    Rectangle {
        anchors.fill: parent
        color: Theme.rgba(Theme.highlightBackgroundColor, 0.1)
        visible: thumbnail.status !== Image.Ready
    }

    Image {
        id: thumbnail
        anchors.fill: parent
        visible: !cell.isVideo
        source: cell.isVideo ? "" : cell.itemUrl
        sourceSize.width: width
        sourceSize.height: height
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        clip: true
    }

    Icon {
        anchors.centerIn: parent
        visible: cell.isVideo
        source: "image://theme/icon-l-video"
    }

    Label {
        visible: cell.isVideo
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
            margins: Theme.paddingSmall
        }
        text: cell.itemFileName
        font.pixelSize: Theme.fontSizeTiny
        truncationMode: TruncationMode.Fade
    }

    Rectangle {
        anchors.fill: parent
        visible: cell.checked
        color: "transparent"
        border.color: Theme.highlightColor
        border.width: Math.max(2, Math.round(Theme.paddingSmall / 2))
    }
}
