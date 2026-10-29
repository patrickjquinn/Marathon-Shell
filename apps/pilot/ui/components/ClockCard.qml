// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

// An alarm or a reminder: the time it rings in large type, how far away
// that is ("in 2 h 5 min", "tomorrow"), what it is for, and Cancel.

import QtQuick
import Sailfish.Silica 1.0
import Shipwright.Pilot 1.0

Glass {
    id: card

    property string kind: "alarm"      // "alarm" or "reminder"
    property int cookie
    property real at                   // Unix seconds
    property string title: ""
    property bool cancelled: false

    readonly property date when: new Date(at * 1000)
    opacity: cancelled ? 0.6 : 1
    Behavior on opacity {
        FadeAnimator {}
    }

    // "in 25 min", "in 2 h 5 min", "tomorrow", "Friday".
    function relative(nowMs) {
        var mins = Math.round((at * 1000 - nowMs) / 60000);
        if (mins <= 0)
            return qsTr("now");
        if (mins < 60)
            return qsTr("in %1 min").arg(mins);
        var today = new Date(nowMs);
        var days = Math.round((new Date(when.getFullYear(), when.getMonth(), when.getDate()) - new Date(today.getFullYear(), today.getMonth(), today.getDate())) / 86400000);
        if (days === 0 || mins < 12 * 60) {
            var h = Math.floor(mins / 60), m = mins % 60;
            return m > 0 ? qsTr("in %1 h %2 min").arg(h).arg(m) : qsTr("in %1 h").arg(h);
        }
        if (days === 1)
            return qsTr("tomorrow");
        return Format.formatDate(when, Formatter.WeekdayNameStandalone);
    }

    property real nowMs: Date.now()
    Timer {
        interval: 30000
        running: !card.cancelled
        repeat: true
        onTriggered: card.nowMs = Date.now()
    }

    Row {
        width: parent.width
        spacing: Theme.paddingLarge

        Icon {
            anchors.verticalCenter: parent.verticalCenter
            source: card.kind === "alarm" ? "image://theme/icon-m-alarm" : "image://theme/icon-m-note"
            color: card.cancelled ? Theme.secondaryColor : Theme.highlightColor
        }

        Column {
            width: parent.width - Theme.iconSizeMedium - 2 * Theme.paddingLarge - cancel.width
            anchors.verticalCenter: parent.verticalCenter

            Row {
                spacing: Theme.paddingMedium
                Label {
                    objectName: "clockTime"
                    text: Format.formatDate(card.when, Formatter.TimeValue)
                    font.pixelSize: Theme.fontSizeExtraLarge
                    font.family: Theme.fontFamilyHeading
                    font.strikeout: card.cancelled
                    color: card.cancelled ? Theme.secondaryColor : Theme.primaryColor
                }
                Label {
                    anchors.baseline: parent.children[0].baseline
                    text: card.cancelled ? qsTr("Cancelled") : card.relative(card.nowMs)
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.secondaryHighlightColor
                }
            }
            Label {
                width: parent.width
                visible: text.length > 0
                text: card.title.length > 0 ? card.title.charAt(0).toUpperCase() + card.title.slice(1) : card.kind === "alarm" ? qsTr("Alarm") : ""
                wrapMode: Text.Wrap
                maximumLineCount: 2
                truncationMode: TruncationMode.Fade
                font.pixelSize: Theme.fontSizeMedium
                color: Theme.secondaryHighlightColor
            }
        }

        Chip {
            id: cancel
            objectName: "clockCancel"
            anchors.verticalCenter: parent.verticalCenter
            visible: !card.cancelled
            text: qsTr("Cancel")
            secondary: true
            onClicked: Pilot.cancelClock(card.cookie)
        }
    }

    Connections {
        target: Pilot
        function onClockCancelled(cookie) {
            if (cookie === card.cookie)
                card.cancelled = true;
        }
    }
}
