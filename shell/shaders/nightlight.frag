#version 440

layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 white;
};

// Blended as dst * src: the frame's encoded colour times the white point.
void main()
{
    fragColor = mix(vec4(1.0), white, qt_Opacity);
}
