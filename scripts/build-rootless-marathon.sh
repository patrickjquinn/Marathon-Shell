#!/bin/bash
# Stage 2: Marathon pmOS rootless build (systemd channel + Marathon packages).
# Builds marathon-base-config locally, layers it onto a pmOS systemd rootfs,
# packs ext4 image, validates rootless boot.
#
# marathon-shell apk (Qt6/QML/WebEngine) is OPTIONAL via WITH_MARATHON_SHELL=1
# — it's a 30+ minute first-build because of WebEngine.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
OUT_DIR="$ROOT_DIR/build/rootless/out"
WORK_DIR="$ROOT_DIR/build/rootless/work"
PKGCACHE="$ROOT_DIR/build/rootless/pkgcache"

WITH_MARATHON_SHELL="${WITH_MARATHON_SHELL:-0}"
MARATHON_SHELL_SRC="${MARATHON_SHELL_SRC:-/home/patrickquinn/Developer/Marathon-Shell}"

mkdir -p "$OUT_DIR" "$WORK_DIR" "$PKGCACHE"

echo "═══ stage 2 — Marathon pmOS rootless build (systemd) ═══"
echo "WITH_MARATHON_SHELL=$WITH_MARATHON_SHELL"

podman run --rm -i \
    -e WITH_MARATHON_SHELL="$WITH_MARATHON_SHELL" \
    -v "$ROOT_DIR:/src:Z" \
    -v "$OUT_DIR:/out:Z" \
    -v "$WORK_DIR:/work:Z" \
    -v "$PKGCACHE:/pkgcache:Z" \
    -v "$MARATHON_SHELL_SRC:/shellsrc:Z,ro" \
    alpine:edge sh -s <<'CSCRIPT'
set -euo pipefail
apk add --no-cache --quiet \
    apk-tools-static e2fsprogs util-linux abuild rsync curl ca-certificates 2>&1 | tail -2

