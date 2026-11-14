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
// Upstream: sailfishsilica-qt5-1.2.156 (Sailfish OS 5.2.0.15) PullDownMenu.qml
// Modified by Shipwright for Qt 6: geometry bindings guarded while `flickable` is still null (set in Component.onCompleted), which warned at creation.
// Modified by Shipwright for Qt 6: directory imports ("private", "..") import the module by name.
// Modified by Shipwright for Qt 6: `Screen.` qualified as `KeelSilica.Screen.` (1 places; Qt Quick's attached Screen shadows Silica's in Qt 6).
// Modified by Shipwright for Qt 6: compiled to C++ by qmlcachegen: names qualified with their object's id, `pragma ComponentBehavior: Bound` (its inner components are made only in this file), functions typed `var` (unchanged behaviour).

pragma ComponentBehavior: Bound // Modified by Shipwright for Qt 6: ids of outer objects used in inner components
import QtQuick 2.0
import Sailfish.Silica 1.0
import Sailfish.Silica.private 1.0 as SilicaPrivate
import Sailfish.Silica.private 1.0 // Modified by Shipwright for Qt 6: was import "private"
import "private/Util.js" as Util
import Sailfish.Silica 1.0 as KeelSilica // Modified by Shipwright for Qt 6: see Screen below

