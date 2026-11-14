/****************************************************************************************
**
** Copyright (C) 2019 Open Mobile Platform LLC.
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
import QtQml.Models 2.2
import Sailfish.Silica 1.0
import "Util.js" as Util

SilicaControl {
    id: root

    property Flickable flickable
    property bool allowDeletion: true
    readonly property bool isCurrentItem: _tabContainer && _tabContainer.PagedView.isCurrentItem

    property Item _tabContainer: root
    readonly property real _yOffset: flickable && flickable.pullDownMenu
            ? flickable.contentY - flickable.originY
            : 0
    property alias _cacheExpiry: cleanupTimer.interval

    implicitWidth: _tabContainer ? _tabContainer.PagedView.contentWidth : 0
    implicitHeight: {
        if (!_tabContainer) {
            return 0
        } else {
            var view = flickable && flickable.pullDownMenu ? _tabContainer.PagedView.view : null

            return view && !view.hasFooter ? view.height : _tabContainer.PagedView.contentHeight
        }
    }

    clip: !flickable || !flickable.pullDownMenu

    Component.onCompleted: {
        if (_tabContainer) {
            _tabContainer.DelegateModel.inPersistedItems = true
        }
    }

    Timer {
        id: cleanupTimer

        running: root.allowDeletion && root._tabContainer && !root._tabContainer.PagedView.exposed
        interval: 30000

        onTriggered: root._tabContainer.DelegateModel.inPersistedItems = false
    }
}
