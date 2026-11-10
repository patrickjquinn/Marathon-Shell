// SPDX-FileCopyrightText: 2014 Jolla Ltd.
// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: BSD-3-Clause
//
// Qt 6 (Vulkan-style GLSL, compiled to .qsb by build-shaders.sh) port of the
// inline GLSL shader in Silica's BSD ProgressCircleBase.qml (sailfishsilica-qt5 1.2.156).
// Modified by Shipwright for Qt 6: same computation, Qt 6 shader interface.
// Background colour c1 and progress colour c2 around the ring, antialiased.
#version 440
layout(location = 0) in float coverage;
layout(location = 1) in float angle;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 posdata;       // (centerX, centerY, outerRadius, borderWidth)
    float aaStrength;
    float value;
    vec4 c1;
    vec4 c2;
};
void main()
{
    fragColor = mix(c1, c2, step(angle, value))
                * smoothstep(0.0, aaStrength, coverage)
                * qt_Opacity;
}
