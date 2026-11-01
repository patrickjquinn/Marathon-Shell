// SPDX-FileCopyrightText: 2016 - 2018 Jolla Ltd.
// SPDX-FileCopyrightText: 2025 Jolla Mobile Ltd
// SPDX-FileCopyrightText: 2026 Patrick Quinn
//
// SPDX-License-Identifier: BSD-3-Clause

import QtQuick 2.0
import Sailfish.Silica 1.0
import MarathonApp.Camera 1.0

OverlayAnchor {
    property int index

    z: 1

    enabled: !anchorContainer.visible || overlay._captureButtonLocation != index
    parent: overlay._captureButtonLocation == index ? (anchorContainer.visible ? overlay : container) : anchorContainer

    MouseArea {
        anchors.fill: parent
        onClicked: {
            if (index >= 0) {
                if (overlay.isPortrait) {
                    Settings.global.portraitCaptureButtonLocation = index;
                } else {
                    Settings.global.landscapeCaptureButtonLocation = index;
                }
            }
        }
    }

    Rectangle {
        radius: Theme.itemSizeSmall / 2
        width: Theme.itemSizeSmall
        height: Theme.itemSizeSmall

        anchors.centerIn: parent

        border {
            color: Theme.colorScheme == Theme.LightOnDark ? Theme.highlightColor : Theme.highlightFromColor(Theme.highlightColor, Theme.LightOnDark)
            width: 5
        }
        z: 1
        color: "transparent"
        visible: anchorContainer.visible
        opacity: overlay._captureButtonLocation == index ? anchorContainer.opacity : 1.0
    }
}
