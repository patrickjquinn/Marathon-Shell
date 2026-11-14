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

PathView {
    id: view

    property real itemWidth: view.width
    property real itemHeight: view.height
    property int orientation: Qt.Horizontal

    property real _itemSize: orientation === Qt.Horizontal ? itemWidth : itemHeight

    // half of the centre item, plus the number of items partially or fully
    // visible in half the view
    property real _multiplier: Math.ceil((view.width/2) / view._itemSize) + (pathItemCount <= 2 ? 0 : 0.5)

    property real _prevOffset

    flickDeceleration: Theme.flickDeceleration
    maximumFlickVelocity: Theme.maximumFlickVelocity * width / Screen.height
    width: parent ? parent.width : Screen.width
    height: parent ? parent.height : Screen.width
    preferredHighlightBegin: _multiplier / pathItemCount
    preferredHighlightEnd: _multiplier / pathItemCount
    snapMode: PathView.SnapOneItem

    onOffsetChanged: {
        if (snapMode == PathView.SnapOneItem && dragging) {
            var delta = Math.abs(Math.floor(_prevOffset) - Math.floor(offset))
            if (delta == 1 || delta == count - 1) {
                offset = _prevOffset
            }
        }
        _prevOffset = offset
    }

    // show as many items on the path as possible, given the number of items
    // we can fit in the view according to itemWidth
    // itemWidth < 1 check ensures we don't divide by itemWidth when it is 0
    pathItemCount: (itemWidth < 1 || (count <= 2 && itemWidth >= width))
                   ? 2 : Math.max(3, Math.ceil(width / itemWidth) + 1)
    interactive: count > 1

    path: Path {
        id: path

        startX: orientation === Qt.Horizontal ? -(view.itemWidth * view._multiplier - view.width/2)
                                              : view.itemWidth / 2
        startY: orientation === Qt.Horizontal ? view.itemHeight / 2
                                              : -(view.itemHeight * view._multiplier - view.height/2)

        PathLine {
            x: orientation === Qt.Horizontal ? (view.pathItemCount * view.itemWidth) + path.startX
                                             : view.itemWidth / 2
            y: orientation === Qt.Horizontal ? view.itemHeight / 2
                                             : (view.pathItemCount * view.itemHeight) + path.startY
        }
    }
}
