#!/bin/sh
# Build the MT6858 CONNSYS (Wi-Fi, Bluetooth, GNSS) modules against the
# linux-mt6858 tree; its APKBUILD runs this after the kernel.
#
#   build.sh KSRC KOBJ MODULES DEVICE_MODULES OUT
#
# MODULES: github.com/YaAlex3/kernel_xiaomi_tanzanite-mediatek_modules at
# 9fe8054b021c59e1abfc9c8ca52a9e6c19156749 (only connectivity/ is read).
# DEVICE_MODULES: github.com/YaAlex3/kernel_xiaomi_tanzanite-modules at
# a7f9e9efa1ec7e31dd8aade57716cd61ae50da1a (only
# drivers/misc/mediatek/connectivity/ is read).
# OUT is created: OUT/modules holds the modules; nothing else is written.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
ksrc=$1 kobj=$2 conn=$3/connectivity dev=$4/drivers/misc/mediatek/connectivity out=$5
mkdir -p "$out"
out=$(cd "$out" && pwd)
s=$out/src

# The donor files in the layout connectivity.patch expects.
rm -rf "$s"
mkdir -p "$s/wlan" "$s/bt" "$s/gps" "$s/connadp"
cp -r "$conn/conninfra" "$conn/connfem" "$s/"
cp -r "$conn/wlan/core/gen4m" "$conn/wlan/adaptor" "$s/wlan/"
cp -r "$conn/bt/mt66xx/btif" "$conn/bt/mt66xx/include" "$s/bt/"
cp "$conn"/bt/mt66xx/btmtk_*.c "$s/bt/"
# plat/v051 is mostly links into the shared data_link tree.
cp -rL "$conn/gps/data_link/plat/v051" "$s/gps/data_link"
cp -r "$dev/common" "$dev/power_throttling" "$s/connadp/"
(cd "$s" && patch -p1 -s < "$here/connectivity.patch")

printf '#!/bin/sh\nexec ld.lld --thinlto-jobs=1 "$@"\n' > "$out/ld"
chmod +x "$out/ld"
kmake() {
	src=$1 obj=$2
	shift 2
	mkdir -p "$obj"
	make -C "$ksrc" O="$kobj" M="$src" MO="$obj" ARCH=arm64 LLVM=1 \
		LD="$out/ld" -j"${JOBS:-2}" "$@" modules
}
o=$out/obj
kmake "$s/connadp" "$o/connadp"
sym="$o/connadp/Module.symvers"
kmake "$s/conninfra" "$o/conninfra" KBUILD_EXTRA_SYMBOLS="$sym"
kmake "$s/connfem" "$o/connfem"
sym="$sym $o/conninfra/Module.symvers"
kmake "$s/wlan/adaptor/wlan_page_pool" "$o/wlan_page_pool"
kmake "$s/wlan/adaptor" "$o/wlan_adaptor" KBUILD_EXTRA_SYMBOLS="$sym"
kmake "$s/wlan/gen4m" "$o/gen4m" KBUILD_EXTRA_SYMBOLS="$sym \
	$o/connfem/Module.symvers $o/wlan_adaptor/Module.symvers \
	$o/wlan_page_pool/Module.symvers"
kmake "$s/bt" "$o/bt" KBUILD_EXTRA_SYMBOLS="$sym $o/connfem/Module.symvers"
kmake "$s/gps/data_link" "$o/gps" KBUILD_EXTRA_SYMBOLS="$sym"

mkdir -p "$out/modules"
find "$o" -name '*.ko' -exec sh -c \
	'llvm-strip --strip-debug -o "$0/$(basename "$1")" "$1"' "$out/modules" {} \;
