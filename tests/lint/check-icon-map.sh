#!/bin/sh
# Every image://theme/icon-* name used by Marathon's QML, or by the Keel QML
# trees given after the root (Silica, Keel apps), must be in the Marathon icon
# theme's map (names built at runtime end in "-"), as must every other theme
# name they load whole, except those Keel draws itself (busy indicators) and
# Silica's icon-launcher prefix test.
set -eu
root=${1:-$(cd "$(dirname "$0")/../.." && pwd)}
[ $# -gt 0 ] && shift
map="$root/marathon-icon-theme/icon-map.txt"
status=0
trees="$root/apps $root/shell $root/marathon-silica $*"
names=$(grep -rhoE 'icon-(xs|s|splus|m|l|cover)-[a-z0-9-]*[a-z0-9]' --include='*.qml' --include='*.js' \
	$trees 2>/dev/null | sort -u)
for name in $names; do
	base=$(echo "$name" | sed -E 's/^icon-(xs|s|splus|m|l|cover)-//')
	if ! grep -qE "^$base " "$map"; then
		echo "$name: no mapping in marathon-icon-theme/icon-map.txt"
		status=1
	fi
done
whole=$(grep -rhoE 'image://theme/[a-z][a-z0-9-]*' --include='*.qml' --include='*.js' $trees 2>/dev/null |
	sed 's|^image://theme/||' | grep -vE -e '-$' -e '^icon-(xs|s|splus|m|l|cover)-' \
	-e '^graphic-busyindicator' -e '^icon-launcher$' | sort -u)
for name in $whole; do
	if ! grep -qE "^$name [a-z0-9-]+ [0-9]+$" "$map"; then
		echo "$name: no whole-name mapping in marathon-icon-theme/icon-map.txt"
		status=1
	fi
done
exit $status
