// SPDX-FileCopyrightText: 2013 - 2021 Jolla Ltd.
// SPDX-FileCopyrightText: 2025 Jolla Mobile Ltd
// SPDX-FileCopyrightText: 2026 Patrick Quinn
//
// SPDX-License-Identifier: BSD-3-Clause

import QtQuick 2.4
import Sailfish.Silica 1.0
import MarathonApp.Camera 1.0
import Nemo.Thumbnailer 1.0

CoverBackground {
    id: cover

    property int coverIndex: galleryActive ? galleryIndex : 0

    onCoverIndexChanged: {
        repositionTimer.restart();
    }

    Timer {
        id: repositionTimer

        interval: 1
        running: true // for initial positioning
        onTriggered: {
            list.positionViewAtIndex(coverIndex, ListView.SnapPosition);
        }
    }

    ListView {
        id: list

        width: Math.floor(2 * parent.width / 3)
        height: Math.floor(2 * parent.height / 3)
        anchors {
            centerIn: parent
            // Paddings ignored on purpose from the offset calculation:
            verticalCenterOffset: galleryActive ? settingsBar.height / 2 : 0
        }

        displayMarginBeginning: galleryActive ? width : 0
        displayMarginEnd: galleryActive ? width : 0

        interactive: false
        model: captureModel
        orientation: ListView.Horizontal
        snapMode: ListView.SnapOneItem

        delegate: Item {
            width: list.width
            height: list.height

            // A video shows its poster frame.
            Thumbnail {
                source: /\.mp4$/i.test(model.fileName) ? "file://" + Settings.captures.posterPath(model.filePath) : model.fileUrl
                mimeType: "image/jpeg"
                width: galleryActive ? (index === coverIndex ? parent.width : 0.8 * parent.width) : cover.width
                height: galleryActive ? (index === coverIndex ? parent.height : 0.8 * parent.height) : cover.height
                visible: galleryActive || index === coverIndex
                anchors.centerIn: parent
                smooth: true
                sourceSize.width: width
                sourceSize.height: height
                clip: true
            }
        }
    }

    Rectangle {
        width: parent.width
        height: settingsBar.height + 2 * Theme.paddingMedium

        gradient: Gradient {
            GradientStop {
                position: 0.0
                color: Theme.rgba("black", Theme.opacityOverlay)
            }
            GradientStop {
                position: 1.0
                color: "transparent"
            }
        }
    }

    Row {
        id: settingsBar

        anchors {
            top: parent.top
            topMargin: Theme.paddingMedium
            horizontalCenter: parent.horizontalCenter
        }
        // At the larger text sizes the row (the ISO item's
        // text grows) is wider than the cover; it shrinks to fit instead of
        // running off both edges.
        transformOrigin: Item.Top
        scale: Math.min(1, (cover.width - 2 * Theme.paddingSmall) / Math.max(1, width))

        CoverIcon {
            icon: Settings.captureModeIcon(Settings.global.captureMode)
        }
        CoverIcon {
            id: flashIcon

            visible: icon.toString() !== ""
            icon: CameraConfigs.supportedFlashModes.length > 0 ? Settings.flashIcon(Settings.mode.flash) : ""
        }
        CoverIcon {
            visible: icon.toString() !== ""
            icon: CameraConfigs.supportedExposureModes.length > 1 ? Settings.exposureModeIcon(Settings.mode.exposureMode) : ""
        }
        CoverIcon {
            visible: Settings.mode.exposureMode == Camera.ExposureManual && CameraConfigs.supportedWhiteBalanceModes.length > 1
            icon: Settings.whiteBalanceIcon(Settings.global.whiteBalance)
        }
        IsoItem {
            visible: CameraConfigs.supportedIsoSensitivities.length > 0
            scale: 0.75
            value: Settings.mode.iso
            color: Theme.colorScheme == Theme.LightOnDark ? Theme.highlightColor : Theme.highlightFromColor(Theme.highlightColor, Theme.LightOnDark)
        }
        CoverIcon {
            visible: !flashIcon.visible
            icon: Settings.timerIcon(Settings.mode.timer)
        }
    }

    Item {
        // "Focus indicator"
        width: Math.floor(cover.width / 2)
        height: width
        anchors.centerIn: parent
        visible: !galleryActive

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            border {
                width: Math.round(Theme.pixelRatio * 2)
                color: "white"
            }
            color: "transparent"
        }
    }
}
