#!/bin/bash
# Stage 1: barebones pmOS rootfs build (no Marathon).
# Validates the rootless container + apk.static + mke2fs -d path before we
# layer Marathon on top.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
OUT_DIR="$ROOT_DIR/build/rootless/out"
WORK_DIR="$ROOT_DIR/build/rootless/work"
PKGCACHE="$ROOT_DIR/build/rootless/pkgcache"

mkdir -p "$OUT_DIR" "$WORK_DIR" "$PKGCACHE"

echo "═══ stage 1 — barebones pmOS rootless build ═══"

podman run --rm -i \
    -v "$OUT_DIR:/out:Z" \
    -v "$WORK_DIR:/work:Z" \
    -v "$PKGCACHE:/pkgcache:Z" \
    alpine:edge sh -s <<'CSCRIPT'
set -euo pipefail
apk add --no-cache --quiet apk-tools-static e2fsprogs util-linux 2>&1 | tail -2

ROOTFS=/work/rootfs
rm -rf "$ROOTFS"
mkdir -p "$ROOTFS"

echo "── bootstrapping pmOS rootfs (trigger errors expected on first pass) ──"
apk.static \
    --root "$ROOTFS" --arch aarch64 --initdb \
    --cache-dir /pkgcache \
    -X https://dl-cdn.alpinelinux.org/alpine/edge/main \
    -X https://dl-cdn.alpinelinux.org/alpine/edge/community \
    -X https://mirror.postmarketos.org/postmarketos/master \
    --allow-untrusted --no-progress \
    add \
        alpine-base \
        postmarketos-base \
        postmarketos-mkinitfs \
        device-qemu-aarch64 \
        device-qemu-aarch64-kernel-lts \
        losetup util-linux-misc \
        openrc 2>&1 | tail -10 || echo "  (trigger errors swallowed — fixups run next)"
echo ""
echo "── installed packages ──"
apk --root "$ROOTFS" info 2>/dev/null | wc -l
echo "  package count above"
echo ""

echo "── usr-merge fixups for mkinitfs ──"
# Alpine edge ships losetup at /sbin/losetup; postmarketos-mkinitfs file
# lists reference /usr/sbin/losetup. Symlink so the trigger succeeds.
if [ -x "$ROOTFS/sbin/losetup" ] && [ ! -e "$ROOTFS/usr/sbin/losetup" ]; then
    ln -sf /sbin/losetup "$ROOTFS/usr/sbin/losetup"
fi

echo "── skipping mkinitfs (kernel has virtio_blk + ext4 built-in) ──"
# postmarketos-mkinitfs needs /proc + /sys + /dev bind-mounts inside the
# chroot, which require CAP_SYS_ADMIN inside the container. Rootless podman
# without --privileged can't grant that. We work around by booting the
# kernel directly with `root=/dev/vda` — every required driver is built-in
# (verified against /boot/config: CONFIG_VIRTIO_BLK=y, CONFIG_VIRTIO_PCI=y,
# CONFIG_EXT4_FS=y). No initramfs needed for first-boot.

echo "── kernel + initramfs ──"
ls "$ROOTFS"/boot/ 2>/dev/null

echo ""
echo "── building ext4 image ──"
SIZE=$(du -sb "$ROOTFS" | cut -f1)
SIZE=$((SIZE * 3 / 2 + 128 * 1024 * 1024))
truncate -s "$SIZE" /out/rootfs.img
mke2fs -t ext4 -F -L pmOS_root \
       -d "$ROOTFS" \
       -E root_owner=0:0 \
       /out/rootfs.img 2>&1 | tail -3

# Copy kernel + initramfs out.
KERNEL=$(ls "$ROOTFS"/boot/vmlinuz* 2>/dev/null | head -1)
INITRAMFS=$(ls "$ROOTFS"/boot/initramfs* 2>/dev/null | head -1)
if [ -n "$KERNEL" ]; then cp "$KERNEL" /out/kernel; echo "  kernel: $(basename "$KERNEL") → /out/kernel"; fi
if [ -n "$INITRAMFS" ]; then cp "$INITRAMFS" /out/initramfs; echo "  initramfs: $(basename "$INITRAMFS")"; else echo "  no initramfs (booting direct)"; fi

echo ""
echo "── output ──"
ls -lh /out/
CSCRIPT

echo ""
echo "═══ stage 1 done ═══"
echo "files at: $OUT_DIR"
ls -lh "$OUT_DIR/"
