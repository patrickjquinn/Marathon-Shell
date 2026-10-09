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

Label {
    id: menuItem

    property bool down

    signal earlyClick
    signal clicked
    signal delayedClick

    property int __silica_menuitem
    property int _duration: 50
    property color _enabledColor: (down || highlighted) ^ _invertColors ? palette.highlightColor : palette.primaryColor
    property color _disabledColor: Theme.rgba(palette.secondaryColor, Theme.opacityLow)
    property bool _invertColors
    on_InvertColorsChanged: _duration = 200

    x: Theme.horizontalPageMargin
    width: parent ? parent.width - 2*Theme.horizontalPageMargin : Screen.width
    // Reduce height if inside pulley menu content item on smaller screens
    height: screen.sizeCategory <= Screen.Medium && parent && parent.hasOwnProperty('__silica_pulleymenu_content')
            ? Theme.itemSizeExtraSmall : Theme.itemSizeSmall
    horizontalAlignment: implicitWidth > width && truncationMode != TruncationMode.None
                         ? Text.AlignLeft : Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
    color: enabled ? _enabledColor : _disabledColor

    // Descriptive labels like a label defining a menu item action should not truncate.
    // If there absolutely is no space left to fit the translation just limit the font size.
    fontSizeMode: Text.HorizontalFit
    minimumPixelSize: Theme.fontSizeExtraSmall
    truncationMode: TruncationMode.Fade

    Behavior on color {
        SequentialAnimation {
            ColorAnimation { duration: _duration }
            ScriptAction { script: _duration = 50 }
        }
    }
}
