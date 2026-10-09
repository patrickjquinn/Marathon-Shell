// SPDX-FileCopyrightText: 2019 Jolla Ltd
// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: BSD-3-Clause
/****************************************************************************************
**
** Copyright (C) 2019 Jolla Ltd.
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
// Upstream: sailfishsilica-qt5-1.2.156 (Sailfish OS 5.2.0.15) private/Cursor.qml
// Modified by Shipwright for Qt 6: signal handlers in Connections written as functions, and handlers that use signal parameters declare them (3 places).
// Modified by Shipwright for Qt 6: imports Sailfish.Silica.private for the module's native types.

import QtQuick 2.0
import Sailfish.Silica 1.0
import Sailfish.Silica.private 1.0 as Private
import Sailfish.Silica.private 1.0 // Modified by Shipwright for Qt 6: native types of this module

Private.SilicaRectangle {
    id: cursor

    property bool toggled
    readonly property alias active: timer.running
    property Item editor: parent
    property QtObject preedit

    property bool _blinkEnabled: true

    onActiveChanged: if (active) toggled = true

    function reset() {
        if (active) {
            timer.restart()
            toggled = true
        }
    }

    visible: active && (toggled || !_blinkEnabled)
    color: palette.primaryColor
    width: Math.floor(Theme.dp(2))

    Timer {
        id: timer

        repeat: true
        interval: 800 // TODO: use Qt.styleHints.cursorFlashTime ?
        running: editor.activeFocus && editor.selectionStart === editor.selectionEnd
                 && Qt.application.active
        onTriggered: toggled = !toggled
    }
    Connections {
        target: active ? editor : null
        // Modified by Shipwright for Qt 6: Connections handler as a function
        function onTextChanged() { reset() }
        // Modified by Shipwright for Qt 6: Connections handler as a function
        function onCursorPositionChanged() { reset() }
    }
    Connections {
        target: active ? preedit : null
        // Modified by Shipwright for Qt 6: Connections handler as a function
        function onTextChanged() { reset() }
    }
}
