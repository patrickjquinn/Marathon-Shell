#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    // One texel of the source, times the blur's spread.
    vec2 texel;
};

layout(binding = 1) uniform sampler2D source;

// Dual-filter (Kawase) upsample: a ring of eight taps into a target twice
// the source's size.
void main()
{
    vec2 uv = qt_TexCoord0;
    vec2 h = texel * 0.5;
    vec4 sum = texture(source, uv + vec2(-texel.x, 0.0));
    sum += texture(source, uv + vec2(-h.x, h.y)) * 2.0;
    sum += texture(source, uv + vec2(0.0, texel.y));
    sum += texture(source, uv + vec2(h.x, h.y)) * 2.0;
    sum += texture(source, uv + vec2(texel.x, 0.0));
    sum += texture(source, uv + vec2(h.x, -h.y)) * 2.0;
    sum += texture(source, uv + vec2(0.0, -texel.y));
    sum += texture(source, uv + vec2(-h.x, -h.y)) * 2.0;
    fragColor = sum / 12.0;
}
