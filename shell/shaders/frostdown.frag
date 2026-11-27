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

// Dual-filter (Kawase) downsample: the centre and four diagonal taps, each a
// bilinear average of four texels, into a target half the source's size.
void main()
{
    vec2 uv = qt_TexCoord0;
    vec4 sum = texture(source, uv) * 4.0;
    sum += texture(source, uv - texel);
    sum += texture(source, uv + texel);
    sum += texture(source, uv + vec2(texel.x, -texel.y));
    sum += texture(source, uv - vec2(texel.x, -texel.y));
    fragColor = sum / 8.0;
}
