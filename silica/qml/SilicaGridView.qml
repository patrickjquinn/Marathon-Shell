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
// Upstream: sailfishsilica-qt5-1.2.156 (Sailfish OS 5.2.0.15) SilicaGridView.qml
// Modified by Shipwright for Qt 6: directory imports ("private", "..") import the module by name.

import QtQuick 2.5
import Sailfish.Silica 1.0
import Sailfish.Silica.private 1.0
import Sailfish.Silica.private 1.0 // Modified by Shipwright for Qt 6: was import "private"
import "private/FastScrollAnimation.js" as FastScroll

GridView {
    id: gridView

    // Property quickScrollEnabled deprecated. Use quickScroll instead.
    property alias quickScrollEnabled: quickScrollItem.quickScroll
    property alias quickScroll: quickScrollItem.quickScroll
    property alias quickScrollAnimating: quickScrollItem.quickScrollAnimating
    property alias quickScrollVisible: quickScrollItem.quickScrollVisible
    property Item pullDownMenu
    property Item pushUpMenu
    property QtObject _scrollAnimation
    property bool _pulleyDimmerActive: pullDownMenu && pullDownMenu._activeDimmer
                                       || pushUpMenu && pushUpMenu._activeDimmer

    property alias _quickScrollItem: quickScrollItem
    property alias _quickScrollRightMargin: quickScrollItem.rightMargin

    property Item __silica_contextmenu_instance
    property Item __silica_remorse_item: null
    property real __silica_menu_height: Math.max(__silica_contextmenu_instance
                                                 ? __silica_contextmenu_instance.height : 0,
                                                 __silica_remorse_height)
    property real __silica_remorse_height

    NumberAnimation {
        id: remorseHeightAnimation

        target: gridView
        property: "__silica_remorse_height"
        duration: 200
        to: 0.0
        easing.type: Easing.InOutQuad
    }

    on__Silica_remorse_itemChanged: {
        if (!__silica_remorse_item) {
            remorseHeightAnimation.restart()
        }
    }

    property int __silica_gridview
    property int _menuOpenOffsetItemsIndex: { -1 }

    function scrollToTop() {
        FastScroll.scrollToTop(gridView, quickScrollItem)
    }
    function scrollToBottom() {
        FastScroll.scrollToBottom(gridView, quickScrollItem)
    }
    // Modified by Shipwright for Qt 6: positionViewAt*() go through Util, which
    // defers them while the header or footer is being created (a call from the
    // header's own handlers otherwise corrupts Qt 6's header creation and
    // crashes when the view is destroyed; see Keel's private/misc.cpp).
    function positionViewAtBeginning() {
        Util._keelPositionView(gridView, "positionViewAtBeginning")
    }
    function positionViewAtEnd() {
        Util._keelPositionView(gridView, "positionViewAtEnd")
    }
    function positionViewAtIndex(index, mode) {
        Util._keelPositionView(gridView, "positionViewAtIndex", index, mode)
    }

    pixelAligned: true
    flickDeceleration: Theme.flickDeceleration
    maximumFlickVelocity: Theme.maximumFlickVelocity
    cacheBuffer: Theme.itemSizeMedium * 8
    boundsBehavior: (pullDownMenu && pullDownMenu._activationPermitted)
                    || (pushUpMenu && pushUpMenu._activationPermitted)
                    ? Flickable.DragOverBounds : Flickable.StopAtBounds

    BoundsBehavior { flickable: gridView }

    QuickScroll {
        id: quickScrollItem

        flickable: gridView
    }
}
