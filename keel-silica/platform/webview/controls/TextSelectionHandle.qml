// SPDX-FileCopyrightText: 2013 - 2020 Jolla Ltd
// SPDX-FileCopyrightText: 2020 Open Mobile Platform LLC
// SPDX-License-Identifier: MPL-2.0
/****************************************************************************
**
** Copyright (c) 2013 - 2020 Jolla Ltd.
** Copyright (c) 2020 Open Mobile Platform LLC.
**
****************************************************************************/

/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/. */

import QtQuick 2.1
import Sailfish.Silica 1.0

Image {
    id: handle

    property real contentWidth
    property real contentHeight

    // Deprecated compatibility property; no longer used by selection handling.
    property real lineHeight

    property real fixedX
    property real fixedY

    property QtObject contentItem
    property QtObject selectionController

    // the moving property is updated upon dragActive change to make sure
    // that Browser:SelectionMoveStart is sent out before Browser:SelectionMove
    property bool moving
    readonly property bool dragActive: mouseArea.drag.active

    // We could use these to programmatically scroll the content.
    readonly property bool atXBeginning: x - Theme.horizontalPageMargin <= 0
    readonly property bool atXEnd: x + width + Theme.horizontalPageMargin > contentWidth

    readonly property bool atYBeginning: y - Theme.horizontalPageMargin <= 0
    readonly property bool atYEnd: y + height + Theme.horizontalPageMargin > contentHeight

    property alias targetPositionAnimation: targetPositionAnimation

    property string markerTag
    // Mask area for touch handling, should cover whole mousearea
    property rect mask: Qt.rect(0, 0, 0, 0)

    source: "image://theme/icon-m-textselection-" + markerTag
    width: Theme.iconSizeSmallPlus
    height: Theme.iconSizeSmallPlus

    onDragActiveChanged: {
        if (dragActive) {
            contentItem.sendAsyncMessage("Browser:SelectionMoveStart",
                                         selectionController.getMarkerBaseMessage(markerTag))
            moving = true
        } else {
            contentItem.sendAsyncMessage("Browser:SelectionMoveEnd",
                                         selectionController.getMarkerBaseMessage(markerTag))
            moving = false
        }
    }

    onVisibleChanged: {
        if (visible) {
            showAnimation.restart()
        } else {
            mask = Qt.rect(0, 0, 0, 0)
        }
    }

    onXChanged: mask = Qt.rect(x - Theme.paddingLarge, y,
                               width + 2 * Theme.paddingLarge, height + Theme.paddingLarge)
    onYChanged: mask = Qt.rect(x - Theme.paddingLarge, y,
                               width + 2 * Theme.paddingLarge, height + Theme.paddingLarge)

    MouseArea {
        id: mouseArea

        property real previousX: -1
        property real previousY: -1

        anchors {
            fill: parent
            leftMargin: -Theme.paddingLarge
            rightMargin: -Theme.paddingLarge
            bottomMargin: -Theme.paddingLarge
        }

        drag {
            target: parent
            axis: Drag.XandYAxis
            maximumX: handle.contentWidth
            maximumY: handle.contentHeight
        }

        preventStealing: true

        onPositionChanged: {
            var targetX = mouse.x
            var targetY = mouse.y

            if (!handle.moving || Math.abs(targetX - previousX) < 0.99 && Math.abs(targetY - previousY) < 0.99) {
                return
            }

            var markerMessage = selectionController.getMarkerBaseMessage(markerTag)
            contentItem.sendAsyncMessage("Browser:SelectionMove", markerMessage)
            previousX = targetX
            previousY = targetY
        }
    }

    ParallelAnimation {
        id: showAnimation

        FadeAnimation {
            target: handle
            from: 0
            to: 1.0
        }
        NumberAnimation {
            target: handle
            property: "x"
            from: handle.markerTag === "start" ? handle.x - Theme.itemSizeExtraLarge
                                               : handle.x + Theme.itemSizeExtraLarge
            to: handle.x
            duration: 200
            easing.type: Easing.InOutQuad
        }
    }

    ParallelAnimation {
        id: targetPositionAnimation

        NumberAnimation {
            target: handle
            property: "x"
            to: handle.fixedX
            duration: 100
            easing.type: Easing.InOutQuad
        }
        NumberAnimation {
            target: handle
            property: "y"
            to: handle.fixedY
            duration: 100
            easing.type: Easing.InOutQuad
        }
    }
}
