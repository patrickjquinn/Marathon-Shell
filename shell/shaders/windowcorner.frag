#version 440

layout(location = 0) in vec2 texCoord;
layout(location = 1) in vec2 corner;

layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 edges;
};

layout(binding = 1) uniform sampler2D qt_Texture;

void main()
{
    fragColor = texture(qt_Texture, texCoord) * (smoothstep(edges.x, edges.y, dot(corner, corner)) * qt_Opacity);
}
