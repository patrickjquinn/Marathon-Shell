#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;
    float radius;
    // Backdrop lookup: screen space (shared, full-screen blur) or the
    // platter's own rect (a blur of just what is behind it).
    float screenSpace;
    vec2 screenSize;
    float flipY;
    vec4 tint;
    float rim;
};

layout(binding = 1) uniform sampler2D backdrop;

float roundedBox(vec2 p, vec2 halfSize, float r)
{
    vec2 q = abs(p) - halfSize + r;
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
}

void main()
{
    vec2 p = qt_TexCoord0 * size;
    float d = roundedBox(p - size * 0.5, size * 0.5, radius);
    float coverage = clamp(0.5 - d, 0.0, 1.0);

    vec2 uv = qt_TexCoord0;
    if (screenSpace > 0.5) {
        uv = gl_FragCoord.xy / screenSize;
        if (flipY > 0.5)
            uv.y = 1.0 - uv.y;
    }
    vec3 color = mix(texture(backdrop, uv).rgb, tint.rgb, tint.a);

    // The system's depth recipe as one pass: an outer hairline that crushes
    // toward black and an inner one that catches the light, a touch
    // brighter along the top.
    float inside = -d;
    float outer = 1.0 - smoothstep(0.0, 1.0, inside);
    float inner = smoothstep(0.5, 1.25, inside) * (1.0 - smoothstep(1.25, 2.25, inside));
    float top = mix(0.7, 1.3, 1.0 - qt_TexCoord0.y);
    color = mix(color, vec3(0.0), outer * 0.45 * rim);
    color += vec3(1.0) * inner * 0.12 * top * rim;

    fragColor = vec4(color, 1.0) * (coverage * qt_Opacity);
}
