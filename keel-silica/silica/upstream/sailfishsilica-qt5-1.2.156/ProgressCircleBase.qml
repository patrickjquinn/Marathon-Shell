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

SilicaItem {
    id: root

    property color progressColor: "lightgray"
    property color backgroundColor: "darkgray"
    property real value
    property real progressValue: Math.max(0.0, Math.min(value, 1.0))
    property real borderWidth: Theme.paddingSmall

    width: Theme.itemSizeSmall
    height: Theme.itemSizeSmall

    ShaderEffect {
        anchors.centerIn: parent
        width: Math.min(parent.width, parent.height)
        height: width

        /* The shader effect is created as a mesh which has plenty of vertices along the
           x axis and 3 vertices along the y axis. The texture coordinate along the x
           axis is used to wrap the mesh into a circle around the origin of this item
           with radius equal to width/2. The generated vertices are discareded

           Using width/2 vertices along the x axis was choosen based on what gives good
           for arbitrary sizes while keeping the number of vertices down. It results in
           roughly one vertex per 6 pixels along the outside of the circle.

           Using 2 for the y axis means we get three vertex coordinates, 0, 0.5 and 1
           which we change into 0, 1, 0 in the vertex shader to produce coverage for
           the antialiasing.
         */
        mesh: Qt.size(Math.max(32, width / 2), 2)

        // Must be smaller than radius, and set aside one extra pixel for antialiasing.
        property real strokeWidth: Math.min(width / 2, root.borderWidth + 1)

        property var posdata: Qt.vector4d(width/2, width/2, width/2, strokeWidth)
        property real aaStrength: 3 / strokeWidth

        property color c1: root.backgroundColor
        property color c2: root.progressColor

        property real value: root.progressValue

        vertexShader: "
            attribute highp vec4 qt_Vertex;
            attribute highp vec2 qt_MultiTexCoord0;

            uniform highp mat4 qt_Matrix;
            uniform highp vec4 posdata;         // (centerX, centerY, outerRadius, borderWidth)

            const highp float PI = 3.141592653589793;
            const highp float PIx2 = PI * 2.0;

            varying lowp float coverage;
            varying lowp float angle;

            void main() {
                vec2 pos = posdata.xy
                           + mix(posdata.z, posdata.z - posdata.w, qt_MultiTexCoord0.y)
                             * vec2(sin(-PIx2 * qt_MultiTexCoord0.x),
                                    cos(-PIx2 * qt_MultiTexCoord0.x)
                                   ) * -1.0;
                gl_Position = qt_Matrix * vec4(pos, 0, 1);

                if (qt_MultiTexCoord0.y < 0.001 || qt_MultiTexCoord0.y > 0.999)
                    coverage = 0.0;
                else
                    coverage = 1.0;
                angle = qt_MultiTexCoord0.x;
            }
        "

        fragmentShader: "
            uniform lowp float qt_Opacity;
            uniform lowp float aaStrength;
            uniform lowp float value;

            uniform lowp vec4 c1;
            uniform lowp vec4 c2;

            varying lowp float coverage;
            varying lowp float angle;

            void main() {
                gl_FragColor = mix(c1, c2, step(angle, value)) // color
                               * smoothstep(0.0, aaStrength, coverage) // antialiasing
                               * qt_Opacity;
            }
        "
    }
}
