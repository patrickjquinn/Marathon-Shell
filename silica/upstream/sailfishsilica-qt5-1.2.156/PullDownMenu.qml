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
import Sailfish.Silica.private 1.0 as SilicaPrivate
import "private"
import "private/Util.js" as Util

PulleyMenuBase {
    id: pullDownMenu

    property real topMargin: Theme.itemSizeSmall
    property real _effectiveTopMargin: topMargin
                                       + ((_page && _page.orientation == Orientation.Portrait)
                                          ? Screen.topCutout.height : 0)
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
    y: flickable.originY - height

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
            bottomMargin: (pullDownMenu.spacing - _shadowHeight) * Math.min(1, _dragDistance / Theme.itemSizeSmall)
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

    function _resetPosition() {
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
            flickable.contentY = _finalPosition
        }
    }

    Column {
        id: contentColumn

        property int __silica_pulleymenu_content

        property real menuContentY: pullDownMenu.active ? pullDownMenu.height - _dragDistance - pullDownMenu.spacing : -1
        onMenuContentYChanged: {
            if (menuContentY >= 0) {
                if (flickable.dragging && !_bounceBackRunning) {
                    _highlightMenuItem(contentColumn, menuContentY - y + _menuItemActivationThreshold)
                } else if (quickSelect) {
                    _quickSelectMenuItem(contentColumn, menuContentY - y + _menuItemHeight)
                }
            }
        }

        y: pullDownMenu._effectiveTopMargin
        width: parent.width
        visible: active
    }

    Binding {
        target: flickable
        property: "topMargin"
        value: active ? pullDownMenu.height : _inactiveHeight + spacing
    }

    // Create a bottomMargin to fill the remaining space in views
    // with content size < view height.  This allows the view to
    // be positioned above the bottomMargin even when
    // its content is smaller than the available space.
    Binding {
        when: !flickable.pushUpMenu  // If there is a PushUpMenu then it will take care of it.
        target: flickable
        property: "bottomMargin"
        value: Math.max(flickable.height - flickable.contentHeight - (_inactiveHeight + pullDownMenu.spacing), 0)
    }

    // If the content size is less than view height and there is no
    // push up menu, then we must also prevent moving in the wrong direction
    property real _maxDragPosition: Math.min(flickable.height - flickable.contentHeight, _inactivePosition)

    function _addToFlickable(flickableItem) {
        if (flickableItem.pullDownMenu !== undefined) {
            flickableItem.pullDownMenu = pullDownMenu
        } else {
            console.log('Warning: PullDownMenu must be added to an instance of SilicaFlickable.')
        }
    }

    // for testing
    function _menuContentY() {
        return contentColumn.menuContentY
    }

    Component.onCompleted: {
        if (background) {
            background.createObject(pullDownMenu, {"z": -2})
        }
        _updateFlickable()
    }
}
