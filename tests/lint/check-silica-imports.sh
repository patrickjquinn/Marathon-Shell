#!/bin/sh
# Marathon.Silica shadows Silica's controls, so every file that imports
# Sailfish.Silica and uses one of those controls must import Marathon.Silica
# after it. A file using none of them has no use for the import, and qmllint
# reports it unused.
set -eu
root=${1:-$(cd "$(dirname "$0")/../.." && pwd)}
shadowed=$(awk '$2 ~ /^[0-9]/ { printf "%s%s", sep, $1; sep = "|" }' "$root/marathon-silica/Marathon/Silica/qmldir")
status=0
for f in $(grep -rl --include='*.qml' '^import Sailfish\.Silica' "$root/apps" "$root/shell" 2>/dev/null); do
	silica=$(grep -n '^import Sailfish\.Silica\( 1\.0\)\?$' "$f" | head -1 | cut -d: -f1)
	[ -n "$silica" ] || continue
	sed -e '/^import /d' -e 's://.*$::' "$f" |
		grep -Eq "(^|[^.[:alnum:]_])($shadowed)[[:space:]]*\{|(property|as)[[:space:]]+($shadowed)\b" || continue
	marathon=$(grep -n '^import Marathon\.Silica' "$f" | head -1 | cut -d: -f1)
	if [ -z "$marathon" ] || [ "$marathon" -lt "$silica" ]; then
		echo "${f#$root/}: uses a control Marathon.Silica shadows without importing it after Sailfish.Silica"
		status=1
	fi
done
exit $status
