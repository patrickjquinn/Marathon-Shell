#version 440

layout(location = 0) in vec4 qt_VertexPosition;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 white;
};

out gl_PerVertex { vec4 gl_Position; };

void main()
{
    gl_Position = qt_Matrix * qt_VertexPosition;
}
