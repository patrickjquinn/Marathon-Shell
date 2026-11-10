// SPDX-FileCopyrightText: 2013-2021 Jolla Ltd
// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: BSD-3-Clause
/****************************************************************************************
**
** Copyright (C) 2013-2021 Jolla Ltd.
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
// Upstream: sailfishsilica-qt5-1.2.156 (Sailfish OS 5.2.0.15) private/VerticalScrollBase.qml
// Modified by Shipwright for Qt 6: `flickable` is bound to the nearest flickable so that bindings do not read null at creation.
// Modified by Shipwright for Qt 6: signal handlers in Connections written as functions, and handlers that use signal parameters declare them (1 places).
// Modified by Shipwright for Qt 6: imports Sailfish.Silica.private for the module's native types.
// Modified by Shipwright for Qt 6: `Screen.` qualified as `KeelSilica.Screen.` (6 places; Qt Quick's attached Screen shadows Silica's in Qt 6).
// Modified by Shipwright for Qt 6: compiled to C++ by qmlcachegen: names qualified with their object's id, functions typed `var` (unchanged behaviour).

import QtQuick 2.0
import Sailfish.Silica 1.0
import Sailfish.Silica.private 1.0 as Private
import "Util.js" as Util
import Sailfish.Silica 1.0 as KeelSilica // Modified by Shipwright for Qt 6: see Screen below
import Sailfish.Silica.private 1.0 // Modified by Shipwright for Qt 6: native types of this module

SilicaItem {
    id: root

    // Modified by Shipwright for Qt 6: found at creation, not only in Component.onCompleted (bindings below read it first)
    property Flickable flickable: Private.Util._keelFindFlickable(root)
    property Item page

    property real _headerSpacing
    property real _topMenuSpacing: flickable.pullDownMenu ? flickable.pullDownMenu.spacing : 0
    property real _bottomMenuSpacing: flickable.pushUpMenu ? flickable.pushUpMenu.spacing : 0
    property bool _inBounds: (!flickable.pullDownMenu || !flickable.pullDownMenu.active)
                             && (!flickable.pushUpMenu || !flickable.pushUpMenu.active)
    property real _sizeRatio: (flickable.height - _headerSpacing - topMargin - bottomMargin) / _range
    property real _range: flickable.contentHeight + _topMenuSpacing + _bottomMenuSpacing
    property Item _forcedParent
    property int _biggestCorner: Math.max(KeelSilica.Screen.topLeftCorner.radius,
                                          KeelSilica.Screen.topRightCorner.radius,
                                          KeelSilica.Screen.bottomLeftCorner.radius,
                                          KeelSilica.Screen.bottomRightCorner.radius)
    property bool _topOnDisplayEdge
    property bool _bottomOnDisplayEdge

    // deprecated, though never been even publicly documented
    property int margin
    // some extra padding in corners in case the config doesn't cover the last pixels with minimal rounding.
    // we assume here that the scroll decorator is placed at the edge of the screen where it needs some extra margins
    property int topMargin: Math.max(_topOnDisplayEdge ? (1.2 * _biggestCorner) : 0, margin)
    property int bottomMargin: Math.max(_bottomOnDisplayEdge ? (1.2 * _biggestCorner) : 0, margin)
    property int hideInterval: 300

    function showDecorator(): void { // Modified by Shipwright for Qt 6: typed
        timer.showDecorator = true
    }

    // If we were declared in a Flickable then our parent is contentItem rather than the Flickable itself
    onFlickableChanged: {
        parent = _forcedParent ? _forcedParent : flickable
        _updateEdges()
    }

    anchors.right: parent ? parent.right : undefined
    opacity: (timer.moving && _inBounds) || timer.running || highlighted ? 1.0 : 0.0
    visible: flickable.contentHeight > flickable.height
    Behavior on opacity { FadeAnimation { duration: 400 } }
    y: Math.max(topMargin,
                Math.min(topMargin
                         + ((parent.height / flickable.height)
                            * (_headerSpacing + (flickable.contentY - flickable.originY + _topMenuSpacing) * _sizeRatio)),
                         (parent.height - height - bottomMargin)))

    Component.onCompleted: {
        if (!flickable) {
            flickable = Util.findFlickable(root)
        }
        if (!page) {
            page = Util.findPage(root)
        }
        if (page && page["_dialogHeader"] !== undefined) {
            if (Util.findFlickable(page._dialogHeader) === flickable) {
                // The DialogHeader is a child of the flickable
                _headerSpacing = Qt.binding(function() { return page._dialogHeader._overlayHeight })
            }
        }
        _updateEdges()
    }

    Timer {
        id: timer

        property bool moving: root.flickable.movingVertically // Modified by Shipwright for Qt 6: qualified
        property bool showDecorator

        onMovingChanged: {
            if (!moving && root._inBounds) { // Modified by Shipwright for Qt 6: qualified
                showDecorator = false
                restart()
            }
        }
        onShowDecoratorChanged: if (showDecorator) restart()
        interval: showDecorator ? 800 : root.hideInterval // Modified by Shipwright for Qt 6: qualified
        onTriggered: showDecorator = false
    }

    Connections {
        target: root.flickable // Modified by Shipwright for Qt 6: qualified
        // Modified by Shipwright for Qt 6: Connections handler as a function
        function onHeightChanged(): void { _updateEdges() } // Modified by Shipwright for Qt 6: typed
    }

    function _updateEdges(): void { // Modified by Shipwright for Qt 6: typed
        if (parent && page) {
            var topCoord = parent.mapToItem(page, 0, 0)
            var bottomCoord = parent.mapToItem(page, 0, parent.height)
            _topOnDisplayEdge = topCoord.y == 0

            _bottomOnDisplayEdge = page.height == (page.isPortrait ? KeelSilica.Screen.height : KeelSilica.Screen.width)
                    && bottomCoord.y == page.height
        } else {
            _topOnDisplayEdge = false
            _bottomOnDisplayEdge = false
        }
    }
}
