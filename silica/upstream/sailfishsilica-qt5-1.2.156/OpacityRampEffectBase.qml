/****************************************************************************************
**
** Copyright (C) 2015 Jolla Ltd.
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
import Sailfish.Silica.private 1.0

ShaderEffect {
    id: root

    // API -----------------------

    // Opacity reduces linearly over the span of the item, affected by two
    // tunable properties:
    //  - the slope of the reduction (default 2.0, meaning 100% across half the width)
    //  - the offset from which the reduction is applied (default 0.5, meaning half the width)
    property real slope: 2.0
    property real offset: 0.5

    // clamp will be applied: clamp(factor + ramp value, min, max)
    property real clampFactor: 0.0
    property real clampMin: 0.0
    property real clampMax: 1.0

    // LtR = 0, RtL = 1, TtB = 2, BtT = 3, BothSides = 4, BothEnds = 5
    property int direction: 0 // default = LeftToRight-OpaqueToTranslucent

    // impl. ---------------------
    property var source

    vertexShader: "
        attribute highp vec4 qt_Vertex;
        attribute highp vec2 qt_MultiTexCoord0;

        uniform highp mat4 qt_Matrix;

        uniform lowp float slope;
        uniform lowp float offset;
        uniform lowp int direction;

        varying highp vec2 vTC;
        varying lowp float vLevel;

        void main() {
            gl_Position = qt_Matrix * qt_Vertex;
            vTC = qt_MultiTexCoord0;

            // Right-to-left
            if (direction == 1)
                vLevel = 1.0 + slope * (qt_MultiTexCoord0.x - 1.0 + offset);

            // Top-to-bottom
            else if (direction == 2 || direction == 5)
                vLevel = 1.0 - slope * (qt_MultiTexCoord0.y - offset);

            // Bottom-to-top
            else if (direction == 3)
                vLevel = 1.0 + slope * (qt_MultiTexCoord0.y - 1.0 + offset);

            // Left-to-right (and any bogus value)
            else if (direction == 0 || direction == 4)
                vLevel = 1.0 - slope * (qt_MultiTexCoord0.x - offset);
        }
        "

    fragmentShader: "
        uniform sampler2D source;

        uniform lowp float qt_Opacity;
        uniform lowp float clampFactor;
        uniform lowp float clampMin;
        uniform lowp float clampMax;

        uniform lowp float slope;
        uniform lowp float offset;
        uniform lowp int direction;

        varying highp vec2 vTC;
        varying lowp float vLevel;

        void main(void) {
            if (direction == 4) {
                // Both sides
                gl_FragColor = qt_Opacity * texture2D(source, vTC) * (clamp(clampFactor + (0.5 - slope * (abs(vTC.x - 0.5) - offset * 0.5)), clampMin, clampMax));
            } else if (direction == 5) {
                // Both ends
                gl_FragColor = qt_Opacity * texture2D(source, vTC) * (clamp(clampFactor + (0.5 - slope * (abs(vTC.y - 0.5) - offset * 0.5)), clampMin, clampMax));
            } else {
                gl_FragColor = qt_Opacity * texture2D(source, vTC) * (clamp(clampFactor + vLevel, clampMin, clampMax));
            }
        }
        "
}
