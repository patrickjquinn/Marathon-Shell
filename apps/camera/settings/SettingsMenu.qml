// SPDX-FileCopyrightText: 2016 - 2021 Jolla Ltd.
// SPDX-FileCopyrightText: 2025 Jolla Mobile Ltd
// SPDX-FileCopyrightText: 2026 Patrick Quinn
//
// SPDX-License-Identifier: BSD-3-Clause

// Silica first: on Keel (Qt 6) the first import providing `Screen` wins.
import Sailfish.Silica 1.0
import QtQuick 2.0

Column {
    id: menu

    property var title
    property alias model: repeater.model
    property alias delegate: repeater.delegate
    property Item currentItem
    property MouseArea pressedItem
    readonly property Item highlightItem: pressedItem && pressedItem.pressed ? pressedItem : currentItem
    property Item header

    property bool pressed: pressedItem && pressedItem.pressed
    property bool active: model.length > 0

    onPressedChanged: {
        if (pressed && header) {
            header.pressedMenu = menu;
        }
    }

    width: Screen.width / 4
    visible: active

    Repeater {
        id: repeater
    }
}
