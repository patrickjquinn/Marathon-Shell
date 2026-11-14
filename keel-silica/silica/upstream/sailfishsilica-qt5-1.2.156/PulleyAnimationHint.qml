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

MouseArea {
    id: root

    property Flickable flickable
    property real pullDownDistance: Theme.itemSizeExtraSmall + (menu && menu._bottomDragMargin || 0)
    property Item menu: flickable && (pushUpHint ? flickable.pushUpMenu : flickable.pullDownMenu)
    property real _menuInactivePos: menu !== null ? menu._inactivePosition : 0
    property bool pushUpHint
    property bool flickableDragged: flickable && flickable.dragging
    property bool _bounceBack

    enabled: menu && menu.enabled && menu.visible

    onClicked: {
        if (menu._atInitialPosition) {
            _bounceBack = false
            menuPeek.start()
        }
    }

    onPressed: {
        if (menuPeek.running) {
            menuPeek.pause()
            menu._hinting = false
        }
    }

    onReleased: {
        if (menuPeek.paused) {
            menu._hinting = true
            menuPeek.resume()
        }
    }

    onFlickableDraggedChanged: {
        if (menuPeek.running || menuPeek.paused) {
            menuPeek.stop()
            menu._hinting = false
        }
    }

    SequentialAnimation {
        id: menuPeek
        PropertyAction {
            target: menu
            property: "_hinting"
            value: true
        }
        PropertyAction {
            target: menu
            property: "active"
            value: true
        }
        NumberAnimation {
            target: flickable
            property: "contentY"
            to: _menuInactivePos + (pushUpHint ? pullDownDistance : -pullDownDistance)
            duration: 400*Math.max(1.0, pullDownDistance/Theme.itemSizeLarge)
            easing.type: Easing.OutCubic
        }
        PropertyAction {
            target: root
            property: "_bounceBack"
            value: true
        }
        NumberAnimation {
            target: flickable
            property: "contentY"
            to: _menuInactivePos
            duration: 400 // Matches bounceback animation duration
            easing.type: Easing.InOutCubic
        }
        PropertyAction {
            target: root
            property: "_bounceBack"
            value: false
        }
        PropertyAction {
            target: menu
            property: "active"
            value: false
        }
        PropertyAction {
            target: menu
            property: "_hinting"
            value: false
        }
    }

    Binding {
        id: bounceBackOverride

        when: _bounceBack
        target: menu
        property: "_bounceBackRunning"
        value: menuPeek.running
    }

    Component.onCompleted: {
        if (!flickable) {
            var item = Util.findFlickable(root)
            if (item) {
                flickable = item
            } else {
                console.log("PulleyAnimationHint requires a SilicaFlickable parent")
            }
        }
    }
}
