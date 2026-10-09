// SPDX-FileCopyrightText: 2013 Jolla Ltd.
// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: BSD-3-Clause
//
// Qt 6 (Vulkan-style GLSL, compiled to .qsb by build-shaders.sh) port of the
// inline GLSL shader in Silica's BSD TimePicker.qml (sailfishsilica-qt5 1.2.156).
// Modified by Shipwright for Qt 6: same computation, Qt 6 shader interface.
// The faint ring that a TimePicker indicator travels on.
#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;
    float border;
    vec4 color;
};
void main()
{
    float dist = length(qt_TexCoord0 - vec2(0.5));
    fragColor = color * vec4(0.1, 0.1, 0.1, 0.1)
              * (smoothstep(0.5 - border, 0.505 - border, dist) - smoothstep(0.5 - 0.005, 0.5, dist))
              * qt_Opacity;
}
