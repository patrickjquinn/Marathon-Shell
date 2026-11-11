#!/bin/sh
set -eu
here=$(cd "$(dirname "$0")" && pwd)
: "${KEEL_QML:?set KEEL_QML to the qml dir of a Keel build}"
runner=${QMLTESTRUNNER:-$(qtpaths6 --query QT_INSTALL_BINS)/qmltestrunner}
QT_FORCE_STDERR_LOGGING=1 QT_QPA_PLATFORM=offscreen exec "$runner" -import "$KEEL_QML" \
	-import "$here/../../../marathon-silica" -import "$here/stubs" -input "$here"
