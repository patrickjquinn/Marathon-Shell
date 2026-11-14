// SPDX-FileCopyrightText: 2014 Jolla Ltd
// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: BSD-3-Clause
/****************************************************************************************
**
** Copyright (C) 2014 Jolla Ltd.
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
// Upstream: sailfishsilica-qt5-1.2.156 (Sailfish OS 5.2.0.15) private/PageEdgeTransition.qml
// Modified by Shipwright for Qt 6: imports Sailfish.Silica.private for the module's native types.
// Modified by Shipwright for Qt 6: compiled to C++ by qmlcachegen: names qualified with their object's id, functions typed `var` (unchanged behaviour).

import QtQuick 2.2
import Sailfish.Silica 1.0
import Sailfish.Silica.private 1.0 // Modified by Shipwright for Qt 6: native types of this module

SilicaItem {
    id: transition

    // Visualizes the edge of the page exiting the view
    property Item stack
    property alias transitionDuration: animator.duration
    property bool active: container && container.parent
    property Item container: stack._currentContainer === null || stack._currentContainer.transitionPartner === null
                                 ? null
                                 : (stack._currentContainer.page.status === PageStatus.Activating
                                    ? stack._currentContainer.transitionPartner
                                    : stack._currentContainer)
    property bool landscape: container && container.page.isLandscape

    width: parent && container ? (landscape ? container.width : container.width/2)
                               : 0
    height: parent && container ? (landscape ? container.height/2 : container.height)
                                : 0
    x: parent && container && !landscape ? (useAnimator ? container.width/2
                                                        : (container.x < 0 ? width : 0))
                                         : 0
    y: parent && container && landscape ? (useAnimator ? container.height/2
                                                       : (container.y < 0 ? height : 0))
                                        : 0
    parent: active ? container : null

    property bool useAnimator: active && container.useAnimator

    OpacityAnimator {
        id: animator

        target: grad
        easing.type: Easing.InOutQuad
        from: 0.0
        to: 0.6
        running: transition.useAnimator // Modified by Shipwright for Qt 6: qualified
    }

    Rectangle {
        id: grad

        anchors.centerIn: parent
        width: transition.landscape ? parent.width : parent.height // Modified by Shipwright for Qt 6: qualified
        height: transition.landscape ? parent.height : parent.width // Modified by Shipwright for Qt 6: qualified
        color: transition.palette.highlightDimmerColor
        opacity: !transition.useAnimator && transition.active // Modified by Shipwright for Qt 6: qualified
                 ? Math.min(Theme.opacityHigh,
                            Math.abs(transition.container.lateralOffset / transition.container.width) * 0.7) // Modified by Shipwright for Qt 6: qualified
                 : 0.0
        rotation: transition.landscape ? ((transition.container && transition.container.y < 0) || transition.useAnimator ? 180 : 0) // Modified by Shipwright for Qt 6: qualified
                            : ((transition.container && transition.container.x < 0) || transition.useAnimator ? 90 : 270) // Modified by Shipwright for Qt 6: qualified
        gradient: Gradient {
            GradientStop { position: 0.0; color: transition.palette.highlightDimmerColor }
            GradientStop { position: 0.7; color: transition.palette.highlightDimmerColor }
            GradientStop { position: 1.0; color: "transparent" }
        }
    }
}
