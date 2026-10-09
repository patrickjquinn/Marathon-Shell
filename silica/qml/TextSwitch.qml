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
// Upstream: sailfishsilica-qt5-1.2.156 (Sailfish OS 5.2.0.15) TextSwitch.qml
// Modified by Shipwright for Qt 6: signal handlers in Connections written as functions, and handlers that use signal parameters declare them (1 places).
// Modified by Shipwright for Qt 6: directory imports ("private", "..") import the module by name.
// Modified by Shipwright for Qt 6: `Screen.` qualified as `KeelSilica.Screen.` (1 places; Qt Quick's attached Screen shadows Silica's in Qt 6).
// Modified by Shipwright for Qt 6: compiled to C++ by qmlcachegen: names qualified with their object's id, functions typed `var` (unchanged behaviour).

import QtQuick 2.0
import Sailfish.Silica 1.0
import Sailfish.Silica.private 1.0
import Sailfish.Silica.private 1.0 // Modified by Shipwright for Qt 6: was import "private"
import Sailfish.Silica 1.0 as KeelSilica // Modified by Shipwright for Qt 6: see Screen below

SilicaMouseArea {
    id: root

    property alias text: label.text
    property alias description: desc.text
    property alias _label: label

    property bool checked
    property bool automaticCheck: true
    property real leftMargin: Theme.horizontalPageMargin
    property real rightMargin: Theme.horizontalPageMargin
    property real _rightPadding
    property bool down: pressed && containsMouse && !DragFilter.canceled
    property bool busy

    // This is only used by ButtonGroup - if ButtonGroup is removed, this should be also:
    property int __silica_textswitch

    width: parent ? parent.width : KeelSilica.Screen.width
    implicitHeight: Math.max(toggle.height, desc.y + desc.height)

    highlighted: down || pressTimer.running

    Item {
        id: toggle

        width: Theme.itemSizeExtraSmall
        height: Theme.itemSizeSmall
        anchors {
            left: parent.left; leftMargin: root.leftMargin - Theme.paddingLarge
        }

        GlassItem {
            id: indicator

            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            opacity: root.enabled ? 1.0 : Theme.opacityLow
            dimmed: !root.checked // Modified by Shipwright for Qt 6: qualified
            falloffRadius: root.checked ? defaultFalloffRadius // Modified by Shipwright for Qt 6: qualified
                                   : (root.palette.colorScheme === Theme.LightOnDark ? 0.075 : 0.1)
            Behavior on falloffRadius {
                NumberAnimation { duration: root.busy ? 450 : 50; easing.type: Easing.InOutQuad } // Modified by Shipwright for Qt 6: qualified
            }
            // KLUDGE: Behavior and State don't play well together
            // http://qt-project.org/doc/qt-5/qtquick-statesanimations-behaviors.html
            // force re-evaluation of brightness when returning to default state
            brightness: { return 1.0 }
            Behavior on brightness {
                NumberAnimation { duration: root.busy ? 450 : 50; easing.type: Easing.InOutQuad } // Modified by Shipwright for Qt 6: qualified
            }
            color: highlighted ? root.palette.highlightColor
                               : dimmed ? root.palette.primaryColor
                                        : Theme.lightPrimaryColor
            backgroundColor: root.checked || root.busy ? root.palette.backgroundGlowColor : "transparent" // Modified by Shipwright for Qt 6: qualified
        }
        states: State {
            when: root.busy
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

            running: root.busy && Qt.application.active // Modified by Shipwright for Qt 6: qualified
            interval: 500
            repeat: true
            onRunningChanged: {
                brightness = root.checked ? 1.0 : Theme.opacityLow // Modified by Shipwright for Qt 6: qualified
                falloffRadius = root.checked ? indicator.defaultFalloffRadius : 0.075 // Modified by Shipwright for Qt 6: qualified
            }
            onTriggered: {
                falloffRadius = falloffRadius === 0.075 ? indicator.defaultFalloffRadius : 0.075
                brightness = brightness == Theme.opacityLow ? 1.0 : Theme.opacityLow
            }
        }
    }
    Label {
        id: label

        width: parent.width - toggle.width - root.leftMargin - root.rightMargin - root._rightPadding
        opacity: root.enabled ? 1.0 : Theme.opacityLow
        anchors {
            verticalCenter: toggle.verticalCenter
            // center on the first line if there are multiple lines
            verticalCenterOffset: lineCount > 1 ? (lineCount-1)*height/lineCount/2 : 0
            left: toggle.right
            leftMargin: root.palette.colorScheme === Theme.DarkOnLight ? Theme.paddingMedium : 0
        }
        wrapMode: Text.Wrap
    }
    Label {
        id: desc

        width: label.width
        height: text.length ? (implicitHeight + Theme.paddingMedium) : 0
        opacity: root.enabled ? 1.0 : Theme.opacityLow
        anchors.top: label.bottom
        anchors.left: label.left
        wrapMode: Text.Wrap
        font.pixelSize: Theme.fontSizeExtraSmall
        color: highlighted ? root.palette.secondaryHighlightColor : root.palette.secondaryColor
    }
    Timer {
        id: pressTimer
        interval: Theme.minimumPressHighlightTime
    }

    // Modified by Shipwright for Qt 6: signal parameter declared
    onPressed: function(mouse) {
        root.DragFilter.begin(mouse.x, mouse.y)
        pressTimer.restart()
    }
    onCanceled: {
        root.DragFilter.end()
        pressTimer.stop()
    }
    onPreventStealingChanged: if (preventStealing) root.DragFilter.end()

    onClicked: {
        if (automaticCheck) {
            checked = !checked
        }
    }

    // for testing
    function _indicator(): var { // Modified by Shipwright for Qt 6: typed
        return indicator
    }
}
