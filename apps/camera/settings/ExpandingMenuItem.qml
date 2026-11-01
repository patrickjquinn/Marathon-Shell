// SPDX-FileCopyrightText: 2016 - 2024 Jolla Ltd.
// SPDX-FileCopyrightText: 2025 Jolla Mobile Ltd
// SPDX-FileCopyrightText: 2026 Patrick Quinn
//
// SPDX-License-Identifier: BSD-3-Clause

import QtQuick 2.0
import Sailfish.Silica 1.0

MouseArea {
    id: menuItem

    property string icon
    property var value

    property string property
    property QtObject settings

    property QtObject menu

    property bool persistentHighlight
    // settings is null while the engine tears the page down.
    readonly property bool selected: !!settings && settings[property] == value
    readonly property bool highlighted: (parent.open || parent.pressed) && ((persistentHighlight && selected) || menuItem.pressed)
    property color highlightColor: Theme.colorScheme == Theme.LightOnDark ? Theme.highlightColor : Theme.highlightFromColor(Theme.highlightColor, Theme.LightOnDark)

    width: parent.width
    height: selected ? parent.width : parent.itemHeight

    onSelectedChanged: {
        if (selected && parent) {
            parent.currentIndex = index;
            parent.currentItem = menuItem;
        }
    }

    onParentChanged: {
        if (selected && parent) {
            parent.currentIndex = index;
            parent.currentItem = menuItem;
        }
    }

    onClicked: {
        settings[property] = value;
    }

    Item {
        anchors.fill: parent

        opacity: menuItem.selected || !menuItem.parent ? 1.0 : menuItem.parent.itemOpacity
        visible: menuItem.selected || (menuItem.parent && menuItem.parent.itemsVisible)

        Rectangle {
            anchors.centerIn: parent

            width: Theme.itemSizeExtraSmall
            height: Theme.itemSizeExtraSmall

            radius: width / 2

            color: highlightColor
            opacity: menuItem.highlighted ? Theme.opacityLow : 0.0
            Behavior on opacity {
                FadeAnimation {}
            }
        }

        Image {
            anchors.centerIn: parent
            source: menuItem.icon != "" ? (menuItem.pressed ? menuItem.icon + "?" + highlightColor : menuItem.icon + "?" + Theme.lightPrimaryColor) : ""
        }
    }
}
