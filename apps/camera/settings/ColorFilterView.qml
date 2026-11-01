// SPDX-FileCopyrightText: 2021 - 2024 Jolla Ltd.
// SPDX-FileCopyrightText: 2025 Jolla Mobile Ltd
// SPDX-FileCopyrightText: 2026 Patrick Quinn
//
// SPDX-License-Identifier: BSD-3-Clause

import QtQuick 2.6
import Sailfish.Silica 1.0
import MarathonApp.Camera 1.0

ListView {
    id: root

    property int itemWidth: {
        var count = model ? model.length : 0;
        var maxWidth = 0;
        for (var i = 0; i < count; i++) {
            var width = fontMetrics.boundingRect(Settings.colorFilterText(model[i])).width;
            if (width > maxWidth) {
                maxWidth = width;
            }
        }
        return maxWidth + 2 * Theme.paddingLarge;
    }

    property int horizontalContentMargin: (width - itemWidth) / 2
    property int minContentX: originX + horizontalContentMargin
    property int maxContentX: contentWidth + originX - width + horizontalContentMargin

    property bool orientationTransitionRunning
    property int oldIndex

    onOrientationTransitionRunningChanged: if (orientationTransitionRunning)
        oldIndex = currentIndex
    onCurrentIndexChanged: if (orientationTransitionRunning)
        currentIndex = oldIndex

    // QTBUG-95676: StopAtBounds does not work with StrictlyEnforceRange,
    // work-around by implementing StopAtBounds locally
    onContentXChanged: {
        if (moving) {
            if (contentX < minContentX) {
                contentX = minContentX;
            }
            if (contentX > maxContentX) {
                contentX = maxContentX;
            }
        }
    }

    currentIndex: 0
    height: Theme.itemSizeLarge
    orientation: ListView.Horizontal
    flickDeceleration: 2 * Theme.flickDeceleration
    maximumFlickVelocity: Theme.maximumFlickVelocity / 2

    highlightMoveDuration: 200
    highlightRangeMode: ListView.StrictlyEnforceRange
    preferredHighlightBegin: horizontalContentMargin
    preferredHighlightEnd: horizontalContentMargin

    boundsBehavior: Flickable.StopAtBounds
    snapMode: ListView.SnapToItem

    header: Item {
        height: 1
        width: root.horizontalContentMargin
    }

    footer: Item {
        height: 1
        width: root.horizontalContentMargin
    }

    delegate: MouseArea {
        property bool highlighted: (pressed && containsMouse) || ListView.isCurrentItem

        onClicked: root.currentIndex = model.index
        height: root.height
        width: root.itemWidth

        Label {
            id: label

            text: Settings.colorFilterText(modelData)
            anchors.centerIn: parent
            truncationMode: TruncationMode.Fade
            highlighted: parent.highlighted
            style: Text.Raised
            styleColor: "black"
        }
    }

    FontMetrics {
        id: fontMetrics
        font.pixelSize: Theme.fontSizeMedium
    }
}
