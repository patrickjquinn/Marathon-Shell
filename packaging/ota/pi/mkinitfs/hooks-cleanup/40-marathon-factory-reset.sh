#!/bin/sh
# "Erase all content" (docs/FACTORY_RESET.md): marathon-factory-reset left
# a marker on this slot's root. Erase the data partition before
# 50-marathon-ab.sh opens or mounts it; that hook then seeds it as on a
# first boot. The marker stays until the erase succeeds.
root=${MARATHON_AB_TEST_ROOT:-}
marker=$root/sysroot/.marathon-factory-reset
[ -e "$marker" ] || exit 0

log() {
	echo "marathon-factory-reset: $*" > "$root/dev/kmsg"
}

link=$root/dev/disk/by-partlabel/marathon_data
[ -e "$link" ] || { log "no marathon_data partition to erase"; exit 1; }
data=$(readlink -f "$link")
log "erasing $data"
if ! "$root/usr/libexec/marathon-wipe-data" "$data"; then
	log "could not erase $data; trying again at the next boot"
	exit 1
fi
rm -f "$marker"
sync
log "erased $data"
