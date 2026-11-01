// SPDX-FileCopyrightText: 2016 - 2021 Jolla Ltd.
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
    id: indicator

    property real zoom
    property real maximumZoom

    property color color: Theme.colorScheme == Theme.LightOnDark ? Theme.highlightColor : Theme.highlightFromColor(Theme.highlightColor, Theme.LightOnDark)

    implicitWidth: line.width + minimumLabel.implicitWidth / 2 + maximumLabel.implicitWidth / 2
    implicitHeight: Theme.itemSizeSmall

    opacity: opacityAnimation.running ? 1 : 0
    Behavior on opacity {
        FadeAnimation {
            id: opacityBehavior
        }
    }
    visible: opacityAnimation.running || opacityBehavior.running

    function show() {
        if (!opacityBehavior.running) {
            opacityAnimation.restart();
        }
    }

    Label {
        anchors {
            horizontalCenter: dot.horizontalCenter
            bottom: line.top
            bottomMargin: S.Screen.sizeCategory >= S.Screen.Large ? Theme.paddingMedium : Theme.paddingSmall
        }

        color: indicator.color
        font.pixelSize: minimumLabel.font.pixelSize
        font.bold: minimumLabel.font.bold
        //: Title for current zoom position
        text: qsTr("Zoom")
    }

    Rectangle {
        id: line

        anchors.centerIn: parent
        width: S.Screen.width * 0.75  // same length in both portrait and landscape
        height: Math.round(2 * Theme.pixelRatio)
        radius: height / 2

        color: indicator.color
    }

    Rectangle {
        id: dot

        anchors {
            verticalCenter: line.verticalCenter
            horizontalCenter: line.left
            horizontalCenterOffset: indicator.maximumZoom > 1 ? line.width * (indicator.zoom - 1) / (indicator.maximumZoom - 1) : line.width / 2
        }

        width: Math.round(10 * Theme.pixelRatio)
        height: width
        radius: height / 2

        color: indicator.color
    }

    Label {
        id: minimumLabel

        anchors {
            horizontalCenter: line.left
            top: line.bottom
            topMargin: S.Screen.sizeCategory >= S.Screen.Large ? Theme.paddingLarge : Theme.paddingMedium
        }

        color: indicator.color
        font.pixelSize: Theme.fontSizeExtraSmall
        font.bold: true
        //: Abbreviated text for minimum extent of the zoom indicator
        text: qsTr("min")
    }

    Label {
        id: maximumLabel

        anchors {
            horizontalCenter: line.right
            top: minimumLabel.top
        }

        color: indicator.color
        font.pixelSize: minimumLabel.font.pixelSize
        font.bold: minimumLabel.font.bold
        //: Abbreviated text for maximum extent of the zoom indicator
        text: qsTr("max")
    }

    PauseAnimation {
        id: opacityAnimation
        duration: 2000
    }
}
