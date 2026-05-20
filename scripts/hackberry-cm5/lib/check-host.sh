#!/usr/bin/env bash
# Verify the host has what we need to customize a RaspiOS image into
# a Marathon Edition CM5 SD card.
set -euo pipefail

missing=0
need() {
    if ! command -v "$1" >/dev/null; then
        echo "  missing: $1   ($2)" >&2
        missing=1
    fi
}

# Image manipulation
need losetup        "util-linux"
need parted         "parted"
need mkfs.vfat      "dosfstools"
need mkfs.ext4      "e2fsprogs"
need resize2fs      "e2fsprogs"
need rsync          "rsync"
need xz             "xz"
need curl           "curl"

# Container / chroot
need systemd-nspawn "systemd-container"

# Device-tree compiler for hackberrypi.dtbo
need dtc            "device-tree-compiler"

# binfmt is needed if we ever cross-bake. On an aarch64 host we don't
# need it for an aarch64 target, but warn for completeness.
if [ "$(uname -m)" != "aarch64" ]; then
    if ! [ -d /proc/sys/fs/binfmt_misc/qemu-aarch64 ]; then
        echo "  warn: host is $(uname -m), and qemu-aarch64 binfmt_misc is not registered." >&2
        echo "        Install qemu-user-static + systemd-binfmt and re-run." >&2
        missing=1
    fi
fi

if [ "$missing" = "1" ]; then
    cat >&2 <<EOF

Install hints:
  Fedora/RHEL:   sudo dnf install util-linux parted dosfstools e2fsprogs rsync xz curl systemd-container dtc mtools
  Debian/Ubuntu: sudo apt install util-linux parted dosfstools e2fsprogs rsync xz-utils curl systemd-container device-tree-compiler mtools
  Alpine:        sudo apk add util-linux parted dosfstools e2fsprogs rsync xz curl systemd dtc mtools

(Fedora calls the device-tree compiler 'dtc'; Debian calls it
'device-tree-compiler'. Same binary either way.)

Sudo is required for losetup + systemd-nspawn. The orchestrator will
prompt when it needs it.
EOF
    exit 1
fi

echo "  ok"
