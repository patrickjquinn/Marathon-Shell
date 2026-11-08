#!/bin/sh
set -eu
here=$(cd "$(dirname "$0")" && pwd)
: "${KEEL_QML:?set KEEL_QML to a Keel build's qml dir}"
runner=${QMLTESTRUNNER:-$(qtpaths6 --query QT_INSTALL_BINS)/qmltestrunner}

# MarathonApp.Camera as the app installs it, with stand-ins for its C++ types.
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
module=$stage/MarathonApp/Camera
mkdir -p "$module"
(cd "$here/.." && find . -name '*.qml' ! -path './tests/*' | tar -cf - -T -) | tar -C "$module" -xf -
cp "$here"/native/*.qml "$module"
(
	cd "$module"
	echo "module MarathonApp.Camera"
	find . -name '*.qml' | sed 's|^\./||' | sort | while read -r file; do
		type=$(basename "$file" .qml)
		case $type in
		Settings | CameraConfigs) echo "singleton $type 1.0 $file" ;;
		*) echo "$type 1.0 $file" ;;
		esac
	done
) >"$module/qmldir"

KEEL_DCONF_FILE=$stage/dconf.json QML_XHR_ALLOW_FILE_READ=1 QT_FORCE_STDERR_LOGGING=1 QT_QPA_PLATFORM=offscreen "$runner" \
	-import "$KEEL_QML" -import "$here/../../../marathon-silica" -import "$here/stubs" -import "$stage" -input "$here"
