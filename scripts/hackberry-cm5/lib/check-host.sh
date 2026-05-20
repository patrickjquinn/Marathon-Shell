#!/usr/bin/env bash
# Verify the host has what we need to customize a RaspiOS image into
# a Marathon Edition CM5 SD card.
#
# The pipeline is fully rootless AND requires NO new host installs
# beyond what duranium already needs. Everything image-related runs
# inside a rootless podman container (built from
# scripts/hackberry-cm5/Containerfile) which carries guestfs-tools
# internally. The host kernel never touches loop devices.
set -euo pipefail

missing=0
need() {
    if ! command -v "$1" >/dev/null; then
        echo "  missing: $1   ($2)" >&2
        missing=1
    fi
}

# Same prereqs as duranium — podman + qemu user-mode emulator for kvm
# acceleration inside the container.
need podman    "podman"
need curl      "curl"
need xz        "xz"
need tar       "tar"

# /dev/kvm passthrough lets virt-customize's helper VM run at native
# speed. Without it the build still works but takes ~5x longer.
if [ ! -r /dev/kvm ] || [ ! -w /dev/kvm ]; then
    echo "  warn: /dev/kvm not readable+writable by your user" >&2
    echo "        rootless podman will fall back to software emulation (~5x slower)" >&2
    echo "        fix: add yourself to the kvm group (sudo usermod -aG kvm \$USER, then re-login)" >&2
    # Not a hard fail — slow is better than not working.
fi

if [ "$missing" = "1" ]; then
    cat >&2 <<EOF

Install hints (Fedora syntax; same packages on other distros under
different names):
  Fedora/RHEL:   sudo dnf install podman curl xz tar
  Debian/Ubuntu: sudo apt install podman curl xz-utils tar
  Alpine:        sudo apk add podman curl xz tar

(These are the SAME packages duranium needs. There are no
CM5-specific host installs — guestfs-tools comes from the rootless
podman container built on first run.)
EOF
    exit 1
fi

echo "  ok"
