#!/bin/bash
# Marathon-Image — fully rootless aarch64 pmOS image build.
#
# No `sudo` invoked anywhere on the host. Uses rootless podman + Alpine to
# host the apk install, then `mke2fs -d` (e2fsprogs >= 1.43) to build a
# bootable ext4 image FROM the populated tree without ever mount(2)ing.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
OUT_DIR="$ROOT_DIR/build/rootless/out"
WORK_DIR="$ROOT_DIR/build/rootless/work"
PKGCACHE="$ROOT_DIR/build/rootless/pkgcache"

PMOS_BRANCH="${PMOS_BRANCH:-master}"
ARCH="aarch64"

mkdir -p "$OUT_DIR" "$WORK_DIR" "$PKGCACHE"

echo "═══ rootless pmOS build (no host sudo) ═══"
echo "host arch:    $(uname -m)"
echo "target arch:  $ARCH"
echo "pmos branch:  $PMOS_BRANCH"
echo "out dir:      $OUT_DIR"
echo ""

MARATHON_SHELL_SRC="${MARATHON_SHELL_SRC:-/home/patrickquinn/Developer/Marathon-Shell}"

# Run as root inside the rootless podman container — that's still rootless on
# the host (container root maps to host UID via user namespaces). Use abuild
# with -F (force-as-root) since rootless podman doesn't have the subuid range
# to give us a separate non-root build user.
podman run --rm -i \
    -v "$ROOT_DIR:/src:Z" \
    -v "$OUT_DIR:/out:Z" \
    -v "$WORK_DIR:/work:Z" \
    -v "$PKGCACHE:/pkgcache:Z" \
    -v "$MARATHON_SHELL_SRC:/shellsrc:Z,ro" \
    alpine:edge sh -s <<'CONTAINER_SCRIPT'
set -euo pipefail
echo "container: $(uname -a | head -1)"
echo "apk: $(apk --version 2>&1 | head -1)"

# ── tools ──────────────────────────────────────────────────────────────
apk add --no-cache --quiet \
    apk-tools-static e2fsprogs xz cpio gzip rsync abuild bash \
    curl ca-certificates git util-linux 2>&1 | tail -2

