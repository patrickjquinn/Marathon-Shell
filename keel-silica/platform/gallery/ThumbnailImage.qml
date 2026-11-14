// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Sailfish.Gallery ThumbnailImage, clean-room from the type's use in apps:
// a square, pressable thumbnail of a photo (or a video: the theme's video
// icon, Keel extracts no frames) of `size` x `size`, cropped to fill.
//   source     the image (a URL or a local path)
//   size       the side of the square (also the decoded size)
//   mimeType   "video/..." shows a video placeholder; else derived from it
//   selected   draws the highlight frame of a picked item (Keel's addition
//              for pickers; the look follows Silica's GridItem)
//   status     the image's Image.status
//   clicked, pressAndHold (with the mouse event), as GridItem
import QtQuick 2.6
import Sailfish.Silica 1.0

GridItem {
    id: thumbnail

    property url source
    property real size: Theme.itemSizeExtraLarge
    property string mimeType
    property bool selected
    // Videos' running time in seconds, shown in the corner when > 0.
    property int duration
    readonly property alias status: image.status
    readonly property bool isVideo: mimeType.indexOf("video/") === 0
                                    || /\.(mp4|m4v|mkv|webm|mov|3gp|avi|ogv)$/i.test(String(source))

    width: size
    height: size
    contentHeight: size
    highlighted: down || selected

    Rectangle {
        anchors.fill: parent
        color: Theme.rgba(Theme.highlightBackgroundColor, Theme.opacityFaint)
        visible: image.status !== Image.Ready
    }

    Image {
        id: image
        anchors.fill: parent
        visible: !thumbnail.isVideo
        source: thumbnail.isVideo ? "" : thumbnail.source
        sourceSize.width: thumbnail.size
        sourceSize.height: thumbnail.size
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        autoTransform: true
        clip: true
        smooth: true
    }

    HighlightImage {
        anchors.centerIn: parent
        visible: thumbnail.isVideo
        width: Math.min(Theme.iconSizeLarge, thumbnail.size * 0.6)
        height: width
        sourceSize.width: width
        sourceSize.height: height
        source: "image://theme/icon-l-video"
        highlighted: thumbnail.highlighted
        color: Theme.primaryColor
    }

    Label {
        visible: thumbnail.isVideo && thumbnail.duration > 0
        anchors {
            right: parent.right
            bottom: parent.bottom
            margins: Theme.paddingSmall
        }
        font.pixelSize: Theme.fontSizeExtraSmall
        text: Format.formatDuration(thumbnail.duration,
                                    thumbnail.duration >= 3600 ? Formatter.DurationLong : Formatter.DurationShort)
    }

    Rectangle {
        anchors.fill: parent
        visible: thumbnail.selected
        color: "transparent"
        border.color: Theme.highlightColor
        border.width: Math.max(2, Math.round(Theme.paddingSmall / 2))
    }
}
