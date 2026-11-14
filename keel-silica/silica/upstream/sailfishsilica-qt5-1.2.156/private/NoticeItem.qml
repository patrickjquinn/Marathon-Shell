/****************************************************************************************
**
** Copyright (c) 2020 Open Mobile Platform LLC.
** All rights reserved.
**
** This file is part of Sailfish Silica UI component package.
**
** You may use this file under the terms of BSD license as follows:
**
** Redistribution and use in source and binary forms, with or without
** modification, are permitted provided that the following conditions are met:
**     * Redistributions of source code must retain the above copyright
**       notice, this list of conditions and the following disclaimer.
**     * Redistributions in binary form must reproduce the above copyright
**       notice, this list of conditions and the following disclaimer in the
**       documentation and/or other materials provided with the distribution.
**     * Neither the name of the Jolla Ltd nor the
**       names of its contributors may be used to endorse or promote products
**       derived from this software without specific prior written permission.
**
** THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
** ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
** WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
** DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDERS OR CONTRIBUTORS BE LIABLE FOR
** ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
** (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
** LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
** ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
** (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
** SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
**
****************************************************************************************/

import QtQuick 2.6
import Sailfish.Silica 1.0

SilicaControl {
    id: noticeItem

    property var notice
    property ApplicationWindow applicationWindow
    property int orientation: applicationWindow.pageStack.currentOrientation

    property real horizontalMargin: Theme.horizontalPageMargin
    property real verticalMargin: Theme.paddingLarge
    property real cutoutMargin: (Screen.topCutout.height > 0)
                                ? (Screen.topCutout.height + Theme.paddingSmall) : 0

    x: {
        var left = Math.max(horizontalMargin,
                            (orientation == Orientation.Landscape)
                            ? cutoutMargin : 0)

        var right = parent.width - width
                - (Math.max(horizontalMargin,
                            (orientation == Orientation.LandscapeInverted)
                            ? cutoutMargin : 0))

        var x
        switch (notice.anchor & (Notice.Left | Notice.Right)) {
        case Notice.Left:
            x = left
            break
        case Notice.Right:
            x = right
            break
        default:
            x = (parent.width - width) / 2
        }
        return Math.max(left, Math.min(right, x + notice.horizontalOffset))
    }

    y: {
        var top = Math.max(verticalMargin,
                           orientation == Orientation.Portrait ? cutoutMargin : 0)
        var bottom = parent.height - height
                - ((orientation == Orientation.PortraitInverted)
                   ? cutoutMargin : verticalMargin)

        var y
        switch (notice.anchor & (Notice.Top | Notice.Bottom)) {
        case Notice.Top:
            y = top
            break
        case Notice.Bottom:
            y = bottom
            break
        default:
            y = (parent.height - height) / 2
        }
        return Math.max(top, Math.min(bottom, y + notice.verticalOffset))
    }

    implicitHeight: Math.max(Theme.itemSizeExtraSmall, label.implicitHeight)
    implicitWidth: Math.min(label.implicitWidth,
                            parent.width
                            - horizontalMargin
                            - (Math.max(horizontalMargin,
                                        (orientation & orientation.LandscapeMask) ? cutoutMargin : 0)))

    clip: label.implicitWidth > width

    highlighted: mouseArea.pressed

    MouseArea {
        id: mouseArea

        width: noticeItem.width
        height: noticeItem.height

        onClicked: Notices._dismissCurrent()
    }

    Rectangle {
        width: noticeItem.width
        height: noticeItem.height
        color: Qt.tint(
                   Theme.rgba(noticeItem.palette.overlayBackgroundColor, Theme.opacityOverlay),
                   Theme.rgba(noticeItem.palette.highlightBackgroundColor, Theme.highlightBackgroundOpacity))
        radius: Theme.paddingSmall
    }

    Label {
        id: label

        width: Math.max(noticeItem.width, implicitWidth)
        height: noticeItem.height

        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        leftPadding: Theme.paddingLarge
        rightPadding: Theme.paddingLarge
        topPadding: Theme.paddingSmall
        bottomPadding: Theme.paddingSmall

        text: noticeItem.notice.text

        font.pixelSize: Theme.fontSizeExtraSmall

        SequentialAnimation on x {
            running: label.width > noticeItem.width
            loops: Animation.Infinite

            PauseAnimation {
                duration: 1500
            }
            SmoothedAnimation {
                velocity: 100 * Theme.pixelRatio
                duration: -1
                from: 0
                to: -label.width + noticeItem.width
                easing.type: Easing.Linear
            }
            PauseAnimation {
                duration: 2000
            }
            PropertyAction {
                value: 0
            }
        }
    }
}
