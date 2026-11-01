// SPDX-FileCopyrightText: 2016 - 2018 Jolla Ltd.
// SPDX-FileCopyrightText: 2025 Jolla Mobile Ltd
// SPDX-FileCopyrightText: 2026 Patrick Quinn
//
// SPDX-License-Identifier: BSD-3-Clause

// Silica's Screen is qualified (S.Screen): which import an unqualified
// `Screen` names depends on the Qt version (the first up to Qt 6.8, the
// last from 6.10).
import Sailfish.Silica 1.0
import Sailfish.Silica 1.0 as S
import QtQuick 2.0

Item {
    id: header

    property Item pressedMenu
    readonly property Item highlightItem: pressedMenu ? pressedMenu.highlightItem : null

    height: Theme.itemSizeSmall

    Label {
        id: label

        anchors.centerIn: parent

        font.pixelSize: S.Screen.sizeCategory >= S.Screen.Large ? Theme.fontSizeSmall : Theme.fontSizeExtraSmall
        font.bold: S.Screen.sizeCategory < S.Screen.Large
        color: Theme.colorScheme == Theme.LightOnDark ? Theme.highlightColor : Theme.highlightFromColor(Theme.highlightColor, Theme.LightOnDark)

        textFormat: Text.AutoText
        text: header.highlightItem ? header.pressedMenu.title(header.highlightItem.value) : ""
        opacity: header.pressedMenu && header.pressedMenu.pressed || timer.running ? 1.0 : 0.0

        Behavior on opacity {
            FadeAnimation {}
        }
    }

    Timer {
        id: timer

        interval: 3000
        running: header.pressedMenu && !header.pressedMenu.pressed
    }
}
