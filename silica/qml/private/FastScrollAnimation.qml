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
// Upstream: sailfishsilica-qt5-1.2.156 (Sailfish OS 5.2.0.15) private/FastScrollAnimation.qml
// Modified by Shipwright for Qt 6: imports Sailfish.Silica.private for the module's native types.
// Modified by Shipwright for Qt 6: `Screen.` qualified as `KeelSilica.Screen.` (1 places; Qt Quick's attached Screen shadows Silica's in Qt 6).
// Modified by Shipwright for Qt 6: compiled to C++ by qmlcachegen: names qualified with their object's id, functions typed `var` (unchanged behaviour).

import QtQuick 2.0
import Sailfish.Silica 1.0
import Sailfish.Silica 1.0 as KeelSilica // Modified by Shipwright for Qt 6: see Screen below
import Sailfish.Silica.private 1.0 // Modified by Shipwright for Qt 6: native types of this module

Item {
    id: fastScrollAnimation

    property real _duration
    property real fadeDistance: KeelSilica.Screen.width
    property real defaultDuration: 300
    property Flickable flickable
    property QuickScroll quickScroll
    property bool animating: scrollAnimation.running || leaveAnimation.running || returnAnimation.running
    property bool scrollingToTop

    function scrollToTop(): void { // Modified by Shipwright for Qt 6: typed
        scrollingToTop = true
        if (overMinimumDistance(scrollToTopTarget())) {
            fadeOut.to = flickable.contentY - fadeDistance
            _duration = defaultDuration
            leaveAnimation.start()
        } else {
            shortScrollContentYAnimation.to = scrollToTopTarget()
            scrollAnimation.start()
        }
    }
    function scrollToBottom(): void { // Modified by Shipwright for Qt 6: typed
        scrollingToTop = false
        if (overMinimumDistance(scrollToBottomTarget())) {
            fadeOut.to = flickable.contentY + fadeDistance
            _duration = defaultDuration
            leaveAnimation.start()
        } else {
            shortScrollContentYAnimation.to = scrollToBottomTarget()
            scrollAnimation.start()
        }
    }
    function overMinimumDistance(to: var): var { // Modified by Shipwright for Qt 6: typed
        return (Math.abs(flickable.contentY - to) > 2*fadeDistance)
    }
    function scrollToTopTarget(): var { // Modified by Shipwright for Qt 6: typed
        return flickable.pullDownMenu ? flickable.pullDownMenu._inactivePosition : flickable.originY - flickable.topMargin
    }
    function scrollToBottomTarget(): var { // Modified by Shipwright for Qt 6: typed
        return flickable.pushUpMenu ? flickable.pushUpMenu._inactivePosition
                                    : flickable.originY + flickable.contentHeight - flickable.height + flickable.bottomMargin
    }
    function cancelBounceBack(): void { // Modified by Shipwright for Qt 6: typed
        if (flickable.pushUpMenu) {
            flickable.pushUpMenu.cancelBounceBack()
        }
        if (flickable.pullDownMenu) {
            flickable.pullDownMenu.cancelBounceBack()
        }
    }

    Binding {
        target: fastScrollAnimation.quickScroll // Modified by Shipwright for Qt 6: qualified
        property: "quickScrollAnimating"
        value: fastScrollAnimation.animating // Modified by Shipwright for Qt 6: qualified
    }

    MouseArea {
        id: mouseBlocker

        z: 1000
        states: State {
            when: fastScrollAnimation.flickable && fastScrollAnimation.animating // Modified by Shipwright for Qt 6: qualified
            PropertyChanges {
                target: mouseBlocker
                parent: flickable
                width: flickable.width
                height: flickable.height
            }
        }
    }
    SequentialAnimation {
        id: scrollAnimation

        ScriptAction { script: fastScrollAnimation.cancelBounceBack() }
        ParallelAnimation {
            SmoothedAnimation {
                id: shortScrollContentYAnimation

                target: flickable
                property: "contentY"
                velocity: 4000
                maximumEasingTime: 100
                easing.type: Easing.InOutExpo
            }
            SmoothedAnimation {
                target: flickable
                property: "opacity"
                velocity: 4000
                to: 1.0
                maximumEasingTime: 100
                easing.type: Easing.InOutExpo
            }
        }
    }

    SequentialAnimation {
        id: leaveAnimation

        ScriptAction { script: fastScrollAnimation.cancelBounceBack() }
        ParallelAnimation {
            NumberAnimation {
                target: flickable
                property: "opacity"
                duration: fastScrollAnimation._duration // Modified by Shipwright for Qt 6: qualified
                to: 0.0
                easing.type: Easing.InQuad
            }
            NumberAnimation {
                id: fadeOut

                target: flickable
                property: "contentY"
                duration: fastScrollAnimation._duration // Modified by Shipwright for Qt 6: qualified
            }
        }
        ScriptAction {
            script: {
                // preload the new delegates
                if (fastScrollAnimation.scrollingToTop) { // Modified by Shipwright for Qt 6: qualified
                    fastScrollAnimation.flickable.contentY = scrollToTopTarget() // Modified by Shipwright for Qt 6: qualified
                    flickable.contentY = flickable.contentY + fadeDistance
                } else {
                    flickable.contentY = scrollToBottomTarget()
                    flickable.contentY = flickable.contentY - fadeDistance
                }
            }
        }
        PauseAnimation { duration: 100 }
        ScriptAction {
            script: {
                if (fastScrollAnimation.scrollingToTop) { // Modified by Shipwright for Qt 6: qualified
                    fadeIn.to = scrollToTopTarget()
                    fadeIn.from = fadeIn.to + fadeDistance
                } else {
                    fadeIn.to = scrollToBottomTarget()
                    fadeIn.from = fadeIn.to - fadeDistance
                }
                returnAnimation.start()
            }
        }
    }
    SequentialAnimation {
        id: returnAnimation

        ParallelAnimation {
            NumberAnimation {
                target: flickable
                property: "opacity"
                duration: fastScrollAnimation._duration // Modified by Shipwright for Qt 6: qualified
                to: 1.0
                easing.type: Easing.OutQuad
            }
            NumberAnimation {
                id: fadeIn

                target: flickable
                property: "contentY"
                duration: fastScrollAnimation._duration // Modified by Shipwright for Qt 6: qualified
                easing.type: Easing.OutQuad
            }
        }
    }
}
