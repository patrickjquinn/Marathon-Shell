#!/usr/bin/env bash
# Report duplicate and missing numbers in packaging/pipeline-patches/.
set -euo pipefail

dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/packaging/pipeline-patches"
nums=$(cd "$dir" && ls [0-9][0-9][0-9][0-9]-*.patch | cut -c1-4)

dups=$(printf '%s\n' "$nums" | uniq -d)
[ -n "$dups" ] && echo "duplicate: $dups"

last=$(printf '%s\n' "$nums" | tail -1)
for i in $(seq 1 "$((10#$last))"); do
    n=$(printf '%04d' "$i")
    printf '%s\n' "$nums" | grep -qx "$n" || echo "missing: $n"
done
[ -z "$dups" ]
