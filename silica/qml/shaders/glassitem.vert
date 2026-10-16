// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// GlassItem's quad (plugin/cpp/private/glassitem.cpp): passes the position
// in item units on to glassitem.frag.
#version 440
layout(location = 0) in vec4 qt_Vertex;
layout(location = 1) in vec2 itemPos;
layout(location = 0) out vec2 pos;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 color;
    vec4 haloColor;
    vec4 shape;     // x0, x1, cy, reach
    vec4 glow;      // core, length, fade, strength
    vec4 dash;      // on (0 or 1), start, period, dashLength
    vec4 extra;     // the item's origin in the scene; halo length; end of the dashes
};
out gl_PerVertex { vec4 gl_Position; };
void main()
{
    pos = itemPos;
    gl_Position = qt_Matrix * qt_Vertex;
}
