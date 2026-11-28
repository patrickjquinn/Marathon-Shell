#version 440

layout(location = 0) in vec4 qt_Vertex;
layout(location = 1) in vec2 qt_MultiTexCoord0;
layout(location = 0) out vec2 frostCoord;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    // Window pixels to the frost texture's coordinates, as two rows of an
    // affine map applied to the vertex's place on screen.
    vec4 mapX;
    vec4 mapY;
    vec2 viewport;
    vec2 texel;
    float yUp;
    float saturation;
    float tone;
    float dimAmount;
    float light;
    float knee;
    float ceiling;
    vec4 dim;
};

// The frost is sampled where the item lies on screen, not where it lies in
// its parent: it stays over what it frosts while the Hub slides or the
// shade grows.
void main()
{
    gl_Position = qt_Matrix * qt_Vertex;
    vec2 ndc = gl_Position.xy / gl_Position.w;
    vec2 win = vec2(ndc.x * 0.5 + 0.5, yUp > 0.5 ? 0.5 - ndc.y * 0.5 : 0.5 + ndc.y * 0.5) * viewport;
    frostCoord = vec2(dot(mapX.xyz, vec3(win, 1.0)), dot(mapY.xyz, vec3(win, 1.0)));
}
