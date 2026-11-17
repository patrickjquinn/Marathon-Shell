// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

// What Pilot is doing while it works: thinking, searching the web for
// what, reading which sites, using which app, writing. Three dots breathe
// beside it, so a three-second web answer reads as work in progress rather
// than a stall. While the model on the phone reads the request, a line
// under it fills as far as it has read, and on at its rate.
// Once the model on the phone starts writing, the answer itself shows here
// as it comes (`partial`), and its finished card takes its place.

import QtQuick
import Sailfish.Silica 1.0

Item {
    id: line

    property string stage: "thinking"
    property string detail: ""
    property string partial: ""
    property real read: -1
    property real readLeft: 0
    property bool running: true
    // Only while it can be seen: shown, in the active window (see Orb.qml:
    // a running animation anywhere keeps the app drawing at the display's
    // rate).
    readonly property bool _animate: visible && Window.active && !Conversation.reduceMotion

    width: parent ? parent.width : 0
    height: (partial.length > 0 ? answer.height + Theme.paddingSmall : 0) + row.height + 2 * Theme.paddingMedium

    // The line's fill: the share read, then on towards the end, easing out
    // over the time left so it slows rather than stops, until the next
    // report sets it right. The first report (nothing read yet) has no time
    // left to go by.
    property real _shown: 0
    onReadChanged: {
        fill.stop();
        if (read < 0) {
            _shown = 0;
            return;
        }
        _shown = Math.max(_shown, read);
        if (!_animate || read >= 1 || readLeft <= 0)
            return;
        fill.to = Math.max(_shown, read + (1 - read) * 0.97);
        fill.duration = readLeft * 1.5;
        fill.start();
    }
    NumberAnimation {
        id: fill
        target: line
        property: "_shown"
        easing.type: Easing.OutCubic
    }

    function words() {
        switch (stage) {
        case "searching":
            return detail.length > 0 ? qsTr("Searching the web for “%1”").arg(detail) : qsTr("Searching the web");
        case "reading":
            return detail.length > 0 ? qsTr("Reading %1").arg(detail) : qsTr("Reading");
        case "writing":
            return qsTr("Writing the answer");
        case "acting":
            return detail.length > 0 ? detail : qsTr("Working on it");
        default:
            return qsTr("Thinking");
        }
    }

    Label {
        id: answer
        objectName: "stagePartial"
        x: Theme.horizontalPageMargin + Theme.paddingLarge
        y: Theme.paddingMedium
        width: parent.width - 2 * x
        visible: line.partial.length > 0
        height: visible ? implicitHeight : 0
        text: line.partial
        wrapMode: Text.Wrap
        textFormat: Text.PlainText
        font.pixelSize: Theme.fontSizeMedium
        lineHeight: 1.1
        color: Theme.primaryColor
    }

    Row {
        id: row
        x: Theme.horizontalPageMargin + Theme.paddingLarge
        y: Theme.paddingMedium + (answer.visible ? answer.height + Theme.paddingSmall : 0)
        width: parent.width - 2 * x
        spacing: Theme.paddingMedium

        Row {
            id: dots
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.paddingSmall / 2
            Repeater {
                model: 3
                delegate: Rectangle {
                    id: dot
                    required property int index
                    width: Theme.paddingSmall
                    height: width
                    radius: width / 2
                    color: Theme.highlightColor
                    opacity: 0.3
                    SequentialAnimation on opacity {
                        running: line.running && line._animate
                        loops: Animation.Infinite
                        PauseAnimation {
                            duration: dot.index * 160
                        }
                        NumberAnimation {
                            to: 1
                            duration: 320
                            easing.type: Easing.InOutQuad
                        }
                        NumberAnimation {
                            to: 0.3
                            duration: 320
                            easing.type: Easing.InOutQuad
                        }
                        PauseAnimation {
                            duration: (2 - dot.index) * 160
                        }
                    }
                }
            }
        }
        Label {
            objectName: "stageText"
            width: parent.width - dots.width - Theme.paddingMedium
            anchors.verticalCenter: parent.verticalCenter
            text: line.partial.length > 0 ? "" : line.words()
            truncationMode: TruncationMode.Fade
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.secondaryColor
        }
    }

    Rectangle {
        objectName: "stageRead"
        x: row.x
        y: row.y + row.height + Theme.paddingSmall
        width: row.width
        height: Math.max(2, Theme.paddingSmall / 2)
        radius: height / 2
        visible: line.read >= 0 && line.partial.length === 0
        color: Theme.rgba(Theme.highlightColor, 0.2)
        Rectangle {
            width: parent.width * Math.min(1, line._shown)
            height: parent.height
            radius: parent.radius
            color: Theme.highlightColor
        }
    }
}
