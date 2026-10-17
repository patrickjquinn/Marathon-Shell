#!/bin/sh
# An app made by `marathon-dev init` passes `marathon-dev lint` as a
# third-party app, and its icon is well-formed SVG (the shell's renderer
# drops a malformed one and leaves a blank tile).
set -eu
dev=$1
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cd "$work"
"$dev" init "Demo App" >/dev/null
"$dev" lint demo-app
python3 -c 'import sys, xml.dom.minidom as m; d = m.parse(sys.argv[1]).documentElement; sys.exit(d.tagName != "svg" or d.getAttribute("xmlns") != "http://www.w3.org/2000/svg")' demo-app/assets/icon.svg
