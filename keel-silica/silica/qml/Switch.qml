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
// Upstream: sailfishsilica-qt5-1.2.156 (Sailfish OS 5.2.0.15) Switch.qml
// Modified by Shipwright for Qt 6: signal handlers in Connections written as functions, and handlers that use signal parameters declare them (1 places).
// Modified by Shipwright for Qt 6: directory imports ("private", "..") import the module by name.
// Modified by Shipwright for Qt 6: compiled to C++ by qmlcachegen: names qualified with their object's id, functions typed `var` (unchanged behaviour).

import QtQuick 2.0
import Sailfish.Silica 1.0
import Sailfish.Silica.private 1.0
import Sailfish.Silica.private 1.0 // Modified by Shipwright for Qt 6: was import "private"

SilicaMouseArea {
    id: switchItem

    property bool checked
    property alias iconSource: image.source //XXX Deprecated
    property alias icon: image
    property bool down: pressed && containsMouse && !DragFilter.canceled
    property bool busy
    property bool automaticCheck: true

    // Modified by Shipwright for Qt 6: signal parameter declared
    onPressed: function(mouse) { switchItem.DragFilter.begin(mouse.x, mouse.y) }
    onCanceled: switchItem.DragFilter.end()
    onPreventStealingChanged: if (preventStealing) switchItem.DragFilter.end()

    onClicked: {
        if (automaticCheck) {
            checked = !checked
        }
    }

    width: column.width
    height: column.height
    highlighted: down

    Column {
        id: column

        spacing: switchItem.palette.colorScheme === Theme.DarkOnLight ? Theme.paddingMedium : -Theme.paddingLarge
        anchors.centerIn: parent

        GlassItem {
            id: indicator

            opacity: switchItem.enabled ? 1.0 : Theme.opacityLow
            color: highlighted ? switchItem.palette.highlightColor
                               : dimmed ? switchItem.palette.primaryColor
                                        : Theme.lightPrimaryColor
            backgroundColor: switchItem.checked || switchItem.busy ? switchItem.palette.backgroundGlowColor : "transparent" // Modified by Shipwright for Qt 6: qualified
            anchors.horizontalCenter: parent.horizontalCenter
            dimmed: !switchItem.checked // Modified by Shipwright for Qt 6: qualified
            falloffRadius: switchItem.checked ? defaultFalloffRadius // Modified by Shipwright for Qt 6: qualified
                                   : (switchItem.palette.colorScheme === Theme.LightOnDark ? 0.075 : 0.1)
            Behavior on falloffRadius {
                NumberAnimation { duration: switchItem.busy ? 450 : 50; easing.type: Easing.InOutQuad } // Modified by Shipwright for Qt 6: qualified
            }
            // KLUDGE: Behavior and State don't play well together
            // http://qt-project.org/doc/qt-5/qtquick-statesanimations-behaviors.html
            // force re-evaluation of brightness when returning to default state
            brightness: { return 1.0 }
            Behavior on brightness {
                NumberAnimation { duration: switchItem.busy ? 450 : 50; easing.type: Easing.InOutQuad } // Modified by Shipwright for Qt 6: qualified
            }
        }
        Icon {
            id: image

            opacity: switchItem.enabled ? 1.0 : Theme.opacityLow
            anchors.horizontalCenter: parent.horizontalCenter
        }
        states: State {
            when: switchItem.busy
            PropertyChanges {
                target: indicator
                brightness: busyTimer.brightness
                dimmed: false
                falloffRadius: busyTimer.falloffRadius
                opacity: 1.0
            }
        }
        Timer {
            id: busyTimer

            property real brightness: Theme.opacityLow
            property real falloffRadius: 0.075

            running: switchItem.busy && Qt.application.active // Modified by Shipwright for Qt 6: qualified
            interval: 500
            repeat: true
            onRunningChanged: {
                brightness = switchItem.checked ? 1.0 : Theme.opacityLow // Modified by Shipwright for Qt 6: qualified
                falloffRadius = switchItem.checked ? indicator.defaultFalloffRadius : 0.075 // Modified by Shipwright for Qt 6: qualified
            }
            onTriggered: {
                falloffRadius = falloffRadius === 0.075 ? indicator.defaultFalloffRadius : 0.075
                brightness = brightness == Theme.opacityLow ? 1.0 : Theme.opacityLow
            }
        }
    }

    // for testing
    function _indicator(): var { // Modified by Shipwright for Qt 6: typed
        return indicator
    }
}
