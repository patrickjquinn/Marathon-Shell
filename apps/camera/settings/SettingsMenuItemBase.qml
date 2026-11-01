// SPDX-FileCopyrightText: 2017 - 2021 Jolla Ltd.
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

MouseArea {
    id: menuItem

    property var value

    property string property
    property QtObject settings

    // settings is null while the engine tears the page down.
    property bool selected: !!settings && settings[property] == value

    width: parent.width
    height: width

    // Only show setting if it fits the screen also on landscape
    // E.g. the layout only supports showing maximum of 6 items on 5" HD screen
    visible: y + height < S.Screen.width

    onSelectedChanged: {
        if (selected) {
            parent.currentItem = menuItem;
        }
    }

    onPressed: {
        parent.pressedItem = menuItem;
    }

    onClicked: {
        settings[property] = value;
    }

    Rectangle {
        anchors.centerIn: parent
        width: S.Screen.sizeCategory >= S.Screen.Large ? Theme.iconSizeMedium + Theme.paddingMedium : Theme.iconSizeMedium + Theme.paddingSmall
        height: width
        radius: width / 2
        color: Theme.highlightBackgroundColor

        opacity: menuItem.selected || menuItem.pressed ? Theme.opacityFaint : 0.0
        Behavior on opacity {
            FadeAnimation {}
        }
    }
}
