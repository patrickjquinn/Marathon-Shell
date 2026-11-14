/****************************************************************************************
**
** Copyright (C) 2013 - 2020 Jolla Ltd.
** Copyright (c) 2019 - 2020 Open Mobile Platform LLC.
** All rights reserved.
**
** This file is part of Sailfish Silica UI component package
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
import "private/RemorsePopup.js" as RemorseJs
import "private/Util.js" as Util
import "private"

RemorseBase {
    id: remorsePopup

    readonly property bool active: state === "active"

    function execute(text, callback, timeout) {
        if (text === undefined) {
            remorsePopup.text = ""
        } else {
            remorsePopup.text = text
        }

        RemorseJs.callback = callback
        _timeout = timeout === undefined ? 4000 : timeout
        _triggered = false
        _page = Util.findPage(remorsePopup)
        if (_page) {
            parent = _page
        }
        state = "active"
    }

    function cancel() {
        _close()
        canceled()
    }

    function trigger() {
        _execute()
        _close()
    }

    function _trigger() {
        trigger()
    }

    function _close() {
        _countdown.stop()
        state = "inactive"
    }

    function _execute() {
        if (!_triggered) {
            _triggered = true
            triggered()
            if (RemorseJs.callback !== undefined) {
                RemorseJs.callback.call()
            }
        }
    }

    height: Math.max(Theme.itemSizeSmall, _labels.height + 2 * Theme.paddingMedium)
    y: -height
    z: 1
    _wideMode: screen.sizeCategory > Screen.Medium
    _screenMargin: 0
    leftMargin: {
        if (_page && _page.orientation == Orientation.Portrait && Screen.topCutout.height > Theme.paddingLarge) {
            // assuming the popup pushed down enough not to need further corner avoidance
            return Theme.horizontalPageMargin
        }

        var biggestCorner = Math.max(Screen.topLeftCorner.radius,
                                     Screen.topRightCorner.radius,
                                     Screen.bottomLeftCorner.radius,
                                     Screen.bottomRightCorner.radius)

        // popup is quite close to the edge so avoid the whole rounding area
        return Math.max(biggestCorner, Theme.horizontalPageMargin)
    }
    rightMargin: leftMargin

    states: [
        State {
            name: "active"
            PropertyChanges {
                target: _page
                showNavigationIndicator: false
            }
            PropertyChanges {
                target: remorsePopup
                visible: true
                y: (_page && _page.orientation == Orientation.Portrait ? Screen.topCutout.height : 0)
                   + Theme.paddingMedium
                _contentOpacity: 1
            }
        },
        State {
            name: "inactive"
            PropertyChanges {
                target: _page
                showNavigationIndicator: false
            }
            PropertyChanges {
                target: remorsePopup
                visible: true
                _contentOpacity: 1
            }
        }
    ]

    transitions: [
        Transition {
            to: "active"
            SequentialAnimation {
                PropertyAction { properties: "showNavigationIndicator" }
                PropertyAction { properties: "visible" }
                ParallelAnimation {
                    PropertyAnimation {
                        target: remorsePopup
                        property: "y"
                        duration: 200
                        easing.type: Easing.OutQuad
                    }
                    SequentialAnimation {
                        PauseAnimation { duration: 150 }
                        PropertyAnimation {
                            target: remorsePopup
                            property: "_contentOpacity"
                            duration: 150
                        }
                    }
                    ScriptAction {
                        script: _countdown.restart()
                    }
                }
            }
        },
        Transition {
            to: "inactive"
            SequentialAnimation {
                PropertyAnimation {
                    target: remorsePopup
                    property: "y"
                    duration: 200
                    easing.type: Easing.OutQuad
                }
                ScriptAction {
                    script: remorsePopup.state = ""
                }
            }
        }
    ]

    Connections {
        target: _page
        onStatusChanged: {
            if (_page && _page.status == PageStatus.Deactivating && _countdown.running) {
                // if the page is changed then execute immediately
                _execute()
                _close()
            }
        }
    }

    Component.onDestruction: {
        if (_countdown.running) {
            _execute()
        }
    }
}
