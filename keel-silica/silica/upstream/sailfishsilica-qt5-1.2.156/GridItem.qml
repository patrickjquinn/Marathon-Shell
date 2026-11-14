/****************************************************************************************
**
** Copyright (C) 2019 Jolla Ltd.
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
import "private/Util.js" as Util
import "private"

ViewItem {
    id: gridItem

    property bool openRemorseBelow: width < Theme.itemSizeHuge
    property Item _gridView
    property Item __silica_remorse_content
    property Item _flickable

    width: _gridView ? _gridView.cellWidth : Screen.width/3
    contentHeight: _gridView ? _gridView.cellHeight : Screen.width/3
    contentItem.y: { 0 }

    Component.onCompleted: {
        _gridView = Util.findParentWithProperty(gridItem, "__silica_gridview")
        _flickable = Util.findFlickable(gridItem)
    }

    function remorseDelete(action, timeout) {
        return remorseAction("", action, timeout)
    }

    function remorseAction(text, action, timeout) {
        var previousRemorse = _gridView ? _gridView.__silica_remorse_item : null
        if (previousRemorse && previousRemorse.state == "active") {
            _gridView.__silica_remorse_item._trigger()
        }

        if (!openRemorseBelow) {
            return Remorse.itemAction(contentItem, text, action, timeout)
        } else {
            remorseContainer.active = true
            __silica_remorse_item = Remorse.itemAction(__silica_remorse_content, text, action, timeout)
            __silica_remorse_item._belowGridItem = true
            if (_gridView)
                _gridView.__silica_remorse_item = __silica_remorse_item
            return __silica_remorse_item
        }
    }

    function _calculateMenuOffset() {
        if (_gridView) {
            var columns = Math.round(_gridView.width / _gridView.cellWidth)
            _gridView._menuOpenOffsetItemsIndex = model.index - (model.index % columns) + columns
        }
    }

    StateGroup {
        states: [
            State {
                name: "menuOpen"
                when: !!(gridItem._menuItem && gridItem._menuItem.parent)

                PropertyChanges {
                    target: gridItem._menuItem
                    width: _flickable ? _flickable.width : Screen.width
                }
                PropertyChanges {
                    target: gridItem
                    z: 1000
                }
            }
        ]
        transitions: Transition {
            to: "menuOpen"
            ScriptAction {
                script: {
                    var previousRemorse = _gridView ? _gridView.__silica_remorse_item : null
                    if (previousRemorse && previousRemorse.state == "active") {
                        _gridView.__silica_remorse_item._trigger()
                    }
                    _calculateMenuOffset()
                }
            }
        }
    }

    Loader {
        id: remorseContainer

        active: false
        source: "private/GridItemRemorseContainer.qml"
    }

    Binding {
        when: !!(_gridView && model.index >= _gridView._menuOpenOffsetItemsIndex)
        target: gridItem.contentItem
        property: "y"
        value: _gridView ? _gridView.__silica_menu_height : 0
    }
}
