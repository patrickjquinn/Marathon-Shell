/****************************************************************************************
**
** Copyright (C) 2013-2019 Jolla Ltd.
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

BackgroundItem {
    id: viewItem

    property var menu
    property bool menuOpen: _menuItem != null && _menuItem._open
    property bool openMenuOnPressAndHold: true

    property Item _menuItem
    property bool _menuItemCreated
    property bool _connectPressAndHold: openMenuOnPressAndHold && menu !== null && menu !== undefined

    property Item __silica_remorse_item
    onMenuOpenChanged: {
        var view = viewItem.ListView.view || viewItem.GridView.view
        if (view && ('__silica_contextmenu_instance' in view)) {
            if (menuOpen) {
                view.__silica_contextmenu_instance = _menuItem
            } else if (viewItem.__silica_contextmenu_instance === _menuItem) {
                view.__silica_contextmenu_instance = null
            }
        }
    }

    function openMenu(properties) {
        if (menu == null) {
            return null
        }
        if (_menuItem == null) {
            _initMenuItem(properties)
        } else {
            for (var prop in properties) {
                if (prop in _menuItem) {
                    _menuItem[prop] = properties[prop]
                }
            }
        }
        if (_menuItem) {
            _menuItem.open(viewItem)
        }
        return _menuItem
    }

    function closeMenu() {
        if (_menuItem != null) {
            _menuItem.close()
        }
    }

    function _initMenuItem(properties) {
        if (_menuItem || (menu == null)) {
            return
        }
        var result
        if (menu.createObject !== undefined) {
            result = menu.createObject(viewItem, properties || {})
            _menuItemCreated = true
            result.closed.connect(function() { _menuItem.destroy() })
        } else {
            result = menu
            _menuItemCreated = false
            for (var prop in properties) {
                if (prop in result) {
                    result[prop] = properties[prop]
                }
            }
        }
        _menuItem = result
    }

    highlighted: down || menuOpen
    implicitHeight: menuOpen ? _menuItem.height + contentItem.height : contentItem.height
    contentHeight: Theme.itemSizeSmall
    _backgroundColor: Theme.rgba(palette.highlightBackgroundColor,
                                 _showPress && !menuOpen ? Theme.highlightBackgroundOpacity : 0)

    on_ConnectPressAndHoldChanged: {
        if (_connectPressAndHold) {
            viewItem.pressAndHold.connect(handlePressAndHold)
        } else {
            viewItem.pressAndHold.disconnect(handlePressAndHold)
        }
    }

    function handlePressAndHold() {
        if (down)
            openMenu()
    }

    onMenuChanged: {
        if (menu != null && _menuItem != null) {
            if (_menuItemCreated) {
                // delete the previously created context menu instance
                _menuItem.destroy()
            }
            _menuItem = null
        }
    }

    Component.onDestruction: {
        if (_menuItem != null) {
            _menuItem.close()
            _menuItem._parentDestroyed()
        }
    }
}
