#!/bin/bash
# SPDX-FileCopyrightText: 2026 Patrick Quinn
# SPDX-License-Identifier: Apache-2.0
#
# Fetches the third-party data the package bundles into <dir>, each checked
# against the pins in core/data/versions.env:
#   autoconsent/autoconsent.js  DuckDuckGo autoconsent standalone (MPL-2.0)
#   adblock/resources.json      Brave adblock-resources (MPL-2.0)
#   filter-lists/<id>.txt       the default filter lists, so blocking works
#                               offline from the first start; the app
#                               refreshes them every four days.
#
#   apps/pacific/fetch-data.sh <dir>
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
data=${1:?usage: fetch-data.sh <dir>}
pins=$here/core/data/versions.env
pin() { sed -n "s/^$1=//p" "$pins"; }
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$data/autoconsent" "$data/adblock" "$data/filter-lists"

check() { # file sha256
    echo "$2  $1" | sha256sum -c - >/dev/null || { echo "fetch-data: $1 does not match its pin" >&2; exit 1; }
}

# autoconsent: the npm tarball, then the standalone build inside it.
curl -fsSL -o "$work/ac.tgz" "$(pin AUTOCONSENT_URL)"
check "$work/ac.tgz" "$(pin AUTOCONSENT_TGZ_SHA256)"
tar -xzf "$work/ac.tgz" -C "$work" package/dist/autoconsent.standalone.js package/LICENSE
check "$work/package/dist/autoconsent.standalone.js" "$(pin AUTOCONSENT_JS_SHA256)"
install -m 0644 "$work/package/dist/autoconsent.standalone.js" "$data/autoconsent/autoconsent.js"
install -m 0644 "$work/package/LICENSE" "$data/autoconsent/LICENSE"

curl -fsSL -o "$work/resources.json" "$(pin ADBLOCK_RESOURCES_URL)"
check "$work/resources.json" "$(pin ADBLOCK_RESOURCES_SHA256)"
install -m 0644 "$work/resources.json" "$data/adblock/resources.json"

# The default filter lists: their publishers offer no dated URLs, so the
# newest copy is taken and its hash recorded next to it (SHA256SUMS).
: > "$data/filter-lists/SHA256SUMS"
while read -r id url; do
    curl -fsSL -o "$work/$id.txt" "$url"
    head -c 512 "$work/$id.txt" | grep -qiE '^\[adblock|^!' || { echo "fetch-data: $url is not a filter list" >&2; exit 1; }
    install -m 0644 "$work/$id.txt" "$data/filter-lists/$id.txt"
    (cd "$data/filter-lists" && sha256sum "$id.txt" >> SHA256SUMS)
done <<LISTS
easylist https://easylist.to/easylist/easylist.txt
easyprivacy https://easylist.to/easylist/easyprivacy.txt
ubo-filters https://ublockorigin.github.io/uAssets/filters/filters.txt
ubo-privacy https://ublockorigin.github.io/uAssets/filters/privacy.txt
peter-lowe https://pgl.yoyo.org/adservers/serverlist.php?hostformat=adblockplus&showintro=1&mimetype=plaintext
LISTS
