// SPDX-FileCopyrightText: 2013-2021 Jolla Ltd.
// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: BSD-3-Clause
//
// Qt 6 (Vulkan-style GLSL, compiled to .qsb by build-shaders.sh) port of the
// inline GLSL shader in Silica's BSD ContextMenu.qml and DockedPanel.qml (sailfishsilica-qt5 1.2.156).
// Modified by Shipwright for Qt 6: same computation, Qt 6 shader interface.
// Draws the layer as is, without the inherited opacity (removes the window
// dimming from a context menu or a modal docked panel).
#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
};
layout(binding = 1) uniform sampler2D source;
void main()
{
    fragColor = texture(source, qt_TexCoord0);
}
