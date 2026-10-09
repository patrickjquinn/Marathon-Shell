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
import "private/Util.js" as Util

Item {
    id: resultsList

    property alias delegate: resultsView.delegate
    property alias model: resultsView.model
    readonly property alias count: resultsView.count
    property alias cacheBuffer: resultsView.cacheBuffer

    property real itemHeight: -1
    property real maximumVisibleHeight: Screen.height

    property Flickable flickable

    property alias currentItem: resultsView.currentItem
    property alias currentIndex: resultsView.currentIndex

    property alias menuOpen: resultsView.menuOpen

    function _listStartPosition() {
        return y + mapToItem(flickable.contentItem, 0, 0).y
    }

    property real _screenTopPosition: y + (flickable.contentY - flickable.originY)
    property real _maxOffset: Math.max(height - maximumVisibleHeight, 0)
    property real _listOffset: Math.min(Math.max(_screenTopPosition - _listStartPosition(), 0), _maxOffset)

    property Item _listView: resultsView

    width: parent.width
    implicitHeight: resultsView._contentHeight

    Component.onCompleted: {
        if (itemHeight == -1) {
            console.log('Warning: itemHeight must be specified for ColumnView.')
        }
        if (!flickable) {
            flickable = Util.findFlickable(resultsList)
        }
    }

    ListView {
        id: resultsView

        // ContextMenu should not treat this item as a flickable
        property int __silica_hidden_flickable

        property Item __silica_contextmenu_instance
        property bool menuOpen: __silica_contextmenu_instance && __silica_contextmenu_instance._open
        property real _menuHeight: menuOpen
                  ? __silica_contextmenu_instance._displayHeight
                  : 0
        property real _originYOffset: originY
        onOriginYChanged: {
            if (!menuOpen) {
                _originYOffset = originY
            }
        }
        onMenuOpenChanged: _originYOffset = originY

        // We have to calculate our own contentHeight, as changing contentY causes contentHeight
        // to change when the ListView is estimating contentHeight (which occurs when the context
        // menu is open) - binding to the real contentHeight causes binding loops
        property real _contentHeight: (resultsView.count * itemHeight) + _menuHeight
        property real _displayHeight: Math.min(resultsList.height, resultsList.maximumVisibleHeight)

        width: parent.width
        height: Math.min(_contentHeight, _displayHeight)

        y: Math.max(resultsList._listOffset, 0)
        contentY: y + _originYOffset

        currentIndex: -1
        interactive: false
        clip: true
        cacheBuffer: Math.max(0, resultsList.itemHeight * 6)
    }
}

