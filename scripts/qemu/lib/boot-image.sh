#!/usr/bin/env bash
# Boot the latest baked Marathon QEMU image with GL acceleration.
#
# Used by:
#   • scripts/build-qemu-image.sh --boot   (interactive shell window)
#   • Patrick's dev simulator at :2222
#   • Anywhere we want "just boot Marathon in QEMU and let me poke at it"
#
# Display mode is auto-detected from the host environment but
# overridable via $MARATHON_QEMU_DISPLAY:
#
#   gtk      pop a GTK window for direct interaction. Default when
#            $DISPLAY or $WAYLAND_DISPLAY is set on the host.
#   vnc      headless QEMU + VNC server on 127.0.0.1:5905 (display :5).
#            Use a VNC viewer (`remmina vnc://127.0.0.1:5905`,
#            `vncviewer 127.0.0.1:5`, etc.) to interact.
#   none     headless background. SSH-only access.
#
# Marathon-Shell's QML scene-graph crashes under software rasterisation,
# so we always use `virtio-gpu-gl-pci` + a GL-capable display. Mesa-
# virgl in the guest translates virgl3d wire protocol to native host GL.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Resolved by setup-trees.sh when called from build-qemu-image.sh;
# fall back to the conventional cache path otherwise.
DURANIUM_DIR="${DURANIUM_DIR:-${HOME}/.cache/marathon-build/duranium}"
OUT_BASE="$DURANIUM_DIR/mkosi.output/qemu-aarch64_marathon_edge"

# Ports under user discretion via $MARATHON_QEMU_SSH_PORT / VNC_PORT,
# but defaults stay out of the way of the other harnesses in this
# repo (verify-mail.sh uses :2223, boot-and-verify-shell.sh :2228).
SSH_PORT="${MARATHON_QEMU_SSH_PORT:-2233}"
VNC_DISPLAY_NUM="${MARATHON_QEMU_VNC_DISPLAY:-5}"  # → 127.0.0.1:5905

# Locate the freshly baked image.
IMG="$(ls -1t "$OUT_BASE"/qemu-aarch64_marathon_edge_*.raw 2>/dev/null \
        | grep -E '/qemu-aarch64_marathon_edge_[0-9]+\.raw$' | head -1)"
[ -z "$IMG" ] && { echo "no raw image found in $OUT_BASE" >&2; exit 1; }
echo "==> image: $IMG"

# mkosi writes the raw at its on-disk minimum; qemu wants room to
# grow for /var work. Resize is a no-op if already 20G.
qemu-img resize -f raw -q "$IMG" 20G 2>/dev/null || true

# Boot the extracted kernel+initrd directly instead of via UEFI/UKI — the
# systemd-boot path can't discover root on the QEMU image (masked
# cryptsetup + gpt-auto), so it hangs in the initrd. See lib/extract-uki.sh.
UKI="$(ls -1t "$OUT_BASE"/qemu-aarch64_marathon_edge_*.efi 2>/dev/null | head -1)"
[ -z "$UKI" ] && { echo "no UKI (.efi) found in $OUT_BASE" >&2; exit 1; }
. "$SCRIPT_DIR/extract-uki.sh"
extract_uki_kernel_initrd "$UKI" /tmp/marathon-qemu-uki || exit 1

# Pick the display flag set. VNC is the default because it works in
# every environment — local desktop, SSH session, headless server.
# Connect with any VNC client (Remmina, vinagre, vncviewer, the macOS
# Screen Sharing app, …).
#
# Set MARATHON_QEMU_DISPLAY=gtk to pop a native GTK window if you'd
# rather click around directly. (Requires a working $DISPLAY or
# $WAYLAND_DISPLAY on the host and qemu-system-aarch64 built with GTK.)
DISPLAY_MODE="${MARATHON_QEMU_DISPLAY:-vnc}"

DISPLAY_ARGS=()
case "$DISPLAY_MODE" in
    gtk)
        DISPLAY_ARGS=(-display "gtk,gl=on")
        echo "==> display: gtk window (GL accelerated)"
        ;;
    vnc)
        DISPLAY_ARGS=(-display "egl-headless,gl=on" -vnc "127.0.0.1:$VNC_DISPLAY_NUM")
        echo "==> display: VNC on 127.0.0.1:$((5900 + VNC_DISPLAY_NUM)) (egl-headless GL)"
        ;;
    none)
        DISPLAY_ARGS=(-display "none")
        echo "==> display: none (SSH-only)"
        ;;
    *)
        echo "unknown MARATHON_QEMU_DISPLAY=$DISPLAY_MODE; expected gtk/vnc/none" >&2
        exit 64
        ;;
esac

echo "==> ssh:      sshpass -p marathon ssh -p $SSH_PORT root@127.0.0.1"
echo "    or, as the user account: ... user@127.0.0.1   (no password; sudo passwd user inside to set one)"
echo
echo "Ctrl-C in this terminal stops QEMU."

# Explicit root=LABEL=pmOS_root bypasses gpt-auto/cryptsetup (masked here);
# mask repart + cryptsetup so duranium's first-boot resize-and-encrypt
# logic doesn't loop on QEMU. No SYSTEMD_SULOGIN_FORCE — with the boot
# fixed it only ever hurts (a headless `none`-mode failure would hang in
# an emergency shell we can't reach).
DIRECT_CMDLINE="root=LABEL=pmOS_root rw rootwait \
systemd.wants=network.target \
systemd.mask=systemd-repart.service systemd.mask=cryptsetup.target \
systemd.mask=systemd-cryptsetup@pmOS_root.service \
module_blacklist=vmw_vmci loglevel=4 console=tty0 console=ttyAMA0,115200 \
pmos.force-partition-resize psi=1"

exec qemu-system-aarch64 \
    -machine type=virt,memory-backend=mem -cpu host -accel kvm \
    -smp 2 -m 2048M \
    -object memory-backend-memfd,id=mem,size=2048M,share=on \
    -object rng-random,filename=/dev/urandom,id=rng0 \
    -device virtio-rng-pci,rng=rng0 -device virtio-balloon \
    -nic user,model=virtio-net-pci,hostfwd=tcp:127.0.0.1:$SSH_PORT-:22 \
    -drive file="$IMG",format=raw,if=none,id=hd0,cache=writeback,discard=unmap \
    -device virtio-blk-pci,drive=hd0 \
    -device virtio-gpu-gl-pci,xres=720,yres=1440 \
    -device virtio-keyboard-pci -device virtio-tablet-pci \
    "${DISPLAY_ARGS[@]}" \
    -kernel "$UKI_KERNEL" -initrd "$UKI_INITRD" -append "$DIRECT_CMDLINE"
