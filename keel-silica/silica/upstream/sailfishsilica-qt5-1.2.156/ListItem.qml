/****************************************************************************************
**
** Copyright (C) 2014 Jolla Ltd.
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

ViewItem {
    id: listItem

    property bool hidden

    // deprecated
    property alias showMenuOnPressAndHold: listItem.openMenuOnPressAndHold

    function animateRemoval(delegate) {
        if (delegate === undefined) {
            delegate = listItem
        }
        removeComponent.createObject(delegate, { "target": delegate })
    }

    function showMenu(properties) {
        console.warn("ListItem::showMenu is deprecated in Sailfish Silica package 0.25.6 (Dec 2017), use ListItem::openMenu instead.")
        console.trace()
        return openMenu(properties)
    }

    function hideMenu() {
        console.warn("ListItem::hideMenu is deprecated in Sailfish Silica package 0.25.6 (Dec 2017), use ListItem::closeMenu instead.")
        console.trace()
        closeMenu()
    }

    function remorseDelete(action, timeout) {
        return remorseAction("", action, timeout)
    }

    function remorseAction(text, action, timeout) {
        return Remorse.itemAction(contentItem, text, action, timeout)
    }

    Component {
        id: removeComponent

        RemoveAnimation {
            running: true
        }
    }

    Item {
        states: State {
            when: listItem.hidden
            name: "hidden"
            PropertyChanges {
                target: listItem
                contentHeight: 0
                enabled: false
                opacity: 0.0
            }
        }

        transitions: Transition {
            NumberAnimation {
                properties: "contentHeight, opacity"
                easing.type: Easing.InOutQuad
                duration: 200
            }
        }
    }
}
