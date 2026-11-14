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
import "private"
import "private/Util.js" as Util

PulleyMenuBase {
    id: pushUpMenu

    property real topMargin: _menuLabel ? 0 : Theme.paddingLarge
    property real bottomMargin: Theme.itemSizeSmall
    property Item _menuLabel: {
        var firstChild = contentColumn.visible && Util.childAt(contentColumn, width/2, 1)
        if (firstChild && firstChild.hasOwnProperty("__silica_menulabel")) {
            return firstChild
        }
        return null
    }
    property real _topDragMargin: (_menuLabel ? _menuLabel.height : 0) + topMargin
    default property alias _content: contentColumn.children

    spacing: 0
    y: flickable.originY + flickable.contentHeight + _contentDeficit

    _contentEnd: contentColumn.height + topMargin
    _contentColumn: contentColumn
    _isPullDownMenu: false
    _inactiveHeight: 0
    _activeHeight: contentColumn.height + topMargin + bottomMargin
    _inactivePosition: Math.round(y + _inactiveHeight + spacing - flickable.height)
    _finalPosition: _inactivePosition + _activeHeight
    _menuIndicatorPosition: -Theme.paddingSmall + spacing
    _highlightIndicatorPosition: Math.max(Math.min(_dragDistance, _contentEnd)
                                          - _menuItemHeight + spacing,
                                          _menuIndicatorPosition + (_dragDistance / (_menuItemHeight + _topDragMargin)
                                                                    * (Theme.paddingSmall + _topDragMargin)))

    property Component background: Rectangle {
        id: bg

        anchors {
            fill: parent
            topMargin: (pushUpMenu.spacing - _shadowHeight) * Math.min(1, _dragDistance/Theme.itemSizeSmall)
        }
        opacity: pushUpMenu.active ? 1.0 : 0.0
        gradient: Gradient {
            GradientStop { position: 0.0; color: Theme.rgba(pushUpMenu.backgroundColor, 0.0) }
            GradientStop {
                position: 1.0-(pushUpMenu.height-pushUpMenu.spacing)/bg.height
                color: Theme.rgba(pushUpMenu.backgroundColor, Theme.highlightBackgroundOpacity)
            }
            GradientStop { position: 1.0; color: Theme.rgba(pushUpMenu.backgroundColor, Theme.highlightBackgroundOpacity + 0.1) }
        }
    }

    property Component menuIndicator // Remains for API compatibility
    onMenuIndicatorChanged: console.log("WARNING: PushUpMenu.menuIndicator is no longer supported.")

    Column {
        id: contentColumn

        property int __silica_pulleymenu_content

        property real menuContentY: pushUpMenu.active ? _dragDistance + pushUpMenu.spacing : -1
        onMenuContentYChanged: {
            if (menuContentY >= 0) {
                if (flickable.dragging && !_bounceBackRunning) {
                    _highlightMenuItem(contentColumn, menuContentY - y - _menuItemHeight)
                } else if (quickSelect) {
                    _quickSelectMenuItem(contentColumn, menuContentY - y - _menuItemHeight)
                }
            }
        }

        y: pushUpMenu.spacing + pushUpMenu.topMargin
        width: parent.width
        visible: active
    }

    Binding {
        target: flickable
        property: "bottomMargin"
        value: (active ? pushUpMenu.height : _inactiveHeight + spacing) + _contentDeficit
    }

    // Ensure that we are positioned at the bottom limit, even if the content does not fill the height
    property real _contentDeficit: Math.max(flickable.height - (flickable.contentHeight + _pdmHeight + spacing), 0)
    property real _pdmHeight: flickable.pullDownMenu
                              ? (flickable.pullDownMenu._inactiveHeight + flickable.pullDownMenu.spacing)
                              : 0

    function _addToFlickable(flickableItem) {
        if (flickableItem.pushUpMenu !== undefined) {
            flickableItem.pushUpMenu = pushUpMenu
        } else {
            console.log('Warning: PushUpMenu must be added to an instance of SilicaFlickable.')
        }
    }

    // for testing
    function _menuContentY() {
        return contentColumn.menuContentY
    }

    Component.onCompleted: {
        if (background) {
            background.createObject(pushUpMenu, {"z": -2})
        }
        _updateFlickable()
    }
}
