/****************************************************************************************
**
** Copyright (C) 2013-2021 Jolla Ltd.
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
import Sailfish.Silica.Background 1.0

VerticalScrollBase {
    id: scrollbar

    property alias text: label.text
    property alias description: description.text
    property int headerHeight
    property int stepSize: -1

    property int rightMargin: highlighted ? Theme.itemSizeExtraLarge : column.x
    Behavior on rightMargin { NumberAnimation { duration: 200; easing.type: Easing.InOutQuad }}

    topMargin: Math.max(Theme.paddingLarge, _biggestCorner)
    bottomMargin: Math.max(Theme.paddingLarge, _biggestCorner)
    height: Math.max(Theme.itemSizeExtraSmall, column.height + 2*Theme.paddingSmall)
    width: column.width + column.x + rightMargin

    anchors.rightMargin: Theme.paddingMedium
    hideInterval: 2000
    highlighted: mouse.pressed
    visible: flickable.contentHeight > 2*flickable.height
    _range: flickable.contentHeight + _topMenuSpacing + _bottomMenuSpacing - parent.height

    ColorBackground {
        property real contrast: scrollbar.highlighted ? 1.65 : 1.35

        anchors.fill: parent
        radius: Theme.paddingMedium
        color: palette.colorScheme === Theme.LightOnDark
               ? Qt.darker(palette.highlightBackgroundColor, contrast)
               : Qt.lighter(palette.highlightBackgroundColor, contrast)

        roundedCorners: (Corners.TopRight | Corners.BottomLeft)
    }

    Column {
        id: column

        x: Theme.paddingMedium + Theme.paddingSmall
        anchors.verticalCenter: parent.verticalCenter

        Label {
            id: label
        }
        Label {
            id: description
        }
    }

    MouseArea {
        id: mouse

        property real startY

        z: 1000
        x: scrollbar.x
        parent: flickable.parent
        states: State {
            when: !mouse.pressed
            PropertyChanges {
                target: mouse
                y: scrollbar.y
            }
        }

        width: scrollbar.width
        height: scrollbar.height
        preventStealing: true
        visible: scrollbar.visible

        onParentChanged: startY = scrollbar.y - height/2
        onPositionChanged: {
            var relative = (mouse.y + startY - scrollbar.height + scrollbar.topMargin)
                    / (scrollbar.parent.height - scrollbar.topMargin - scrollbar.bottomMargin - scrollbar.height/2)
            var min = flickable.originY - _topMenuSpacing

            var absolute = relative * _range
            if (stepSize > 0) {
                var topMargin = flickable.pullDownMenu ? flickable.pullDownMenu.bottomMargin : 0
                absolute = topMargin - headerHeight + stepSize * (Math.round(relative * _range / stepSize))
            }

            flickable.contentY = Math.min(Math.max(min, min + absolute), min + _range)
        }
    }
}
