// SPDX-FileCopyrightText: 2015 Jolla Ltd.
// SPDX-FileCopyrightText: 2020 Open Mobile Platform LLC
// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: BSD-3-Clause
//
// Qt 6 (Vulkan-style GLSL, compiled to .qsb by build-shaders.sh) port of the
// inline GLSL shader in Silica's BSD OpacityRampEffectBase.qml (sailfishsilica-qt5 1.2.156).
// Modified by Shipwright for Qt 6: same computation, Qt 6 shader interface.
// Opacity ramp: the source scaled by the clamped level.
#version 440
layout(location = 0) in vec2 vTC;
layout(location = 1) in float vLevel;
layout(location = 0) out vec4 fragColor;
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
layout(binding = 1) uniform sampler2D source;
void main()
{
    vec4 c = qt_Opacity * texture(source, vTC);
    if (direction == 4)
        fragColor = c * clamp(clampFactor + (0.5 - slope * (abs(vTC.x - 0.5) - offset * 0.5)), clampMin, clampMax);
    else if (direction == 5)
        fragColor = c * clamp(clampFactor + (0.5 - slope * (abs(vTC.y - 0.5) - offset * 0.5)), clampMin, clampMax);
    else
        fragColor = c * clamp(clampFactor + vLevel, clampMin, clampMax);
}
