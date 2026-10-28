// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: LicenseRef-Shipwright-Proprietary

// A running timer: a ring that empties as it counts down, the time left
// in large type inside it, what it is for, when it ends, and "+1 min" and
// Cancel within thumb reach. It counts from `endsAt` (Unix seconds), so it
// is right whenever it is drawn. Cancelled or finished, it says so and
// its buttons go.

import QtQuick
import Sailfish.Silica 1.0
import Shipwright.Pilot 1.0

Glass {
    id: card

    property int cookie
    property int seconds
    property real endsAt          // Unix seconds
    property string label: ""
    property bool cancelled: false
    signal extended(int oldCookie)

    readonly property real nowSecs: clock.now
    readonly property int remaining: Math.max(0, Math.round(endsAt - nowSecs))
    readonly property bool done: remaining === 0 && !cancelled
    readonly property bool live: !done && !cancelled

    accent: live
    opacity: cancelled ? 0.6 : 1
    Behavior on opacity { FadeAnimator {} }

    function hms(s) {
        var h = Math.floor(s / 3600), m = Math.floor(s % 3600 / 60), x = s % 60
        var mm = (h > 0 && m < 10 ? "0" : "") + m
        return (h > 0 ? h + ":" : "") + mm + ":" + (x < 10 ? "0" : "") + x
    }

    QtObject {
        id: clock
        property real now: Date.now() / 1000
    }
    Timer {
        interval: 250
        running: card.live
        repeat: true
        triggeredOnStart: true
        onTriggered: clock.now = Date.now() / 1000
    }

    Row {
        width: parent.width
        spacing: Theme.paddingLarge

        Item {
            width: Theme.itemSizeHuge
            height: width
            ProgressCircleBase {
                anchors.fill: parent
                borderWidth: Theme.paddingSmall
                value: card.cancelled || card.seconds <= 0 ? 0 : card.remaining / card.seconds
                progressColor: card.live ? Theme.highlightColor : Theme.secondaryColor
                backgroundColor: Theme.rgba(Theme.primaryColor, 0.10)
                Behavior on value { enabled: card.live; NumberAnimation { duration: 250 } }
            }
            Label {
                objectName: "timerLeft"
                anchors.centerIn: parent
                text: card.cancelled ? "–" : card.done ? qsTr("Done") : card.hms(card.remaining)
                font.pixelSize: card.remaining >= 3600 ? Theme.fontSizeMedium : Theme.fontSizeLarge
                font.family: Theme.fontFamilyHeading
                color: card.live ? Theme.highlightColor : Theme.secondaryColor
            }
        }

        Column {
            width: parent.width - Theme.itemSizeHuge - Theme.paddingLarge
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.paddingSmall

            Label {
                width: parent.width
                text: card.label.length > 0 ? card.label : qsTr("Timer")
                truncationMode: TruncationMode.Fade
                font.pixelSize: Theme.fontSizeLarge
                color: Theme.highlightColor
            }
            Label {
                width: parent.width
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.secondaryHighlightColor
                text: card.cancelled ? qsTr("Cancelled")
                    : card.done ? qsTr("Finished")
                    : qsTr("Ends at %1").arg(Format.formatDate(new Date(card.endsAt * 1000), Formatter.TimeValue))
            }
            Row {
                visible: card.live
                width: parent.width
                spacing: Theme.paddingMedium
                topPadding: Theme.paddingSmall
                Chip {
                    objectName: "timerExtend"
                    text: qsTr("+1 min")
                    onClicked: Pilot.extendTimer(card.cookie, 60)
                }
                Chip {
                    objectName: "timerCancel"
                    text: qsTr("Cancel")
                    secondary: true
                    onClicked: Pilot.cancelClock(card.cookie)
                }
            }
        }
    }

    Connections {
        target: Pilot
        function onClockCancelled(cookie) {
            if (cookie === card.cookie)
                card.cancelled = true
        }
        function onTimerExtended(oldCookie, json) {
            if (oldCookie !== card.cookie)
                return
            var t = JSON.parse(json)
            card.cookie = t.cookie
            card.endsAt = t.ends_at
            card.seconds = t.seconds
            card.extended(oldCookie)
        }
    }
}
