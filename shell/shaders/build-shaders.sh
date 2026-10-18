#!/bin/sh
# Regenerates the committed .qsb files from the shader sources here, as Keel
# does: the device build roots carry no qsb. GLSL ES 100 for the devices
# (etnaviv, lima, V3D), 120/150 for desktop GL hosts; the vertex shader of a
# scene-graph material also needs the batchable variant (-b).
#   QSB=/path/to/qsb shell/shaders/build-shaders.sh
set -eu
here=$(cd "$(dirname "$0")" && pwd)
qsb=${QSB:-qsb}
"$qsb" -b --glsl "100 es,120,150" -o "$here/windowcorner.vert.qsb" "$here/windowcorner.vert"
"$qsb" --glsl "100 es,120,150" -o "$here/windowcorner.frag.qsb" "$here/windowcorner.frag"
"$qsb" --glsl "100 es,120,150" -o "$here/glassplatter.frag.qsb" "$here/glassplatter.frag"
