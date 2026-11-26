// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0
//
// A tab card's picture: the image cropped as PreserveAspectCrop with
// AlignTop shows it, its lower corners rounded, in one pass.
#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    // The shown part of the image: offset (xy) and size (zw), normalized.
    vec4 crop;
    vec2 size;
    float radius;
};
layout(binding = 1) uniform sampler2D source;
void main()
{
    vec2 p = qt_TexCoord0 * size;
    vec2 c = vec2(clamp(p.x, radius, size.x - radius), min(p.y, size.y - radius));
    float d = length(p - c);
    float a = d > 0.0 ? clamp(radius - d + 0.5, 0.0, 1.0) : 1.0;
    fragColor = texture(source, crop.xy + qt_TexCoord0 * crop.zw) * (a * qt_Opacity);
}
