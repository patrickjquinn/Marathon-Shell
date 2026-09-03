#!/usr/bin/env bash
# Boot the latest baked image and verify the Marathon SHELL is up
# (compositor + greetd auto-login + wayland socket + the QML scene
# graph painting something). Mirrors boot-and-verify-mail.sh's
# launch sequence so we get one path that's known to boot.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DURANIUM_DIR="${DURANIUM_DIR:-${HOME}/.cache/marathon-build/duranium}"
OUT_BASE="$DURANIUM_DIR/mkosi.output/qemu-aarch64_marathon_edge"
SERIAL=/tmp/marathon-shell-serial.sock
QMP=/tmp/marathon-shell-qmp.sock
SCREEN=/tmp/marathon-shell-screen.ppm
SCREEN_PNG=/tmp/marathon-shell-screen.png

cd "$DURANIUM_DIR"

IMG="$(ls -1t "$OUT_BASE"/qemu-aarch64_marathon_edge_*.raw 2>/dev/null \
         | grep -E '/qemu-aarch64_marathon_edge_[0-9]+\.raw$' | head -1)"
[ -z "$IMG" ] && { echo "no raw image found in $OUT_BASE" >&2; exit 1; }
echo "==> image: $IMG"

# Boot the extracted kernel+initrd directly instead of via UEFI/UKI — the
# systemd-boot path can't discover root on the QEMU image (masked
# cryptsetup + gpt-auto), so it hangs in the initrd. See lib/extract-uki.sh.
# `|| true`: under `set -euo pipefail` an unmatched glob makes ls exit 2,
# pipefail carries it through head, and the assignment kills the script
# before the explicit "no UKI found" check below can report anything.
UKI="$(ls -1t "$OUT_BASE"/qemu-aarch64_marathon_edge_*.efi 2>/dev/null | head -1 || true)"
[ -z "$UKI" ] && { echo "no UKI (.efi) found in $OUT_BASE" >&2; exit 1; }
. "$SCRIPT_DIR/extract-uki.sh"
extract_uki_kernel_initrd "$UKI" /tmp/marathon-shell-uki || exit 1

qemu-img resize -f raw -q "$IMG" 20G 2>/dev/null || true
rm -f "$SERIAL" "$QMP" "$SCREEN" "$SCREEN_PNG"

# Explicit root= bypasses gpt-auto/cryptsetup; no SYSTEMD_SULOGIN_FORCE so
# a non-fatal early failure can't drop us into a headless emergency shell.
DIRECT_CMDLINE="root=LABEL=pmOS_root rw rootwait \
systemd.mask=systemd-repart.service systemd.mask=cryptsetup.target \
systemd.mask=systemd-cryptsetup@pmOS_root.service \
module_blacklist=vmw_vmci loglevel=4 console=tty0 console=ttyAMA0,115200 \
pmos.force-partition-resize psi=1"

echo "==> launching QEMU (KVM, serial=$SERIAL, qmp=$QMP)"
qemu-system-aarch64 \
    -machine type=virt,memory-backend=mem -cpu host -accel kvm \
    -smp 2 -m 2048M \
    -object memory-backend-memfd,id=mem,size=2048M,share=on \
    -object rng-random,filename=/dev/urandom,id=rng0 \
    -device virtio-rng-pci,rng=rng0 \
    -device virtio-balloon \
    -nic user,model=virtio-net-pci,hostfwd=tcp:127.0.0.1:2228-:22 \
    -drive file="$IMG",format=raw,if=none,id=hd0,cache=writeback,discard=unmap \
    -device virtio-blk-pci,drive=hd0 \
    -device virtio-gpu-gl-pci,xres=720,yres=1440 \
    -device virtio-keyboard-pci -device virtio-tablet-pci \
    -display egl-headless,gl=on \
    -serial unix:"$SERIAL",server,nowait \
    -qmp unix:"$QMP",server,nowait \
    -kernel "$UKI_KERNEL" -initrd "$UKI_INITRD" -append "$DIRECT_CMDLINE" &
QEMU_PID=$!
trap 'echo "==> tearing down QEMU pid=$QEMU_PID"; kill -TERM $QEMU_PID 2>/dev/null || true' EXIT

echo "==> waiting for guest SSH on :2228 (up to 5 min)…"
for _ in $(seq 1 60); do
    nc -z 127.0.0.1 2228 2>/dev/null && break
    sleep 5
done
nc -z 127.0.0.1 2228 || { echo "guest SSH never appeared" >&2; exit 2; }

SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
          -o ConnectTimeout=30 -o ServerAliveInterval=10 -o ServerAliveCountMax=6 \
          -o PreferredAuthentications=password -o PubkeyAuthentication=no -p 2228"
SSHPASS="sshpass -p marathon"

echo "==> waiting for sshd banner (up to 90 s)"
for _ in $(seq 1 18); do
    if $SSHPASS ssh $SSH_OPTS root@127.0.0.1 true 2>/dev/null; then
        break
    fi
    sleep 5
done

echo "==> giving the shell another 30s to bring up compositor + greetd auto-login"
sleep 30

echo "==> piping verify-shell.sh into bash on the guest"
set +e
$SSHPASS ssh $SSH_OPTS root@127.0.0.1 'bash -s' < "$SCRIPT_DIR/verify-shell.sh"
RC=$?
set -e
echo "==> verify-shell.sh exit=$RC"

echo "==> capturing screendump via QMP"
printf '{"execute":"qmp_capabilities"}\n{"execute":"screendump","arguments":{"filename":"%s"}}\n' \
    "$SCREEN" | nc -U "$QMP" -w 2 >/dev/null
sleep 2
if [ -s "$SCREEN" ]; then
    SIZE=$(stat -c%s "$SCREEN")
    echo "    ppm: $SCREEN ($SIZE bytes, 720x1440)"
    if command -v magick >/dev/null; then
        magick "$SCREEN" "$SCREEN_PNG" 2>/dev/null
    elif command -v convert >/dev/null; then
        convert "$SCREEN" "$SCREEN_PNG" 2>/dev/null
    elif command -v pnmtopng >/dev/null; then
        pnmtopng "$SCREEN" > "$SCREEN_PNG" 2>/dev/null
    fi
    [ -f "$SCREEN_PNG" ] && echo "    png: $SCREEN_PNG ($(stat -c%s "$SCREEN_PNG") bytes)"
else
    echo "    screendump produced no output" >&2
fi

exit $RC
