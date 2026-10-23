#!/bin/sh
# Every image://theme/icon-* name used by Marathon's QML, or by the Keel QML
# trees given after the root (Silica, Keel apps), must be in the Marathon icon
# theme's map (names built at runtime end in "-").
set -eu
root=${1:-$(cd "$(dirname "$0")/../.." && pwd)}
[ $# -gt 0 ] && shift
map="$root/marathon-icon-theme/icon-map.txt"
status=0
names=$(grep -rhoE 'icon-(xs|s|splus|m|l|cover)-[a-z0-9-]*[a-z0-9]' --include='*.qml' --include='*.js' \
	"$root/apps" "$root/shell" "$root/marathon-silica" "$@" 2>/dev/null | sort -u)
for name in $names; do
	base=$(echo "$name" | sed -E 's/^icon-(xs|s|splus|m|l|cover)-//')
	if ! grep -qE "^$base " "$map"; then
		echo "$name: no mapping in marathon-icon-theme/icon-map.txt"
		status=1
	fi
done
exit $status
