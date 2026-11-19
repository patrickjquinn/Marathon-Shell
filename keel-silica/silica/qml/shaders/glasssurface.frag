// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Keel's glass in one pass: a rounded box (rect, pill or circle) lit from
// above. The body runs from `bodyTop` to `bodyBottom` (straight alpha);
// light pools just inside the edge in `glow`, most at the bottom; the rim is
// bright along the top and shaded along the bottom. Item-local coordinates
// only: Mali-400 has no highp.
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
    vec4 glow;
    float glowWidth;
    float rim;
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
    float inside = max(-d, 0.0);

    vec4 body = mix(bodyTop, bodyBottom, smoothstep(0.25, 1.0, qt_TexCoord0.y));
    vec3 color = body.rgb;
    float alpha = body.a;

    float pool = exp(-inside / glowWidth) * glow.a * qt_TexCoord0.y * qt_TexCoord0.y;
    color = mix(color, glow.rgb, pool);
    alpha = max(alpha, pool);

    // The edge's normal, exact for a circle and close for a pill or card.
    vec2 n = normalize(p / max(halfSize, vec2(1.0)) + vec2(0.0, 1e-4));
    float light = -n.y;
    float band = 1.0 - smoothstep(0.5, 2.0, inside * dpr);
    float lit = band * rim * pow(max(light, 0.0), 1.5);
    color = mix(color, vec3(1.0), lit * 0.8);
    color *= 1.0 - band * rim * max(-light, 0.0) * 0.35;
    color += vec3(band * rim * 0.05);
    alpha = max(alpha, lit * 0.85);

    // Interleaved gradient noise: no banding in the gradients on 6-bit panels.
    float noise = fract(52.9829189 * fract(dot(gl_FragCoord.xy, vec2(0.06711056, 0.00583715))));
    color += (noise - 0.5) / 255.0;

    fragColor = vec4(color * alpha, alpha) * (coverage * qt_Opacity);
}
