/****************************************************************************************
**
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

import QtQuick 2.0
import Sailfish.Silica 1.0
import "private/Util.js" as Util

SilicaItem {
    id: placeholder

    property Item flickable
    property alias text: mainLabel.text
    property alias textFormat: mainLabel.textFormat
    property alias hintText: hintLabel.text
    // deprecated
    property real verticalOffset
    property real leftMargin: Theme.horizontalPageMargin
    property real rightMargin: Theme.horizontalPageMargin
    readonly property int _yBase: __silica_applicationwindow_instance._rotatingItem.height/3 - height/2 + verticalOffset

    // stay centered in screen
    x: (flickable ? flickable.originX : 0) + (__silica_applicationwindow_instance._rotatingItem.width - width) / 2
    y: (flickable ? flickable.originY : 0) + _yBase

    width: flickable ? flickable.width : screen.width
    height: mainLabel.height + (hintLabel.text.length > 0 ? hintLabel.height : 0)
    enabled: false
    opacity: enabled ? 1.0 : 0

    onEnabledChanged: {
        if (enabled && !_content) {
            _content = activeContent.createObject(placeholder)
        }
    }

    property Item _content
    property alias _mainLabel: mainLabel
    property alias _hintLabel: hintLabel

    Behavior on opacity { FadeAnimation { duration: 300 } }

    InfoLabel { id: mainLabel }
    Text {
        id: hintLabel

        x: leftMargin
        anchors.top: mainLabel.bottom
        width: parent.width - parent.leftMargin - parent.rightMargin
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        textFormat: mainLabel.textFormat
        font {
            pixelSize: Theme.fontSizeLarge
            family: Theme.fontFamilyHeading
        }
        color: placeholder.palette.highlightColor
        opacity: Theme.opacityLow
    }

    Component {
        // content we don't need until we're active
        id: activeContent

        PulleyAnimationHint {
            flickable: placeholder.flickable
            width: parent.width - 2 * Theme.paddingLarge
            height: flickable ? flickable.height - 2 * Theme.paddingLarge : 0
            anchors.horizontalCenter: parent.horizontalCenter
            y: -_yBase + Theme.paddingLarge
        }
    }

    Component.onCompleted: {
        if (!flickable) {
            flickable = Util.findFlickable(placeholder)
            if (flickable) {
                parent = flickable.contentItem
            }
        }
        if (!flickable) {
            console.log("ViewPlaceholder requires a SilicaFlickable parent. Instance with text:", placeholder.text)
        }
    }
}
