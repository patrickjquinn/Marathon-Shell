// SPDX-FileCopyrightText: 2013 Jolla Ltd
// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: BSD-3-Clause
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
// Upstream: sailfishsilica-qt5-1.2.156 (Sailfish OS 5.2.0.15) BackgroundItem.qml
// Modified by Shipwright for Qt 6: signal handlers in Connections written as functions, and handlers that use signal parameters declare them (1 places).
// Modified by Shipwright for Qt 6: `Screen.` qualified as `KeelSilica.Screen.` (1 places; Qt Quick's attached Screen shadows Silica's in Qt 6).
// Modified by Shipwright for Qt 6: compiled to C++ by qmlcachegen: names qualified with their object's id, functions typed `var` (unchanged behaviour).

import QtQuick 2.0
import Sailfish.Silica 1.0
import Sailfish.Silica.private 1.0
import Sailfish.Silica 1.0 as KeelSilica // Modified by Shipwright for Qt 6: see Screen below

SilicaMouseArea {
    id: item

    property bool down: pressed && containsMouse && !DragFilter.canceled && !pressDelayTimer.running
    property color highlightedColor: Theme.rgba(palette.highlightBackgroundColor, Theme.highlightBackgroundOpacity)
    property alias contentHeight: content.height
    property alias contentWidth: content.width
    property alias contentX: content.x
    property bool _pressEffectDelay: true

    property bool _showPress: highlighted || pressTimer.running
    property alias contentItem: content
    property alias _backgroundColor: content.color
    property real _screenMargin: Theme.paddingLarge

    default property alias children: content.data

    width: parent ? parent.width : KeelSilica.Screen.width
    implicitHeight: Theme.itemSizeSmall

    DragFilter.screenMargin: item._screenMargin

    highlighted: down

    // Modified by Shipwright for Qt 6: signal parameter declared
    onPressed: function(mouse) { item.DragFilter.begin(mouse.x, mouse.y) }
    onCanceled: item.DragFilter.end()

    onPreventStealingChanged: if (preventStealing) item.DragFilter.end()

    Rectangle {
        id: content

        width: parent.width
        height: item.height

        color: item._showPress ? item.highlightedColor : "transparent" // Modified by Shipwright for Qt 6: qualified
    }

    Timer {
        id: pressTimer

        interval: Theme.minimumPressHighlightTime
        running: item.pressed && !pressDelayTimer.running
    }

    Timer {
        id: pressDelayTimer

        interval: 48
        running: item.pressed && item._pressEffectDelay
    }
}
