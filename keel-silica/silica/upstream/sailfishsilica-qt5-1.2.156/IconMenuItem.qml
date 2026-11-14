/****************************************************************************************
**
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

import QtQuick 2.6
import Sailfish.Silica 1.0

MenuItem {
    id: iconMenuItem

    property alias description: descriptionLabel.text
    property alias icon: icon
    property bool _highlighted: highlighted

    height: Theme.itemSizeSmall + Theme.paddingSmall*2
    topPadding: descriptionLabel.text.length ? -descriptionLabel.implicitHeight : 0
    leftPadding: Theme.iconSizeMedium + Theme.paddingMedium
    horizontalAlignment: Text.AlignLeft

    HighlightImage {
        id: icon

        anchors.verticalCenter: parent.verticalCenter
        sourceSize.width: Theme.iconSizeMedium
        sourceSize.height: Theme.iconSizeMedium
        highlighted: _highlighted
    }

    Label {
        id: descriptionLabel

        anchors {
            verticalCenter: parent.verticalCenter
            verticalCenterOffset: parent.implicitHeight + Theme.paddingSmall
        }
        width: parent.width
        text: description
        leftPadding: parent.leftPadding

        horizontalAlignment: parent.horizontalAlignment
        verticalAlignment: parent.verticalAlignment
        color: Theme.rgba(parent.color, Theme.opacityHigh)

        font.pixelSize: Theme.fontSizeExtraSmall
        truncationMode: parent.truncationMode
    }
}
