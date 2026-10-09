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
import "HintReferenceCounter.js" as HintReferenceCounter

Item {
    property int count
    property bool initialized

    anchors.centerIn: parent
    width: parent ? (pageStack.verticalOrientation ? parent.width : parent.height) : Screen.width
    height: parent ? (pageStack.verticalOrientation ? parent.height : parent.width) : Screen.height
    rotation: pageStack.currentOrientation === Orientation.Landscape
              ? 90
              : pageStack.currentOrientation === Orientation.PortraitInverted
                ? 180
                : pageStack.currentOrientation === Orientation.LandscapeInverted
                  ? 270
                  : 0

    InteractionHintLabel {
        //% "Swipe over left or right edge to return to home"
        text: qsTrId("components-la-swipe_left_or_right_to_return_to_home")
        anchors.bottom: parent.bottom
        opacity: initialized && count < 2 ? 1.0 : 0.0
        Behavior on opacity { FadeAnimation { duration: 1000 } }
    }
    TouchInteractionHint {
        id: leftSwipeHint

        startX: -width
        direction: TouchInteraction.Right
        interactionMode: TouchInteraction.EdgeSwipe
        anchors.verticalCenter: parent.verticalCenter
        loops: 1
        onRunningChanged: {
            if (!running) {
                count = count + 1
                if (count < 2) {
                    rightSwipeHint.start()
                }
            }
        }
    }
    TouchInteractionHint {
        id: rightSwipeHint

        startX: parent.width
        direction: TouchInteraction.Left
        interactionMode: TouchInteraction.EdgeSwipe
        anchors.verticalCenter: parent.verticalCenter
        loops: 1
        onRunningChanged: if (!running) leftSwipeHint.start()
    }
    Timer {
        running: Qt.application.active
        interval: 1000
        onTriggered: {
            if (HintReferenceCounter.count === 0) {
                initialized = true
                rightSwipeHint.start()
                running = false
            }
        }
    }
}
