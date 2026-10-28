// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

// Cover: the number of updates, or an install's progress, and a refresh
// action. Rendered through keel-shell's cover window (docs/plan.md,
// "keel-shell"; Phase 0 probe 3).

import QtQuick
import Sailfish.Silica 1.0
import Shipwright.Reef 1.0
import "../components/Texts.js" as Texts

CoverBackground {
    id: cover

    readonly property bool hasProgress: Reef.busy && Reef.progress >= 0

    // Never under the cover action: at the larger text sizes, in the
    // smaller cover, the state shrinks to fit what is left above it.
    Column {
        id: content
        x: Theme.paddingLarge
        y: Theme.paddingLarge
        width: parent.width - 2 * Theme.paddingLarge
        height: cover.coverActionArea.y - y - Theme.paddingSmall
        spacing: Theme.paddingSmall

        // The number or progress, at most half of what is above the cover
        // action (the smaller cover at a large text size has little).
        Item {
            id: badge
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.min(Theme.iconSizeExtraLarge, Math.round(content.height / 2))
            height: width

            // Updates waiting: their number, large.
            Label {
                objectName: "coverCount"
                anchors.centerIn: parent
                visible: !Reef.busy && Reef.updateCount > 0
                text: Reef.updateCount
                font.pixelSize: Math.min(Theme.fontSizeHuge, badge.height)
            }
            // An operation with progress: a circle with the percentage.
            ProgressCircle {
                anchors.fill: parent
                visible: cover.hasProgress
                progressColor: Theme.highlightColor
                backgroundColor: Theme.highlightDimmerColor
                value: Math.max(0, Reef.progress) / 100
            }
            Label {
                anchors.centerIn: parent
                visible: cover.hasProgress
                text: qsTr("%1%").arg(Reef.progress)
            }
            BusyIndicator {
                anchors.centerIn: parent
                size: BusyIndicatorSize.Medium
                running: Reef.busy && !cover.hasProgress
                visible: running
            }
            Icon {
                anchors.centerIn: parent
                visible: !Reef.busy && Reef.updateCount === 0
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
            text: Reef.busy ? Texts.busyText(Reef.busyText)
                : Reef.updateCount > 0 ? qsTr("update(s)", "", Reef.updateCount)
                : qsTr("Up to date")

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
