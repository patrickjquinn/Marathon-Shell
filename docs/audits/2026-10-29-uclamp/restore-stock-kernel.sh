#!/bin/sh
set -eu
[ "${1:-}" = --restore ] || { echo "usage: sh restore-stock-kernel.sh --restore" >&2; exit 2; }
boot=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
test -f "$boot/config.txt.stock-before-uclamp-default"
cp "$boot/config.txt.stock-before-uclamp-default" "$boot/config.txt.restore-new"
sync
mv -f "$boot/config.txt.restore-new" "$boot/config.txt"
sync
echo 'Stock kernel selected for the next normal boot; no reboot issued.'
