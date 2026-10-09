// SPDX-FileCopyrightText: 2015 Jolla Ltd.
// SPDX-FileCopyrightText: 2020 Open Mobile Platform LLC
// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: BSD-3-Clause
//
// Qt 6 (Vulkan-style GLSL, compiled to .qsb by build-shaders.sh) port of the
// inline GLSL shader in Silica's BSD OpacityRampEffectBase.qml (sailfishsilica-qt5 1.2.156).
// Modified by Shipwright for Qt 6: same computation, Qt 6 shader interface.
// Opacity ramp: the level along the ramp direction, per vertex.
// direction: LtR = 0, RtL = 1, TtB = 2, BtT = 3, BothSides = 4, BothEnds = 5
#version 440
layout(location = 0) in vec4 qt_Vertex;
layout(location = 1) in vec2 qt_MultiTexCoord0;
layout(location = 0) out vec2 vTC;
layout(location = 1) out float vLevel;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float slope;
    float offset;
    int direction;
    float clampFactor;
    float clampMin;
    float clampMax;
};
out gl_PerVertex { vec4 gl_Position; };
void main()
{
    gl_Position = qt_Matrix * qt_Vertex;
    vTC = qt_MultiTexCoord0;
    vLevel = 1.0;
    if (direction == 1)
        vLevel = 1.0 + slope * (qt_MultiTexCoord0.x - 1.0 + offset);
    else if (direction == 2 || direction == 5)
        vLevel = 1.0 - slope * (qt_MultiTexCoord0.y - offset);
    else if (direction == 3)
        vLevel = 1.0 + slope * (qt_MultiTexCoord0.y - 1.0 + offset);
    else if (direction == 0 || direction == 4)
        vLevel = 1.0 - slope * (qt_MultiTexCoord0.x - offset);
}
