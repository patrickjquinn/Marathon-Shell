/****************************************************************************************
**
** Copyright (C) 2018 Jolla Ltd.
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

import QtQuick 2.6
import Sailfish.Silica 1.0
import Sailfish.Silica.private 1.0 as Private

Private.AutoScrollController {
    id: attached

    onScrollHorizontally: {
        if (Math.abs(flickable.contentX - x) < 5) {
            flickable.contentX = x
            contentXAnimation.stop()
        } else if (animated || contentXAnimation.running) {
            contentXAnimation.to = x
            contentXAnimation.restart()
        } else {
            flickable.contentX = x
        }
    }

    onScrollVertically: {
        if (Math.abs(flickable.contentY - y) < 5) {
            flickable.contentY = y
            contentYAnimation.stop()
        } else if (animated || contentYAnimation.running) {
            contentYAnimation.to = y
            contentYAnimation.restart()
        } else {
            flickable.contentY = y
        }
    }

    SmoothedAnimation {
        id: contentXAnimation

        target: attached.flickable
        property: "contentX"
        easing.type: Easing.InOutQuad
        duration: 160
        onStopped: attached.flickable.returnToBounds()
        running: false
    }

    SmoothedAnimation {
        id: contentYAnimation

        target: attached.flickable
        property: "contentY"
        easing.type: Easing.InOutQuad
        duration: 160
        onStopped: attached.flickable.returnToBounds()
        running: false
    }

    StateGroup {
        states: [
            State {
                when: attached.modal

                PropertyChanges {
                    target: attached.flickable
                    interactive: false
                    onWidthChanged: attached.scheduleHorizontalScroll()
                    onHeightChanged: attached.scheduleVerticalScroll()
                }
            }, State {
                when: attached.active

                PropertyChanges {
                    target: attached.flickable
                    onWidthChanged: attached.scheduleHorizontalScroll()
                    onHeightChanged: attached.scheduleVerticalScroll()
                }
            }
        ]
    }
}
