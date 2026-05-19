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

# Per-boot EFI vars file so two boots don't clobber each other's
# variable store. /tmp is fine — it's regenerated every run.
EFI_VARS="/tmp/marathon-qemu-vars-$$.qcow2"
cp /usr/share/edk2/aarch64/QEMU_EFI-qemuvars-pflash.qcow2 "$EFI_VARS"
trap 'rm -f "$EFI_VARS"' EXIT

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

# Same kernel cmdline workarounds verify-mail.sh / verify-shell.sh use:
# mask repart + cryptsetup so the auto-resize-and-encrypt-root logic
# from postmarketos-duranium's first-boot doesn't loop on QEMU.
CMDLINE='systemd.wants=network.target SYSTEMD_SULOGIN_FORCE=1 rw \
systemd.mask=systemd-repart.service \
systemd.mask=cryptsetup.target \
systemd.mask=systemd-cryptsetup@pmOS_root.service \
module_blacklist=vmw_vmci loglevel=4 console=tty0 console=ttyAMA0,,115200'

exec qemu-system-aarch64 \
    -machine type=virt,memory-backend=mem -cpu host -accel kvm \
    -smp 2 -m 2048M \
    -object memory-backend-memfd,id=mem,size=2048M,share=on \
    -object rng-random,filename=/dev/urandom,id=rng0 \
    -device virtio-rng-pci,rng=rng0 -device virtio-balloon \
    -nic user,model=virtio-net-pci,hostfwd=tcp:127.0.0.1:$SSH_PORT-:22 \
    -drive if=pflash,format=qcow2,readonly=on,file=/usr/share/edk2/aarch64/QEMU_EFI-pflash.qcow2 \
    -drive if=pflash,format=qcow2,file="$EFI_VARS" \
    -drive file="$IMG",format=raw,if=none,id=hd0,cache=writeback,discard=unmap \
    -device virtio-blk-pci,drive=hd0,bootindex=1 \
    -device virtio-gpu-gl-pci,xres=720,yres=1440 \
    -device virtio-keyboard-pci -device virtio-tablet-pci \
    "${DISPLAY_ARGS[@]}" \
    -smbios "type=11,value=io.systemd.stub.kernel-cmdline-extra=$CMDLINE" \
    -smbios "type=11,value=io.systemd.boot.kernel-cmdline-extra=$CMDLINE" \
    -boot menu=on,splash-time=0
