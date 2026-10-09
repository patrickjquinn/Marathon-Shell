// SPDX-FileCopyrightText: 2014 Jolla Ltd
// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: BSD-3-Clause
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
// Upstream: sailfishsilica-qt5-1.2.156 (Sailfish OS 5.2.0.15) TouchInteractionHint.qml
// Modified by Shipwright for Qt 6: signal handlers in Connections written as functions, and handlers that use signal parameters declare them (1 places).
// Modified by Shipwright for Qt 6: `Screen.` qualified as `KeelSilica.Screen.` (6 places; Qt Quick's attached Screen shadows Silica's in Qt 6).
// Modified by Shipwright for Qt 6: the first PauseAnimation's duration is set only while the group is stopped (_startGroup), not bound to _interrupted, which the group's own ScriptActions change while it runs (Qt 6.4 crashed in QAnimationGroupJob::ungroupChild).

import QtQuick 2.2
import Sailfish.Silica 1.0
import "private/HintReferenceCounter.js" as HintReferenceCounter
import Sailfish.Silica 1.0 as KeelSilica // Modified by Shipwright for Qt 6: see Screen below

Icon {
    id: root

    property real startX: {
        if (!parent)
            return 0

        switch (interactionMode) {
        case TouchInteraction.Swipe:
        case TouchInteraction.Pull:
            return (direction === TouchInteraction.Right ? parent.width/3 : 2*parent.width/3) - width/2
        case TouchInteraction.EdgeSwipe:
            return direction === TouchInteraction.Right ? -width : parent.width
        default:
            console.log("Invalid TouchInteraction.Mode value defined")
        }
    }
    property real startY: {
        if (!parent)
            return 0

        switch (interactionMode) {
        case TouchInteraction.Swipe:
        case TouchInteraction.Pull:
            return (direction === TouchInteraction.Down ? parent.height/3 : 2*parent.height/3) - height/2
        case TouchInteraction.EdgeSwipe:
            return direction === TouchInteraction.Down ? -height : parent.height
        default:
            console.log("Invalid TouchInteraction.Mode value defined")
        }
    }

    property real distance: (interactionMode == TouchInteraction.Pull && KeelSilica.Screen.sizeCategory >= KeelSilica.Screen.Large)
                            ? KeelSilica.Screen.width / 4
                            : KeelSilica.Screen.width / 2
    property int direction: TouchInteraction.Right
    property int interactionMode: TouchInteraction.Swipe
    property alias running: animationGroup.running
    property alias alwaysRunToEnd: animationGroup.alwaysRunToEnd
    // TODO: Would be better if this was alias to animationGroup having loop count set, so that running wouldn't
    // get false between the loops, but that doesn't play well along with code that adjusts direction
    // between the loops. Could be considered a Qt bug too. See JB#43752
    property int loops: 3
    property int _loopsRun
    property bool _stopped: true
    property bool _testMode
    property bool _interrupted
    property bool _restartingGroup // Modified by Shipwright for Qt 6
    readonly property real _durationScale: KeelSilica.Screen.sizeCategory >= KeelSilica.Screen.Large ? 1.5 : 1

    color: palette.primaryColor

    anchors {
        horizontalCenter: direction === TouchInteraction.Up || direction === TouchInteraction.Down
                          ? parent.horizontalCenter : undefined
        verticalCenter: direction === TouchInteraction.Left || direction === TouchInteraction.Right
                        ? parent.verticalCenter : undefined
    }

    function start() {
        _stopped = false
        _loopsRun = 0
        _startGroup() // Modified by Shipwright for Qt 6
    }
    // Modified by Shipwright for Qt 6: starts the group with the resume
    // pause set while it is stopped.
    function _startGroup() {
        if (animationGroup.running) {
            animationGroup.restart()
            return
        }
        resumePause.duration = _interrupted ? 800 : 0
        animationGroup.start()
    }
    function _restartGroup() {
        _restartingGroup = true
        animationGroup.stop()
        _restartingGroup = false
        _startGroup()
    }
    function restart() {
        stop()
        start()
    }
    function stop() {
        _stopped = true
        animationGroup.stop()
    }

    onRunningChanged: {
        if (running) {
            HintReferenceCounter.increase()
        } else {
            HintReferenceCounter.decrease()
            // Animation.Infinite == -2
            if (!_restartingGroup && !_stopped && (loops < 0 || _loopsRun < loops)) { // Modified by Shipwright for Qt 6
                _startGroup()
            }
        }
    }

    Component.onDestruction: if (running) HintReferenceCounter.decrease()

    opacity: 0.0
    source: {
        switch (interactionMode) {
        case TouchInteraction.EdgeSwipe:
            return "image://theme/graphics-edge-swipe-arrow"
        case TouchInteraction.Swipe:
        case TouchInteraction.Pull:
        default:
            return "image://theme/graphic-gesture-hint"
        }
    }

    rotation: {
        if (interactionMode !== TouchInteraction.EdgeSwipe)
            return 0

        switch (direction) {
        case TouchInteraction.Left:
            return -90
        case TouchInteraction.Up:
            return 0
        case TouchInteraction.Right:
            return 90
        case TouchInteraction.Down:
            return 180
        }
    }

    Connections {
        target: Qt.application
        // Modified by Shipwright for Qt 6: Connections handler as a function
        function onActiveChanged() {
            if (animationGroup.running) {
                if (Qt.application.active) {
                    _restartGroup() // Modified by Shipwright for Qt 6
                } else {
                    animationGroup.pause()
                }
            }
        }
    }

    // Don't use an animator. It can cause assert in animation framework
    FadeAnimation {
        id: hideAnimation

        target: root
        running: !animationGroup.running
        to: 0
    }

    SequentialAnimation {
        id: animationGroup

        PauseAnimation {
            id: resumePause // Modified by Shipwright for Qt 6
            // avoids animation glitches when resuming after app becomes active
            duration: 0 // Modified by Shipwright for Qt 6: set by _startGroup()
        }

        ScriptAction {
            script: {
                _interrupted = true
                switch (direction) {
                case TouchInteraction.Up:
                case TouchInteraction.Down:
                    root.y = startY
                    break
                case TouchInteraction.Left:
                case TouchInteraction.Right:
                    root.x = startX
                    break
                default:
                    break
                }
            }
        }

        ParallelAnimation {
            FadeAnimator {
                target: root
                to: 1
            }
            SequentialAnimation {
                PauseAnimation { duration: _testMode ? 10 : (800 * root._durationScale - 300) }
                OpacityAnimator {
                    target: root
                    from: 1
                    to: interactionMode === TouchInteraction.Pull ? 1 : 0
                    easing.type: Easing.InCubic
                    duration: _testMode ? 10 : 300
                }
            }
            XAnimator {
                target: root
                from: {
                    switch (direction) {
                    case TouchInteraction.Up:
                    case TouchInteraction.Down:
                        return root.x
                    case TouchInteraction.Left:
                    case TouchInteraction.Right:
                        return startX
                    default:
                        console.log("Invalid TouchInteraction.Direction value defined")
                        return 0
                    }
                }
                to: {
                    switch (direction) {
                    case TouchInteraction.Up:
                    case TouchInteraction.Down:
                        return root.x
                    case TouchInteraction.Left:
                        return startX - distance
                    case TouchInteraction.Right:
                        return startX + distance
                    default:
                        console.log("Invalid TouchInteraction.Direction value defined")
                        return 0
                    }
                }
                easing.type: interactionMode === TouchInteraction.Pull ? Easing.Linear : Easing.InQuad
                duration: _testMode ? 20 : (800 * root._durationScale)
            }
            YAnimator {
                target: root
                from: {
                    switch (direction) {
                    case TouchInteraction.Up:
                    case TouchInteraction.Down:
                        return startY
                    case TouchInteraction.Left:
                    case TouchInteraction.Right:
                        return root.y
                    default:
                        console.log("Invalid TouchInteraction.Direction value defined")
                        return 0
                    }
                }

                to: {
                    switch (direction) {
                    case TouchInteraction.Up:
                        return startY - distance
                    case TouchInteraction.Down:
                        return startY + distance
                    case TouchInteraction.Left:
                    case TouchInteraction.Right:
                        return root.y
                    default:
                        console.log("Invalid TouchInteraction.Direction value defined")
                        return 0
                    }
                }
                easing.type: interactionMode === TouchInteraction.Pull ? Easing.Linear : Easing.InQuad
                duration: _testMode ? 20 : (800 * root._durationScale)
            }
        }

        SequentialAnimation {
            id: pullReleaseIndication

            property bool enabled: interactionMode === TouchInteraction.Pull

            SequentialAnimation {
                loops: 2
                OpacityAnimator {
                    target: root
                    from: pullReleaseIndication.enabled ? 1 : 0
                    to: 0.1
                    duration: pullReleaseIndication.enabled ? 200 : 0
                }
                OpacityAnimator {
                    target: root
                    from: 0.1
                    to: pullReleaseIndication.enabled ? 1 : 0
                    duration: pullReleaseIndication.enabled ? 100 : 0
                }
            }
            OpacityAnimator {
                target: root
                from: pullReleaseIndication.enabled ? 1 : 0
                to: 0
                duration: pullReleaseIndication.enabled ? 200 : 0
            }
        }

        PauseAnimation { duration: _testMode ? 10 : 800 }
        ScriptAction { script: { _interrupted = false; _loopsRun++ } }
    }
}
