#!/usr/bin/env bash
# setup-librem5-recovery.sh — bootstrap a Librem 5 recovery rig.
#
# Stages:
#   1. dnf install build deps for uuu
#   2. Clone Purism mfgtools fork, patch for GCC 15, build, install uuu
#   3. Install udev rules + add user to plugdev
#   4. Download Jumpdrive 0.8 + record locally-computed SHA256
#   5. Download latest postmarketOS phosh Librem 5 image + verify SHA256
#
# Reference: ~/Developer/Marathon-Image/docs/LIBREM5_RECOVERY.md
#
# Usage:
#   ./setup-librem5-recovery.sh [STAGE_DIR]
# STAGE_DIR defaults to $HOME/librem5-recovery.

set -euo pipefail

STAGE_DIR="${1:-$HOME/librem5-recovery}"
mkdir -p "$STAGE_DIR"
cd "$STAGE_DIR"

echo "==> 1/5 install uuu build deps (Fedora-flavoured)"
if command -v dnf >/dev/null 2>&1; then
    sudo -A dnf install -y --quiet git cmake gcc-c++ pkgconf-pkg-config \
        libusb1-devel libzip-devel bzip2-devel libzstd-devel \
        openssl-devel zlib-devel tinyxml2-devel libstdc++-static
else
    echo "warning: non-dnf host. Install the equivalents manually."
fi

echo "==> 2/5 clone + patch + build uuu (Purism fork)"
if [ ! -d mfgtools ]; then
    git clone --depth 1 https://source.puri.sm/Librem5/mfgtools
fi

# Patch all .h/.cpp files that use uint*_t / int*_t but don't include
# <cstdint>. GCC 15 / libstdc++ 15 enforce the explicit include where
# earlier versions accepted it transitively. Affects ~29 files in the
# Purism fork.
echo "    patching cstdint includes (GCC 15 compatibility)"
patched=0
for f in $(find mfgtools/libuuu mfgtools/uuu -name '*.h' -o -name '*.cpp'); do
    if grep -lq 'uint[0-9]*_t\|int[0-9]*_t' "$f" 2>/dev/null \
        && ! grep -q '#include <cstdint>' "$f" 2>/dev/null; then
        sed -i '1i #include <cstdint>' "$f"
        patched=$((patched + 1))
    fi
done
echo "    patched $patched files"

mkdir -p mfgtools-build
( cd mfgtools-build && cmake ../mfgtools >/dev/null && make -j"$(nproc)" )

echo "==> 3/5 install uuu + udev rules"
sudo -A install -m 0755 mfgtools-build/uuu/uuu /usr/local/bin/uuu
uuu -V 2>&1 | head -1 | sed 's/^/    /'

sudo -A tee /etc/udev/rules.d/99-librem5-uuu.rules > /dev/null <<'UDEV'
# Librem 5 recovery: uuu over USB Serial Download Protocol.
# See ~/Developer/Marathon-Image/docs/LIBREM5_RECOVERY.md.
SUBSYSTEM!="usb", GOTO="librem5_uuu_rules_end"

# i.MX 8M Quad ROM SDP — Librem 5 in Vol+power-on recovery mode.
ATTR{idVendor}=="1fc9", ATTR{idProduct}=="012b", GROUP+="plugdev", TAG+="uaccess"

# Purism USB gadget (Jumpdrive U-Boot presents this after SDP boot).
ATTR{idVendor}=="316d", ATTR{idProduct}=="4c05", GROUP+="plugdev", TAG+="uaccess"

# Linux Foundation USB Gadget Framework — older U-Boot fastboot phase.
ATTR{idVendor}=="0525", ATTR{idProduct}=="a4a5", GROUP+="plugdev", TAG+="uaccess"
ATTR{idVendor}=="0525", ATTR{idProduct}=="b4a4", GROUP+="plugdev", TAG+="uaccess"

LABEL="librem5_uuu_rules_end"
UDEV
sudo -A udevadm control --reload-rules
sudo -A groupadd -f plugdev
sudo -A usermod -aG plugdev "$USER"
echo "    udev rules installed; you may need to re-login for plugdev membership"

echo "==> 4/5 Jumpdrive 0.8 (purism-librem5)"
if [ ! -f purism-librem5.tar.xz ]; then
    curl -fLO https://github.com/dreemurrs-embedded/Jumpdrive/releases/download/0.8/purism-librem5.tar.xz
fi
sha256sum purism-librem5.tar.xz > purism-librem5.tar.xz.sha256.local
echo "    local sha256: $(cut -d' ' -f1 purism-librem5.tar.xz.sha256.local)"
[ -f boot-purism-librem5.sh ] || tar xJf purism-librem5.tar.xz

echo "==> 5/5 postmarketOS phosh Librem 5 reset image"
PMOS_IMG=20260620-0010-postmarketOS-edge-phosh-29-purism-librem5.img.xz
PMOS_URL=https://images.postmarketos.org/bpo/edge/purism-librem5/phosh/20260620-0010/$PMOS_IMG
PMOS_SHA=607e0df59b8b8d8e4d164d3fb2deb1079a8813f97effd401b70481df197a7079
if [ ! -f "$PMOS_IMG" ]; then
    curl -fLO "$PMOS_URL"
fi
if echo "$PMOS_SHA  $PMOS_IMG" | sha256sum -c -; then
    echo "    SHA256 verified"
else
    echo "    ERROR: SHA256 mismatch — abort, do not flash"
    exit 1
fi

echo
echo "==> done. Recovery rig at $STAGE_DIR"
echo "    next: LIBREM5_RECOVERY.md §2 to enter SDP mode"
