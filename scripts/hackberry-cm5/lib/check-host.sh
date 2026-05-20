#!/usr/bin/env bash
# Verify the host has what we need to customize a RaspiOS image into
# a Marathon Edition CM5 SD card.
#
# The pipeline is fully rootless: virt-customize + virt-resize +
# guestfish (libguestfs) do all image modification inside a tiny QEMU
# VM, so the host kernel never touches loop devices.
set -euo pipefail

missing=0
need() {
    if ! command -v "$1" >/dev/null; then
        echo "  missing: $1   ($2)" >&2
        missing=1
    fi
}

# Image manipulation — all via libguestfs (rootless).
need virt-customize  "guestfs-tools"
need virt-resize     "guestfs-tools"
need guestfish       "guestfs-tools"

# Compression + fetch.
need xz              "xz"
need curl            "curl"

# Container for the apk-build helpers (not used by the CM5 path
# itself, but the orchestrator may invoke them — keep the check).
need podman          "podman"

if [ "$missing" = "1" ]; then
    cat >&2 <<EOF

Install hints:
  Fedora/RHEL:   sudo dnf install guestfs-tools xz curl podman
  Debian/Ubuntu: sudo apt install guestfs-tools xz-utils curl podman
  Alpine:        sudo apk add guestfs-tools xz curl podman

guestfs-tools is the only essential prereq — it ships virt-customize,
virt-resize, and guestfish. These run rootless via a private QEMU VM,
so the build never needs sudo.
EOF
    exit 1
fi

echo "  ok"
