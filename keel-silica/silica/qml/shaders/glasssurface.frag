// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Keel's glass in one pass: a rounded box (rect, pill or circle) with a body
// from `bodyTop` to `bodyBottom` (straight alpha), its top edge catching the
// light and its bottom edge in shade. Item-local coordinates only: Mali-400
// has no highp.
#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;
    float radius;
    float dpr;
    vec4 bodyTop;
    vec4 bodyBottom;
    float edgeLight;
    float edgeShade;
};

float roundedBox(vec2 p, vec2 halfSize, float r)
{
    vec2 q = abs(p) - halfSize + r;
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
}

void main()
{
    vec2 halfSize = size * 0.5;
    vec2 p = qt_TexCoord0 * size - halfSize;
    float d = roundedBox(p, halfSize, radius);
    float coverage = clamp(0.5 - d * dpr, 0.0, 1.0);

    vec4 body = mix(bodyTop, bodyBottom, qt_TexCoord0.y);
    vec3 color = body.rgb;
    float alpha = body.a;

    // One device pixel inside the edge: lit where it faces up, shaded where
    // it faces down.
    float band = 1.0 - smoothstep(0.75, 1.75, -d * dpr);
    vec2 n = normalize(p / max(halfSize, vec2(1.0)) + vec2(0.0, 1e-4));
    float lit = band * clamp(-n.y * 1.6, 0.0, 1.0) * edgeLight;
    float shade = band * clamp(n.y * 1.6, 0.0, 1.0) * edgeShade;
    color = mix(color, vec3(1.0), lit / max(alpha + lit, 1e-3));
    alpha = max(alpha, lit);
    color = mix(color, vec3(0.0), shade / max(alpha + shade, 1e-3));
    alpha = max(alpha, shade);

    // Interleaved gradient noise: no banding in the gradient on 6-bit panels.
    float noise = fract(52.9829189 * fract(dot(gl_FragCoord.xy, vec2(0.06711056, 0.00583715))));
    color += (noise - 0.5) / 255.0;

    fragColor = vec4(color * alpha, alpha) * (coverage * qt_Opacity);
}
