// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

// Cover: what Reef is doing, and a refresh action.

import QtQuick
import Sailfish.Silica 1.0
import Shipwright.Reef 1.0
import "../components/Texts.js" as Texts

CoverBackground {
    id: cover

    // Never under the cover action: at the larger text sizes, in the
    // smaller cover, the state shrinks to fit what is left above it.
    Column {
        id: content
        x: Theme.paddingLarge
        y: Theme.paddingLarge
        width: parent.width - 2 * Theme.paddingLarge
        height: cover.coverActionArea.y - y - Theme.paddingSmall
        spacing: Theme.paddingSmall

        // At most half of what is above the cover action (the smaller cover
        // at a large text size has little).
        Item {
            id: badge
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.min(Theme.iconSizeExtraLarge, Math.round(content.height / 2))
            height: width

            BusyIndicator {
                anchors.centerIn: parent
                size: BusyIndicatorSize.Medium
                running: Reef.busy
                visible: running
            }
            Icon {
                anchors.centerIn: parent
                visible: !Reef.busy
                source: "image://theme/icon-m-cloud-download"
            }
        }
        Label {
            id: stateLabel
            objectName: "coverState"
            width: parent.width
            // As tall as its text needs at full size (one line or two),
            // at most what is left: only then does it shrink.
            readonly property real needed: (stateMetrics.advanceWidth > width ? 2 : 1) * stateLine.lineSpacing
            height: Math.max(0, Math.min(needed, content.height - badge.height - content.spacing
                                                 - (name.visible ? name.height + content.spacing : 0)))
            horizontalAlignment: Text.AlignHCenter
            // Between words only: a word too wide shrinks the text instead.
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            fontSizeMode: Text.Fit
            minimumPixelSize: Theme.fontSizeExtraSmall
            text: Reef.busy ? Texts.busyText(Reef.busyText) : qsTr("Store")

            TextMetrics {
                id: stateMetrics
                font.pixelSize: Theme.fontSizeMedium
                text: stateLabel.text
            }
            FontMetrics {
                id: stateLine
                font.pixelSize: Theme.fontSizeMedium
            }
        }
        // The app's name, where there is room for it under the state (not
        // in the smaller cover at the larger text sizes).
        Label {
            id: name
            visible: content.height - badge.height - stateLabel.needed - 2 * content.spacing >= height
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            font.pixelSize: Theme.fontSizeExtraSmall
            color: Theme.secondaryColor
            text: qsTr("Reef")
        }
    }

    CoverActionList {
        objectName: "coverActions"
        enabled: !Reef.busy
        CoverAction {
            iconSource: "image://theme/icon-cover-refresh"
            onTriggered: Reef.refresh()
        }
    }
}
