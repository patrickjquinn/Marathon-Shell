#!/bin/sh
set -eu
here=$(cd "$(dirname "$0")" && pwd)
: "${KEEL_QML:?set KEEL_QML to a Keel build's qml dir}"
runner=${QMLTESTRUNNER:-$(qtpaths6 --query QT_INSTALL_BINS)/qmltestrunner}
QT_FORCE_STDERR_LOGGING=1 QT_QPA_PLATFORM=offscreen exec "$runner" -import "$KEEL_QML" \
	-import "$here/../../../build-ui" -import "$here/stubs" -input "$here"
