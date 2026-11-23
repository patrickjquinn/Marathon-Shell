#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    // 1 while the panel is in its fast waveform: two levels.
    float binary;
};

layout(binding = 1) uniform sampler2D source;

// Bayer's 2x2 rank, from 4x4 cells: 0, 2 / 3, 1.
float rank2(vec2 p) {
    return mod(2.0 * p.x + 3.0 * p.y, 4.0);
}

// A 4x4 ordered-dither threshold in (0, 1), fixed to the panel's pixels so
// a still screen stays byte-identical frame to frame.
float threshold(vec2 frag) {
    vec2 p = mod(floor(frag), 4.0);
    float r = 4.0 * rank2(mod(p, 2.0)) + rank2(floor(p / 2.0));
    return (r + 0.5) / 16.0;
}

// The frame as the e-paper panel can show it: grey, on its 16 levels, or
// black and white while it draws with the fast waveform. Exact levels
// pass unchanged; what lies between is dithered, not rounded.
void main()
{
    vec4 c = texture(source, qt_TexCoord0);
    float y = dot(c.rgb, vec3(0.299, 0.587, 0.114));
    float t = threshold(gl_FragCoord.xy);
    float g = binary > 0.5 ? step(t, y) : floor(y * 15.0 + t) / 15.0;
    fragColor = vec4(vec3(g), 1.0) * qt_Opacity;
}
