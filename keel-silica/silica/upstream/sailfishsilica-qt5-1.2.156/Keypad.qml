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
import Sailfish.Silica.private 1.0 as Private
import "private"

SilicaControl {
    id: dialer

    property alias voiceMailIconSource: voiceMailIcon.source
    //% "pause"
    property var vanityDialNumbers: ["", "abc", "def", "ghi", "jkl", "mno", "pqrs", "tuv", "wxyz", qsTrId("components-bt-pause"), "+", ""]
    property bool vanityDialNumbersVisible: true
    property bool symbolsVisible: true
    property color textColor: palette.primaryColor
    property color pressedTextColor: palette.highlightColor
    property color secondaryTextColor: palette.secondaryColor
    property color pressedSecondaryTextColor: palette.secondaryHighlightColor
    property alias pressedButtonColor: pressedButtonBackground.color
    property bool preventStealing: true

    property string _numbers: "0123456789"
    property QtObject _feedbackEffect
    property int _buttonWidth: (3*Theme.itemSizeHuge - 4*Theme.paddingLarge) / 3
    property int _buttonHeight: screen.sizeCategory > Screen.Medium ? Theme.itemSizeExtraLarge : Theme.itemSizeLarge
    property int _horizontalSpacing: screen.sizeCategory > Screen.Medium ? Theme.paddingLarge : 0
    property int _horizontalPadding: Math.max((width - column.implicitWidth) / 2, 0)

    signal pressed(string number)
    signal released(string number)
    signal canceled(string number)
    signal clicked(string number)
    signal pressAndHold(string number, QtObject mouse)

    signal voiceMailCalled

    function _buttonPressed(item, number) {
        if (_feedbackEffect) {
            _feedbackEffect.play()
        }
        _centerPressedButtonBackgroundOnItem(item)
        pressedButtonBackground.opacity = 1
        pressedButtonBackground.visible = true
        dialer.pressed(number)
    }

    function _buttonReleased(number) {
        pressedButtonBackground.visible = false
        dialer.released(number)
    }

    function _buttonCanceled(number) {
        pressedButtonBackground.visible = false
        dialer.canceled(number)
    }

    function _buttonClicked(number) {
        dialer.clicked(number)
    }

    function _buttonEntered() {
        pressedButtonBackground.opacity = 1
    }

    function _buttonExited() {
        pressedButtonBackground.opacity = 0
    }

    function _centerPressedButtonBackgroundOnItem(item) {
        pressedButtonBackground.x = 0
        pressedButtonBackground.y = 0
        var itemCenter = pressedButtonBackground.mapFromItem(item, item.width/2, item.height/2)
        pressedButtonBackground.x = itemCenter.x - pressedButtonBackground.width/2
        pressedButtonBackground.y = itemCenter.y - pressedButtonBackground.height/2
    }

    width: parent ? parent.width : column.implicitWidth
    implicitHeight: column.implicitHeight

    Component.onCompleted: {
        // Avoid hard dependency to feedback
        _feedbackEffect = Qt.createQmlObject("import QtQuick 2.0; import QtFeedback 5.0; ThemeEffect { effect: ThemeEffect.PressWeak }",
                                             dialer, 'ThemeEffect')
    }

    Rectangle {
        id: pressedButtonBackground

        width: dialer._buttonWidth
        height: dialer._buttonHeight + 2*Theme.paddingSmall // make highlight more square
        visible: false
        radius: 4

        // same as BackgroundItem
        color: Theme.rgba(dialer.palette.highlightBackgroundColor, Theme.highlightBackgroundOpacity)
    }

    Column {
        id: column

        width: dialer.width
        height: dialer.height

        Row {
            x: dialer._horizontalPadding
            spacing: dialer._horizontalSpacing

            KeypadButton {
                key: Qt.Key_1
                text: _numbers.charAt(1)
                secondaryText: vanityDialNumbers[0]
                onPressAndHold: dialer.voiceMailCalled()
                Image {
                    id: voiceMailIcon

                    anchors {
                        bottom: parent.bottom
                        horizontalCenter: parent.horizontalCenter
                    }
                }
            }
            KeypadButton {
                key: Qt.Key_2
                text: _numbers.charAt(2)
                secondaryText: vanityDialNumbers[1]
            }
            KeypadButton {
                key: Qt.Key_3
                text: _numbers.charAt(3)
                secondaryText: vanityDialNumbers[2]
            }
        }
        Row {
            x: dialer._horizontalPadding
            spacing: dialer._horizontalSpacing

            Repeater {
                model: 3
                KeypadButton {
                    key: Qt.Key_4 + index
                    text: _numbers.charAt(4 + index)
                    secondaryText: vanityDialNumbers[3 + index]
                }
            }
        }

        Row {
            x: dialer._horizontalPadding
            spacing: dialer._horizontalSpacing

            Repeater {
                model: 3
                KeypadButton {
                    key: Qt.Key_7 + index
                    text: _numbers.charAt(7 + index)
                    secondaryText: vanityDialNumbers[6 + index]
                }
            }
        }
        Row {
            x: dialer._horizontalPadding
            spacing: dialer._horizontalSpacing

            Item {
                width: asteriskButton.width
                height: asteriskButton.height

                KeypadButton {
                    id: asteriskButton

                    visible: symbolsVisible
                    key: Qt.Key_Asterisk
                    text: "*"
                    secondaryText: vanityDialNumbers[9]
                }
            }
            KeypadButton {
                key: Qt.Key_0
                text: "0"
                secondaryText: symbolsVisible ? vanityDialNumbers[10] : ""
            }
            Item {
                width: hashButton.width
                height: hashButton.height

                KeypadButton {
                    id: hashButton

                    visible: symbolsVisible
                    text: "#"
                    key: Qt.Key_NumberSign
                    secondaryText: vanityDialNumbers[11]
                }
            }
        }
    }
}
