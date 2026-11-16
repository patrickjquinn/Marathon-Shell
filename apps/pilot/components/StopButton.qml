// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

// Stops the answer Pilot is working on: a square in a ring, as players
// and other assistants show it. The theme has no stop icon.

import QtQuick
import Sailfish.Silica 1.0

MouseArea {
    id: button

    width: Theme.itemSizeSmall
    height: Theme.itemSizeSmall
    Accessible.role: Accessible.Button
    Accessible.name: qsTr("Stop")
    Accessible.onPressAction: clicked(null)

    readonly property color _color: pressed ? Theme.highlightColor : Theme.primaryColor

    Rectangle {
        anchors.centerIn: parent
        width: Theme.iconSizeMedium * 0.75
        height: width
        radius: width / 2
        color: "transparent"
        border.width: Math.max(2, Theme.paddingSmall / 3)
        border.color: button._color
        Rectangle {
            anchors.centerIn: parent
            width: parent.width * 0.36
            height: width
            radius: Theme.paddingSmall / 3
            color: button._color
        }
    }
}