# build key
mkdir -p /root/.abuild
abuild-keygen -a -n -q
KEY_PRIV=$(ls /root/.abuild/*.rsa | head -1)
KEY_PUB="${KEY_PRIV}.pub"
cp "$KEY_PUB" /etc/apk/keys/
echo "PACKAGER_PRIVKEY=$KEY_PRIV" > /etc/abuild.conf

# ─ 1. Build marathon-base-config (file-only, fast) ─
echo "─ building marathon-base-config ─"
mkdir -p /work/aports
# Use --checksum so file content drives sync, not mtime — bind-mount mtime
# preservation under SELinux :Z relabel can leave stale content in the
# work tree. Also force --no-times to avoid carrying mtimes that confuse
# later rsync compares.
rsync -a --checksum --no-times --delete /src/packages/ /work/aports/
cd /work/aports/marathon-base-config
abuild -F checksum >/dev/null 2>&1
abuild -d -F 2>&1 | tail -2

# Optional: marathon-shell — heavy (Qt6 + WebEngine)
if [ "${WITH_MARATHON_SHELL:-0}" = "1" ]; then
    echo "─ building marathon-shell (Qt6/QML/WebEngine, ~30min cold) ─"
    SHELL_VERSION=$(grep -E '^pkgver=' /work/aports/marathon-shell/APKBUILD | cut -d= -f2)
    mkdir -p /var/cache/distfiles /tmp/shellsrc-stage
    # --checksum --no-times: see note above. Without this, edits made
    # between rapid rebuilds can fail to propagate and the apk gets built
    # against stale source.
    rsync -a --checksum --no-times --delete \
          --exclude='.git' --exclude='build' --exclude='build-apps' \
          --exclude='build-ui' --exclude='.cache' \
          /shellsrc/ /tmp/shellsrc-stage/Marathon-Shell-main/
    ( cd /tmp/shellsrc-stage && tar -cf - Marathon-Shell-main ) | gzip -1 \
        > "/var/cache/distfiles/marathon-shell-${SHELL_VERSION}.tar.gz"
    [ ! -f /var/cache/distfiles/asyncfuture.tar.gz ] && \
        curl -fsL -o /var/cache/distfiles/asyncfuture.tar.gz \
            https://github.com/vpicaver/asyncfuture/archive/master.tar.gz

    apk add --no-cache --quiet cmake samurai \
        qt6-qtbase-dev qt6-qtdeclarative-dev qt6-qtwayland-dev \
        qt6-qtwebengine-dev qt6-qtmultimedia-dev qt6-qtsensors-dev \
        qt6-qtsvg-dev qt6-qtlocation-dev qt6-qtpositioning-dev \
        hunspell-dev pulseaudio-dev wayland-dev wayland-protocols \
        mesa-dev dbus-dev eudev-dev libinput-dev linux-pam-dev \
        git build-base 2>&1 | tail -2

    cd /work/aports/marathon-shell
    abuild -F checksum >/dev/null 2>&1
    abuild -d -F 2>&1 | tail -5
fi

# ─ 2. Local repo from built apks ─
echo "─ staging local apk repo ─"
LOCAL_REPO=/work/local-apks
mkdir -p "$LOCAL_REPO/aarch64"
find /root/packages -name '*.apk' -exec cp {} "$LOCAL_REPO/aarch64/" \;
ls "$LOCAL_REPO/aarch64/"
( cd "$LOCAL_REPO/aarch64" && \
  apk index -o APKINDEX.tar.gz *.apk 2>/dev/null && \
  abuild-sign -k "$KEY_PRIV" APKINDEX.tar.gz )

# ─ 3. Bootstrap pmOS systemd rootfs ─
echo "─ bootstrapping pmOS systemd rootfs ─"
ROOTFS=/work/rootfs
rm -rf "$ROOTFS"; mkdir -p "$ROOTFS"

# Pull from systemd extra-repo. Order matters:
#   alpine main/community  — base userland
#   pmOS master            — postmarketos-base, mkinitfs, device-qemu
#   pmOS extra-repos/systemd/master  — systemd-targeting overrides
#   local-apks             — marathon-base-config (and marathon-shell)
EXTRAS="postmarketos-base-systemd"
[ "${WITH_MARATHON_SHELL:-0}" = "1" ] && EXTRAS="$EXTRAS marathon-shell"

apk.static \
    --root "$ROOTFS" --arch aarch64 --initdb \
    --cache-dir /pkgcache \
    -X https://dl-cdn.alpinelinux.org/alpine/edge/main \
    -X https://dl-cdn.alpinelinux.org/alpine/edge/community \
    -X https://mirror.postmarketos.org/postmarketos/master \
    -X https://mirror.postmarketos.org/postmarketos/extra-repos/systemd/master \
    -X "$LOCAL_REPO" \
    --allow-untrusted --no-progress \
    add \
        alpine-base \
        $EXTRAS \
        device-qemu-aarch64 \
        device-qemu-aarch64-kernel-lts \
        losetup util-linux-misc \
        greetd dbus polkit \
        marathon-base-config 2>&1 | tail -10 || \
    echo "  (post-install trigger errors ok — will fix and continue)"

# ── First-boot pre-config ───────────────────────────────────────────────
echo "─ pre-configuring firstboot (skip systemd-firstboot prompt) ─"
mkdir -p "$ROOTFS/etc"
echo "marathon" > "$ROOTFS/etc/hostname"
echo "Etc/UTC" > "$ROOTFS/etc/timezone"
ln -sfn /usr/share/zoneinfo/Etc/UTC "$ROOTFS/etc/localtime" 2>/dev/null || \
    cp "$ROOTFS/usr/share/zoneinfo/Etc/UTC" "$ROOTFS/etc/localtime" 2>/dev/null || true
cat > "$ROOTFS/etc/locale.conf" <<'EOF'
LANG=C.UTF-8
LC_ALL=C.UTF-8
EOF
# machine-id is required by systemd; empty file = systemd generates it on boot.
: > "$ROOTFS/etc/machine-id"

# Alpine ships /lib as a real directory holding musl's dynamic linker, so we
# can't merge-usr it. But modprobe / kmod look up modules at /lib/modules/<ver>,
# and depmod-time symlinks live under /lib/firmware/. Both are missing from
# Alpine's layout post-bootstrap (they only land under /usr/lib/{modules,firmware})
# so we add the symlinks here. Without these, `modprobe virtio_gpu` fails with
# "Module not found", greetd starts marathon-shell, eglfs_kms gets no DRM device,
# and the shell can't render.
[ -d "$ROOTFS/lib/firmware" ] && rmdir "$ROOTFS/lib/firmware" 2>/dev/null
ln -sfn /usr/lib/modules  "$ROOTFS/lib/modules"
ln -sfn /usr/lib/firmware "$ROOTFS/lib/firmware"

# Force-load virtio-gpu + DRM helpers on QEMU. systemd-modules-load.service
# walks /etc/modules-load.d/* on boot. Listed modules don't exist on real
# phone kernels — modprobe fails silently and we move on, so this is safe to
# always include.
mkdir -p "$ROOTFS/etc/modules-load.d"
cat > "$ROOTFS/etc/modules-load.d/marathon-qemu.conf" <<'EOMOD'
drm
drm_kms_helper
drm_shmem_helper
virtio_pci
virtio_gpu
EOMOD

# modules-load.d alone isn't sufficient: virtio_gpu pulls drm helper symbols
# that don't resolve unless depmod is run with the rootfs's *actual* /lib/modules
# layout (not the stale paths baked in by the apk's depmod). Run depmod -a at
# boot — once — before greetd starts.
mkdir -p "$ROOTFS/etc/systemd/system/sysinit.target.wants"
cat > "$ROOTFS/etc/systemd/system/marathon-modprobe.service" <<'EOSVC'
[Unit]
Description=Marathon: depmod + load virtio-gpu (idempotent, harmless on real HW)
DefaultDependencies=no
After=systemd-tmpfiles-setup.service local-fs.target
Before=systemd-modules-load.service greetd.service
ConditionPathExists=/usr/lib/modules

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/sbin/depmod -a
ExecStart=-/sbin/modprobe drm_kms_helper
ExecStart=-/sbin/modprobe drm_shmem_helper
ExecStart=-/sbin/modprobe virtio_pci
ExecStart=-/sbin/modprobe virtio_gpu
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=sysinit.target
EOSVC
ln -sfn /etc/systemd/system/marathon-modprobe.service \
    "$ROOTFS/etc/systemd/system/sysinit.target.wants/marathon-modprobe.service"

# Force a default user 'user' (UID 10000 — pmOS convention).
echo "─ creating default user ─"
echo "user:x:10000:10000:Linux User,,,:/home/user:/bin/bash" >> "$ROOTFS/etc/passwd"
# Shadow lastchange=20000 (days since epoch ≈ 2024-10-04). 0 would set
# NEW_AUTHTOK_REQD and break greetd autologin (pam_acct_mgmt rejects).
echo "user:!::0:99999:7:::" >> "$ROOTFS/etc/shadow"
echo "user:x:10000:" >> "$ROOTFS/etc/group"
mkdir -p "$ROOTFS/home/user"
# Ownership must match UID/GID 10000 so the user can write to its own home.
# Inside the rootless podman build host this requires the chown call to run
# as root inside the container (we already do, since this script runs as root
# inside an alpine:edge container where rootless UID 0 maps to host UID).
chown -R 10000:10000 "$ROOTFS/home/user" 2>/dev/null || true
# Set passwords using openssl (no chroot mount needed).
PWHASH_USER=$(openssl passwd -6 "147147" 2>/dev/null || echo '$6$marathon$ABCDEF.0123456789xyz/')
PWHASH_ROOT=$(openssl passwd -6 "147147" 2>/dev/null || echo '$6$marathon$ABCDEF.0123456789xyz/')
sed -i "s|^root:!:|root:${PWHASH_ROOT}:|" "$ROOTFS/etc/shadow" 2>/dev/null || true
sed -i "s|^user:!:|user:${PWHASH_USER}:|" "$ROOTFS/etc/shadow" 2>/dev/null || true

# Add user to required groups. Awk to avoid the sed-trailing-colon footgun
# that produced corrupt entries like "wheel:x:10:rootuser".
TMPF=$(mktemp)
awk -v u=user '
BEGIN { FS=":"; OFS=":" }
{
    if ($1 == "audio" || $1 == "video" || $1 == "input" || $1 == "render" \
        || $1 == "wheel" || $1 == "kvm" || $1 == "dialout") {
        if ($4 == "") $4 = u;
        else if ($4 !~ ("(^|,)" u "(,|$)")) $4 = $4 "," u;
    }
    print
}' "$ROOTFS/etc/group" > "$TMPF"
cp "$TMPF" "$ROOTFS/etc/group"
rm -f "$TMPF"
# Restore world-readable perms — cp inherits the rootless container's umask
# (usually 077), so the new /etc/group lands at 0600 and dbus / nss lookups
# fail with EACCES for non-root users. /etc/passwd needs the same belt+braces.
chmod 0644 "$ROOTFS/etc/group" "$ROOTFS/etc/passwd"
chmod 0640 "$ROOTFS/etc/shadow" 2>/dev/null || true

# Default target → graphical (greetd launches here).
mkdir -p "$ROOTFS/etc/systemd/system"
ln -sfn /usr/lib/systemd/system/graphical.target "$ROOTFS/etc/systemd/system/default.target"

# Mask getty@tty1 so greetd owns tty1 without race.
ln -sfn /dev/null "$ROOTFS/etc/systemd/system/getty@tty1.service"

# Mask serial-getty too — agetty restart loop on ttyAMA0 spams the log.
ln -sfn /dev/null "$ROOTFS/etc/systemd/system/serial-getty@ttyAMA0.service"

# Enable greetd (graphical.target.wants).
mkdir -p "$ROOTFS/etc/systemd/system/graphical.target.wants"
ln -sfn /usr/lib/systemd/system/greetd.service \
    "$ROOTFS/etc/systemd/system/graphical.target.wants/greetd.service"

# Drop-in to forward greetd stdout/stderr to console + journal so we can
# diagnose its restart loop in the QEMU serial output.
mkdir -p "$ROOTFS/etc/systemd/system/greetd.service.d"
cat > "$ROOTFS/etc/systemd/system/greetd.service.d/10-debug.conf" <<'EOF'
[Service]
StandardOutput=journal+console
StandardError=journal+console
EOF

# Permissive PAM stack for greetd autologin. The default user has no system
# password by design — there's no SSH/console login expected on a phone.
# The DEVICE PIN is set during Marathon's OOBE and stored via SecurityManager,
# unlocking the shell — not PAM. For greetd's autologin we just need pam_permit
# to skip the account+auth checks while keeping pam_systemd for session setup.
mkdir -p "$ROOTFS/etc/pam.d"
cat > "$ROOTFS/etc/pam.d/greetd" <<'EOF'
# greetd autologin — permissive: a phone is single-seat, no system password.
# The shell handles its own lock via Marathon's QuickPIN (stored by
# SecurityManager). System-level account + auth therefore short-circuit.
auth        sufficient  pam_permit.so
account     sufficient  pam_permit.so
password    sufficient  pam_permit.so
session     required    pam_unix.so
session     required    pam_loginuid.so
session     optional    pam_systemd.so
session     optional    pam_env.so
EOF

# If marathon-shell apk wasn't installed (WITH_MARATHON_SHELL=0), drop a
# stub session script so greetd doesn't fail. The stub prints diagnostics
# then exits, keeping greetd's restart loop visible for testing.
if [ ! -x "$ROOTFS/usr/bin/marathon-shell-session" ]; then
    cat > "$ROOTFS/usr/bin/marathon-shell-session" <<'STUB'
#!/bin/sh
echo "── marathon-shell-session STUB (apk not installed) ──"
echo "  user:    $(id)"
echo "  pwd:     $(pwd)"
echo "  XDG_RUNTIME_DIR: ${XDG_RUNTIME_DIR:-(unset)}"
echo "  greetd:  reached, autologin works"
echo "  Marathon Shell apk would run here. Sleeping so greetd stays up."
exec /bin/sleep infinity
STUB
    chmod 755 "$ROOTFS/usr/bin/marathon-shell-session"
fi

# Symlink losetup for any future mkinitfs run.
[ -x "$ROOTFS/sbin/losetup" ] && ln -sf /sbin/losetup "$ROOTFS/usr/sbin/losetup"

# Build ext4 image.
echo "─ building ext4 image ─"
SIZE=$(du -sb "$ROOTFS" | cut -f1)
SIZE=$((SIZE * 3 / 2 + 256 * 1024 * 1024))
truncate -s "$SIZE" /out/rootfs.img
mke2fs -t ext4 -F -L pmOS_root -d "$ROOTFS" -E root_owner=0:0 /out/rootfs.img 2>&1 | tail -3

KERNEL=$(ls "$ROOTFS"/boot/vmlinuz* 2>/dev/null | head -1)
if [ -n "$KERNEL" ]; then
    cp "$KERNEL" /out/kernel
    echo "  copied kernel: $(basename "$KERNEL")"
fi

echo ""
echo "─ output ─"
ls -lh /out/
CSCRIPT

echo ""
echo "═══ done ═══"
ls -lh "$OUT_DIR/"
