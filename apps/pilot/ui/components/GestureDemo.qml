// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: LicenseRef-Shipwright-Proprietary

// How to bring Pilot up from anywhere, shown: a phone, and a finger onto
// the glowing bar at its bottom edge, held, and Pilot's orb.
// For the introduction and the getting-started guide.

import QtQuick
import Sailfish.Silica 1.0

Item {
    id: demo
    width: Theme.itemSizeHuge * 1.5
    height: width * 1.6
    clip: true
    Rectangle {
        anchors.fill: parent
        radius: Theme.paddingLarge
        color: "transparent"
        border.width: Math.max(2, Theme.paddingSmall / 2)
        border.color: Theme.rgba(Theme.primaryColor, 0.5)
    }
    Rectangle {
        id: finger
        anchors.horizontalCenter: parent.horizontalCenter
        width: Theme.paddingLarge * 2
        height: width
        radius: width / 2
        color: Theme.rgba(Theme.highlightColor, 0.8)
        y: parent.height - height - Theme.paddingSmall
        // Down onto the bar, held: Pilot.
        property bool held: false
        opacity: 0
        SequentialAnimation on opacity {
            loops: Animation.Infinite
            running: finger.visible
            ScriptAction { script: finger.held = false }
            PauseAnimation { duration: 500 }
            NumberAnimation { to: 1; duration: 200 }
            PauseAnimation { duration: 800 }
            ScriptAction { script: finger.held = true }
            PauseAnimation { duration: 1400 }
            NumberAnimation { to: 0; duration: 200 }
        }
    }
    // The glowing bar at the bottom edge.
    Rectangle {
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: Theme.paddingSmall }
        width: parent.width * (finger.held ? 0.45 : 0.3)
        height: Theme.paddingSmall
        radius: height / 2
        color: Theme.highlightColor
        Behavior on width { NumberAnimation { duration: 300 } }
    }
    Orb {
        anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: parent.height * 0.18 }
        width: Theme.itemSizeMedium
        height: width
        opacity: finger.held ? 1 : 0
        Behavior on opacity { FadeAnimator {} }
    }
}
