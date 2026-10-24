#!/bin/sh
# Names every test a ctest run skipped (QtTest's SKIP, a script's "SKIP:",
# cargo's ignored) and fails on any that tests/expected-skips does not list:
# ctest reports a suite with skips inside as passed.
# Usage: count-skips.sh <ctest LastTest.log> <expected skips>
set -eu
found=$(
	sed -n -e 's/^SKIP   : \([^ (]*\).*/\1/p' \
		-e 's/^SKIP: \(.*\)/script: \1/p' \
		-e 's/^test \(.*\) \.\.\. ignored.*/cargo: \1/p' "$1" | sort -u
)
echo "skipped tests: $(printf '%s' "$found" | grep -c . || true)"
[ -z "$found" ] || printf '%s\n' "$found" | sed 's/^/  /'
unexpected=$(printf '%s\n' "$found" | grep -v '^$' | grep -vxF -f "$2" || true)
[ -z "$unexpected" ] || {
	printf 'skips not in %s:\n%s\n' "$2" "$unexpected" >&2
	exit 1
}
