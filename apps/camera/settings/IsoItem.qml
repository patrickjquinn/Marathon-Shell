// SPDX-FileCopyrightText: 2017 - 2024 Jolla Ltd.
// SPDX-FileCopyrightText: 2025 Jolla Mobile Ltd
// SPDX-FileCopyrightText: 2026 Patrick Quinn
//
// SPDX-License-Identifier: BSD-3-Clause

import QtQuick 2.6
import Sailfish.Silica 1.0

Column {
    id: root

    width: textItem.width
    spacing: Math.round(-textItem.font.pixelSize / 8) // compensate text ascender to make items tight
    property int value
    property alias color: textItem.color

    Image {
        source: "image://theme/icon-camera-iso" + (root.color.toString() !== "" ? ("?" + root.color) : "")
        anchors.right: textItem.right
    }

    Text {
        id: textItem

        color: "white"
        text: root.value == 0 ? qsTr("Auto") : root.value
        font.pixelSize: Theme.fontSizeExtraSmallBase
    }
}
