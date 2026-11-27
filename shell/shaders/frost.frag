#version 440

layout(location = 0) in vec2 frostCoord;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 mapX;
    vec4 mapY;
    vec2 viewport;
    // One texel of the blurred texture, times the blur's spread.
    vec2 texel;
    float yUp;
    // Over 1 lifts the colour that shows through.
    float saturation;
    // How far towards black (white on a light ambience) it is toned.
    float tone;
    // The ambience's dimmer laid over it.
    float dimAmount;
    float light;
    // Luma past `knee` is rolled off towards `ceiling`, so text keeps its
    // contrast over a white page as over the wallpaper.
    float knee;
    float ceiling;
    vec4 dim;
};

layout(binding = 1) uniform sampler2D source;

// Interleaved gradient noise (Jimenez 2014): fixed to the panel's pixels,
// so a still frost stays byte-identical from frame to frame.
float noise(vec2 p)
{
    return fract(52.9829189 * fract(dot(p, vec2(0.06711056, 0.00583715))));
}

void main()
{
    // The last upsample, at full size.
    vec2 uv = frostCoord;
    vec2 h = texel * 0.5;
    vec4 sum = texture(source, uv + vec2(-texel.x, 0.0));
    sum += texture(source, uv + vec2(-h.x, h.y)) * 2.0;
    sum += texture(source, uv + vec2(0.0, texel.y));
    sum += texture(source, uv + vec2(h.x, h.y)) * 2.0;
    sum += texture(source, uv + vec2(texel.x, 0.0));
    sum += texture(source, uv + vec2(h.x, -h.y)) * 2.0;
    sum += texture(source, uv + vec2(0.0, -texel.y));
    sum += texture(source, uv + vec2(-h.x, -h.y)) * 2.0;
    vec3 c = sum.rgb / 12.0;

    const vec3 rec709 = vec3(0.2126, 0.7152, 0.0722);
    float l = dot(c, rec709);
    c = max(vec3(0.0), mix(vec3(l), c, saturation));

    // Worked as darkness on a light ambience: the same tone and roll-off
    // then lighten it instead.
    if (light > 0.5)
        c = 1.0 - c;
    c *= 1.0 - tone;
    if (light > 0.5)
        c = mix(c, 1.0 - dim.rgb, dimAmount);
    else
        c = mix(c, dim.rgb, dimAmount);
    l = dot(c, rec709);
    if (l > knee) {
        float room = max(ceiling - knee, 1e-3);
        float rolled = knee + room * (1.0 - exp(-(l - knee) / room));
        c *= rolled / l;
    }
    if (light > 0.5)
        c = 1.0 - c;

    // Under one 8-bit step of noise against banding. Never more than half a
    // step, so black stays black (the panel's pixels off) and white white.
    c += (noise(gl_FragCoord.xy) - 0.5) / 255.0;
    fragColor = vec4(c, 1.0) * qt_Opacity;
}
