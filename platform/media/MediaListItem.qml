// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Sailfish.Media 1.0 MediaListItem, Keel's clean-room version: a Silica
// ListItem showing a track's title, subtitle and duration. Property names
// from the public Sailfish.Media documentation (`duration`, `playing`,
// `subtitle`, `subtitleTextFormat`, `textFormat`, `title`); the layout is
// Keel's. `duration` is in seconds (a number) or preformatted text.
import QtQuick 2.6
import Sailfish.Silica 1.0

ListItem {
    id: root

    property string title
    property string subtitle
    property var duration
    property bool playing
    property alias textFormat: titleLabel.textFormat
    property alias subtitleTextFormat: subtitleLabel.textFormat

    function _durationText() {
        if (duration === undefined || duration === null || duration === "")
            return ""
        if (typeof duration === "number")
            return Format.formatDuration(duration, duration >= 3600 ? Formatter.DurationLong : Formatter.DurationShort)
        return String(duration)
    }

    contentHeight: Math.max(Theme.itemSizeMedium, column.height + 2 * Theme.paddingSmall)

    Column {
        id: column
        anchors {
            left: parent.left
            right: durationLabel.left
            leftMargin: Theme.horizontalPageMargin
            rightMargin: Theme.paddingMedium
            verticalCenter: parent.verticalCenter
        }
        Label {
            id: titleLabel
            width: parent.width
            text: root.title
            truncationMode: TruncationMode.Fade
            color: root.highlighted || root.playing ? Theme.highlightColor : Theme.primaryColor
        }
        Label {
            id: subtitleLabel
            width: parent.width
            text: root.subtitle
            visible: text.length > 0
            truncationMode: TruncationMode.Fade
            font.pixelSize: Theme.fontSizeExtraSmall
            color: root.highlighted || root.playing ? Theme.secondaryHighlightColor : Theme.secondaryColor
        }
    }

    Label {
        id: durationLabel
        anchors {
            right: parent.right
            rightMargin: Theme.horizontalPageMargin
            verticalCenter: parent.verticalCenter
        }
        text: root._durationText()
        font.pixelSize: Theme.fontSizeExtraSmall
        color: root.highlighted || root.playing ? Theme.secondaryHighlightColor : Theme.secondaryColor
    }
}
