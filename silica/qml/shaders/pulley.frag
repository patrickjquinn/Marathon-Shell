// SPDX-FileCopyrightText: 2013 Jolla Ltd.
// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: BSD-3-Clause
//
// Qt 6 (Vulkan-style GLSL, compiled to .qsb by build-shaders.sh) port of the
// inline GLSL shader in Silica's BSD private/PulleyMenuBase.qml (sailfishsilica-qt5 1.2.156).
// Modified by Shipwright for Qt 6: same computation, Qt 6 shader interface.
// The layer of a pulley menu, multiplied by the flickable content's opacity
// instead of the inherited opacity (so window dimming does not apply).
#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float flickOpacity;
};
layout(binding = 1) uniform sampler2D source;
void main()
{
    fragColor = texture(source, qt_TexCoord0) * flickOpacity;
}
