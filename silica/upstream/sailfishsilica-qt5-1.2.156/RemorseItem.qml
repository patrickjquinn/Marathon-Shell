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
import "private/RemorseItem.js" as RemorseItemJs
import "private/Util.js" as Util
import "private"

RemorseBase {
    id: remorseItem

    property Item _item

    function execute(item, text, callback, timeout) {
        if (text === undefined) {
            remorseItem.text = ""
        } else {
            remorseItem.text = text
        }

        RemorseJs.callback = callback

        _timeout = timeout === undefined ? 4000 : timeout
        _triggered = false
        _page = Util.findPage(remorseItem)
        parent = item.parent
        if ('__silica_remorse_item' in parent) {
            parent.__silica_remorse_item = remorseItem
        }
        _item = item
        state = "active"
        _countdown.restart()
        RemorseItemJs.remorseItemCancel(remorseItem)
        RemorseItemJs.remorseItemActivated(remorseItem)
    }

    function cancel() {
        _close()
        if ('__silica_remorse_item' in parent) {
            parent.__silica_remorse_item = null
        }
        canceled()
        RemorseItemJs.remorseItemCancel(remorseItem)
    }

    function trigger() {
        if (_countdown.running) {
            _countdown.stop()
            return _execute(false)
        }
        return false
    }

    function _trigger() {
        remorseItem.state = "activePending"
        _execute(true)
    }

    function _close() {
        _countdown.stop()
        state = ""
    }

    function _execute(closeAfterExecute) {
        if (!_triggered) {
            _triggered = true
            RemorseItemJs.remorseItemTrigger(remorseItem, RemorseJs.callback, closeAfterExecute)
            return true
        }
        return false
    }

    opacity: 0.0
    height: Theme.itemSizeSmall
    z: 2

    states: [
        State {
            name: "active"
            PropertyChanges {
                target: remorseItem
                anchors.fill: _item
                opacity: remorseItem.width > 0
                         ? 1 - Math.abs(remorseItem.contentItem.x / (_page ? _page.width : Screen.width))
                         : 1
                visible: true
                _contentOpacity: 1
            }
            PropertyChanges {
                target: _item
                opacity: 0
            }
        },
        State {
            name: "activePending"
            extend: "active"
            PropertyChanges {
                target: remorseItem
                opacity: 0
            }
        },
        State {
            // Empty state to restore target item state without any transitions.
            name: "destroying"
        }
    ]

    transitions: [
        Transition {
            to: "active"
            SequentialAnimation {
                PropertyAction { target: remorseItem; properties: "anchors.fill,visible" }
                ParallelAnimation {
                    FadeAnimation {
                        target: remorseItem
                        duration: 200
                    }
                    SequentialAnimation {
                        PauseAnimation { duration: 150 }
                        PropertyAnimation {
                            target: remorseItem
                            property: "_contentOpacity"
                            duration: 150
                        }
                    }
                }
            }
        },
        Transition {
            to: ""
            SequentialAnimation {
                FadeAnimation {
                    target: remorseItem
                    duration: 200
                }
                PropertyAction { target: remorseItem; property: "visible" }
                ScriptAction { script: { RemorseItemJs.remorseItemDeactivated(remorseItem) }}
                FadeAnimation {
                    target: _item
                    duration: 100
                }
            }
        }
    ]

    Connections {
        target: _page
        onStatusChanged: {
            if (_page && _page.status == PageStatus.Deactivating && _countdown.running) {
                // if the page is changed then execute immediately
                _execute(false)
            }
        }
    }

    Component.onDestruction: {
        if (_countdown.running) {
            _execute(false)
        }
        RemorseItemJs.remorseItemDeactivated(remorseItem)
        state = "destroying"
    }
}
