#!/bin/sh
# SPDX-FileCopyrightText: 2026 Patrick Quinn
# SPDX-License-Identifier: MIT
#
# Regenerates the committed .qsb files from the shader sources here with
# Qt's qsb (qt6-shadertools; any Qt 6.4+ qsb works: Qt 6 loads .qsb files of
# older Qt 6 versions). GLSL ES 100 for the device (OpenGL ES), GLSL 120/150
# for desktop GL hosts: the versions Qt's own built-in shaders carry. A
# ShaderEffect with only a fragment shader is linked with Qt's default vertex
# shader, and the GL backend picks the highest version each .qsb has: a
# "300 es" fragment shader next to Qt's "100 es" vertex shader fails to link
# on the phone's Mali ("Shader languages do not match"), and the item draws
# nothing (the pulley menu was empty). The software scene graph does not run
# shaders; the QML falls back to plain drawing there.
#   QSB=/path/to/qsb keel/silica/qml/shaders/build-shaders.sh
set -eu
here=$(cd "$(dirname "$0")" && pwd)
qsb=${QSB:-qsb}
for src in "$here"/*.vert "$here"/*.frag; do
    "$qsb" --glsl "100 es,120,150" -o "$src.qsb" "$src"
    # The compiled shader has its source's licence.
    sed -n 's|^// \(SPDX-[A-Za-z-]*: .*\)|\1|p' "$src" > "$src.qsb.license"
done
