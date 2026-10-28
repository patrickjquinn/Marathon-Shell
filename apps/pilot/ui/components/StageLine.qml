// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: LicenseRef-Shipwright-Proprietary

// What Pilot is doing while it works: thinking, searching the web for
// what, reading which sites, writing. Three dots breathe beside it, so a
// three-second web answer reads as work in progress rather than a stall.

import QtQuick
import Sailfish.Silica 1.0

Item {
    id: line

    property string stage: "thinking"
    property string detail: ""
    property bool running: true
    // Only while it can be seen: shown, in the active window (see Orb.qml:
    // a running animation anywhere keeps the app drawing at the display's
    // rate).
    readonly property bool _animate: visible && Window.active

    width: parent ? parent.width : 0
    height: row.height + 2 * Theme.paddingMedium

    function words() {
        switch (stage) {
        case "searching":
            return detail.length > 0 ? qsTr("Searching the web for “%1”").arg(detail) : qsTr("Searching the web")
        case "reading":
            return detail.length > 0 ? qsTr("Reading %1").arg(detail) : qsTr("Reading")
        case "writing":
            return qsTr("Writing the answer")
        default:
            return qsTr("Thinking")
        }
    }

    Row {
        id: row
        x: Theme.horizontalPageMargin + Theme.paddingLarge
        y: Theme.paddingMedium
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
                        PauseAnimation { duration: dot.index * 160 }
                        NumberAnimation { to: 1; duration: 320; easing.type: Easing.InOutQuad }
                        NumberAnimation { to: 0.3; duration: 320; easing.type: Easing.InOutQuad }
                        PauseAnimation { duration: (2 - dot.index) * 160 }
                    }
                }
            }
        }
        Label {
            objectName: "stageText"
            width: parent.width - dots.width - Theme.paddingMedium
            anchors.verticalCenter: parent.verticalCenter
            text: line.words()
            truncationMode: TruncationMode.Fade
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.secondaryHighlightColor
        }
    }
}
