// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

// Cover (spec section 8.2): a running timer counting down in a ring, or
// the next alarm or reminder, or else Pilot's state and the last
// response; with the two ways to ask as cover actions: type (the app comes up with the sheet
// open and the keyboard up) and speak (a push-to-talk turn). Offline, only
// typing is offered: the local skills still answer typed questions.

import QtQuick
import Sailfish.Silica 1.0
import Shipwright.Pilot 1.0

CoverBackground {
    id: cover

    // For tests: which actions the cover offers.
    readonly property alias onlineActions: onlineActions
    readonly property alias offlineActions: offlineActions

    function bringUp() {
        __silica_applicationwindow_instance.activate()
    }

    // pilotd's home snapshot: what is running.
    property var now: ({})
    readonly property var clock: now.clock || []
    readonly property var timer: clock.filter(function(c) { return c.kind === "timer" })[0]
    readonly property var next: clock.filter(function(c) { return c.kind !== "timer" })[0]
    property real nowSecs: Date.now() / 1000
    readonly property int remaining: timer ? Math.max(0, Math.round(timer.at - nowSecs)) : 0

    function hms(s) {
        var h = Math.floor(s / 3600), m = Math.floor(s % 3600 / 60), x = s % 60
        return (h > 0 ? h + ":" + (m < 10 ? "0" : "") : "") + m + ":" + (x < 10 ? "0" : "") + x
    }

    onStatusChanged: if (status === Cover.Active) Pilot.refreshNow()
    Connections {
        target: Pilot
        function onNowChanged(json) { cover.now = JSON.parse(json) }
    }
    Timer {
        interval: 1000
        repeat: true
        triggeredOnStart: true
        running: cover.status === Cover.Active && !!cover.timer
        onTriggered: {
            cover.nowSecs = Date.now() / 1000
            if (cover.remaining === 0)
                Pilot.refreshNow()
        }
    }

    // A running timer: the ring and the time left.
    Item {
        objectName: "coverTimer"
        visible: !!cover.timer
        anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: Theme.paddingLarge * 2 }
        width: parent.width * 0.72
        height: width
        ProgressCircleBase {
            anchors.fill: parent
            borderWidth: Theme.paddingSmall
            value: cover.timer && cover.timer.seconds > 0 ? cover.remaining / cover.timer.seconds : 0
            progressColor: Theme.highlightColor
            backgroundColor: Theme.rgba(Theme.primaryColor, 0.12)
        }
        Column {
            anchors.centerIn: parent
            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                text: cover.hms(cover.remaining)
                font.pixelSize: Theme.fontSizeLarge
                font.family: Theme.fontFamilyHeading
                color: Theme.highlightColor
            }
            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.min(implicitWidth, cover.width * 0.5)
                text: cover.timer && cover.timer.title.indexOf(" timer") < 0 && cover.timer.title.length > 0
                      ? cover.timer.title : qsTr("Timer")
                truncationMode: TruncationMode.Fade
                font.pixelSize: Theme.fontSizeMedium
                color: Theme.secondaryColor
            }
        }
    }

    // Text at paddingLarge from the sides and paddingMedium from the top,
    // and never under the cover actions.
    Column {
        visible: !cover.timer
        x: Theme.paddingLarge
        y: Theme.paddingMedium
        width: parent.width - 2 * Theme.paddingLarge
        height: cover.coverActionArea.y - y - Theme.paddingMedium
        clip: true
        spacing: Theme.paddingSmall

        Label {
            objectName: "coverState"
            width: parent.width
            truncationMode: TruncationMode.Fade
            font.pixelSize: Theme.fontSizeMedium
            color: Theme.secondaryColor
            text: Pilot.offline ? qsTr("Pilot · offline")
                : Pilot.busy ? qsTr("Pilot · thinking")
                : qsTr("Pilot")
        }
        // The next alarm or reminder.
        Row {
            visible: !!cover.next
            spacing: Theme.paddingSmall
            Icon {
                anchors.verticalCenter: parent.verticalCenter
                source: cover.next && cover.next.kind === "alarm" ? "image://theme/icon-s-alarm" : "image://theme/icon-s-time"
                color: Theme.highlightColor
            }
            Label {
                anchors.verticalCenter: parent.verticalCenter
                text: cover.next ? Format.formatDate(new Date(cover.next.at * 1000), Formatter.TimeValue) : ""
                font.pixelSize: Theme.fontSizeLarge
                color: Theme.highlightColor
            }
        }
        Label {
            objectName: "coverText"
            width: parent.width
            // An answer wraps anywhere a long word (an address) needs to,
            // and ends with an ellipsis on the last whole line that fits.
            wrapMode: Text.Wrap
            height: Math.max(0, parent.height - y)
            maximumLineCount: 5
            elide: Text.ElideRight
            font.pixelSize: Theme.fontSizeMedium
            color: Theme.primaryColor
            // Offline is said above; here what still works.
            text: Pilot.offline ? qsTr("Timers, alarms and reminders still work")
                : Pilot.lastResponse.length > 0 ? Pilot.lastResponse
                : qsTr("Ask anything")
        }
    }

    CoverActionList {
        id: onlineActions
        objectName: "onlineActions"
        enabled: !Pilot.offline
        CoverAction {
            iconSource: "image://theme/icon-cover-message"
            // The main window's showSheet(): activate, sheet up, keyboard.
            onTriggered: __silica_applicationwindow_instance.showSheet()
        }
        CoverAction {
            iconSource: "image://theme/icon-cover-unmute"
            // sailfish-default has no icon-cover-mic; icon-cover-unmute is
            // the cover-sized microphone. A push-to-talk turn through
            // pilot-voice; the answer is spoken and shown here, and the app
            // is brought up so the turn is visible.
            onTriggered: {
                Pilot.listen()
                cover.bringUp()
            }
        }
    }

    CoverActionList {
        id: offlineActions
        objectName: "offlineActions"
        enabled: Pilot.offline
        CoverAction {
            iconSource: "image://theme/icon-cover-message"
            // The main window's showSheet(): activate, sheet up, keyboard.
            onTriggered: __silica_applicationwindow_instance.showSheet()
        }
    }
}