# Generate a build key (for signing the local apks).
mkdir -p /root/.abuild
abuild-keygen -a -n -q
KEY_PRIV=$(ls /root/.abuild/*.rsa | head -1)
KEY_PUB="${KEY_PRIV}.pub"
cp "$KEY_PUB" /etc/apk/keys/
export PACKAGER_PRIVKEY="$KEY_PRIV"
echo "PACKAGER_PRIVKEY=$KEY_PRIV" > /etc/abuild.conf

# ── 1. Marathon-base-config (file-only package, fast) ──────────────────
echo ""
echo "═══ 1/6 building marathon-base-config ═══"
mkdir -p /work/aports
rsync -a /src/packages/ /work/aports/

cd /work/aports/marathon-base-config
abuild -F checksum >/dev/null 2>&1
abuild -d -F 2>&1 | tail -3

# ── 2. Marathon-shell — heavy build (Qt6/QML/WebEngine) ────────────────
echo ""
echo "═══ 2/6 building marathon-shell (Qt6 build, ~10-20min cold) ═══"

# Stage local Marathon-Shell source as a tarball that abuild will use.
SHELL_VERSION=$(grep -E '^pkgver=' /work/aports/marathon-shell/APKBUILD | cut -d= -f2)
mkdir -p /var/cache/distfiles
mkdir -p /tmp/shellsrc-stage
rsync -a --delete \
      --exclude='.git' --exclude='build' --exclude='build-apps' \
      --exclude='build-ui' --exclude='.cache' --exclude='build-rootless' \
      /shellsrc/ /tmp/shellsrc-stage/Marathon-Shell-main/
( cd /tmp/shellsrc-stage && tar -cf - Marathon-Shell-main ) | \
    gzip -1 > "/var/cache/distfiles/marathon-shell-${SHELL_VERSION}.tar.gz"

if [ ! -f /var/cache/distfiles/asyncfuture.tar.gz ]; then
    curl -fsL -o /var/cache/distfiles/asyncfuture.tar.gz \
        https://github.com/vpicaver/asyncfuture/archive/master.tar.gz
fi

cd /work/aports/marathon-shell
abuild -F checksum >/dev/null 2>&1

# Install build deps (cached after first run).
echo "  installing Qt6 build deps..."
apk add --no-cache --quiet \
    cmake samurai \
    qt6-qtbase-dev qt6-qtdeclarative-dev qt6-qtwayland-dev \
    qt6-qtwebengine-dev qt6-qtmultimedia-dev qt6-qtsensors-dev \
    qt6-qtsvg-dev qt6-qtlocation-dev qt6-qtpositioning-dev \
    hunspell-dev pulseaudio-dev wayland-dev wayland-protocols \
    mesa-dev dbus-dev eudev-dev libinput-dev linux-pam-dev \
    git build-base 2>&1 | tail -2

echo "  abuild marathon-shell..."
abuild -d -F 2>&1 | tee /tmp/marathon-shell-build.log | tail -10
echo "  build log: $(wc -l < /tmp/marathon-shell-build.log) lines"
ls /root/packages/aports/aarch64/ 2>/dev/null | head -10

# ── 3. Stage local apks as a repo ───────────────────────────────────────
echo ""
echo "═══ 3/6 staging local apk repo ═══"
LOCAL_REPO_DIR=/work/local-apks
mkdir -p "$LOCAL_REPO_DIR/aarch64"
find /root/packages -name '*.apk' -exec cp {} "$LOCAL_REPO_DIR/aarch64/" \;
ls "$LOCAL_REPO_DIR/aarch64/"

# Build the index for this repo.
( cd "$LOCAL_REPO_DIR/aarch64" && \
  apk index -o APKINDEX.tar.gz *.apk 2>/dev/null && \
  abuild-sign -k "$KEY_PRIV" APKINDEX.tar.gz )

# ── 4. Bootstrap pmOS rootfs ───────────────────────────────────────────
echo ""
echo "═══ 4/6 bootstrapping pmOS rootfs (apk.static --root) ═══"
ROOTFS=/work/rootfs
rm -rf "$ROOTFS"
mkdir -p "$ROOTFS"

apk.static \
    --root "$ROOTFS" --arch aarch64 --initdb \
    --cache-dir /pkgcache \
    --keys-dir /etc/apk/keys \
    -X "https://dl-cdn.alpinelinux.org/alpine/edge/main" \
    -X "https://dl-cdn.alpinelinux.org/alpine/edge/community" \
    -X "https://mirror.postmarketos.org/postmarketos/master" \
    -X "$LOCAL_REPO_DIR" \
    --allow-untrusted \
    --no-progress \
    add \
    alpine-base \
    postmarketos-base \
    postmarketos-mkinitfs \
    linux-postmarketos-qemu \
    e2fsprogs util-linux \
    openrc \
    marathon-base-config marathon-shell 2>&1 | tail -20

# ── 5. Generate initramfs ──────────────────────────────────────────────
echo ""
echo "═══ 5/6 generating initramfs ═══"
chroot "$ROOTFS" /sbin/mkinitfs 2>&1 | tail -5 || true

KERNEL=$(ls "$ROOTFS"/boot/vmlinuz* 2>/dev/null | head -1)
INITRAMFS=$(ls "$ROOTFS"/boot/initramfs* 2>/dev/null | head -1)
echo "kernel:    ${KERNEL:-MISSING}"
echo "initramfs: ${INITRAMFS:-MISSING}"

# ── 6. Build ext4 rootfs.img ───────────────────────────────────────────
echo ""
echo "═══ 6/6 building ext4 image (mke2fs -d) ═══"
SIZE_BYTES=$(du -sb "$ROOTFS" | cut -f1)
SIZE_BYTES=$((SIZE_BYTES * 3 / 2 + 256 * 1024 * 1024))
truncate -s "$SIZE_BYTES" /out/rootfs.img
mke2fs -t ext4 -F -L pmOS_root \
       -d "$ROOTFS" \
       -E root_owner=0:0 \
       /out/rootfs.img 2>&1 | tail -3

if [ -n "$KERNEL" ]; then cp "$KERNEL" /out/kernel; fi
if [ -n "$INITRAMFS" ]; then cp "$INITRAMFS" /out/initramfs; fi

echo ""
echo "=== output ==="
ls -lh /out/
CONTAINER_SCRIPT

cat > "$OUT_DIR/qemu-cmd" <<EOF
#!/bin/bash
exec qemu-system-aarch64 \\
  -M virt -cpu cortex-a72 -m 2G -smp 4 \\
  -kernel "$OUT_DIR/kernel" \\
  -initrd "$OUT_DIR/initramfs" \\
  -drive if=virtio,file="$OUT_DIR/rootfs.img",format=raw \\
  -append "root=/dev/vda rw console=ttyAMA0 console=tty0 video=720x1440 systemd.show_status=true" \\
  -device virtio-gpu-pci -display gtk,gl=off \\
  -nic user,model=virtio-net-pci,hostfwd=tcp::2222-:22 \\
  -serial stdio \\
  "\$@"
EOF
chmod +x "$OUT_DIR/qemu-cmd"

echo ""
echo "═══ build done ═══"
echo "  $OUT_DIR/qemu-cmd"
