#!/bin/sh
set -eu
here=$(cd "$(dirname "$0")" && pwd)
: "${KEEL_QML:?set KEEL_QML to a Keel build's qml dir}"
runner=${QMLTESTRUNNER:-$(qtpaths6 --query QT_INSTALL_BINS)/qmltestrunner}
QML_XHR_ALLOW_FILE_READ=1 QT_FORCE_STDERR_LOGGING=1 QT_QPA_PLATFORM=offscreen exec "$runner" -import "$KEEL_QML" \
	-import "$here/../../../marathon-silica" -import "$here/stubs" -input "$here" "$@"