PulleyMenuBase {
    id: pullDownMenu

    property real topMargin: Theme.itemSizeSmall
    property real _effectiveTopMargin: topMargin
                                       + ((_page && _page.orientation == Orientation.Portrait)
                                          ? KeelSilica.Screen.topCutout.height : 0)
    property real bottomMargin: _menuLabel ? 0 : Theme.paddingLarge
    property Item _menuLabel: {
        var lastChild = contentColumn.visible && Util.childAt(contentColumn, width / 2, contentColumn.height - 1)
        if (lastChild && lastChild.hasOwnProperty("__silica_menulabel")) {
            return lastChild
        }
        return null
    }
    property real _bottomDragMargin: (_menuLabel ? _menuLabel.height : 0) + bottomMargin
    default property alias _content: contentColumn.children

    spacing: 0
    // Modified by Shipwright for Qt 6: no flickable until Component.onCompleted (avoids TypeErrors)
    y: flickable ? flickable.originY - height : 0

    _contentEnd: contentColumn.height + bottomMargin
    _contentColumn: contentColumn
    _isPullDownMenu: true
    _inactiveHeight: 0
    _activeHeight: contentColumn.height + _effectiveTopMargin + bottomMargin
    _inactivePosition: Math.round(flickable.originY - _inactiveHeight - spacing)
    _finalPosition: _inactivePosition - _activeHeight
    _menuIndicatorPosition: height - _menuItemHeight + Theme.paddingSmall - spacing
    _highlightIndicatorPosition: {
        if (_dragDistance <= (_effectiveTopMargin + _menuItemHeight)) {
            // gradually getting closer to (or inside) the lowest menu item
            return _menuIndicatorPosition
                    - ((_dragDistance / (_menuItemActivationThreshold + _bottomDragMargin))
                       * (Theme.paddingSmall + _bottomDragMargin))
        } else {
            // position to topmost item when dragged beyond the items. only briefly shown during fade out.
            // or if there are disabled items in the menu, this ensures the highlight stays at the activation point
            return height
                    - Math.min(_dragDistance - _menuItemActivationThreshold + _menuItemHeight, _contentEnd)
                    - spacing
        }
    }

    property Component background: Rectangle {
        id: bg

        anchors {
            fill: parent
            bottomMargin: (pullDownMenu.spacing - pullDownMenu._shadowHeight) * Math.min(1, pullDownMenu._dragDistance / Theme.itemSizeSmall) // Modified by Shipwright for Qt 6: qualified
        }
        opacity: pullDownMenu.active ? 1.0 : 0.0
        gradient: Gradient {
            GradientStop {
                position: 0.0
                color: Theme.rgba(pullDownMenu.backgroundColor, Theme.highlightBackgroundOpacity + 0.1)
            }
            GradientStop {
                position: (pullDownMenu.height - pullDownMenu.spacing) / bg.height
                color: Theme.rgba(pullDownMenu.backgroundColor, Theme.highlightBackgroundOpacity)
            }
            GradientStop { position: 1.0; color: Theme.rgba(pullDownMenu.backgroundColor, 0.0) }
        }
    }

    function _resetPosition(): void { // Modified by Shipwright for Qt 6: typed
        flickable.contentY = _inactivePosition
    }
    on_AtInitialPositionChanged: {
        if (!_atInitialPosition && !flickable.moving && _page && _page.orientationTransitionRunning) {
            // If this flickable has a context menu open, the menu visibility takes precedence over initial position reset
            if (('__silica_contextmenu_instance' in flickable)
                    && flickable.__silica_contextmenu_instance
                    && flickable.__silica_contextmenu_instance._open) {
                return
            }

            // If the menu was at the inactive position before the orientation transition, it should still be afterward
            SilicaPrivate.Util.asyncInvoke(_resetPosition)
        }
    }

    property Component menuIndicator // Remains for API compatibility
    onMenuIndicatorChanged: console.log("WARNING: PullDownMenu.menuIndicator is no longer supported.")

    property Item _pageStack: Util.findPageStack(pullDownMenu)

    onActiveChanged: {
        if (_pageStack) {
            _pageStack._activePullDownMenu = active ? pullDownMenu : null
        }
    }

    on_EffectiveTopMarginChanged: {
        if (_atFinalPosition) {
            resetOpenPositionTimer.start() // using timer to ensure the position properties have updated
        }
    }

    Timer {
        id: resetOpenPositionTimer
        interval: 0
        onTriggered: {
            pullDownMenu.flickable.contentY = pullDownMenu._finalPosition // Modified by Shipwright for Qt 6: qualified
        }
    }

    Column {
        id: contentColumn

        property int __silica_pulleymenu_content

        property real menuContentY: pullDownMenu.active ? pullDownMenu.height - pullDownMenu._dragDistance - pullDownMenu.spacing : -1 // Modified by Shipwright for Qt 6: qualified
        onMenuContentYChanged: {
            if (menuContentY >= 0) {
                if (pullDownMenu.flickable.dragging && !pullDownMenu._bounceBackRunning) { // Modified by Shipwright for Qt 6: qualified
                    _highlightMenuItem(contentColumn, menuContentY - y + pullDownMenu._menuItemActivationThreshold) // Modified by Shipwright for Qt 6: qualified
                } else if (pullDownMenu.quickSelect) { // Modified by Shipwright for Qt 6: qualified
                    _quickSelectMenuItem(contentColumn, menuContentY - y + pullDownMenu._menuItemHeight) // Modified by Shipwright for Qt 6: qualified
                }
            }
        }

        y: pullDownMenu._effectiveTopMargin
        width: parent.width
        visible: pullDownMenu.active // Modified by Shipwright for Qt 6: qualified
    }

    Binding {
        target: pullDownMenu.flickable // Modified by Shipwright for Qt 6: qualified
        property: "topMargin"
        value: pullDownMenu.active ? pullDownMenu.height : pullDownMenu._inactiveHeight + pullDownMenu.spacing // Modified by Shipwright for Qt 6: qualified
    }

    // Create a bottomMargin to fill the remaining space in views
    // with content size < view height.  This allows the view to
    // be positioned above the bottomMargin even when
    // its content is smaller than the available space.
    Binding {
        when: !pullDownMenu.flickable.pushUpMenu  // If there is a PushUpMenu then it will take care of it. // Modified by Shipwright for Qt 6: qualified
        target: pullDownMenu.flickable // Modified by Shipwright for Qt 6: qualified
        property: "bottomMargin"
        value: Math.max(pullDownMenu.flickable.height - pullDownMenu.flickable.contentHeight - (pullDownMenu._inactiveHeight + pullDownMenu.spacing), 0) // Modified by Shipwright for Qt 6: qualified
    }

    // If the content size is less than view height and there is no
    // push up menu, then we must also prevent moving in the wrong direction
    property real _maxDragPosition: Math.min(flickable.height - flickable.contentHeight, _inactivePosition)

    function _addToFlickable(flickableItem: var): void { // Modified by Shipwright for Qt 6: typed
        if (flickableItem.pullDownMenu !== undefined) {
            flickableItem.pullDownMenu = pullDownMenu
        } else {
            console.log('Warning: PullDownMenu must be added to an instance of SilicaFlickable.')
        }
    }

    // for testing
    function _menuContentY(): var { // Modified by Shipwright for Qt 6: typed
        return contentColumn.menuContentY
    }

    Component.onCompleted: {
        if (background) {
            background.createObject(pullDownMenu, {"z": -2})
        }
        _updateFlickable()
    }
}
