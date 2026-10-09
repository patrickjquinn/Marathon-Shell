/****************************************************************************************
**
** Copyright (C) 2015-2016 Jolla Ltd.
** Copyright (c) 2020 Open Mobile Platform LLC.
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

import QtQuick 2.6
import Sailfish.Silica 1.0
import Sailfish.Silica.private 1.0

QtObject {
    id: materials

    property var materialNames: [ "glass" ]

    property list<QtObject> objects
    default property alias _objects: materials.objects

    // MaterialPrivate is used in place of Material in types which are instantiated in the the Materials
    // singleton which can't import Sailfish.Silica.Background.
    property MaterialPrivate glass: MaterialPrivate {
        property url noiseTexture: "noise.png"
        property var noiseMatrix: Qt.matrix4x4(
                        Screen.width / 64, 0, 0, 0,
                        0, Screen.height / 64, 0, 0,
                        0, 0, 1, 0,
                        0, 0, 0, 1)

        vertexShader: "
    attribute highp vec4 position;

    uniform highp mat4 positionMatrix;
    uniform highp mat4 patternMatrix;
    uniform highp mat4 noiseMatrix;
    uniform highp mat4 transformMatrix;

    uniform lowp vec4 color;
    uniform lowp vec4 highlightBackgroundColor;

    varying highp vec2 patternCoord;
    varying highp vec2 noiseCoord;
    varying lowp vec4 gradientColor;

    void backgroundMain() {
        gl_Position = positionMatrix * position;
        patternCoord = (patternMatrix * gl_Position).xy;
        noiseCoord = (noiseMatrix * gl_Position).xy;

        gradientColor = mix(
                    color,
                    (color * 0.7) + (highlightBackgroundColor * 0.3),
                    (transformMatrix * gl_Position).y);
    }
"

        fragmentShader: "
    uniform lowp sampler2D patternTexture;
    uniform lowp sampler2D noiseTexture;

    varying highp vec2 patternCoord;
    varying highp vec2 noiseCoord;
    varying lowp vec4 gradientColor;

    void backgroundMain() {
        lowp vec4 pattern = texture2D(patternTexture, patternCoord) * 0.1;
        lowp vec4 noise = texture2D(noiseTexture, noiseCoord) * 0.03;

        gl_FragColor = (gradientColor * (1.0 - pattern.a)) + pattern;
        gl_FragColor = (gl_FragColor * (1.0 - noise.a)) + noise;
    }
"
    }
}
