#version 440

layout(location = 0) in vec4 qt_VertexPosition;
layout(location = 1) in vec2 qt_VertexTexCoord;
layout(location = 2) in vec2 vertexCorner;

layout(location = 0) out vec2 texCoord;
layout(location = 1) out vec2 corner;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 edges;
};

out gl_PerVertex { vec4 gl_Position; };

void main()
{
    texCoord = qt_VertexTexCoord;
    corner = vertexCorner;
    gl_Position = qt_Matrix * qt_VertexPosition;
}
