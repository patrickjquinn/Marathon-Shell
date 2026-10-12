#!/bin/sh
# Marathon.Silica shadows Silica's controls, so every file that imports
# Sailfish.Silica must import Marathon.Silica after it.
set -eu
root=${1:-$(cd "$(dirname "$0")/../.." && pwd)}
status=0
for f in $(grep -rl --include='*.qml' '^import Sailfish\.Silica' "$root/apps" "$root/shell" 2>/dev/null); do
	silica=$(grep -n '^import Sailfish\.Silica\( 1\.0\)\?$' "$f" | head -1 | cut -d: -f1)
	marathon=$(grep -n '^import Marathon\.Silica' "$f" | head -1 | cut -d: -f1)
	if [ -n "$silica" ] && { [ -z "$marathon" ] || [ "$marathon" -lt "$silica" ]; }; then
		echo "${f#$root/}: imports Sailfish.Silica without Marathon.Silica after it"
		status=1
	fi
done
exit $status
