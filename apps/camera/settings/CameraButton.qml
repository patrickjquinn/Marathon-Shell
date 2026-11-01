// SPDX-FileCopyrightText: 2016 - 2024 Jolla Ltd.
// SPDX-FileCopyrightText: 2025 Jolla Mobile Ltd
//
// SPDX-License-Identifier: BSD-3-Clause

import QtQuick 2.0
import Sailfish.Silica 1.0

MouseArea {
    property alias icon: image
    property alias background: backgroundCircle
    property real size: Theme.itemSizeSmall
    property int verticalCenterOffset

    width: Theme.itemSizeExtraLarge
    height: Theme.itemSizeExtraLarge

    Rectangle {
        id: backgroundCircle

        radius: width / 2
        width: image.width
        height: width

        anchors {
            centerIn: parent
            verticalCenterOffset: parent.verticalCenterOffset
        }
        color: Theme.secondaryHighlightColor
    }

    Image {
        id: image

        anchors {
            centerIn: parent
            verticalCenterOffset: parent.verticalCenterOffset
        }
    }
}
