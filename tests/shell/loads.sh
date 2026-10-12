#!/bin/sh
# The shell's QML loads: run it offscreen and fail on a root load error.
bin=$1
qml=$2
out=$(QML_IMPORT_PATH="$qml" QT_QPA_PLATFORM=offscreen timeout 15 "$bin" 2>&1)
if printf '%s\n' "$out" | grep -E "No root QML objects|is ambiguous|Type [A-Za-z.]+ unavailable"; then
	exit 1
fi
