#!/bin/sh
# The shell's QML loads: run it offscreen and fail on a root load error or
# on a type QML can't find, which the shell logs to ~/.marathon/crash.log.
bin=$1
qml=$2
home=$(mktemp -d)
trap 'rm -rf "$home"' EXIT
out=$(HOME="$home" QML_IMPORT_PATH="$qml" QT_QPA_PLATFORM=offscreen timeout 15 "$bin" 2>&1)
if printf '%s\n' "$out" | grep -E "No root QML objects|is ambiguous|Type [A-Za-z.]+ unavailable"; then
	exit 1
fi
if grep -E "ReferenceError: [A-Z][A-Za-z]+ is not defined" "$home/.marathon/crash.log"; then
	exit 1
fi
