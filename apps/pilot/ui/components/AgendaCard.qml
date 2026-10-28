// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: LicenseRef-Shipwright-Proprietary

// Calendar events as a short agenda: the day as the heading, then each
// event's time beside its title and place. Nothing planned reads as a
// calm line, not an error.

import QtQuick
import Sailfish.Silica 1.0

Glass {
    id: card

    property string range: "today"     // today, tomorrow, week, next
    property var events: []

    function heading() {
        switch (range) {
        case "tomorrow": return qsTr("Tomorrow")
        case "week": return qsTr("Next 7 days")
        case "next": return qsTr("Coming up")
        default: return qsTr("Today")
        }
    }

    Row {
        spacing: Theme.paddingMedium
        Icon {
            anchors.verticalCenter: parent.verticalCenter
            width: Theme.iconSizeSmallPlus
            height: width
            source: "image://theme/icon-m-date"
            color: Theme.highlightColor
        }
        Label {
            anchors.verticalCenter: parent.verticalCenter
            text: card.heading()
            font.pixelSize: Theme.fontSizeMedium
            color: Theme.highlightColor
        }
    }

    Label {
        visible: card.events.length === 0
        width: parent.width
        wrapMode: Text.Wrap
        text: card.range === "tomorrow" ? qsTr("Nothing planned for tomorrow.")
              : card.range === "week" ? qsTr("Nothing planned this week.")
              : card.range === "next" ? qsTr("Nothing coming up.")
              : qsTr("Nothing planned for today.")
        font.pixelSize: Theme.fontSizeMedium
        color: Theme.secondaryHighlightColor
    }

    Repeater {
        model: card.events
        delegate: Row {
            id: eventRow
            required property var modelData
            width: parent ? parent.width : 0
            spacing: Theme.paddingLarge
            Label {
                width: Theme.itemSizeMedium
                text: eventRow.modelData.all_day ? qsTr("All day")
                      : Format.formatDate(new Date(eventRow.modelData.start * 1000), Formatter.TimeValue)
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.highlightColor
            }
            Column {
                width: parent.width - Theme.itemSizeMedium - Theme.paddingLarge
                Label {
                    width: parent.width
                    text: eventRow.modelData.title
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    truncationMode: TruncationMode.Fade
                    color: Theme.highlightColor
                }
                Label {
                    width: parent.width
                    visible: !!eventRow.modelData.location
                    text: eventRow.modelData.location || ""
                    truncationMode: TruncationMode.Fade
                    font.pixelSize: Theme.fontSizeExtraSmall
                    color: Theme.secondaryHighlightColor
                }
            }
        }
    }
}
