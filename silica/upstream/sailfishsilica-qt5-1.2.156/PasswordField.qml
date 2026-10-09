/****************************************************************************************
**
** Copyright (C) 2013-2015 Jolla Ltd.
** Copyright (C) 2020 Open Mobile Platform LLC.
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

TextField {
    id: root

    property bool showEchoModeToggle: true
    property int passwordEchoMode: TextInput.Password

    property bool _usePasswordEchoMode: true

    // Used by SettingsPasswordField for overriding toggle behavior
    property bool _automaticEchoModeToggle: true

    signal _echoModeToggleClicked

    width: parent ? parent.width : Screen.width
    echoMode: _usePasswordEchoMode ? passwordEchoMode : TextInput.Normal
    inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase

    //% "Password"
    label: qsTrId("components-la-password")

    // Hide the password when user leaves the app
    Connections {
        target: Qt.application
        onActiveChanged: if (!Qt.application.active && text.length > 0) _usePasswordEchoMode = true
    }

    rightItem: Row {
        visible: root.errorHighlight || showEchoModeToggle
        height: Math.max(passwordVisibilityButton.height, errorIconContainer.height)

        Item {
            id: errorIconContainer

            visible: root.errorHighlight
            width: root._errorIcon.width
            height: root._errorIcon.height
        }

        IconButton {
            id: passwordVisibilityButton

            width: icon.width + 2*Theme.paddingMedium
            height: icon.height

            enabled: showEchoModeToggle
            opacity: showEchoModeToggle ? 1.0 : 0.0
            Behavior on opacity { FadeAnimation {}}
            visible: opacity > 0

            onClicked: {
                if (_automaticEchoModeToggle) {
                    root._usePasswordEchoMode = !root._usePasswordEchoMode
                }
                _echoModeToggleClicked()
            }

            icon.source: "image://theme/icon-splus-" + (root.echoMode == TextInput.Password ? "show-password"
                                                                                            : "hide-password")
        }
        states: State {
            when: root.errorHighlight
            PropertyChanges {
                target: root._errorIcon
                parent: errorIconContainer
            }
        }
    }
}
