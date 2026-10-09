/****************************************************************************************
**
** Copyright (C) 2013-2019 Jolla Ltd.
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

import QtQuick 2.0
import Sailfish.Silica 1.0
import "private/Util.js" as Util

SilicaItem {
    id: placeholder

    property alias icon: image
    property alias text: label.text
    property alias textColor: label.color
    property bool forceFit: (image.source + "").indexOf("image://theme/icon-launcher") > 0

    property Cover _cover
    property real bottomMargin

    Component.onCompleted: {
        var cover = Util.findParentWithProperty(placeholder, "coverActionArea")
        if (cover) {
            bottomMargin = Qt.binding(function () { return cover.coverActionArea.height })
        }
    }

    anchors.fill: parent

    Column {
        width: parent.width
        spacing: Theme.paddingLarge
        anchors {
            verticalCenter: parent.verticalCenter
            verticalCenterOffset: -Theme.paddingLarge
        }

        Image {
            id: image

            anchors.horizontalCenter: parent.horizontalCenter
            states: State {
                when: placeholder.forceFit
                PropertyChanges {
                    target: image
                    width: parent.width/2
                    fillMode: Image.PreserveAspectFit
                }
            }
        }

        Label {
            id: label

            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width - (Screen.sizeCategory > Screen.Medium
                                   ? 2*Theme.paddingMedium : 2*Theme.paddingLarge)
            height: Math.min(implicitHeight,
                             placeholder.height - 2*Theme.paddingLarge - image.height - parent.spacing - placeholder.bottomMargin)
            color: placeholder.palette.secondaryColor
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            font.pixelSize: Theme.fontSizeLarge
            fontSizeMode: Text.VerticalFit
        }
    }
}
