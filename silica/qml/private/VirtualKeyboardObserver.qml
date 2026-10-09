// SPDX-FileCopyrightText: 2015 Jolla Ltd
// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: BSD-3-Clause
/****************************************************************************************
**
** Copyright (C) 2015 Jolla Ltd.
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
// Upstream: sailfishsilica-qt5-1.2.156 (Sailfish OS 5.2.0.15) private/VirtualKeyboardObserver.qml
// Modified by Shipwright for Qt 6: imports Sailfish.Silica.private for the module's native types.

import QtQuick 2.2
import Sailfish.Silica 1.0
import Sailfish.Silica.private 1.0 // Modified by Shipwright for Qt 6: native types of this module

Item {
    id: virtualKeyboardObserver

    property bool transpose
    property bool active

    property int orientation: Orientation.Portrait
    readonly property bool verticalOrientation: orientation === Orientation.Portrait
                                                || orientation === Orientation.PortraitInverted
                                                || orientation === Orientation.None
    readonly property bool horizontalOrientation: orientation === Orientation.Landscape
                                                  || orientation === Orientation.LandscapeInverted

    property bool testMode

    // panelSize is the sometimes animated imSize
    property real panelSize: 0
    property real previousImSize: 0
    property real imSize: !active ? 0 : (verticalOrientation ? (transpose ? Qt.inputMethod.keyboardRectangle.width
                                                                          : Qt.inputMethod.keyboardRectangle.height)
                                                             : (transpose ? Qt.inputMethod.keyboardRectangle.height
                                                                          : Qt.inputMethod.keyboardRectangle.width))

    // When closing im panel imSize changes to zero immediately.
    readonly property bool opened: imSize > 0 && panelSize == imSize
    readonly property bool closed: imSize == 0 && panelSize == imSize
    readonly property bool animating: imHideAnimation.running || imShowAnimation.running

    onImSizeChanged: {
        if (imSize <= 0 && previousImSize > 0) {
            imShowAnimation.stop()
            imHideAnimation.start()
        } else if (imSize > 0 && previousImSize <= 0) {
            imHideAnimation.stop()
            imShowAnimation.to = imSize
            imShowAnimation.start()
        } else {
            panelSize = imSize
        }

        previousImSize = imSize
    }

    SequentialAnimation {
        id: imHideAnimation

        PauseAnimation {
            duration: testMode ? 5 : 200
        }
        NumberAnimation {
            target: virtualKeyboardObserver
            property: 'panelSize'
            to: 0
            duration: testMode ? 5 : 200
            easing.type: Easing.InOutQuad
        }
    }

    NumberAnimation {
        id: imShowAnimation

        target: virtualKeyboardObserver
        property: 'panelSize'
        duration: testMode ? 5 : 200
        easing.type: Easing.InOutQuad
    }
}
