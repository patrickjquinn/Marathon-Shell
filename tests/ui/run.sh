#!/bin/sh
set -eu
here=$(cd "$(dirname "$0")" && pwd)
runner=${QMLTESTRUNNER:-$(qtpaths6 --query QT_INSTALL_BINS)/qmltestrunner}
QT_FORCE_STDERR_LOGGING=1 QT_QPA_PLATFORM=offscreen exec "$runner" \
	-import "$here/../../marathon-silica" -import "$here/stubs" ${KEEL_QML:+-import "$KEEL_QML"} -input "$here"
