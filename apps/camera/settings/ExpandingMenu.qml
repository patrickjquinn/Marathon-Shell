// SPDX-FileCopyrightText: 2016 - 2024 Jolla Ltd.
// SPDX-FileCopyrightText: 2025 Jolla Mobile Ltd
// SPDX-FileCopyrightText: 2026 Patrick Quinn
//
// SPDX-License-Identifier: BSD-3-Clause

import QtQuick 2.0
import Sailfish.Silica 1.0

MouseArea {
    id: menu

    property alias title: titleText.text
    property alias model: repeater.model
    property alias delegate: repeater.delegate
    property alias currentItem: column.currentItem
    property alias currentIndex: column.currentIndex
    readonly property alias count: repeater.count
    property alias openProgress: titleText.opacity
    property alias spacing: column.spacing
    property int alignment

    property bool open
    readonly property alias expanded: column.itemsVisible

    function selectItem(index) {
        var item = repeater.itemAt(index);
        item.settings[item.property] = item.value;
    }

    width: Theme.itemSizeExtraSmall
    height: Theme.itemSizeExtraSmall
    anchors.centerIn: parent

    onClicked: menu.open = true

    Column {
        id: column

        property Item currentItem
        property int currentIndex
        readonly property alias itemOpacity: titleText.opacity
        readonly property bool itemsVisible: menu.open || fadeAnimation.running
        readonly property alias pressed: menu.pressed
        property alias open: menu.open
        property real itemHeight: menu.open ? menu.height : 0
        Behavior on itemHeight {
            NumberAnimation {
                duration: 200
                easing.type: Easing.InOutQuad
            }
        }

        anchors.bottom: alignment & Qt.AlignBottom ? menu.bottom : undefined
        width: menu.width
        spacing: Theme.paddingSmall

        Repeater {
            id: repeater
        }

        enabled: menu.open
    }

    Label {
        id: titleText

        anchors {
            horizontalCenter: menu.horizontalCenter
            horizontalCenterOffset: (horizontalAlignment == Text.AlignRight ? -menu.width : menu.width) + Theme.paddingMedium
            verticalCenter: column.verticalCenter
        }

        width: menu.width

        color: Theme.highlightBackgroundColor
        font {
            pixelSize: Theme.fontSizeExtraSmall
            bold: true
        }
        wrapMode: Text.Wrap
        horizontalAlignment: alignment & Qt.AlignLeft ? Text.AlignLeft : Text.AlignRight

        opacity: menu.open ? 1.0 : 0.0

        Behavior on opacity {
            FadeAnimation {
                id: fadeAnimation
            }
        }
    }
}
