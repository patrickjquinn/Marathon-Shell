#!/usr/bin/env bash
# Host prerequisite check. Sourced by build-qemu-image.sh.
#
# Exit non-zero if a required tool is missing, after printing the
# install hint for the user's package manager (best-effort).

set -euo pipefail

REQUIRED=(
    "podman:podman:Container runtime for rootless apk builds. dnf install podman / apt install podman / pacman -S podman."
    "qemu-system-aarch64:qemu-system-aarch64:aarch64 QEMU emulator. dnf install qemu-system-aarch64 / apt install qemu-system-arm / pacman -S qemu-emulators-full."
    "sshpass:sshpass:Non-interactive SSH password auth for QEMU verify scripts. dnf install sshpass / apt install sshpass / pacman -S sshpass."
    "git:git:Source control."
    "python3:python3:Used by mkosi + the image build wrapper."
)
# nc is provided by either nmap-ncat or openbsd-netcat depending on
# distro; not enforced here.

# Optional but strongly recommended: mkosi. We vendor it under
# $MARATHON_BUILD_DIR/mkosi-src so no system install is required.
# Only flag if neither vendored nor on PATH.

missing=0
for entry in "${REQUIRED[@]}"; do
    bin="${entry%%:*}"
    rest="${entry#*:}"
    name="${rest%%:*}"
    hint="${rest#*:}"
    if ! command -v "$bin" >/dev/null 2>&1; then
        echo "missing host tool: $name" >&2
        echo "  $hint" >&2
        missing=1
    fi
done

# EFI firmware for aarch64 QEMU — varies by distro path. Look in the
# canonical locations.
EFI_CANDIDATES=(
    /usr/share/edk2/aarch64/QEMU_EFI-pflash.qcow2
    /usr/share/AAVMF/AAVMF_CODE.fd
    /usr/share/qemu-efi-aarch64/QEMU_EFI.fd
    /usr/share/qemu/edk2-aarch64-code.fd
)
HAVE_EFI=0
for c in "${EFI_CANDIDATES[@]}"; do
    [ -f "$c" ] && HAVE_EFI=1 && break
done
if [ "$HAVE_EFI" -eq 0 ]; then
    echo "missing host data: aarch64 EFI firmware for QEMU" >&2
    echo "  dnf install edk2-aarch64 / apt install qemu-efi-aarch64 / pacman -S edk2-armvirt" >&2
    missing=1
fi

if [ "$missing" -ne 0 ]; then
    echo
    echo "Install the listed dependencies and re-run." >&2
    exit 1
fi
