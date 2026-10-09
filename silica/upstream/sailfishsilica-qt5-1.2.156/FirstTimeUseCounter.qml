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
import Sailfish.Silica.private 1.0
import Nemo.Configuration 1.0

ConfigurationValue {
    property int count
    property int limit
    readonly property bool active: _active && (ignoreSystemHints || (_systemHintCoordinator.item
                                                                     && _systemHintCoordinator.item.active))
    readonly property bool _active: _initiated && count <= limit && Config.demoMode !== Config.Demo
                                    && _hintsEnabled.value
    property bool _initiated
    property bool ignoreSystemHints

    function increase() {
        if (active) {
            count = count + 1
            value = count
        }
    }
    function reset() {
        count = 0
        value = 0
    }
    function exhaust() {
        if (active) {
            count = limit +1
            value = count
        }
    }

    Component.onCompleted: {
        if (limit === 0) {
            console.log("FirstTimeUseCounter: define limit to use the counter")
        } else if (key.length === 0) {
            console.log("FirstTimeUseCounter: define valid key to use the counter")
        } else {
            count = value
            _initiated = true
        }
    }
    defaultValue: 0

    property ConfigurationValue _hintsEnabled: ConfigurationValue {
        key: "/desktop/sailfish/silica/hints_enabled"
        defaultValue: true
    }

    property var _systemHintCoordinator: Loader {
        active: _active && !ignoreSystemHints
        sourceComponent: ConfigurationValue {
            key: "/desktop/sailfish/hints/coordination_state"
            defaultValue: 3 // no system hints for existing users

            readonly property bool active: (value >= 3)
        }
    }
}
