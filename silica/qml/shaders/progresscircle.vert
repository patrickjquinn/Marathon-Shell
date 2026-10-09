// SPDX-FileCopyrightText: 2014 Jolla Ltd.
// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: BSD-3-Clause
//
// Qt 6 (Vulkan-style GLSL, compiled to .qsb by build-shaders.sh) port of the
// inline GLSL shader in Silica's BSD ProgressCircleBase.qml (sailfishsilica-qt5 1.2.156).
// Modified by Shipwright for Qt 6: same computation, Qt 6 shader interface.
// Wraps the effect's grid mesh into a ring around the item's centre.
#version 440
layout(location = 0) in vec4 qt_Vertex;
layout(location = 1) in vec2 qt_MultiTexCoord0;
layout(location = 0) out float coverage;
layout(location = 1) out float angle;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 posdata;       // (centerX, centerY, outerRadius, borderWidth)
    float aaStrength;
    float value;
    vec4 c1;
    vec4 c2;
};
out gl_PerVertex { vec4 gl_Position; };
const float PI = 3.141592653589793;
const float PIx2 = PI * 2.0;
void main()
{
    vec2 pos = posdata.xy
               + mix(posdata.z, posdata.z - posdata.w, qt_MultiTexCoord0.y)
                 * vec2(sin(-PIx2 * qt_MultiTexCoord0.x),
                        cos(-PIx2 * qt_MultiTexCoord0.x)) * -1.0;
    gl_Position = qt_Matrix * vec4(pos, 0.0, 1.0);
    if (qt_MultiTexCoord0.y < 0.001 || qt_MultiTexCoord0.y > 0.999)
        coverage = 0.0;
    else
        coverage = 1.0;
    angle = qt_MultiTexCoord0.x;
}
