#!/usr/bin/env bash
# Build the Q25's U-Boot, the BL33 in lk_a and lk_b, byte for byte as the
# phone runs it: JamiKettunen/u-boot-mt6789 at $COMMIT with
# devices/zinwa/q25/u-boot, in Fedora 42 with its gcc 15.2.1 cross
# toolchain, at the tested build's clock.
#
#   build-q25-uboot.sh OUT_DIR    ->  OUT_DIR/u-boot-q25.bin
#
# The lk partition also holds MediaTek's bl2_ext, aee and lk_main_dtb and
# their certificates, which cannot be redistributed: the flash script
# puts this U-Boot into the phone's own lk image (gimme-uboot.py).
#
# Env: PODMAN (default podman)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(dirname "$(dirname "$SCRIPT_DIR")")"
OUT="$(realpath -m "${1:?usage: build-q25-uboot.sh OUT_DIR}")"
PODMAN="${PODMAN:-podman}"

URL=https://github.com/JamiKettunen/u-boot-mt6789.git
COMMIT=11b7b36cf6c26774feb93ed5c28b385b9c98f5b9
IMAGE=registry.fedoraproject.org/fedora@sha256:83205934094144b56f645f86c42b84f81083f423b0bea9cb233f91c21bab0919
KOJI=https://kojipkgs.fedoraproject.org/packages
RPMS="
9474d02dd9006266ab7a124d69dc21d56221c1119fb28af2b9be8d6a135e550a cross-gcc/15.2.1/1.fc42/aarch64/gcc-aarch64-linux-gnu-15.2.1-1.fc42.aarch64.rpm
a5270a2635bf07bff2cd3d90742c3bd7b5ee8751feaecd0a8c6ea8bae732fc29 cross-gcc/15.2.1/1.fc42/noarch/cross-gcc-common-15.2.1-1.fc42.noarch.rpm
00626465dbfa03135d0eea6f13e1dce687b2fb0659abeb2142b23c1a0c017b91 cross-binutils/2.44/1.fc42/aarch64/binutils-aarch64-linux-gnu-2.44-1.fc42.aarch64.rpm
f610a2b8ce2072369ddeb8d9475f8b27ac294ec1a13b0ca8b4fb4a6587552503 cross-binutils/2.44/1.fc42/noarch/cross-binutils-common-2.44-1.fc42.noarch.rpm
"
# "U-Boot 2025.10-rc5-g11b7b36cf6c2-dirty (Nov 03 2026 - 17:11:19 +0000)"
SOURCE_DATE_EPOCH=1793725879
UBOOT_SHA256=cc0f5e5258aa5dbb22d5b81a419e82e60f10ed289f21a15891459cd3f29200ba

mkdir -p "$OUT/toolchain"
echo "$RPMS" | while read -r sha path; do
    [ -n "$path" ] || continue
    rpm="$OUT/toolchain/${path##*/}"
    [ -f "$rpm" ] || { curl -fsSL --retry 3 -o "$rpm.part" "$KOJI/$path" && mv "$rpm.part" "$rpm"; }
    echo "$sha  $rpm" | sha256sum -c --quiet
done

SRC="$OUT/src"
rm -rf "$SRC"
git init -q "$SRC"
git -C "$SRC" fetch -q --depth 1 "$URL" "$COMMIT"
git -C "$SRC" checkout -q FETCH_HEAD
# Applied, not committed: the version string is -g<commit>-dirty, as tested.
for p in "$REPO"/devices/zinwa/q25/u-boot/*.patch; do
    git -C "$SRC" apply "$p"
done

# shellcheck disable=SC2016
"$PODMAN" run --rm --network=host --security-opt label=disable -e SOURCE_DATE_EPOCH="$SOURCE_DATE_EPOCH" \
    -v "$OUT:/out" "$IMAGE" sh -euc '
dnf -y -q install /out/toolchain/*.rpm make bison flex bc python3 openssl-devel \
    gnutls-devel libuuid-devel perl diffutils findutils which xxd git-core gcc >/dev/null
git config --global --add safe.directory /out/src
cd /out/src
make mrproper >/dev/null
make CROSS_COMPILE=aarch64-linux-gnu- mt6789_q25_defconfig >/dev/null
# Host signing tools need the OpenSSL ENGINE API, which Fedora dropped;
# u-boot.bin does not use them.
./scripts/config --disable TOOLS_KWBIMAGE --disable TOOLS_LIBCRYPTO
make CROSS_COMPILE=aarch64-linux-gnu- olddefconfig >/dev/null
make CROSS_COMPILE=aarch64-linux-gnu- -j"$(nproc)" u-boot.bin >/out/u-boot-build.log 2>&1
cp u-boot.bin /out/u-boot-q25.bin
'
echo "$UBOOT_SHA256  $OUT/u-boot-q25.bin" | sha256sum -c --quiet || {
    echo "error: $OUT/u-boot-q25.bin is not the U-Boot the Q25 was tested with" >&2
    exit 1
}
echo "==> $OUT/u-boot-q25.bin"
