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
import Sailfish.Silica.private 1.0

Rectangle {
    id: highlightItem

    property bool audioEnabled
    property Item highlightedItem
    property int opacityAnimationDuration: Theme.minimumPressHighlightTime
    property alias yAnimationDuration: yAnimation.duration
    property alias animateY: yBehavior.enabled
    property alias animateOpacity: opacityBehavior.enabled
    property real _highlightedItemPosition
    property bool _transientAnimateY

    property QtObject _ngfEffect

    y: _highlightedItemPosition
    color: Theme.rgba(palette.highlightBackgroundColor, Theme.highlightBackgroundOpacity)

    function clearHighlight() {
        if (highlightedItem) {
            highlightedItem.highlighted = false
        }

        highlightedItem = null
    }

    function highlight(item, container, forceAnimate) {
        // This is a change of item so we deactivate the old item (to stop non-visual feedback)
        if (!item) {
            clearHighlight()
            return
        }

        var newY = parent.mapFromItem(item, 0, item.height/2).y - highlightItem.height/2
        if (_highlightedItemPosition !== newY && highlightedItem !== null && highlightedItem !== item) {
            _transientAnimateY = true
        }

        _transientAnimateY = _transientAnimateY || !!forceAnimate

        _highlightedItemPosition = newY

        if (highlightedItem !== item) {
            if (highlightedItem) {
                highlightedItem.highlighted = false
            }
            highlightedItem = item
            if (highlightedItem) {
                highlightedItem.highlighted = true
            }
            if (audioEnabled && _ngfEffect) {
                _ngfEffect.play()
            }
        }
    }

    function moveTo(yPos) {
        _transientAnimateY = true
        _highlightedItemPosition = yPos
    }

    height: Theme.itemSizeExtraSmall
    width: parent.width
    opacity: highlightedItem ? 1.0 : 0.0

    Component.onCompleted: {
        // avoid hard dependency to ngf module
        _ngfEffect = Qt.createQmlObject("import Nemo.Ngf 1.0; NonGraphicalFeedback { event: 'pulldown_highlight' }",
                           highlightItem, 'NonGraphicalFeedback');
    }

    Connections {
        target: highlightedItem
        onWidthChanged: highlight(highlightedItem)
        onHeightChanged: highlight(highlightedItem)
    }

    Connections {
        target: parent
        onHeightChanged: highlight(highlightedItem)
    }

    Behavior on height {
        enabled: yBehavior.enabled
        NumberAnimation { duration: 100; easing.type: Easing.InOutQuad }
    }

    Behavior on opacity {
        id: opacityBehavior
        SmoothedAnimation { duration: highlightItem.opacityAnimationDuration; velocity: -1 }
    }

    Behavior on y {
        id: yBehavior

        enabled: _transientAnimateY
        SequentialAnimation {
            SmoothedAnimation {
                id: yAnimation

                duration: 100
                velocity: -1
                reversingMode: SmoothedAnimation.Immediate
            }
            PauseAnimation {
                duration: 20
            }
            PropertyAction {
                target: highlightItem
                property: "_transientAnimateY"
                value: false
            }
        }
    }
}
