/****************************************************************************************
**
** Copyright (C) 2013 Jolla Ltd.
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

import QtQuick 2.2
import Sailfish.Silica 1.0

SilicaItem {
    id: root

    property bool running
    property int size: BusyIndicatorSize.Medium
    property alias color: busyIndicator.color
    property bool _forceAnimation

    implicitWidth: busyIndicator.implicitWidth
    implicitHeight: busyIndicator.implicitHeight
    opacity: running ? 1.0 : 0.0
    Behavior on opacity { FadeAnimation { id: fadeAnimation }}

    HighlightImage {
        id: busyIndicator

        function _updateSize() {
            var prefix = "image://theme/graphic-busyindicator-"
            var indicatorSize
            if (root.size == BusyIndicatorSize.ExtraSmall) {
                indicatorSize = "extra-small"
            } else if (root.size == BusyIndicatorSize.Small) {
                indicatorSize = "small"
            } else if (root.size == BusyIndicatorSize.Medium) {
                indicatorSize = "medium"
            } else if (root.size == BusyIndicatorSize.Large) {
                indicatorSize = "large"
            } else {
                console.log("BusyIndicator: invalid size specified")
                return ""
            }

            return prefix + indicatorSize
        }

        color: palette.highlightColor
        smooth: true
        source: _updateSize()
        transformOrigin: Item.Center

        RotationAnimator on rotation {
            from: 0; to: 360
            duration: 2000
            running: (root.running || opacity > 0) && (_forceAnimation || (root.visible && Qt.application.active))
            loops: Animation.Infinite
        }
    }
}
