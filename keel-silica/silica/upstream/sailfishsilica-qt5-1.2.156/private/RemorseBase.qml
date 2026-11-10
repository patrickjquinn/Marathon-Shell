/****************************************************************************************
**
** Copyright (C) 2013 - 2020 Jolla Ltd.
** Copyright (c) 2019 - 2020 Open Mobile Platform LLC.
** All rights reserved.
**
** This file is part of Sailfish Silica UI component package
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
import Sailfish.Silica.private 1.0
import Sailfish.Silica 1.0
import Sailfish.Silica.Background 1.0

SwipeItem {
    id: root

    //% "Deleted"
    property string _deletedText: qsTrId("components-la-deleted")
    property string text: _deletedText
    //% "Undo"
    property string cancelText: fontMetrics.advanceWidth(_cancelTextFull) > labels.width
                                ? qsTrId("components-la-undo")
                                : _cancelTextFull

    //% "Tap to undo"
    property string _cancelTextFull: qsTrId("components-la-tap-to-undo")

    property real leftMargin: Theme.horizontalPageMargin
    property real rightMargin: Theme.horizontalPageMargin
    property alias pending: countdown.running
    property alias wrapMode: textLabel.wrapMode
    property alias horizontalAlignment: textLabel.horizontalAlignment
    property alias font: textLabel.font

    property int _timeout: 4000
    property int _seconds: (_timeout + 999) / 1000
    property int _secsRemaining: (_msRemaining + 999) / 1000
    property real _msRemaining: _timeout
    property bool _triggered
    property real _contentOpacity
    property alias _countdown: countdown
    property bool _wideMode
    property bool _belowGridItem

    readonly property bool _twoLines: secondaryLabel.text.length > 0 && !(showSwipeHint && !_narrowMode)
    readonly property bool _narrowMode: width <= Screen.width/2
    readonly property alias _labels: labels

    signal canceled
    signal triggered

    onClicked: cancel()
    onSwipedAway: _trigger()

    visible: false
    _showPress: false

    BannerBackground {
        id: background

        property real offset
        property int margin: Theme.paddingMedium

        highlighted: root.highlighted
        height: parent.height - 2 * y
        x: margin + (root.leftMargin - Theme.horizontalPageMargin)
        y: _narrowMode || parent.height > Theme.itemSizeMedium || _belowGridItem ? margin : 0
        width: parent.width - 2 * margin
               - (root.leftMargin - Theme.horizontalPageMargin)
               - (root.rightMargin - Theme.horizontalPageMargin)

        ColorBackground {
            anchors {
                top: parent.top
                bottom: parent.bottom
                right: parent.right
            }

            radius: background.radius
            width: Math.round((_seconds - _secsRemaining)/_seconds * background.width)
            roundedCorners: _secsRemaining === 0 ? Corners.All
                                                 : Corners.TopRight | Corners.BottomRight

            opacity: root.palette.colorScheme === Theme.LightOnDark ? Theme.opacityLow : 1.0
            color: Theme.highlightDimmerColor
        }
    }

    Flow {
        id: labels

        spacing: secondaryLabel.y === 0 ? Theme.paddingSmall : 0
        opacity: root._contentOpacity
        anchors {
            left: background.left
            right: parent.right
            leftMargin: root.leftMargin
            rightMargin: root.rightMargin
            verticalCenter: parent.verticalCenter
        }

        Label {
            id: textLabel

            //% "Swipe to hide"
            text: showSwipeHint && !_narrowMode ? qsTrId("components-la-swipe-to-hide")
                                                : cancelText

            width: _wideMode ? Math.min(contentWidth, parent.width)
                             : parent.width
            font.pixelSize: _twoLines ? Math.min(Theme.fontSizeSmall,
                                                 Theme.fontSizeSmallBase * 1.12)
                                      : Theme.fontSizeMedium
            truncationMode: wrapMode !== Text.NoWrap ? TruncationMode.None : TruncationMode.Fade
            wrapMode: _narrowMode ? Text.Wrap : Text.NoWrap
            textFormat: Text.PlainText
        }

        Label {
            id: secondaryLabel

            text: root.text !== root._deletedText ? root.text : ""
            visible: _twoLines

            width: _wideMode ? Math.min(contentWidth, parent.width)
                             : parent.width
            palette.primaryColor: root.palette.secondaryColor
            font.pixelSize: _wideMode ? textLabel.font.pixelSize
                                      : Math.min( Theme.fontSizeExtraSmall, Theme.fontSizeExtraSmallBase * 1.12)
            truncationMode: textLabel.truncationMode
            horizontalAlignment: textLabel.horizontalAlignment
        }
    }

    Item {
        id: hint

        onVisibleChanged: if (!visible) state = ""

        states: State {
            name: "swipeHint"

            PropertyChanges {
                target: countdown
                paused: countdown.running
            }
            PropertyChanges {
                target: secondaryLabel
                visible: false
            }
            PropertyChanges {
                target: textLabel
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeExtraSmall
                //% "You may also swipe to hide the Undo banner"
                text: qsTrId("components-la-remorse_swipe_hint")
            }
            PropertyChanges {
                target: root
                _seconds: 0
                onClicked: {
                    swipeHint.exhaust()
                    _trigger()
                }
            }
        }

        FirstTimeUseCounter {
            id: swipeHint

            limit: 1
            key: "/desktop/sailfish/hints/remorse_swipe_hint_count"
            ignoreSystemHints: true
        }

        Timer {
            interval: 2000
            running: hint.state !== ""
            onTriggered: _trigger()
        }
    }

    NumberAnimation {
        id: countdown

        target: root
        property: "_msRemaining"
        from: _timeout
        to: 0
        paused: running && (root.down || root.drag.active)
        duration: _timeout
        onRunningChanged: {
            if (!running && _msRemaining == 0) {
                if (swipeHint.active && !_narrowMode) {
                    hint.state = "swipeHint"
                    swipeHint.increase()
                } else {
                    if (_narrowMode) {
                        _trigger()
                    } else {
                        root.swipeAway()
                    }
                }
            }
        }
    }

    FontMetrics {
        id: fontMetrics
        font: textLabel.font
    }
}
