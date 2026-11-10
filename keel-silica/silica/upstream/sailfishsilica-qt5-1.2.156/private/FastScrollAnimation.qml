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

Item {
    id: fastScrollAnimation

    property real _duration
    property real fadeDistance: Screen.width
    property real defaultDuration: 300
    property Flickable flickable
    property QuickScroll quickScroll
    property bool animating: scrollAnimation.running || leaveAnimation.running || returnAnimation.running
    property bool scrollingToTop

    function scrollToTop() {
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
    function scrollToBottom() {
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
    function overMinimumDistance(to) {
        return (Math.abs(flickable.contentY - to) > 2*fadeDistance)
    }
    function scrollToTopTarget() {
        return flickable.pullDownMenu ? flickable.pullDownMenu._inactivePosition : flickable.originY - flickable.topMargin
    }
    function scrollToBottomTarget() {
        return flickable.pushUpMenu ? flickable.pushUpMenu._inactivePosition
                                    : flickable.originY + flickable.contentHeight - flickable.height + flickable.bottomMargin
    }
    function cancelBounceBack() {
        if (flickable.pushUpMenu) {
            flickable.pushUpMenu.cancelBounceBack()
        }
        if (flickable.pullDownMenu) {
            flickable.pullDownMenu.cancelBounceBack()
        }
    }

    Binding {
        target: quickScroll
        property: "quickScrollAnimating"
        value: animating
    }

    MouseArea {
        id: mouseBlocker

        z: 1000
        states: State {
            when: flickable && animating
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
                duration: _duration
                to: 0.0
                easing.type: Easing.InQuad
            }
            NumberAnimation {
                id: fadeOut

                target: flickable
                property: "contentY"
                duration: _duration
            }
        }
        ScriptAction {
            script: {
                // preload the new delegates
                if (scrollingToTop) {
                    flickable.contentY = scrollToTopTarget()
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
                if (scrollingToTop) {
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
                duration: _duration
                to: 1.0
                easing.type: Easing.OutQuad
            }
            NumberAnimation {
                id: fadeIn

                target: flickable
                property: "contentY"
                duration: _duration
                easing.type: Easing.OutQuad
            }
        }
    }
}
