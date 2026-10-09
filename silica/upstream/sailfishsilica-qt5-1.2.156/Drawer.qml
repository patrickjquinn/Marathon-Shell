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

SilicaItem {
    id: root

    property bool open

    property int dock: Dock.Top

    property real _progress: open ? 1.0 : 0.0
    property bool opened: open || menuProgressAnimation.running

    property real backgroundSize: dock == Dock.Left || dock == Dock.Right ? width / 2 : height / 2

    property alias backgroundItem: backgroundItem
    property alias background: backgroundItem.children

    property alias foregroundItem: foregroundItem
    property alias foreground: foregroundItem.children

    default property alias data: foregroundItem.data

    property bool hideOnMinimize: false
    property bool hideEvent: !Qt.application.active && hideOnMinimize
    onHideEventChanged: {
        if (hideEvent) {
            open = false
            _completeAnimations()
        }
    }

    property bool _immediate

    Behavior on _progress {
        enabled: !_immediate
        NumberAnimation {
            id: menuProgressAnimation
            duration: 300
            easing.type: Easing.InOutQuad
        }
    }

    onDockChanged: _completeAnimations()

    function _completeAnimations() {
        menuProgressAnimation.complete()
        backgroundOpacityAnimation.complete()
    }

    function show(immediate) {
        _immediate = !!immediate
        open = true
        _immediate = false
    }

    function hide(immediate) {
        _immediate = !!immediate
        open = false
        _immediate = false
    }


    Item {
        id: backgroundClip

        visible: root.opened
        clip: root.opened
        opacity: dimmerRect.opacity * 2
        anchors {
            left: root.dock == Dock.Right ? foregroundItem.right : root.left
            top: root.dock == Dock.Bottom ? foregroundItem.bottom : root.top
            right: root.dock == Dock.Left ? foregroundItem.left : root.right
            bottom: root.dock == Dock.Top ? foregroundItem.top : root.bottom
        }

        Item {
            id: backgroundItem

            x: root.dock == Dock.Right ? backgroundClip.width - root.backgroundSize : 0
            y: root.dock == Dock.Bottom ? backgroundClip.height - root.backgroundSize : 0

            width: root.dock == Dock.Left || root.dock == Dock.Right
                   ? root.backgroundSize
                   : root.width
            height: root.dock == Dock.Top || root.dock == Dock.Bottom
                    ? root.backgroundSize
                    : root.height
        }
    }

    Rectangle {
        id: dimmerRect

        anchors.fill: foregroundItem
        color: root.palette.highlightDimmerColor

        // The dimmed rectangle provides a seam between the background and foreground.  It shouldn't
        // pop in instantly but should be distinct for the majority of the animation so the animation
        // easing is cubic instead of the normal quad.
        opacity: root.open ? Theme.opacityHigh : 0.0
        Behavior on opacity {
            enabled: !_immediate
            NumberAnimation {
                id: backgroundOpacityAnimation
                duration: 300
                easing.type: Easing.InOutCubic
            }
        }
    }

    Item {
        id: foregroundItem

        clip: root.opened
        anchors {
            fill: parent
            leftMargin: root.dock == Dock.Left ? root._progress * root.backgroundSize : 0
            topMargin: root.dock == Dock.Top ? root._progress * root.backgroundSize : 0
            rightMargin: root.dock == Dock.Right ? root._progress * root.backgroundSize : 0
            bottomMargin: root.dock == Dock.Bottom ? root._progress * root.backgroundSize : 0
        }
    }
}
