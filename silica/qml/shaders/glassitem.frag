// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// GlassItem's glow on the GPU (plugin/cpp/private/glassitem.cpp), the same
// computation as its QPainter drawing for the software scene graph: a halo
// in haloColor, the glow in color (clipped to dashes when dashed) and, when
// not dashed, a whiter core, each drawn over the one before. A pixel's glow
// at a distance d from the core: 1 up to core, then exp(-(d - core) / length),
// faded out before the item's edge, through Keel's glass dither towards the
// outside (aligned to the scene, as the window's dither is).
#version 440
layout(location = 0) in vec2 pos;
layout(location = 0) out vec4 fragColor;
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

// Keel's 8x8 glass dither (keel/silica/ambience/make-ambience.py), 0..1;
// written out for GLSL ES 1.00 (no constant arrays).
float ditherRow(float dy)
{
    return dy < 0.5 ? 1.0 : (dy < 1.5 ? 15.0 / 24.0 : (dy < 2.5 ? 8.0 / 24.0 : 4.0 / 24.0));
}

float ditherAt(vec2 p)
{
    float dy = mod(p.y, 8.0);
    float dx = mod(p.x, 8.0);
    if (dy < 3.5 && min(dx, 8.0 - dx) <= dy)
        return ditherRow(dy);
    dy = mod(p.y - 4.0, 8.0);
    dx = mod(p.x - 4.0, 8.0);
    if (dy < 3.5 && min(dx, 8.0 - dx) <= dy)
        return ditherRow(dy);
    return 0.0;
}

// One glow, premultiplied.
vec4 glowAt(float d, float core, float len, vec4 c, float strength, float dither)
{
    float i = d <= core ? 1.0 : exp(-(d - core) / max(0.5, len));
    float toEdge = shape.w - d;
    if (toEdge <= 0.0)
        return vec4(0.0);
    if (toEdge < glow.z)
        i *= toEdge / glow.z;
    if (i < 0.004)
        return vec4(0.0);
    // Dithered towards the outside: the core stays solid.
    float a = clamp(strength * (i >= 0.6 ? i : min(1.0, i * dither)), 0.0, 1.0) * c.a;
    return vec4(c.rgb * a, a);
}

void main()
{
    float nx = clamp(pos.x, shape.x, shape.y);
    float d = length(vec2(pos.x - nx, pos.y - shape.z));
    // The scene pixel this fragment is, the grid the window's dither uses.
    float dither = 0.4 + 3.5 * ditherAt(floor(pos + extra.xy));
    float core = glow.x;
    vec4 result = glowAt(d, core, extra.z, haloColor, 0.5, dither);
    vec4 lit = glowAt(d, core, glow.y, color, glow.w, dither);
    if (dash.x > 0.5) {
        float t = pos.x - dash.y;
        float k = floor(t / dash.z);
        float x = dash.y + k * dash.z;
        if (t < 0.0 || pos.x - x >= dash.w || x >= extra.w)
            lit = vec4(0.0);
    }
    result = lit + result * (1.0 - lit.a);
    if (dash.x < 0.5) {
        vec4 white = glowAt(d, core * 0.6, glow.y * 0.35, vec4(1.0, 1.0, 1.0, 150.0 / 255.0), glow.w, dither);
        result = white + result * (1.0 - white.a);
    }
    fragColor = result * qt_Opacity;
}
