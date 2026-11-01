// SPDX-FileCopyrightText: 2016 - 2024 Jolla Ltd.
// SPDX-FileCopyrightText: 2025 Jolla Mobile Ltd
//
// SPDX-License-Identifier: BSD-3-Clause

import QtQuick 2.0
import Sailfish.Silica 1.0

MouseArea {
    id: menuItem

    property url icon
    property color highlightColor: Theme.colorScheme == Theme.LightOnDark ? Theme.highlightColor : Theme.highlightFromColor(Theme.highlightColor, Theme.LightOnDark)

    width: Theme.itemSizeExtraSmall
    height: Theme.itemSizeExtraSmall

    Rectangle {
        anchors.centerIn: parent

        width: Theme.itemSizeExtraSmall
        height: Theme.itemSizeExtraSmall

        radius: width / 2

        color: highlightColor
        opacity: menuItem.pressed ? Theme.opacityLow : 0.0
        Behavior on opacity {
            FadeAnimation {}
        }
    }

    Image {
        anchors.centerIn: parent
        source: menuItem.pressed ? menuItem.icon + "?" + highlightColor : menuItem.icon + "?" + Theme.lightPrimaryColor
    }
}
