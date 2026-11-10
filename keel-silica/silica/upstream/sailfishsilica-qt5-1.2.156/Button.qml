/****************************************************************************************
**
** Copyright (c) 2020 Open Mobile Platform LLC.
** Copyright (C) 2013 Jolla Ltd.
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
import Sailfish.Silica.private 1.0

SilicaMouseArea {
    id: button

    property bool down: pressed && containsMouse && !DragFilter.canceled
    property alias text: buttonText.text
    property bool _showPress: down || pressTimer.running
    property color color: palette.primaryColor
    property color highlightColor: palette.highlightColor
    property color highlightBackgroundColor: Theme.rgba(palette.highlightBackgroundColor, Theme.opacityFaint)
    property color backgroundColor: Theme.rgba(color, Theme.opacityFaint)
    property real preferredWidth: _implicitPreferredWidth
    property real _implicitPreferredWidth: Theme.buttonWidthSmall
    property bool __silica_button
    property alias icon: image
    property alias layoutDirection: content.layoutDirection
    property alias border: borderColors

    onPressedChanged: {
        if (pressed) {
            pressTimer.start()
        }
    }
    onCanceled: {
        button.DragFilter.end()
        pressTimer.stop()
    }
    onPressed: button.DragFilter.begin(mouse.x, mouse.y)
    onPreventStealingChanged: if (preventStealing) button.DragFilter.end()

    height: implicitHeight
    implicitHeight: Theme.itemSizeExtraSmall
    implicitWidth: image.progress !== 0.0 && text === ""
                   ? Theme.buttonWidthTiny : Math.max(preferredWidth, content.fullWidth)

    highlighted: _showPress

    ButtonBorderColors {
        id: borderColors
    }

    Rectangle {
        anchors {
            fill: parent
            topMargin: (button.height - button.implicitHeight) / 2
            bottomMargin: anchors.topMargin
        }
        radius: Theme.paddingSmall
        color: _showPress ? Theme.rgba(button.highlightBackgroundColor, Theme.highlightBackgroundOpacity)
                          : button.backgroundColor

        opacity: button.enabled ? 1.0 : Theme.opacityLow
        border {
            width: Qt.colorEqual(borderColors.color, "transparent") ? 0 : Theme.dp(2)
            color: button._showPress ? borderColors.highlightColor : borderColors.color
        }

        Row {
            id: content

            property bool alignLeft
            readonly property real fullWidth: image.implicitWidth + spacing
                                              + buttonText.implicitWidth + 2 * Theme.paddingMedium

            anchors.verticalCenter: parent.verticalCenter
            anchors.horizontalCenter: alignLeft ? undefined : parent.horizontalCenter

            spacing: image.progress !== 0.0 && buttonText.text !== "" ? Theme.paddingSmall : 0
            objectName: "contentRow"

            Icon {
                id: image

                anchors.verticalCenter: parent.verticalCenter
                objectName: "image"
            }

            Label {
                id: buttonText

                property real _externalSize: Math.max(0, button.width - image.width -
                                                      2 * Theme.paddingSmall - content.spacing)

                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(_externalSize, implicitWidth)

                color: _showPress ? button.highlightColor : button.color
                font.pixelSize: preferredWidth > Theme.buttonWidthExtraSmall ? Theme.fontSizeMedium
                                                                             : Theme.fontSizeSmall
                truncationMode: TruncationMode.Fade
                objectName: "label"
            }
        }
    }

    Timer {
        id: pressTimer
        interval: Theme.minimumPressHighlightTime
    }
}
