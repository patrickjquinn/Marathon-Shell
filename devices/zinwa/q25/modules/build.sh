#!/bin/sh
# Build the Q25 out-of-tree modules against a prepared 7.0.0-q25-cfi-test
# kernel tree and, given SHIPPED (a directory of the packaged .ko files),
# check each against it with kocmp.py.
#
#   build.sh KSRC KOBJ DONOR OUT [SHIPPED]
#
# KSRC/KOBJ: the kernel source and object trees the kernel APK was built
# from (make -C KSRC O=KOBJ). DONOR: a checkout of
# github.com/iasnezhkov/android_kernel_ikko_mindone at
# 9cd73c15f312cfd1e40a22d871de65a2fb2c5791 (only mindone/modules is read).
# OUT is created; nothing else is written.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
ksrc=$1 kobj=$2 donor=$3/mindone/modules out=$4 shipped=${5:-}
mkdir -p "$out"
out=$(cd "$out" && pwd)

printf '#!/bin/sh\nexec ld.lld --thinlto-jobs=1 "$@"\n' > "$out/ld"
chmod +x "$out/ld"

kmake() {
	src=$1 obj=$2
	shift 2
	mkdir -p "$obj"
	make -C "$ksrc" O="$kobj" M="$src" MO="$obj" ARCH=arm64 LLVM=1 \
		LD="$out/ld" W=1 -j"${JOBS:-2}" "$@" modules
}

for d in keyboard md1 conn-pd imu; do
	rm -rf "$out/src/$d"
	mkdir -p "$out/src"
	cp -r "$here/$d" "$out/src/$d"
done
cp "$ksrc/drivers/spi/spi-mt65xx.c" "$out/src/imu/"

rm -rf "$out/src/wmt" "$out/src/wlan"
mkdir -p "$out/src/wmt" "$out/src/wlan"
while read -r f; do
	mkdir -p "$out/src/wmt/$(dirname "$f")"
	cp -P "$donor/$f" "$out/src/wmt/$f"
done < "$here/wifi/wmt-files.txt"
cp -r "$donor/wlan_drv_gen4m_6789" "$donor/wmt_chrdev_wifi" "$out/src/wlan/"
(cd "$out/src/wmt" && patch -p1 -s < "$here/wifi/0001-wmt-btif-connadp-q25.patch")
(cd "$out/src/wlan" && patch -p1 -s < "$here/wifi/0002-wlan-gen4m-q25.patch")

for d in keyboard md1 conn-pd imu; do
	kmake "$out/src/$d" "$out/obj/$d"
done
kmake "$ksrc/net/rfkill" "$out/obj/rfkill"
kmake "$ksrc/net/wireless" "$out/obj/cfg80211" \
	KBUILD_EXTRA_SYMBOLS="$out/obj/rfkill/Module.symvers"
kmake "$out/src/wmt" "$out/obj/wmt"
kmake "$out/src/wlan" "$out/obj/wlan" JOINT="$out/src/wmt" \
	KBUILD_EXTRA_SYMBOLS="$out/obj/wmt/Module.symvers $out/obj/rfkill/Module.symvers $out/obj/cfg80211/Module.symvers"

# The Wi-Fi stack ships without debug info; the other modules ship as built.
mkdir -p "$out/modules"
for ko in "$out"/obj/*/*.ko; do
	case "$(basename "$ko")" in
	q25-bbq-keys.ko | q25-keyboard-led.ko | q25-md1-owner.ko | inv-icm42607*.ko | spi-mt65xx.ko)
		cp "$ko" "$out/modules/" ;;
	*)
		llvm-strip --strip-debug -o "$out/modules/$(basename "$ko")" "$ko" ;;
	esac
done
[ -n "$shipped" ] || exit 0
mkdir -p "$out/cmp"
status=0
for ko in "$out"/modules/*.ko; do
	m=$(basename "$ko")
	llvm-strip --strip-debug -o "$out/cmp/new-$m" "$ko"
	llvm-strip --strip-debug -o "$out/cmp/shipped-$m" "$shipped/$m"
	printf '%s: ' "$m"
	python3 "$here/kocmp.py" "$out/cmp/shipped-$m" "$out/cmp/new-$m" || status=1
done
exit $status
