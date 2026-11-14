/****************************************************************************************
**
** Copyright (C) 2013 - 2019 Jolla Ltd.
** Copyright (c) 2020 Open Mobile Platform LLC.
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
import QtQuick 2.0
import Sailfish.Silica 1.0

BackgroundItem {
    id: root

    property alias label: titleText.text
    property alias value: valueText.text
    property string description

    property alias labelColor: titleText.color
    property alias valueColor: valueText.color
    property color descriptionColor: root.down ? palette.secondaryHighlightColor : palette.secondaryColor

    property real labelMargin: root.leftMargin
    property real minimumContentHeight: Theme.itemSizeSmall
    property real leftMargin: Theme.horizontalPageMargin
    property real rightMargin: Theme.horizontalPageMargin

    property int _duration: 200
    property Item _descriptionLabel

    width: parent ? parent.width : 0
    height: contentItem.height
    contentHeight: visible ? Math.max(column.height + 2*Theme.paddingMedium, minimumContentHeight) : 0
    opacity: enabled ? 1.0 : Theme.opacityLow

    onDescriptionChanged: {
        if (!_descriptionLabel && description.length > 0)
            _descriptionLabel = descriptionComponent.createObject(column)
    }

    Column {
        id: column

        anchors {
            left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter
            leftMargin: root.labelMargin; rightMargin: root.rightMargin
        }
        Flow {
            id: flow

            width: parent.width
            move: Transition { NumberAnimation { properties: "x,y"; easing.type: Easing.InOutQuad; duration: root._duration } }

            Label {
                id: titleText

                color: root.down ? palette.highlightColor : palette.primaryColor
                width: Math.min(implicitWidth + Theme.paddingMedium, parent.width)
                height: text.length ? implicitHeight : 0
                fontSizeMode: Text.HorizontalFit
                minimumPixelSize: Theme.fontSizeSmallBase
                truncationMode: TruncationMode.Fade
            }

            Label {
                id: valueText

                color: palette.highlightColor
                width: Math.min(implicitWidth, parent.width)
                truncationMode: TruncationMode.Fade
            }
        }
    }

    Component {
        id: descriptionComponent

        Label {
            text: root.description
            height: text.length ? (implicitHeight + Theme.paddingMedium) : 0
            width: parent.width
            font.pixelSize: Theme.fontSizeExtraSmall
            color: descriptionColor
            wrapMode: Text.Wrap
        }
    }
}
