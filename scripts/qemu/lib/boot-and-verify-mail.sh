#!/usr/bin/env bash
# Boot the latest baked image in QEMU, scp verify-mail.sh into the
# guest's auto-login user, run it, exit with its rc.
#
# Same structure as build-and-boot-phaseB.sh but skips the mkosi build
# step — assumes the image is already fresh in mkosi.output/.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DURANIUM_DIR="${DURANIUM_DIR:-${HOME}/.cache/marathon-build/duranium}"
OUT_BASE="$DURANIUM_DIR/mkosi.output/qemu-aarch64_marathon_edge"
SERIAL=/tmp/duranium-mail-serial.sock
QMP=/tmp/duranium-mail-qmp.sock
EFI_CODE=/usr/share/edk2/aarch64/QEMU_EFI-pflash.qcow2
EFI_VARS=/tmp/duranium-mail-efivars.qcow2

cd "$DURANIUM_DIR"

# Only the master bootable image — `<id>_<date>.raw` with no extra
# suffix. mkosi also emits .esp.raw / .usr-arm64*.raw / verity
# partitions; those aren't bootable on their own.
IMG="$(ls -1t "$OUT_BASE"/qemu-aarch64_marathon_edge_*.raw 2>/dev/null \
         | grep -E '/qemu-aarch64_marathon_edge_[0-9]+\.raw$' | head -1)"
[ -z "$IMG" ] && { echo "no raw image found in $OUT_BASE" >&2; exit 1; }
echo "==> image: $IMG"

qemu-img resize -f raw -q "$IMG" 20G 2>/dev/null || true

cp /usr/share/edk2/aarch64/QEMU_EFI-qemuvars-pflash.qcow2 "$EFI_VARS"
rm -f "$SERIAL" "$QMP"

echo "==> launching QEMU (KVM, serial on $SERIAL)"
qemu-system-aarch64 \
    -machine type=virt,memory-backend=mem -cpu host -accel kvm \
    -smp 2 -m 2048M \
    -object memory-backend-memfd,id=mem,size=2048M,share=on \
    -object rng-random,filename=/dev/urandom,id=rng0 \
    -device virtio-rng-pci,rng=rng0 \
    -device virtio-balloon \
    -nic user,model=virtio-net-pci,hostfwd=tcp:127.0.0.1:2223-:22 \
    -drive if=pflash,format=qcow2,readonly=on,file="$EFI_CODE" \
    -drive if=pflash,format=qcow2,file="$EFI_VARS" \
    -drive file="$IMG",format=raw,if=none,id=hd0,cache=writeback,discard=unmap \
    -device virtio-blk-pci,drive=hd0,bootindex=1 \
    -device virtio-gpu-pci,xres=720,yres=1440 \
    -device virtio-keyboard-pci -device virtio-tablet-pci \
    -display none \
    -serial unix:"$SERIAL",server,nowait \
    -qmp unix:"$QMP",server,nowait \
    -smbios "type=11,value=io.systemd.stub.kernel-cmdline-extra=systemd.wants=network.target SYSTEMD_SULOGIN_FORCE=1 rw systemd.mask=systemd-repart.service systemd.mask=cryptsetup.target systemd.mask=systemd-cryptsetup@pmOS_root.service module_blacklist=vmw_vmci loglevel=4 console=tty0 console=ttyAMA0,,115200" \
    -smbios "type=11,value=io.systemd.boot.kernel-cmdline-extra=systemd.wants=network.target SYSTEMD_SULOGIN_FORCE=1 rw systemd.mask=systemd-repart.service systemd.mask=cryptsetup.target systemd.mask=systemd-cryptsetup@pmOS_root.service module_blacklist=vmw_vmci loglevel=4 console=tty0 console=ttyAMA0,,115200" \
    -boot menu=on,splash-time=0 &
QEMU_PID=$!
trap 'echo "==> tearing down QEMU pid=$QEMU_PID"; kill -TERM $QEMU_PID 2>/dev/null || true' EXIT

echo "==> waiting for guest SSH on :2223 (up to 5 min)…"
for _ in $(seq 1 60); do
    if nc -z 127.0.0.1 2223 2>/dev/null; then break; fi
    sleep 5
done
nc -z 127.0.0.1 2223 || { echo "guest SSH never appeared" >&2; exit 2; }

# SSH in as root with the password from mkosi.postinst (sshd_config.d/
# 99-marathon-qemu.conf permits root password login for headless validation).
# Disable pubkey auth so we don't waste cycles trying our host's keys.
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
          -o ConnectTimeout=10 -o ServerAliveInterval=10 -o ServerAliveCountMax=3 \
          -o PreferredAuthentications=password -o PubkeyAuthentication=no -p 2223"
SSHPASS="sshpass -p marathon"

# Wait for sshd to be fully responsive (the listen-port becomes readable
# before sshd_config and host-keys are settled).
echo "==> waiting for sshd to accept commands (up to 60 s)"
for _ in $(seq 1 12); do
    if $SSHPASS ssh $SSH_OPTS root@127.0.0.1 true 2>/dev/null; then break; fi
    sleep 5
done

echo "==> piping verify-mail.sh into bash on the guest"
$SSHPASS ssh $SSH_OPTS root@127.0.0.1 'bash -s' < "$SCRIPT_DIR/verify-mail.sh"
RC=$?
echo "==> verify-mail.sh exit=$RC"
exit $RC
